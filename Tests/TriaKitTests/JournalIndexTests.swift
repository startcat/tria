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
}
