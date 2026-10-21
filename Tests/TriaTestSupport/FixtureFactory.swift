import AppKit
import CoreText
import Foundation
import PDFKit

/// Genera documentos de prueba en tiempo de test: así el repo no lleva binarios ni documentos reales.
public enum FixtureFactory {
    public static func textPDF(at url: URL, pages: [String]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { throw CocoaError(.fileWriteUnknown) }
        for text in pages {
            context.beginPDFPage(nil)
            let attributed = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 12)])
            let framesetter = CTFramesetterCreateWithAttributedString(attributed)
            let path = CGPath(rect: box.insetBy(dx: 40, dy: 40), transform: nil)
            CTFrameDraw(CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil), context)
            context.endPDFPage()
        }
        context.closePDF()
    }

    public static func encryptedPDF(at url: URL, text: String) throws {
        let plain = url.deletingLastPathComponent().appendingPathComponent("plain-\(UUID().uuidString).pdf")
        try textPDF(at: plain, pages: [text])
        defer { try? FileManager.default.removeItem(at: plain) }
        guard let document = PDFDocument(url: plain),
              document.write(to: url, withOptions: [.userPasswordOption: "secret", .ownerPasswordOption: "owner"])
        else { throw CocoaError(.fileWriteUnknown) }
    }

    public static func richText(at url: URL, text: String, type: NSAttributedString.DocumentType) throws {
        let attributed = NSAttributedString(string: text)
        let data = try attributed.data(from: NSRange(location: 0, length: attributed.length),
                                       documentAttributes: [.documentType: type])
        try data.write(to: url)
    }

    /// xlsx mínimo (sharedStrings + una hoja) comprimido con /usr/bin/zip.
    public static func xlsx(at url: URL, sheetName: String, rows: [[String]]) throws {
        let staging = url.deletingLastPathComponent().appendingPathComponent("xlsx-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: staging) }
        func write(_ path: String, _ xml: String) throws {
            let target = staging.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try xml.write(to: target, atomically: true, encoding: .utf8)
        }
        let strings = Array(Set(rows.flatMap { $0 })).sorted()
        let index = Dictionary(uniqueKeysWithValues: strings.enumerated().map { ($1, $0) })
        let head = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"#
        let main = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
        let rel = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
        let pkg = "http://schemas.openxmlformats.org/package/2006/relationships"
        try write("[Content_Types].xml", head + #"<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/></Types>"#)
        try write("_rels/.rels", head + "<Relationships xmlns=\"\(pkg)\"><Relationship Id=\"rId1\" Type=\"\(rel)/officeDocument\" Target=\"xl/workbook.xml\"/></Relationships>")
        try write("xl/workbook.xml", head + "<workbook xmlns=\"\(main)\" xmlns:r=\"\(rel)\"><sheets><sheet name=\"\(sheetName)\" sheetId=\"1\" r:id=\"rId1\"/></sheets></workbook>")
        try write("xl/_rels/workbook.xml.rels", head + "<Relationships xmlns=\"\(pkg)\"><Relationship Id=\"rId1\" Type=\"\(rel)/worksheet\" Target=\"worksheets/sheet1.xml\"/><Relationship Id=\"rId2\" Type=\"\(rel)/sharedStrings\" Target=\"sharedStrings.xml\"/></Relationships>")
        try write("xl/sharedStrings.xml", head + "<sst xmlns=\"\(main)\" count=\"\(strings.count)\" uniqueCount=\"\(strings.count)\">"
                  + strings.map { "<si><t>\($0)</t></si>" }.joined() + "</sst>")
        let columns = Array("ABCDEFGHIJ")
        let sheetRows = rows.enumerated().map { r, row in
            "<row r=\"\(r + 1)\">" + row.enumerated().map { c, value in
                "<c r=\"\(columns[c])\(r + 1)\" t=\"s\"><v>\(index[value]!)</v></c>"
            }.joined() + "</row>"
        }.joined()
        try write("xl/worksheets/sheet1.xml", head + "<worksheet xmlns=\"\(main)\"><sheetData>\(sheetRows)</sheetData></worksheet>")

        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.currentDirectoryURL = staging
        zip.arguments = ["-q", "-r", "-X", url.path, "[Content_Types].xml", "_rels", "xl"]
        try zip.run()
        zip.waitUntilExit()
        guard zip.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
    }
}

import ImageIO
import UniformTypeIdentifiers

extension FixtureFactory {
    public static func textImage(lines: [String], width: Int = 1600, lineHeight: Int = 90) -> CGImage {
        let height = lineHeight * (lines.count + 1)
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        for (index, line) in lines.enumerated() {
            let attributed = NSAttributedString(string: line, attributes: [
                .font: NSFont.systemFont(ofSize: 44), .foregroundColor: NSColor.black])
            context.textPosition = CGPoint(x: 40, y: height - lineHeight * (index + 1))
            CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
        }
        return context.makeImage()!
    }

    public static func png(at url: URL, lines: [String]) throws {
        try writePNG(textImage(lines: lines), to: url)
    }

    public static func blankPNG(at url: URL, width: Int = 3000, height: Int = 2000) throws {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        try writePNG(context.makeImage()!, to: url)
    }

    /// PDF sin capa de texto: la página es una imagen (como un escaneo).
    public static func imageOnlyPDF(at url: URL, lines: [String]) throws {
        let image = textImage(lines: lines)
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { throw CocoaError(.fileWriteUnknown) }
        context.beginPDFPage(nil)
        let width = 515.0, height = width * Double(image.height) / Double(image.width)
        context.draw(image, in: CGRect(x: 40, y: 842 - 40 - height, width: width, height: height))
        context.endPDFPage()
        context.closePDF()
    }

    public static func blankPDF(at url: URL, pages: Int) throws {
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { throw CocoaError(.fileWriteUnknown) }
        for _ in 0..<pages { context.beginPDFPage(nil); context.endPDFPage() }
        context.closePDF()
    }

    private static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }
}
