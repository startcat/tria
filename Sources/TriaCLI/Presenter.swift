import Foundation
import TriaKit

enum Presenter {
    static func confidence(_ confidence: Confidence, _ env: CLIEnvironment) -> String {
        switch confidence {
        case .high: return env.t(.confHigh)
        case .medium: return env.t(.confMedium)
        case .low: return env.t(.confLow)
        }
    }

    static func reason(_ reason: PendingReason, _ env: CLIEnvironment) -> String {
        switch reason {
        case .modelDoubt(let doubt): return doubt
        case .invalidProposal(let feedback): return env.t(.pendInvalid, feedback)
        case .unreadable(let detail): return env.t(.pendUnreadable, detail)
        case .unsupported(let ext): return env.t(.pendUnsupported, ext)
        case .encrypted: return env.t(.pendEncrypted)
        case .refused: return env.t(.pendRefused)
        case .offline: return env.t(.pendOffline)
        case .paused(let message): return env.t(.pendPaused, message)
        case .providerError(let message): return env.t(.pendProvider, message)
        case .held: return env.t(.pendHeld)
        }
    }

    /// Verde lo que se puede aplicar sin mirar; ámbar lo que pide una mirada.
    static func role(_ confidence: Confidence) -> StyleRole {
        confidence == .high ? .success : .warning
    }

    /// La ficha de un documento (spec CLI §4), con las líneas debajo del nombre:
    ///
    ///      1/9  scan_0012.pdf
    ///           → 2-Facturas Recibidas/2026/4T/Factura Papeleria Mar - 2026-10-05.pdf
    ///           ● Confianza alta · Factura de Papelería Mar del 5 de octubre.
    ///
    /// Con el ancho del terminal, el nombre se recorta por el medio y lo demás se parte en varias líneas, debajo del
    /// texto que sigue al símbolo: lo que se aprueba se ve entero. Se parte antes de pintar. Sin ancho (una tubería),
    /// cada cosa va en su línea, sin partir.
    static func card(_ item: SortItem, index: Int, total: Int, _ env: CLIEnvironment, style: Style) -> [String] {
        let clean = TextWidth.singleLine
        let counterWidth = 2 * String(total).count + 1
        let indent = String(repeating: " ", count: counterWidth + 3)
        let width = env.terminal.capabilities.size?.columns
        /// `text` partido: la primera línea la arma `first` y las demás van dos columnas más adentro, con `role`.
        func block(_ text: String, path: Bool = false, role: StyleRole?, first: (String) -> String) -> [String] {
            let parts = width.map { TextWidth.wrap(text, width: max(1, $0 - indent.count - 2), path: path) } ?? [text]
            return [indent + first(parts.first ?? "")]
                + parts.dropFirst().map { part in indent + "  " + (role.map { style.paint(part, $0) } ?? part) }
        }
        let name = clean(item.file.lastPathComponent)
        var lines = [" " + TextWidth.padLeft("\(index)/\(total)", to: counterWidth) + "  "
                     + style.paint(width.map { TextWidth.truncateMiddle(name, to: max(1, $0 - indent.count)) } ?? name,
                                   .strong)]
        switch item.kind {
        case .proposal(let proposal, let action):
            let arrow = env.t(.itemProposal, "")
            lines += block(clean(action.destination), path: true, role: .accent) { style.paint(arrow + $0, .accent) }
            let label = env.t(.itemConfidence, confidence(proposal.confidence, env), "")
            lines += block(label + clean(proposal.reason), role: nil) {
                style.paint("●", role(proposal.confidence)) + " " + $0
            }
            if proposal.confidence != .high, let doubt = proposal.doubt {
                lines += block(env.t(.itemDoubt, clean(doubt)), role: .warning) { style.paint($0, .warning) }
            }
        case .duplicate(let original, let action):
            lines += block(env.t(.itemDuplicate, clean(original), clean(action.destination)), path: true, role: .warning) {
                style.paint("≡ " + $0, .warning)
            }
        case .pending(_, let reason):
            lines += block(env.t(.itemPending, clean(self.reason(reason, env))), role: .warning) {
                style.paint("○ " + $0, .warning)
            }
        }
        if item.undoneBefore {
            lines += block(env.t(.itemUndone), role: .muted) { style.paint("↺ " + $0, .muted) }
        }
        return lines
    }

    /// «5 listos · 2 con duda · 1 duplicado · 1 pendiente» (spec CLI §4). Lo que no hay no se nombra.
    static func summary(_ plan: SortPlan, _ env: CLIEnvironment, style: Style) -> String {
        var ready = 0, doubtful = 0, duplicates = 0, pending = 0
        for item in plan.items {
            switch item.kind {
            case .proposal(let proposal, _): if proposal.confidence == .high { ready += 1 } else { doubtful += 1 }
            case .duplicate: duplicates += 1
            case .pending: pending += 1
            }
        }
        var parts: [String] = []
        if ready > 0 { parts.append(style.paint(L10n.count(ready, .summaryReadyOne, .summaryReadyMany, env.lang), .success)) }
        if doubtful > 0 { parts.append(style.paint(L10n.count(doubtful, .summaryDoubt, .summaryDoubt, env.lang), .warning)) }
        if duplicates > 0 {
            parts.append(style.paint(L10n.count(duplicates, .summaryDuplicateOne, .summaryDuplicateMany, env.lang), .warning))
        }
        if pending > 0 {
            parts.append(style.paint(L10n.count(pending, .summaryPendingOne, .summaryPendingMany, env.lang), .warning))
        }
        return parts.joined(separator: " · ")
    }

    /// La cabecera de `tria sort`, en gris: «Tria · Despacho · Anthropic claude-haiku-5-5». El nombre de la carpeta y el
    /// modelo van sin caracteres de control.
    static func header(workspace: String, provider: ProviderID, model: String, style: Style) -> String {
        let clean = TextWidth.singleLine
        return style.paint("Tria · \(clean(workspace)) · \(providerName(provider)) \(clean(model))", .muted)
    }

    static func providerName(_ provider: ProviderID) -> String {
        switch provider {
        case .anthropic: return "Anthropic"
        case .openai: return "OpenAI"
        }
    }

    static func cost(_ usage: TokenUsage, model: String, _ env: CLIEnvironment, style: Style = .plain) -> String {
        style.paint(env.t(.costLine, String(usage.inputTokens), String(usage.outputTokens),
                          String(usage.cacheReadTokens), L10n.money(Pricing.cost(usage, model: model), env.lang)),
                    .muted)
    }

    /// «✓ Movidos: 3 · fallidos: 0 · lote …» en verde, y cada fallo con ✗ en rojo (spec CLI §4).
    static func applied(_ report: ApplyReport, _ env: CLIEnvironment, style: Style) -> [String] {
        [style.paint("✓ " + env.t(.applied, String(report.applied.count), String(report.failed.count),
                                  TextWidth.singleLine(report.batch)),
                     .success)]
            + report.failed.map {
                "  " + style.paint("✗ " + env.t(.failedMove, TextWidth.singleLine($0.source), TextWidth.singleLine($0.message)),
                                   .danger)
            }
    }

    /// «✓ texto», con la marca en verde.
    static func done(_ text: String, style: Style) -> String {
        style.paint("✓", .success) + " " + text
    }

    /// «✓ 9 documentos leídos en 12 s (6 sin gastar: ya estaban leídos)» (spec CLI §4). Sin documentos, nada.
    static func readingDone(_ plan: SortPlan, seconds: Int, cached: Int, _ env: CLIEnvironment, style: Style) -> String? {
        guard !plan.items.isEmpty else { return nil }
        let read = done(L10n.count(plan.items.count, .readDoneOne, .readDoneMany, env.lang, String(seconds)), style: style)
        guard cached > 0 else { return read }
        return read + " " + style.paint(env.t(.readCached, String(cached)), .muted)
    }

    /// La bandeja como tabla (spec CLI §4): «nombre:» y el estado alineado y en color. Sin procesar en gris, propuesta
    /// en acento, y duplicado y pendiente en ámbar. Nombres y estados, sin caracteres de control.
    static func status(_ items: [StatusItem], _ env: CLIEnvironment, style: Style) -> [String] {
        func name(_ item: StatusItem) -> String { TextWidth.singleLine(item.file.lastPathComponent) }
        let width = items.map { TextWidth.columns(name($0)) + 1 }.max() ?? 0
        return items.map { item in
            let text: String
            let role: StyleRole
            switch item.state {
            case .unprocessed:
                text = env.t(.statusUnprocessed)
                role = .muted
            case .inUse:
                text = env.t(.statusInUse)
                role = .muted
            case .duplicate(let original):
                text = env.t(.statusDuplicate, original)
                role = .warning
            case .proposed(let proposal, let destination):
                text = env.t(.statusProposed, destination, confidence(proposal.confidence, env))
                role = .accent
            case .pending(_, let reason):
                text = env.t(.statusPending, self.reason(reason, env))
                role = .warning
            }
            return TextWidth.pad(name(item) + ":", to: width) + " " + style.paint(TextWidth.singleLine(text), role)
        }
    }

    /// Cada lote: el id, la fecha en acento y las cifras alineadas (spec CLI §4).
    static func batches(_ batches: [BatchSummary], _ env: CLIEnvironment, style: Style) -> [String] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        func width(_ value: (BatchSummary) -> Int) -> Int { batches.map { String(value($0)).count }.max() ?? 0 }
        let done = width(\.done), undone = width(\.undone), failed = width(\.failed)
        return batches.map { batch in
            env.t(.logBatch, TextWidth.singleLine(batch.id), style.paint(formatter.string(from: batch.startedAt), .accent),
                  TextWidth.padLeft(String(batch.done), to: done), TextWidth.padLeft(String(batch.undone), to: undone),
                  TextWidth.padLeft(String(batch.failed), to: failed))
        }
    }

    /// Una operación de un lote, con su símbolo en color.
    static func operation(_ operation: JournalOperation, _ env: CLIEnvironment, style: Style) -> String {
        let symbol: String
        let role: StyleRole
        switch operation.state {
        case .done:
            symbol = "✓"
            role = .success
        case .failed:
            symbol = "✗"
            role = .danger
        case .undone:
            symbol = "↺"
            role = .muted
        case .intent:
            symbol = "…"
            role = .warning
        }
        return env.t(.logOperation, style.paint(symbol, role), TextWidth.singleLine(operation.from),
                     TextWidth.singleLine(operation.to))
    }

    /// Las teclas de una pregunta, resaltadas: «[s] aplicar · [e] editar…». Solo los corchetes con una letra.
    static func keys(_ prompt: String, style: Style) -> String {
        guard style.depth != .none else { return prompt }
        var result = ""
        var rest = Substring(prompt)
        while let open = rest.firstIndex(of: "[") {
            let letter = rest.index(after: open)
            let close = letter < rest.endIndex ? rest.index(after: letter) : rest.endIndex
            guard close < rest.endIndex, rest[close] == "]" else {
                result += String(rest[...open])
                rest = rest[rest.index(after: open)...]
                continue
            }
            result += String(rest[..<open]) + "[" + style.paint(style.paint(String(rest[letter]), .accent), .strong) + "]"
            rest = rest[rest.index(after: close)...]
        }
        return result + String(rest)
    }

    /// El cambio de TRIA.md con las líneas añadidas en verde (spec CLI §4). Cada línea, sin caracteres de control.
    static func rulePreview(_ preview: String, style: Style) -> String {
        preview.components(separatedBy: "\n")
            .map(TextWidth.singleLine)
            .map { $0.hasPrefix("+ ") ? style.paint($0, .success) : $0 }
            .joined(separator: "\n")
    }

    /// Un cambio de reglas (spec de Reglas, §5): por cada parte que cambia, sus líneas (las que salen en rojo con «- »,
    /// las que entran en verde con «+ » y las demás con dos espacios), «Cabecera» delante de la cabecera, y al final
    /// «Se creará la carpeta …». Cada línea, sin caracteres de control.
    static func rulesChange(_ change: RulesChange, _ env: CLIEnvironment, style: Style) -> String {
        var lines: [String] = []
        for diff in change.preview {
            if !lines.isEmpty { lines.append("") }
            if diff.kind == .header { lines.append(style.paint(env.t(.rulesAskHeader), .strong)) }
            for line in diff.lines {
                switch line {
                case .same(let text): lines.append("  " + TextWidth.singleLine(text))
                case .removed(let text): lines.append(style.paint("- " + TextWidth.singleLine(text), .danger))
                case .added(let text): lines.append(style.paint("+ " + TextWidth.singleLine(text), .success))
                }
            }
        }
        if !change.createFolders.isEmpty, !lines.isEmpty { lines.append("") }
        for folder in change.createFolders {
            lines.append(style.paint(env.t(.rulesAskCreateFolder, TextWidth.singleLine(folder)), .accent))
        }
        return lines.joined(separator: "\n")
    }
}

/// Salida de `tria sort --json`.
struct SortOutput: Encodable {
    struct Item: Encodable {
        var file: String
        var status: String
        var destination: String?
        var confidence: String?
        var reason: String?
        var doubt: String?
    }

    struct Move: Encodable {
        var from: String
        var to: String
    }

    var items: [Item]
    var applied: [Move]
    var failed: [Move]
    var model: String
    var usage: TokenUsage
    var cost: Double?
    var interrupted: String?

    init(plan: SortPlan, report: ApplyReport?, env: CLIEnvironment) {
        items = plan.items.map { item in
            switch item.kind {
            case .proposal(let proposal, let action):
                return Item(file: item.relativePath, status: "proposal", destination: action.destination,
                            confidence: proposal.confidence.rawValue, reason: proposal.reason, doubt: proposal.doubt)
            case .duplicate(let original, let action):
                return Item(file: item.relativePath, status: "duplicate", destination: action.destination,
                            confidence: nil, reason: original, doubt: nil)
            case .pending(let proposal, let reason):
                return Item(file: item.relativePath, status: "pending", destination: nil,
                            confidence: proposal?.confidence.rawValue, reason: Presenter.reason(reason, env), doubt: proposal?.doubt)
            }
        }
        applied = report?.applied.map { Move(from: $0.from, to: $0.to) } ?? []
        failed = report?.failed.map { Move(from: $0.source, to: $0.message) } ?? []
        model = plan.model
        usage = plan.usage
        cost = plan.cost
        interrupted = plan.interruption.map { String(describing: $0) }
    }
}
