import Foundation
import Testing
import TriaTestSupport
@testable import TriaKit

private func proposal(_ destination: String, _ filename: String = "Modelo 303 - 2023 - 1T.pdf") -> Proposal {
    Proposal(action: .file, destination: destination, filename: filename, documentType: "Modelo 303",
             documentDate: "2023-04-20", confidence: .high, reason: "r", doubt: nil)
}

@Test func acceptsAnExistingFolder() throws {
    let dir = try TempDir()
    let validator = Validator(workspace: try WorkspaceFixture.make(in: dir))
    let result = validator.validate(proposal("1-Modelos Tributarios/Modelo 303 - IVA"), originalFilename: "doc.pdf")
    #expect(result == .success("1-Modelos Tributarios/Modelo 303 - IVA/Modelo 303 - 2023 - 1T.pdf"))
}

@Test func canonicalizesCaseToTheFolderOnDisk() throws {   // Review Focus 2
    let dir = try TempDir()
    let validator = Validator(workspace: try WorkspaceFixture.make(in: dir))
    let result = validator.validate(proposal("1-modelos tributarios/modelo 303 - iva"), originalFilename: "doc.pdf")
    #expect(result == .success("1-Modelos Tributarios/Modelo 303 - IVA/Modelo 303 - 2023 - 1T.pdf"))
}

@Test func matchesDecomposedFolderNames() throws {   // Review Focus 3
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir, folders: ["Correspondencia\u{0300}"])
    let result = Validator(workspace: ws).validate(proposal("Correspondencià", "carta.pdf"), originalFilename: "c.pdf")
    #expect(result == .success("Correspondencià/carta.pdf"))
}

@Test func rejectsUnsafeAndEscapingPaths() throws {
    let dir = try TempDir()
    let outside = try TempDir("tria-outside")
    let ws = try WorkspaceFixture.make(in: dir)
    try FileManager.default.createSymbolicLink(at: dir.url.appendingPathComponent("Enlace"), withDestinationURL: outside.url)
    let validator = Validator(workspace: ws)
    #expect(validator.validate(proposal("../fuera"), originalFilename: "a.pdf") == .failure(.unsafePath("../fuera")))
    #expect(validator.validate(proposal("/etc"), originalFilename: "a.pdf") == .failure(.unsafePath("/etc")))
    #expect(validator.validate(proposal(".tria/cache"), originalFilename: "a.pdf") == .failure(.unsafePath(".tria/cache")))
    #expect(validator.validate(proposal("Enlace/sub"), originalFilename: "a.pdf") == .failure(.outsideRoot("Enlace/sub")))
    #expect(validator.validate(proposal("  "), originalFilename: "a.pdf") == .failure(.emptyDestination))
}

@Test func rejectsProtectedInboxAndDuplicates() throws {
    let dir = try TempDir()
    let validator = Validator(workspace: try WorkspaceFixture.make(in: dir))
    #expect(validator.validate(proposal("7-Facturas/2013/1T"), originalFilename: "a.pdf")
            == .failure(.protectedPath("7-Facturas/2013/1T")))
    #expect(validator.validate(proposal("99-Pendiente"), originalFilename: "a.pdf") == .failure(.intoInbox))
    #expect(validator.validate(proposal("98-duplicados/sub"), originalFilename: "a.pdf") == .failure(.intoDuplicates))
}

@Test func appliesNewFoldersPolicy() throws {
    let dir = try TempDir()
    let validator = Validator(workspace: try WorkspaceFixture.make(in: dir))
    #expect(validator.validate(proposal("7-Facturas/Emitidas/2025"), originalFilename: "a.pdf")
            == .success("7-Facturas/Emitidas/2025/Modelo 303 - 2023 - 1T.pdf"))
    #expect(validator.validate(proposal("Nueva Carpeta/x"), originalFilename: "a.pdf")
            == .failure(.newTopLevelFolder("Nueva Carpeta")))

    let strictDir = try TempDir()
    let strictRules = WorkspaceFixture.defaultRules.replacingOccurrences(of: "subfolders_only", with: "never")
    let strict = Validator(workspace: try WorkspaceFixture.make(in: strictDir, rules: strictRules))
    #expect(strict.validate(proposal("7-Facturas/Emitidas"), originalFilename: "a.pdf")
            == .failure(.folderMissing("7-Facturas/Emitidas")))
}

@Test func rejectsPathsThroughFiles() throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    try dir.write("1-Modelos Tributarios/nota.txt")
    #expect(Validator(workspace: ws).validate(proposal("1-Modelos Tributarios/nota.txt/sub"), originalFilename: "a.pdf")
            == .failure(.blockedByFile("1-Modelos Tributarios/nota.txt")))
}

@Test func neverOverwritesAndRespectsReservedNames() throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    try dir.write("1-Modelos Tributarios/Modelo 303 - IVA/Modelo 303 - 2023 - 1T.pdf")
    let validator = Validator(workspace: ws)
    let folder = "1-Modelos Tributarios/Modelo 303 - IVA"
    #expect(validator.validate(proposal(folder), originalFilename: "a.pdf")
            == .success("\(folder)/Modelo 303 - 2023 - 1T (2).pdf"))
    #expect(validator.validate(proposal(folder), originalFilename: "a.pdf",
                               reserved: ["\(folder)/Modelo 303 - 2023 - 1T (2).pdf"])
            == .success("\(folder)/Modelo 303 - 2023 - 1T (3).pdf"))
}

@Test func rejectsEmptyFilenameAndBuildsDuplicateDestinations() throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    let validator = Validator(workspace: ws)
    #expect(validator.validate(proposal("7-Facturas/Recibidas", "..."), originalFilename: "a.pdf") == .failure(.emptyFilename))
    try dir.write("98-Duplicados/scan.pdf")
    #expect(validator.duplicateDestination(originalFilename: "scan.pdf") == "98-Duplicados/scan (2).pdf")
}

@Test func everyErrorExplainsItselfToTheModel() {
    let errors: [ValidationError] = [.emptyDestination, .unsafePath("x"), .outsideRoot("x"), .protectedPath("x"),
                                     .intoInbox, .intoDuplicates, .folderMissing("x"), .newTopLevelFolder("x"),
                                     .blockedByFile("x"), .emptyFilename, .fileNameInDestination("x")]
    for error in errors { #expect(!error.feedback.isEmpty) }
}

@Test func symlinksIntoProtectedFoldersOrTheInboxAreRejected() throws {   // revisión final: invariante 2 con enlaces
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    let fm = FileManager.default
    try fm.createSymbolicLink(at: dir.url.appendingPathComponent("1-Modelos Tributarios/Atajo"),
                              withDestinationURL: dir.url.appendingPathComponent("7-Facturas/2013/1T"))
    try fm.createSymbolicLink(at: dir.url.appendingPathComponent("1-Modelos Tributarios/Bandeja"), withDestinationURL: ws.inboxURL)
    let validator = Validator(workspace: ws)
    guard case .failure(.protectedPath) = validator.validate(proposal("1-Modelos Tributarios/Atajo"), originalFilename: "a.pdf")
    else { Issue.record("un enlace a una carpeta protegida se ha aceptado"); return }
    #expect(validator.validate(proposal("1-Modelos Tributarios/Bandeja"), originalFilename: "a.pdf") == .failure(.intoInbox))
}

@Test func hiddenFoldersAndStateFolderVariantsAreRejected() throws {
    let dir = try TempDir()
    let validator = Validator(workspace: try WorkspaceFixture.make(in: dir))
    for destination in ["./.tria", ".TRIA/cache", "7-Facturas/.oculta"] {
        #expect(validator.validate(proposal(destination), originalFilename: "a.pdf") == .failure(.unsafePath(destination)))
    }
}

@Test func paddedPathComponentsResolveToTheExistingFolders() throws {   // Review Focus 2: sin carpetas gemelas
    let dir = try TempDir()
    let validator = Validator(workspace: try WorkspaceFixture.make(in: dir))
    #expect(validator.validate(proposal("7-Facturas / Recibidas "), originalFilename: "a.pdf")
            == .success("7-Facturas/Recibidas/Modelo 303 - 2023 - 1T.pdf"))
    #expect(validator.validate(proposal("7-Facturas/Recibidas /2025"), originalFilename: "a.pdf")
            == .success("7-Facturas/Recibidas/2025/Modelo 303 - 2023 - 1T.pdf"))
}

@Test func aFileNameInTheDestinationIsRejected() throws {
    let dir = try TempDir()
    let validator = Validator(workspace: try WorkspaceFixture.make(in: dir))
    #expect(validator.validate(proposal("7-Facturas/Recibidas/Factura Luz.pdf", "Factura Luz.pdf"), originalFilename: "a.pdf")
            == .failure(.fileNameInDestination("Factura Luz.pdf")))
}

@Test func collisionSuffixKeepsTheNameWithin255Bytes() throws {
    let dir = try TempDir()
    let name = String(repeating: "a", count: 251) + ".pdf"
    try dir.write(name)
    let unique = Collision.uniqueRelativePath(name, root: dir.url)
    #expect(unique.utf8.count <= 255)
    #expect(unique.hasSuffix(" (2).pdf"))
}
