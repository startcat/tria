#if DEBUG
import Foundation
import Testing
import TriaTestSupport
@testable import TriaKit

/// La Papelera de la tanda QA: con `QATrash.folder`, lo que Tria manda a la Papelera va ahí y se deshace igual; sin
/// ella, todo como siempre. Ninguna prueba toca `QATrash.folder` (es de todo el proceso y otras suites corren a la
/// vez): usan `QATrash.$override`, de la tarea. Ninguna toca la Papelera del Mac.
struct QATrashTests {
    @Test func withAQATrashFolderTheTrashGoesThereAndCanBeUndone() throws {
        let dir = try TempDir()
        let ws = try WorkspaceFixture.make(in: dir)
        let trash = dir.url.appendingPathComponent("qa/papelera", isDirectory: true)
        try QATrash.$override.withValue(Optional<URL?>.some(trash)) {
            try dir.write("99-Pendiente/basura.pdf", "uno")
            try dir.write("99-Pendiente/sub/basura.pdf", "dos")
            let trashing = { (source: String) in
                ApprovedItem(action: FilingAction(kind: .trash, source: source, destination: ""), reason: "trash")
            }

            // El Executor de siempre, con su Papelera por defecto (`Executor.systemTrash`): la del CLI y la de la app.
            let report = Executor(workspace: ws).apply([trashing("99-Pendiente/basura.pdf"),
                                                        trashing("99-Pendiente/sub/basura.pdf")])
            #expect(report.failed.isEmpty)
            #expect(report.applied.map(\.to) == [trash.appendingPathComponent("basura.pdf").path,
                                                 trash.appendingPathComponent("basura (2).pdf").path])
            #expect(try String(contentsOf: trash.appendingPathComponent("basura (2).pdf"), encoding: .utf8) == "dos")
            #expect(!FileManager.default.fileExists(atPath: dir.url.appendingPathComponent("99-Pendiente/basura.pdf").path))

            let undone = try #require(try Undoer(workspace: ws).undoLast())
            #expect(undone.skipped.isEmpty)
            #expect(try String(contentsOf: dir.url.appendingPathComponent("99-Pendiente/basura.pdf"), encoding: .utf8)
                    == "uno")
            #expect(try String(contentsOf: dir.url.appendingPathComponent("99-Pendiente/sub/basura.pdf"), encoding: .utf8)
                    == "dos")
    
        }
    }

    /// Sin carpeta, lo de siempre: solo cuentan como Papelera `.Trash` y `.Trashes`. No se manda nada a la Papelera de
    /// verdad para comprobarlo.
    @Test func withoutAFolderOnlyTheRealTrashCounts() throws {
        let dir = try TempDir()
        try QATrash.$override.withValue(Optional<URL?>.some(nil)) {
        #expect(QATrash.folder == nil)
        #expect(!PathSafety.isInTrash(dir.url.appendingPathComponent("qa/papelera/basura.pdf").path))
        #expect(PathSafety.isInTrash("/Users/alguien/.Trash/basura.pdf"))
        #expect(PathSafety.isInTrash("/Volumes/Disco/.Trashes/501/basura.pdf"))

        }
        try QATrash.$override.withValue(Optional<URL?>.some(dir.url.appendingPathComponent("qa/papelera", isDirectory: true))) {
        #expect(PathSafety.isInTrash(dir.url.appendingPathComponent("qa/papelera/basura.pdf").path))
        #expect(!PathSafety.isInTrash(dir.url.appendingPathComponent("qa/papelera-no/basura.pdf").path))
        #expect(!PathSafety.isInTrash(dir.url.appendingPathComponent("qa/papelera/../fuera.pdf").path))
        }
    }

    /// La decisión del CLI es una función pura: no toca `QATrash.folder`.
    @Test func theCLIFolderIsDecidedFromTheEnvironment() {
        #expect(QATrash.folder(forEnvironment: [:]) == nil)
        #expect(QATrash.folder(forEnvironment: ["TRIA_QA": "0", "TRIA_QA_ROOT": "/tmp/r"]) == nil)
        #expect(QATrash.folder(forEnvironment: ["TRIA_QA": "1", "TRIA_QA_ROOT": "/tmp/r"])?.path == "/tmp/r/papelera")
        #expect(QATrash.folder(forEnvironment: ["TRIA_QA": "1"])
                == FileManager.default.temporaryDirectory.appendingPathComponent("tria-qa/papelera", isDirectory: true))
    }
}
#endif
