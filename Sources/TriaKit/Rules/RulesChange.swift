import Foundation

/// Una línea de la vista previa de un cambio de reglas.
public enum RulesDiffLine: Equatable, Sendable {
    case same(String)
    case removed(String)
    case added(String)
}

/// Lo que cambia en la cabecera o en una sección de `TRIA.md`, línea a línea (spec de Reglas, §4.1).
public struct RulesSectionDiff: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case header
        case changed
        case added
    }

    public var kind: Kind
    /// El título de la sección («Carpetas»); vacío en la cabecera.
    public var title: String
    public var lines: [RulesDiffLine]

    public init(kind: Kind, title: String, lines: [RulesDiffLine]) {
        self.kind = kind
        self.title = title
        self.lines = lines
    }

    /// Si hay alguna línea quitada o añadida.
    var changesLines: Bool {
        lines.contains { if case .same = $0 { false } else { true } }
    }

    /// Lo que cambia de `old` a `new`: la cabecera y cada sección, por posición. Un cambio nunca borra ni reordena
    /// secciones (spec, §12). Lo que solo cambia en las líneas vacías del final no cuenta: es el hueco que se deja
    /// antes de una sección nueva.
    public static func between(_ old: RulesDocument, _ new: RulesDocument) -> [RulesSectionDiff] {
        var result: [RulesSectionDiff] = []
        if trimmed(old.frontmatter) != trimmed(new.frontmatter) {
            result.append(RulesSectionDiff(kind: .header, title: "",
                                           lines: lines(from: old.frontmatter, to: new.frontmatter)))
        }
        for (index, section) in new.sections.enumerated() {
            guard index < old.sections.count else {
                result.append(RulesSectionDiff(kind: .added, title: section.title, lines: lines(from: "", to: section.text)))
                continue
            }
            let before = old.sections[index]
            guard trimmed(before.text) != trimmed(section.text) else { continue }
            result.append(RulesSectionDiff(kind: .changed, title: section.title,
                                           lines: lines(from: before.text, to: section.text)))
        }
        return result
    }

    /// Diferencia por líneas con la subsecuencia común más larga: las secciones son cortas.
    static func lines(from old: String, to new: String) -> [RulesDiffLine] {
        let a = split(old), b = split(new)
        var common = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                common[i][j] = a[i] == b[j] ? common[i + 1][j + 1] + 1 : max(common[i + 1][j], common[i][j + 1])
            }
        }
        var result: [RulesDiffLine] = []
        var i = 0, j = 0
        while i < a.count && j < b.count {
            if a[i] == b[j] {
                result.append(.same(a[i]))
                i += 1
                j += 1
            } else if common[i + 1][j] >= common[i][j + 1] {
                result.append(.removed(a[i]))
                i += 1
            } else {
                result.append(.added(b[j]))
                j += 1
            }
        }
        result += a[i...].map(RulesDiffLine.removed) + b[j...].map(RulesDiffLine.added)
        return result
    }

    /// Las líneas, sin saltos y sin las vacías del final.
    static func split(_ text: String) -> [String] {
        var lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeLast() }
        return lines
    }

    private static func trimmed(_ text: String) -> String { split(text).joined(separator: "\n") }
}

public enum RulesChangeError: Error, Equatable, Sendable {
    /// `TRIA.md` ya no es el del cambio: alguien lo ha cambiado desde que se preparó.
    case changedOnDisk
    /// El CLI u otro Mac está ordenando el espacio.
    case locked
    /// Lo está ordenando este mismo proceso (la app, a la vez): no es el CLI ni otro Mac.
    case lockedByThisProcess
    case unknownSection(String)
    /// Una sección editada que queda vacía: borrar una sección se hace en el editor (spec, §12).
    case emptySection
    /// El texto no empieza por una línea «## »: la primera línea con algo, contando desde 1.
    case missingTitle(line: Int)
    /// Hay otra línea «## »: la línea donde empezaría la segunda sección, contando desde 1.
    case notOneSection(line: Int)
    /// Un bloque de código («```» o «~~~») que no se cierra: la línea donde se abre, contando desde 1. Al volver a leer
    /// `TRIA.md`, se tragaría las secciones de detrás.
    case unclosedCodeBlock(line: Int)
    /// El `TRIA.md` resultante no se puede leer.
    case invalidRules(RulesError)
    /// Una carpeta que quedaría fuera del espacio.
    case unsafeFolder(String)
    /// `protected` cubriría la bandeja o la carpeta de duplicados (lo que avisa `tria rules check`).
    case inboxProtected
    case duplicatesProtected
    /// El cambio deja `TRIA.md` como estaba.
    case noChange
}

/// Un cambio de reglas pendiente, venga de donde venga (spec de Reglas, §4.1): se prepara, se enseña y se aplica con
/// `Workspace.apply(_:)`.
public struct RulesChange: Equatable, Sendable {
    /// El hash de `TRIA.md` cuando se preparó el cambio.
    public var baseHash: String
    /// `TRIA.md` entero tal como quedará.
    public var newText: String
    /// Rutas relativas a la raíz del espacio.
    public var createFolders: [String]
    /// Una frase: qué cambia. Vacío salvo en «pídeselo a Tria».
    public var summary: String
    public var preview: [RulesSectionDiff]

    public init(baseHash: String, newText: String, createFolders: [String] = [], summary: String = "",
                preview: [RulesSectionDiff]) {
        self.baseHash = baseHash
        self.newText = newText
        self.createFolders = createFolders
        self.summary = summary
        self.preview = preview
    }

    /// Una sección editada a mano: el texto nuevo empieza por su línea `## ` (o por otra) y no lleva otra sección.
    public static func editing(section id: String, newText: String, in workspace: Workspace) throws -> RulesChange {
        let document = RulesDocument.parse(workspace.rules.raw)
        guard document.section(id) != nil else { throw RulesChangeError.unknownSection(id) }
        let text = try oneSection(newText)
        guard let edited = document.replacing(id, with: text) else { throw RulesChangeError.unknownSection(id) }
        return try make(from: workspace, to: edited)
    }

    /// La cabecera desde el formulario: solo cambian `new_folders` y `protected`; `inbox` y `duplicates` se quedan. Se
    /// reescribe con `RulesFile.render` (los comentarios de dentro de la cabecera se pierden); el resto, igual.
    public static func header(newFolders: NewFoldersPolicy, protected: [String],
                              in workspace: Workspace) throws -> RulesChange {
        guard let header = workspace.rules.header.updating(newFolders: newFolders, protected: protected) else {
            throw RulesChangeError.noChange
        }
        if header.protectsInbox { throw RulesChangeError.inboxProtected }
        if header.protectsDuplicates { throw RulesChangeError.duplicatesProtected }
        let document = RulesDocument.parse(workspace.rules.raw)
            .replacingFrontmatter(RulesFile.render(header: header, body: ""))
        return try make(from: workspace, to: document)
    }

    /// De lo que hay en `workspace` a `document`: valida el resultado y calcula la vista previa. Lo que se escribe tiene
    /// que volver a leerse con las mismas secciones: si no (un bloque de código abierto se tragaría las de detrás, por
    /// ejemplo una sección nueva tras un `TRIA.md` escrito a mano que acaba con uno), `unclosedCodeBlock` con la línea
    /// del bloque dentro de su sección. Un cambio que la vista previa no enseñaría (solo líneas en blanco del final) y no
    /// crea carpetas es `noChange`.
    static func make(from workspace: Workspace, to document: RulesDocument, createFolders: [String] = [],
                     summary: String = "") throws -> RulesChange {
        let old = RulesDocument.parse(workspace.rules.raw)
        guard document.text != old.text || !createFolders.isEmpty else { throw RulesChangeError.noChange }
        if let lost = document.firstLostSection() {
            let before = lost == 0 ? document.preamble : document.sections[lost - 1].text
            throw RulesChangeError.unclosedCodeBlock(line: RulesDocument.openFenceLine(before) ?? 1)
        }
        do { _ = try RulesFile.parse(document.text) } catch let error as RulesError {
            throw RulesChangeError.invalidRules(error)
        }
        let preview = RulesSectionDiff.between(old, document)
        guard preview.contains(where: \.changesLines) || !createFolders.isEmpty else { throw RulesChangeError.noChange }
        return RulesChange(baseHash: workspace.rules.hash, newText: document.text, createFolders: createFolders,
                           summary: summary, preview: preview)
    }

    /// El texto de una sección, sin las líneas en blanco de delante, si es una sola sección: empieza por `## `, no
    /// lleva otra línea `## ` fuera de un bloque de código y cierra los bloques que abre (uno abierto se tragaría las
    /// secciones de detrás al volver a leer `TRIA.md`). Si no, el error dice en qué línea del texto escrito.
    static func oneSection(_ text: String) throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw RulesChangeError.emptySection }
        var lines = RulesDocument.lines(text)
        var skipped = 0
        while let first = lines.first, first.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.removeFirst()
            skipped += 1
        }
        let cleaned = lines.joined()
        let document = RulesDocument.parse(cleaned)
        guard document.frontmatter.isEmpty, document.preamble.isEmpty, let first = document.sections.first else {
            throw RulesChangeError.missingTitle(line: skipped + 1)
        }
        guard document.sections.count == 1 else {
            throw RulesChangeError.notOneSection(line: skipped + RulesDocument.lines(first.text).count + 1)
        }
        if let line = RulesDocument.openFenceLine(cleaned) {
            throw RulesChangeError.unclosedCodeBlock(line: skipped + line)
        }
        return cleaned
    }
}

extension RulesHeader {
    /// La cabecera con otra política de carpetas nuevas y otros patrones protegidos (sin los espacios de alrededor ni
    /// los vacíos); `inbox` y `duplicates` se quedan. `nil` si no cambia nada: los patrones se comparan ya normalizados.
    public func updating(newFolders: NewFoldersPolicy, protected: [String]) -> RulesHeader? {
        let patterns = protected.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard newFolders != self.newFolders
                || ProtectedPaths(patterns).patterns != ProtectedPaths(self.protected).patterns else { return nil }
        var header = self
        header.newFolders = newFolders
        header.protected = patterns
        return header
    }

    /// Si `protected` cubre la bandeja o la carpeta de duplicados, con la misma comprobación que el aviso de
    /// `tria rules check`: Tria ya no podría dejar nada en ellas.
    var protectsInbox: Bool { ProtectedPaths(protected).contains(inbox) }
    var protectsDuplicates: Bool { ProtectedPaths(protected).contains(duplicates) }
}
