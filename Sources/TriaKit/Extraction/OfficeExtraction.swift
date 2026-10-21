import AppKit
import CoreXLSX
import Foundation

extension DocumentExtractor {
    func extractRichText(_ url: URL) throws -> ExtractedDocument {
        do {
            let attributed = try NSAttributedString(url: url, options: [:], documentAttributes: nil)
            return ExtractedDocument(text: Self.tidy(attributed.string, limit: limits.maxCharacters),
                                     pageCount: nil, method: .converted)
        } catch {
            throw ExtractionError.unreadable(url.pathExtension.lowercased())
        }
    }

    func extractSpreadsheet(_ url: URL) throws -> ExtractedDocument {
        guard let file = XLSXFile(filepath: url.path) else { throw ExtractionError.unreadable("xlsx") }
        do {
            let shared = try file.parseSharedStrings()
            var sections: [String] = []
            for workbook in try file.parseWorkbooks() {
                for (name, path) in try file.parseWorksheetPathsAndNames(workbook: workbook) {
                    let worksheet = try file.parseWorksheet(at: path)
                    let rows = (worksheet.data?.rows ?? []).map { row in
                        row.cells.map { cell -> String in
                            if let shared, let value = cell.stringValue(shared) { return value }
                            return cell.value ?? ""
                        }.joined(separator: "\t")
                    }
                    sections.append("## \(name ?? "Sheet")\n" + rows.joined(separator: "\n"))
                }
            }
            return ExtractedDocument(text: Self.tidy(sections.joined(separator: "\n\n"), limit: limits.maxCharacters),
                                     pageCount: nil, method: .spreadsheet)
        } catch {
            throw ExtractionError.unreadable("xlsx")
        }
    }

    func extractPlainText(_ url: URL) throws -> ExtractedDocument {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .windowsCP1252)
                ?? String(data: data, encoding: .isoLatin1) else {
            throw ExtractionError.unreadable(url.pathExtension.lowercased())
        }
        return ExtractedDocument(text: Self.tidy(text, limit: limits.maxCharacters), pageCount: nil, method: .plainText)
    }
}
