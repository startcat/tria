/// Plantillas de `TRIA.md` pensadas para España (spec §7.2). Son texto Swift, no recursos, para que
/// el binario del CLI funcione solo (Homebrew).
public enum Templates {
    public static func text(_ kind: TemplateKind, language: TemplateLanguage) -> String {
        switch (kind, language) {
        case (.autonomo, .es): return TemplatesES.autonomo
        case (.sl, .es): return TemplatesES.sl
        case (.hogar, .es): return TemplatesES.hogar
        case (.autonomo, .ca): return TemplatesCA.autonomo
        case (.sl, .ca): return TemplatesCA.sl
        case (.hogar, .ca): return TemplatesCA.hogar
        }
    }

    public static func folders(_ kind: TemplateKind, language: TemplateLanguage) -> [String] {
        switch (kind, language) {
        case (.autonomo, .es): return TemplatesES.autonomoFolders
        case (.sl, .es): return TemplatesES.slFolders
        case (.hogar, .es): return TemplatesES.hogarFolders
        case (.autonomo, .ca): return TemplatesCA.autonomoFolders
        case (.sl, .ca): return TemplatesCA.slFolders
        case (.hogar, .ca): return TemplatesCA.hogarFolders
        }
    }

    /// El `PERFIL.md` de cada plantilla: el tipo y los campos vacíos, comentados (spec del perfil, §3).
    public static func profile(_ kind: TemplateKind, language: TemplateLanguage) -> String {
        ProfileFile.render(Profile(kind: kind), language: language)
    }
}
