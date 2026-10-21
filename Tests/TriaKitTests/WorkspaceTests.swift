import Foundation
import Testing
import TriaTestSupport
@testable import TriaKit

@Test func initializeCreatesRulesAndStructure() throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    let fm = FileManager.default
    #expect(fm.fileExists(atPath: dir.url.appendingPathComponent("TRIA.md").path))
    #expect(fm.fileExists(atPath: ws.inboxURL.path))
    #expect(fm.fileExists(atPath: ws.duplicatesURL.path))
    #expect(fm.fileExists(atPath: ws.cacheURL.path))
    #expect(ws.inboxURL.lastPathComponent == "99-Pendiente")
}

@Test func initializeRefusesToOverwriteRules() throws {
    let dir = try TempDir()
    _ = try WorkspaceFixture.make(in: dir)
    #expect(throws: WorkspaceError.rulesAlreadyExist) {
        try Workspace.initialize(at: dir.url, rulesText: WorkspaceFixture.defaultRules)
    }
}

@Test func openFailsWithoutRulesAndWithInvalidRules() throws {
    let dir = try TempDir()
    #expect(throws: WorkspaceError.rulesNotFound(dir.url.path)) { try Workspace.open(at: dir.url) }
    try dir.write("TRIA.md", "sin cabecera")
    #expect(throws: WorkspaceError.rules(.missingFrontmatter)) { try Workspace.open(at: dir.url) }
}

@Test func discoverWalksUpToTheRoot() throws {
    let dir = try TempDir()
    _ = try WorkspaceFixture.make(in: dir)
    let nested = dir.url.appendingPathComponent("1-Modelos Tributarios/Modelo 303 - IVA")
    #expect(try Workspace.discover(from: nested).root == dir.url)
}

@Test func relativePathIsNFCAndRootRelative() throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    let url = dir.url.appendingPathComponent("Correspondencia\u{0300}/carta.pdf")
    #expect(ws.relativePath(of: url) == "Correspondencià/carta.pdf")
    #expect(ws.relativePath(of: URL(fileURLWithPath: "/etc/hosts")) == nil)
}

@Test func inboxSkipsHiddenFoldersAndFilesStillBeingWritten() throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    let old = try dir.write("99-Pendiente/b-viejo.pdf")
    let fresh = try dir.write("99-Pendiente/a-copiandose.pdf")
    try dir.write("99-Pendiente/.DS_Store")
    let sub = try dir.mkdir("99-Pendiente/subcarpeta")
    let now = Date()
    try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-10)], ofItemAtPath: old.path)
    try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-0.5)], ofItemAtPath: fresh.path)

    let listing = try ws.inboxFiles(stableFor: 2, now: now)
    #expect(listing.ready.map(\.lastPathComponent) == ["b-viejo.pdf"])
    #expect(listing.inUse.map(\.lastPathComponent) == ["a-copiandose.pdf"])
    #expect(listing.ignoredFolders.map(\.lastPathComponent) == [sub.lastPathComponent])
}

@Test func archiveFilesExcludeInboxDuplicatesStateAndRules() throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    try dir.write("99-Pendiente/nuevo.pdf")
    try dir.write("98-Duplicados/dup.pdf")
    try dir.write(".tria/cache/x.json")
    try dir.write("1-Modelos Tributarios/Modelo 303 - IVA/Modelo 303 - 2023 - 1T.pdf", "abc")
    try dir.write("7-Facturas/2013/1T/f.pdf")
    let files = try ws.archiveFiles().map(\.relativePath).sorted()
    #expect(files == ["1-Modelos Tributarios/Modelo 303 - IVA/Modelo 303 - 2023 - 1T.pdf", "7-Facturas/2013/1T/f.pdf"])
    #expect(try ws.archiveFiles().first { $0.relativePath.hasPrefix("1-") }?.size == 3)
}

@Test func scannerHonoursMaxDepth() throws {
    let dir = try TempDir()
    try dir.write("a/b/c/d/e/deep.pdf")
    try dir.write("a/b/shallow.pdf")
    let files = try ArchiveScanner.files(in: dir.url, maxDepth: 3).map(\.relativePath)
    #expect(files == ["a/b/shallow.pdf"])
}

@Test func openWithExternalRulesDoesNotWriteIntoTheArchive() throws {
    let archive = try TempDir()
    try archive.mkdir("7-Facturas/Recibidas")
    let elsewhere = try TempDir()
    let rulesURL = try elsewhere.write("reglas.md", WorkspaceFixture.defaultRules)
    let ws = try Workspace.open(at: archive.url, rulesFile: rulesURL)
    #expect(ws.rules.header.inbox == "99-Pendiente")
    #expect(!FileManager.default.fileExists(atPath: archive.url.appendingPathComponent("TRIA.md").path))
}

@Test func finderCopiesInProgressStayInUse() throws {   // Review Focus 1: el Finder marca la copia en curso con fecha 24/1/1984
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    let copying = try dir.write("99-Pendiente/copiandose.pdf")
    let busy = Calendar.current.date(from: DateComponents(year: 1984, month: 1, day: 24, hour: 9))!
    try FileManager.default.setAttributes([.modificationDate: busy], ofItemAtPath: copying.path)
    #expect(try ws.inboxFiles(stableFor: 0.1).inUse.map(\.lastPathComponent) == ["copiandose.pdf"])
}

@Test func filesDatedInTheFutureAreReadyOnceTheirSizeIsStable() throws {   // reloj desajustado de un NAS
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    let skewed = try dir.write("99-Pendiente/nas.pdf")
    try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(86_400)], ofItemAtPath: skewed.path)
    #expect(try ws.inboxFiles(stableFor: 0.1).ready.map(\.lastPathComponent) == ["nas.pdf"])
}

@Test func withoutAProfileTheContextHashIsTheRulesHash() throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    #expect(ws.profile == nil)
    #expect(ws.contextHash == ws.rules.hash)
}

@Test func theProfileIsReadAndChangesTheContextHash() throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    let saved = try ws.saveProfile(Profile(kind: .sl, name: "EMPRESA EJEMPLO SL", taxID: "B00000000"), language: .es)
    #expect(saved.profile?.profile.name == "EMPRESA EJEMPLO SL")
    #expect(try Workspace.open(at: dir.url).profile?.profile.taxID == "B00000000")
    #expect(saved.contextHash != ws.rules.hash)
    let changed = try saved.saveProfile(Profile(kind: .sl, name: "OTRA EJEMPLO SL", taxID: "B00000000"), language: .es)
    #expect(changed.contextHash != saved.contextHash)
    #expect(dir.url.appendingPathComponent("PERFIL.md") == saved.profileURL)
}

@Test func aBrokenProfileStopsTheWorkspace() throws {
    let dir = try TempDir()
    _ = try WorkspaceFixture.make(in: dir)
    try dir.write("PERFIL.md", "---\nkind: empresa\n---\n")
    #expect(throws: WorkspaceError.profile(.unknownKind("empresa", line: 2))) { try Workspace.open(at: dir.url) }
}

@Test func theProfileIsNotADocument() throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    _ = try ws.saveProfile(Profile(kind: .hogar), language: .es)
    try dir.write("Clientes/PERFIL.md", "un documento que se llama así")
    let files = try ws.archiveFiles().map(\.relativePath)
    #expect(!files.contains("PERFIL.md"))
    #expect(files.contains("Clientes/PERFIL.md"))
    #expect(Workspace.isSpaceFile("PERFIL.md") && Workspace.isSpaceFile("perfil.md") && Workspace.isSpaceFile("TRIA.md"))
    #expect(!Workspace.isSpaceFile("Clientes/PERFIL.md"))
}

@Test func theProfileStaysOutOfTheTreeAndOfLearning() throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    _ = try ws.saveProfile(Profile(kind: .sl, name: "EMPRESA EJEMPLO SL"), language: .es)
    try dir.write("7-Facturas/Recibidas/Factura Luz - 2025-01-10.txt", "Factura de luz")
    #expect(!(try ws.folderTree()).contains("PERFIL"))
    let plan = try RulesLearner(provider: ScriptedProvider { _ in "" }).plan(root: dir.url)
    #expect(!plan.samples.contains { $0.relativePath.contains("PERFIL") })
}

@Test func initializeWithABrokenProfileThrowsAndWritesNothing() throws {
    let dir = try TempDir()
    try dir.write("PERFIL.md", "---\nkind: empresa\n---\n")
    #expect {
        try Workspace.initialize(at: dir.url, rulesText: WorkspaceFixture.defaultRules)
    } throws: { error in
        if case WorkspaceError.profile = error { return true }
        return false
    }
    #expect(!FileManager.default.fileExists(atPath: dir.url.appendingPathComponent("TRIA.md").path))
}

@Test func filesOnlyInTheCloudWaitAsInUse() throws {   // spec de la app, §7 y §12
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    let now = Date()
    for name in ["en-la-nube.pdf", "local.pdf"] {
        let url = try dir.write("99-Pendiente/\(name)")
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-60)], ofItemAtPath: url.path)
    }

    let listing = try ws.inboxFiles(stableFor: 2, now: now, isDownloaded: { $0.lastPathComponent != "en-la-nube.pdf" })

    #expect(listing.ready.map(\.lastPathComponent) == ["local.pdf"])
    #expect(listing.inUse.map(\.lastPathComponent) == ["en-la-nube.pdf"])
}

@Test func aLocalFileIsDownloaded() throws {
    let dir = try TempDir()
    let file = try dir.write("99-Pendiente/local.pdf")
    #expect(Workspace.isDownloaded(file))
}
