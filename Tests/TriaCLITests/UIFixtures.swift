import Foundation
@testable import TriaCLI
@testable import TriaKit

/// Documentos inventados para las piezas de la interfaz.
enum UIFixtures {
    static let inbox = "99-Pendiente"

    static func proposal(_ name: String, _ destination: String, confidence: Confidence = .high,
                         reason: String = "Factura de Papelería Mar del 5 de octubre.", doubt: String? = nil,
                         undone: Bool = false) -> SortItem {
        let proposal = Proposal(action: .file, destination: (destination as NSString).deletingLastPathComponent,
                                filename: (destination as NSString).lastPathComponent, documentType: "Factura",
                                documentDate: nil, confidence: confidence, reason: reason, doubt: doubt)
        return item(name, .proposal(proposal, FilingAction(kind: .file, source: "\(inbox)/\(name)",
                                                           destination: destination)), undone: undone)
    }

    static func duplicate(_ name: String, of original: String) -> SortItem {
        item(name, .duplicate(original: original, FilingAction(kind: .duplicate, source: "\(inbox)/\(name)",
                                                               destination: "98-Duplicados/\(name)")))
    }

    static func pending(_ name: String, _ reason: PendingReason) -> SortItem {
        item(name, .pending(nil, reason))
    }

    static func plan(_ items: [SortItem], model: String = "claude-haiku-5-5") -> SortPlan {
        SortPlan(items: items, inUse: [], ignoredFolders: [], usage: .zero, provider: .anthropic, model: model,
                 reconciled: [])
    }

    /// Las cinco filas del boceto de la spec (§5).
    static let mockup: [SortItem] = [
        proposal("scan_0012.pdf", "2-Facturas Recibidas/2026/4T/Factura Papeleria Mar - 2026-10-05.pdf"),
        proposal("scan_0013.pdf", "2-Facturas Recibidas/2026/3T/Factura Imprenta Litoral - 2026-09-12.pdf",
                 reason: "Factura de Imprenta Litoral de septiembre."),
        proposal("nota.pdf", "6-Varios/Nota.pdf", confidence: .low, reason: "Una nota escrita a mano.",
                 doubt: "No queda claro qué es: parece una nota suelta."),
        duplicate("descarga (2).pdf", of: "5-Bancos/descarga.pdf"),
        pending("IMG_4471.jpg", .unreadable("no text")),
    ]

    private static func item(_ name: String, _ kind: SortItem.Kind, undone: Bool = false) -> SortItem {
        SortItem(file: URL(fileURLWithPath: "/tmp/Despacho/\(inbox)/\(name)"), relativePath: "\(inbox)/\(name)",
                 sha256: "sha-\(name)", kind: kind, undoneBefore: undone)
    }
}
