/// Tipo de plantilla de reglas. Vive en el núcleo porque `Profile` lo necesita.
public enum TemplateKind: String, CaseIterable, Sendable {
    case autonomo, sl, hogar
}

public enum TemplateLanguage: String, CaseIterable, Sendable {
    case es, ca

    /// El idioma de un espacio ya creado, por la bandeja de sus reglas: `99-Pendent` es la de las plantillas en catalán.
    public static func guess(from rules: RulesFile) -> TemplateLanguage {
        rules.header.inbox == "99-Pendent" ? .ca : .es
    }
}
