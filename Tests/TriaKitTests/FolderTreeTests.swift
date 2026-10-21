import Foundation
import Testing
import TriaTestSupport
@testable import TriaKit

private func touch(_ dir: TempDir, _ path: String, age: TimeInterval) throws {
    let url = try dir.write(path)
    try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-age)], ofItemAtPath: url.path)
}

@Test func rendersFoldersExamplesAndProtectedMarkers() throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    try touch(dir, "1-Modelos Tributarios/Modelo 303 - IVA/Modelo 303 - 2023 - 1T.pdf", age: 400)
    try touch(dir, "1-Modelos Tributarios/Modelo 303 - IVA/Modelo 303 - 2023 - 2T.pdf", age: 300)
    try touch(dir, "1-Modelos Tributarios/Modelo 303 - IVA/Modelo 303 - 2023 - 3T.pdf", age: 200)
    try touch(dir, "1-Modelos Tributarios/Modelo 303 - IVA/Modelo 303 - 2023 - 4T.pdf", age: 100)
    try touch(dir, "7-Facturas/2013/1T/secreta.pdf", age: 10)
    try dir.write("99-Pendiente/nuevo.pdf")

    let tree = try ws.folderTree()
    #expect(tree == """
    1-Modelos Tributarios/
      Modelo 303 - IVA/
        · Modelo 303 - 2023 - 4T.pdf
        · Modelo 303 - 2023 - 3T.pdf
        · Modelo 303 - 2023 - 2T.pdf
    7-Facturas/
      2013/ [protected]
      Recibidas/
    """)
}

@Test func respectsMaxDepthAndExcludedFiles() throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir, folders: ["A/B/C/D/E"])
    try dir.write("A/B/visible.pdf")
    try dir.write("A/B/oculto.pdf")
    let tree = try ws.folderTree(options: FolderTreeOptions(excludedFiles: ["A/B/oculto.pdf"]))
    #expect(tree.contains("      D/"))
    #expect(!tree.contains("E/"))
    #expect(tree.contains("· visible.pdf"))
    #expect(!tree.contains("oculto.pdf"))
}

@Test func trimsExamplesThenDepthWhenTooLong() throws {
    let dir = try TempDir()
    let folders = (1...30).map { String(format: "Cliente %02d/Proyecto", $0) }
    let ws = try WorkspaceFixture.make(in: dir, folders: folders)
    for folder in folders { for n in 1...3 { try dir.write("\(folder)/doc \(n).pdf") } }
    let tree = try ws.folderTree(options: FolderTreeOptions(maxLines: 40))
    let lines = tree.split(separator: "\n")
    #expect(lines.count <= 40)
    #expect(!tree.contains("·"))
    #expect(tree.contains("Cliente 30/"))
}
