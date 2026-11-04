import Foundation
import Testing
import TriaTestSupport
@testable import TriaKit

struct JournalIndexTests {
    private func done(_ id: String, from: String, to: String, ts: TimeInterval, op: JournalEvent.Op = .move) -> JournalEvent {
        JournalEvent(id: id, batch: "b_1", op: op, state: .done, from: from, to: to, ts: Date(timeIntervalSince1970: ts))
    }

    @Test func findsTheOperationByCurrentPathIgnoringCaseAndUnicodeForm() throws {
        let dir = try TempDir()
        let journal = Journal(workspace: try WorkspaceFixture.make(in: dir))
        try journal.append(done("op_1", from: "99-Pendiente/Scan_0042.pdf",
                                to: "7-Facturas/Recibidas/Factura Papelería Mar.pdf", ts: 1_000))
        let index = try journal.index()
        // Desde SMB el nombre llega en NFD ("i" + acento combinado) y con otra capitalización.
        #expect(index.operation(at: "7-facturas/recibidas/Factura Papeleri\u{0301}a Mar.pdf")?.id == "op_1")
        #expect(index.operation(at: "7-Facturas/Recibidas/Otra.pdf") == nil)
    }

    @Test func undoneOperationsAreNotAtTheirFiledPathAnymore() throws {
        let dir = try TempDir()
        let journal = Journal(workspace: try WorkspaceFixture.make(in: dir))
        try journal.append(done("op_1", from: "99-Pendiente/a.pdf", to: "7-Facturas/Recibidas/A.pdf", ts: 1_000))
        try journal.append(JournalEvent(id: "op_1", batch: "b_1", op: .move, state: .undone,
                                        from: "7-Facturas/Recibidas/A.pdf", to: "99-Pendiente/a.pdf",
                                        ts: Date(timeIntervalSince1970: 2_000)))
        let index = try journal.index()
        #expect(index.operation(at: "7-Facturas/Recibidas/A.pdf") == nil)
        #expect(index.search("a.pdf").map(\.state) == [.undone])
    }

    @Test func searchMatchesOriginalAndNewNamesWithoutCaseOrAccentsNewestFirst() throws {
        let dir = try TempDir()
        let journal = Journal(workspace: try WorkspaceFixture.make(in: dir))
        try journal.append(done("op_old", from: "99-Pendiente/Scan_0042.pdf",
                                to: "5-Bancos/Banco Ejemplo - Extracto - 2026-08.pdf", ts: 1_000))
        try journal.append(done("op_new", from: "99-Pendiente/IMG_7.jpg",
                                to: "2-Facturas Recibidas/Factura Papelería Mar.jpg", ts: 2_000))
        try journal.append(done("op_trash", from: "99-Pendiente/copia.pdf", to: "/Users/prueba/.Trash/copia.pdf",
                                ts: 500, op: .trash))
        let index = try journal.index()
        #expect(index.search("scan_0042").map(\.id) == ["op_old"])
        #expect(index.search("papeleria").map(\.id) == ["op_new"])
        #expect(index.search("copia").map(\.id) == ["op_trash"])
        #expect(index.search(".").map(\.id) == ["op_new", "op_old", "op_trash"])
        #expect(index.search(".", limit: 1).map(\.id) == ["op_new"])
        #expect(index.search("   ").isEmpty)
        #expect(index.operation(at: "/Users/prueba/.Trash/copia.pdf") == nil)
    }

    @Test func failedAndInterruptedOperationsAreLeftOut() throws {
        let dir = try TempDir()
        let journal = Journal(workspace: try WorkspaceFixture.make(in: dir))
        try journal.append(JournalEvent(id: "op_f", batch: "b", op: .move, state: .intent,
                                        from: "99-Pendiente/x.pdf", to: "7-Facturas/Recibidas/X.pdf"))
        try journal.append(JournalEvent(id: "op_f", batch: "b", op: .move, state: .failed,
                                        from: "99-Pendiente/x.pdf", to: "", error: "boom"))
        try journal.append(JournalEvent(id: "op_i", batch: "b", op: .move, state: .intent,
                                        from: "99-Pendiente/y.pdf", to: "7-Facturas/Recibidas/Y.pdf"))
        let index = try journal.index()
        #expect(index.search("pdf").isEmpty)
        #expect(index.operation(at: "7-Facturas/Recibidas/Y.pdf") == nil)
    }

    @Test func aFilingMovedByTheUserIsFoundAtItsCurrentPath() throws {
        let dir = try TempDir()
        let ws = try WorkspaceFixture.make(in: dir, folders: WorkspaceFixture.defaultFolders
                                           + ["2-Contratos/Telefonía", "4-Correspondencia"])
        try dir.write("99-Pendiente/scan.pdf", "contrato")
        try dir.write("99-Pendiente/carta.pdf", "carta")
        let filed = "4-Correspondencia/Contrato telefonía.pdf"
        let executor = Executor(workspace: ws)
        let filing = executor.apply([
            ApprovedItem(action: FilingAction(kind: .file, source: "99-Pendiente/scan.pdf", destination: filed)),
            ApprovedItem(action: FilingAction(kind: .file, source: "99-Pendiente/carta.pdf",
                                              destination: "4-Correspondencia/Carta.pdf")),
        ])
        // Todo en el mismo segundo, como cuando el usuario mueve justo después de archivar.
        _ = executor.relocate([RelocationItem(source: filed, folder: "2-Contratos")])
        let last = executor.relocate([RelocationItem(source: "2-Contratos/Contrato telefonía.pdf",
                                                     folder: "2-Contratos/Telefonía")])
        let index = try Journal(workspace: ws).index()
        let contract = try #require(index.operations.first { $0.id == filing.applied.first?.operationID })
        let letter = try #require(index.operations.first { $0.id == filing.applied.last?.operationID })

        #expect(index.currentPath(of: contract) == "2-Contratos/Telefonía/Contrato telefonía.pdf")
        #expect(index.operation(at: "2-Contratos/Telefonía/Contrato telefonía.pdf")?.id == contract.id)
        #expect(index.lastUserMove(at: "2-Contratos/Telefonía/Contrato telefonía.pdf")?.id
                == last.moved.first?.operationID)
        #expect(index.isSuperseded(contract))
        #expect(index.operation(at: filed) == nil)
        #expect(index.operation(at: "2-Contratos/Contrato telefonía.pdf") == nil)
        // Lo que nadie movió sigue donde lo dejó Tria.
        #expect(index.currentPath(of: letter) == "4-Correspondencia/Carta.pdf")
        #expect(!index.isSuperseded(letter))
        #expect(index.operation(at: "4-Correspondencia/Carta.pdf")?.id == letter.id)
        #expect(index.lastUserMove(at: "4-Correspondencia/Carta.pdf") == nil)
    }
}
