import Foundation
import Testing
import TriaTestSupport
@testable import TriaKit

@Test func findsExactDuplicatesOfArchivedFiles() throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    try dir.write("7-Facturas/Recibidas/Factura Luz - 2025-01-10.pdf", "PDF-LUZ")
    try dir.write("7-Facturas/Recibidas/Otra.pdf", "PDF-XYZ")   // mismo tamaño, otro contenido
    let scan = try dir.write("99-Pendiente/scan.pdf", "PDF-LUZ")
    let result = try DuplicateFinder(workspace: ws).scan([scan])
    #expect(result.originals[scan] == "7-Facturas/Recibidas/Factura Luz - 2025-01-10.pdf")
    #expect(result.hashes[scan] == Hashing.sha256("PDF-LUZ"))
}

@Test func laterInboxCopiesPointToTheFirstOne() throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    let first = try dir.write("99-Pendiente/a.pdf", "MISMO")
    let second = try dir.write("99-Pendiente/b.pdf", "MISMO")
    let result = try DuplicateFinder(workspace: ws).scan([first, second])
    #expect(result.originals[first] == nil)
    #expect(result.originals[second] == "99-Pendiente/a.pdf")
}

@Test func emptyFilesAreNeverDuplicates() throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    try dir.write("7-Facturas/Recibidas/vacio.pdf", "")
    let empty = try dir.write("99-Pendiente/vacio.pdf", "")
    #expect(try DuplicateFinder(workspace: ws).scan([empty]).originals.isEmpty)
}

/// Sin nada que buscar (la bandeja vacía, o solo ficheros vacíos), el archivo no se recorre: en una unidad de red, la
/// vigilancia de la app lo haría en cada vuelta.
@Test func withNothingToLookForTheArchiveIsNotWalked() throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    try dir.write("7-Facturas/Recibidas/Factura Luz - 2025-01-10.pdf", "PDF-LUZ")
    let empty = try dir.write("99-Pendiente/vacio.pdf", "")
    let finder = DuplicateFinder(workspace: ws)
    var walks = 0
    let archive = { () throws -> [ArchiveFile] in
        walks += 1
        return try ws.archiveFiles()
    }

    _ = try finder.scan([], isDownloaded: { _ in true }, archiveFiles: archive)
    _ = try finder.scan([empty], isDownloaded: { _ in true }, archiveFiles: archive)
    #expect(walks == 0)

    let copy = try dir.write("99-Pendiente/scan.pdf", "PDF-LUZ")   // con algo que buscar, sí
    let found = try finder.scan([copy], isDownloaded: { _ in true }, archiveFiles: archive)
    #expect(found.originals[copy] == "7-Facturas/Recibidas/Factura Luz - 2025-01-10.pdf")
    #expect(walks == 1)
}

@Test func onlyHashesArchivedFilesOfTheSameSize() throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    let unreadable = try dir.write("7-Facturas/Recibidas/bloqueado.pdf", "contenido de otro tamaño")
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: unreadable.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: unreadable.path) }
    let inbox = try dir.write("99-Pendiente/x.pdf", "corto")
    #expect(try DuplicateFinder(workspace: ws).scan([inbox]).originals.isEmpty)
}

/// Un archivado que solo está en la nube no se lee para buscar repetidos: leerlo forzaría su descarga (spec de la app,
/// §7). El original y la copia tienen el mismo contenido, así que si se leyera, la copia saldría como repetido.
@Test func anArchivedOriginalOnlyInTheCloudIsNeverRead() throws {
    let dir = try TempDir()
    let ws = try WorkspaceFixture.make(in: dir)
    try dir.write("7-Facturas/Recibidas/Factura Luz - 2025-01-10.pdf", "PDF-LUZ")
    let copy = try dir.write("99-Pendiente/scan.pdf", "PDF-LUZ")
    var asked: [String] = []

    let inTheCloud = try DuplicateFinder(workspace: ws).scan([copy], isDownloaded: { url in
        asked.append(url.lastPathComponent)
        return url.lastPathComponent != "Factura Luz - 2025-01-10.pdf"
    })

    #expect(inTheCloud.originals[copy] == nil)
    #expect(inTheCloud.hashes[copy] == Hashing.sha256("PDF-LUZ"))
    #expect(asked == ["Factura Luz - 2025-01-10.pdf"])   // solo se pregunta por los archivados del mismo tamaño

    let downloaded = try DuplicateFinder(workspace: ws).scan([copy])
    #expect(downloaded.originals[copy] == "7-Facturas/Recibidas/Factura Luz - 2025-01-10.pdf")
}
