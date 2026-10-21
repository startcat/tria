import Foundation
import Yams

public enum ProfileError: Error, Equatable, Sendable {
    case missingFrontmatter
    /// `line` es la línea de `PERFIL.md`, contando desde 1, cuando se sabe.
    case invalidYAML(line: Int?, detail: String)
    case missingKind
    case unknownKind(String, line: Int?)
    case invalidValue(key: String, line: Int?)
}

public enum ProfileWarning: Equatable, Sendable {
    /// Una clave que Tria no conoce: se conserva y se envía.
    case unknownKey(String)
    /// Una clave conocida que no es del tipo (por ejemplo, `partners` en `autonomo`): se conserva y se envía.
    case notForKind(ProfileField)
}

/// `PERFIL.md`: cabecera YAML con los datos del titular y cuerpo con notas libres (spec del perfil, §2-3).
public struct ProfileFile: Sendable, Equatable {
    public static let fileName = "PERFIL.md"

    public let profile: Profile
    public let raw: String
    /// El idioma de los comentarios del fichero: al guardar se escriben en el mismo.
    public let language: TemplateLanguage
    public let warnings: [ProfileWarning]

    /// `PERFIL.md` de una carpeta; `nil` si no tiene.
    public static func read(in root: URL) throws -> ProfileFile? {
        guard let data = FileManager.default.contents(atPath: root.appendingPathComponent(fileName).path) else {
            return nil
        }
        return try parse(String(decoding: data, as: UTF8.self))
    }

    public static func parse(_ source: String) throws -> ProfileFile {
        var normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
        if normalized.hasPrefix("\u{FEFF}") { normalized.removeFirst() }
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let end = lines.dropFirst().firstIndex(where: { isClosingMarker($0) })
        else { throw ProfileError.missingFrontmatter }
        let yaml = lines[1..<end].joined(separator: "\n")
        let notes = lines[(end + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

        let root: Node?
        do { root = try Yams.compose(yaml: yaml) } catch { throw yamlError(error) }
        guard let root else { throw ProfileError.missingKind }
        guard case .mapping(let mapping) = root else {
            throw ProfileError.invalidYAML(line: fileLine(root.mark), detail: "la cabecera no es una lista de claves")
        }

        var kind: TemplateKind?
        var profile = Profile(kind: .autonomo)
        var warnings: [ProfileWarning] = []
        for (keyNode, value) in mapping {
            guard let key = keyNode.scalar?.string else {
                throw ProfileError.invalidValue(key: "?", line: fileLine(keyNode.mark))
            }
            switch ProfileField(rawValue: key) {
            case .name: profile.name = try scalarText(value, key: key)
            case .taxID: profile.taxID = try scalarText(value, key: key)
            case .tradeNames: profile.tradeNames = try items(value, key: key).compactMap { try scalarText($0, key: key) }
            case .partners:
                profile.partners = try pairs(value, key: key, "name", "tax_id").map { ProfilePerson(name: $0.0, taxID: $0.1) }
            case .clients:
                profile.clients = try pairs(value, key: key, "name", "short").map { ProfileClient(name: $0.0, short: $0.1) }
            case .banks:
                profile.banks = try pairs(value, key: key, "name", "account_end").map { ProfileBank(name: $0.0, accountEnd: $0.1) }
            case .members:
                profile.members = try pairs(value, key: key, "name", "tax_id").map { ProfilePerson(name: $0.0, taxID: $0.1) }
            case .vehicles:
                profile.vehicles = try pairs(value, key: key, "short", "plate").map { ProfileVehicle(short: $0.0, plate: $0.1) }
            case .homes:
                profile.homes = try pairs(value, key: key, "short", "address").map { ProfileHome(short: $0.0, address: $0.1) }
            case nil where key == "kind":
                guard let text = try scalarText(value, key: key) else { throw ProfileError.missingKind }
                guard let parsed = TemplateKind(rawValue: text) else {
                    throw ProfileError.unknownKind(text, line: fileLine(value.mark))
                }
                kind = parsed
            case nil:
                warnings.append(.unknownKey(key))
                profile.extras.append(ProfileExtra(key: key, yaml: try serialized(keyNode, value)))
            }
        }
        guard let kind else { throw ProfileError.missingKind }
        profile.kind = kind
        profile.notes = notes
        let own = ProfileField.fields(for: kind)
        warnings += ProfileField.allCases.filter { !own.contains($0) && profile.hasValue($0) }.map(ProfileWarning.notForKind)
        let language: TemplateLanguage = yaml.contains(ProfileComments.header(.ca)) ? .ca : .es
        return ProfileFile(profile: profile, raw: source, language: language, warnings: warnings)
    }

    /// `---` en la columna 0 (con espacios detrás permitidos): uno con sangría puede ser parte de un bloque de texto.
    private static func isClosingMarker(_ line: String) -> Bool {
        line.hasPrefix("---") && line.dropFirst(3).allSatisfy { $0 == " " || $0 == "\t" }
    }

    // MARK: - Lectura

    /// Un texto. Vacío, `~` o `null` sin comillas cuenta como sin valor. Se lee el texto tal cual: `0123` sigue
    /// siendo `0123`.
    private static func scalarText(_ node: Node, key: String) throws -> String? {
        guard case .scalar(let scalar) = node else {
            throw ProfileError.invalidValue(key: key, line: fileLine(node.mark))
        }
        if scalar.style == .plain, ["", "~", "null", "Null", "NULL"].contains(scalar.string) { return nil }
        let value = scalar.string.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// Una lista. Un solo valor cuenta como lista de uno, y uno vacío como lista vacía.
    private static func items(_ node: Node, key: String) throws -> [Node] {
        switch node {
        case .sequence(let sequence): return Array(sequence)
        case .scalar: return try scalarText(node, key: key) == nil ? [] : [node]
        default: throw ProfileError.invalidValue(key: key, line: fileLine(node.mark))
        }
    }

    /// Una lista de elementos con dos campos (`{ name: …, tax_id: … }`) o solo con el texto del primero. Un elemento
    /// sin el primero o con otras claves es un error: el formulario de la app no podría conservarlo.
    private static func pairs(_ node: Node, key: String, _ first: String, _ second: String) throws -> [(String, String?)] {
        try items(node, key: key).compactMap { item -> (String, String?)? in
            switch item {
            case .scalar:
                guard let text = try scalarText(item, key: key) else { return nil }
                return (text, nil)
            case .mapping(let mapping):
                var values: [String: String] = [:]
                for (field, value) in mapping {
                    guard let name = field.scalar?.string, name == first || name == second else {
                        throw ProfileError.invalidValue(key: key, line: fileLine(field.mark))
                    }
                    values[name] = try scalarText(value, key: key)
                }
                // `- { name: "", tax_id: "" }`: una fila vacía, como las que el formulario descarta.
                if values.isEmpty { return nil }
                guard let main = values[first] else {
                    throw ProfileError.invalidValue(key: key, line: fileLine(item.mark))
                }
                return (main, values[second])
            default:
                throw ProfileError.invalidValue(key: key, line: fileLine(item.mark))
            }
        }
    }

    private static func serialized(_ key: Node, _ value: Node) throws -> String {
        try Yams.serialize(node: .mapping(Node.Mapping([(key, value)])), allowUnicode: true)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// La línea en `PERFIL.md`: la cabecera YAML empieza en la segunda.
    private static func fileLine(_ mark: Mark?) -> Int? { mark.map { $0.line + 1 } }

    private static func yamlError(_ error: Error) -> ProfileError {
        if let error = error as? YamlError {
            switch error {
            case .scanner(_, let problem, let mark, _), .parser(_, let problem, let mark, _),
                 .composer(_, let problem, let mark, _):
                return .invalidYAML(line: fileLine(mark), detail: problem)
            default:
                break
            }
        }
        return .invalidYAML(line: nil, detail: String(describing: error))
    }
}

// MARK: - Escritura

extension ProfileFile {
    /// Siempre con la misma forma: los campos del tipo con su comentario, después los de otros tipos que tengan algo,
    /// las claves desconocidas tal cual y, debajo de la cabecera, las notas (spec del perfil, §3).
    public static func render(_ profile: Profile, language: TemplateLanguage) -> String {
        var lines = ["---", ProfileComments.header(language), ProfileComments.intro(language),
                     ProfileComments.kind(language), "kind: \(profile.kind.rawValue)"]
        let own = ProfileField.fields(for: profile.kind)
        for field in own {
            lines.append(ProfileComments.field(field, kind: profile.kind, language: language))
            lines += yamlLines(field, of: profile)
        }
        for field in ProfileField.allCases where !own.contains(field) && profile.hasValue(field) {
            lines += yamlLines(field, of: profile)
        }
        lines += profile.extras.map(\.yaml)
        lines += ["---", ""]
        let notes = profile.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return lines.joined(separator: "\n") + (notes.isEmpty ? "" : notes + "\n")
    }

    private static func yamlLines(_ field: ProfileField, of profile: Profile) -> [String] {
        let key = field.rawValue
        func list(_ entries: [String]) -> [String] {
            entries.isEmpty ? ["\(key): []"] : ["\(key):"] + entries.map { "  - \($0)" }
        }
        func pair(_ first: String, _ a: String, _ second: String, _ b: String?) -> String {
            var parts = ["\(first): \(quoted(a))"]
            if let b, !b.isEmpty { parts.append("\(second): \(quoted(b))") }
            return "{ " + parts.joined(separator: ", ") + " }"
        }
        switch field {
        case .name: return ["name: \(quoted(profile.name ?? ""))"]
        case .taxID: return ["tax_id: \(quoted(profile.taxID ?? ""))"]
        case .tradeNames: return ["trade_names: [" + profile.tradeNames.map(quoted).joined(separator: ", ") + "]"]
        case .partners: return list(profile.partners.map { pair("name", $0.name, "tax_id", $0.taxID) })
        case .clients: return list(profile.clients.map { pair("name", $0.name, "short", $0.short) })
        case .banks: return list(profile.banks.map { pair("name", $0.name, "account_end", $0.accountEnd) })
        case .members: return list(profile.members.map { pair("name", $0.name, "tax_id", $0.taxID) })
        case .vehicles: return list(profile.vehicles.map { pair("short", $0.short, "plate", $0.plate) })
        case .homes: return list(profile.homes.map { pair("short", $0.short, "address", $0.address) })
        }
    }

    /// Entre comillas dobles, con `\` y `"` escapados y sin saltos de línea.
    private static func quoted(_ value: String) -> String {
        let flat = value.replacingOccurrences(of: "\r\n", with: " ").replacingOccurrences(of: "\n", with: " ")
        return "\"" + flat.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

/// Los comentarios que la app y el CLI escriben en `PERFIL.md`. La primera línea dice el idioma del fichero.
enum ProfileComments {
    static func header(_ language: TemplateLanguage) -> String {
        language == .ca
            ? "# Perfil de Tria: qui és el titular d'aquest arxiu. S'envia al proveïdor d'IA amb cada document."
            : "# Perfil de Tria: quién es el titular de este archivo. Se envía al proveedor de IA con cada documento."
    }

    static func intro(_ language: TemplateLanguage) -> String {
        language == .ca
            ? "# Les claus van en anglès. Sota la segona línia ---, notes lliures per a Tria."
            : "# Las claves van en inglés. Debajo de la segunda línea ---, notas libres para Tria."
    }

    static func kind(_ language: TemplateLanguage) -> String {
        language == .ca ? "# Tipus: autonomo, sl o hogar." : "# Tipo: autonomo, sl u hogar."
    }

    static func field(_ field: ProfileField, kind: TemplateKind, language: TemplateLanguage) -> String {
        let ca = language == .ca
        switch field {
        case .name:
            if kind == .sl { return ca ? "# Raó social." : "# Razón social." }
            return ca ? "# Nom i cognoms." : "# Nombre y apellidos."
        case .taxID:
            return "# NIF."
        case .tradeNames:
            return ca ? "# Noms comercials, si n'hi ha: [\"Nom\", \"Un altre nom\"]."
                      : "# Nombres comerciales, si los hay: [\"Nombre\", \"Otro nombre\"]."
        case .partners:
            return ca ? "# Socis: - { name: \"Nom Cognom\", tax_id: \"NIF\" }. El nom és la seva carpeta de documents personals."
                      : "# Socios: - { name: \"Nombre Apellido\", tax_id: \"NIF\" }. El nombre es su carpeta de documentos personales."
        case .clients:
            return ca ? "# Clients habituals: - { name: \"RAÓ SOCIAL\", short: \"Nom curt\" }, perquè carpetes i noms surtin sempre iguals."
                      : "# Clientes habituales: - { name: \"RAZÓN SOCIAL\", short: \"Nombre corto\" }, para que carpetas y nombres salgan siempre iguales."
        case .banks:
            return ca ? "# Bancs: - { name: \"Banc\", account_end: \"1234\" }, amb els últims dígits del compte, mai l'IBAN sencer."
                      : "# Bancos: - { name: \"Banco\", account_end: \"1234\" }, con los últimos dígitos de la cuenta, nunca el IBAN entero."
        case .members:
            return ca ? "# Membres de la llar: - { name: \"Nom\", tax_id: \"NIF\" }. El nom és la seva subcarpeta a Salut."
                      : "# Miembros del hogar: - { name: \"Nombre\", tax_id: \"NIF\" }. El nombre es su subcarpeta en Salud."
        case .vehicles:
            return ca ? "# Vehicles: - { short: \"Cotxe\", plate: \"0000 XXX\" }. El nom curt és el que porten els documents."
                      : "# Vehículos: - { short: \"Coche\", plate: \"0000 XXX\" }. El nombre corto es el que llevan los documentos."
        case .homes:
            return ca ? "# Habitatges: - { short: \"Pis\", address: \"Carrer, número, ciutat\" }."
                      : "# Viviendas: - { short: \"Piso\", address: \"Calle, número, ciudad\" }."
        }
    }
}
