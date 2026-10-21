import Foundation
import TriaKit

public enum Lang: String, Sendable {
    case ca, es, en

    public static func detect(environment: [String: String],
                              preferred: [String] = Locale.preferredLanguages) -> Lang {
        // `TRIA_LANG` vale en mayúsculas y con región (`EN`, `ca_ES`); si no es ca, es ni en, mandan los del sistema.
        let forced = environment["TRIA_LANG"]?.lowercased().split(whereSeparator: { $0 == "_" || $0 == "-" }).first
        if let forced = forced.flatMap({ Lang(rawValue: String($0)) }) { return forced }
        let first = preferred.first?.lowercased() ?? "en"
        if first.hasPrefix("ca") { return .ca }
        if first.hasPrefix("es") { return .es }
        return .en
    }

    public var templateLanguage: TemplateLanguage { self == .ca ? .ca : .es }
}

/// Mensajes del CLI en catalán, castellano e inglés. Marcadores {0}, {1}…
public enum L10n {
    public enum Key: Sendable {
        case noWorkspace, invalidRules, locked, noKey, invalidKey, keyWithoutWorkspace, quota, providerError, learnFailed, nonInteractive, cancelled
        case rulesMissingFrontmatter, rulesInvalidYAML, rulesMissingKey, rulesInvalidValue, rulesUnsafePath, rulesOverlapping
        case invalidProfile, profileLine, profileMissingFrontmatter, profileInvalidYAML, profileMissingKind
        case profileUnknownKind, profileInvalidValue
        case initAskName, initAskCompany, initAskTaxID, initAskMember, initProfileCreated, initProfileToFill
        case profileNone, profileKept, profileWarnMissing, profileWarnUnknownKey, profileWarnNotForKind, profileWarnTaxID
        case rulesOKWithProfile, fieldName, fieldTaxID, fieldMembers
        case initExists, initExistsShort, initCreated, initChooseTemplate, initOfferLearn
        case learnEstimate, learnConfirmSave, learnDraftSaved
        case templateAutonomo, templateSL, templateHogar, templateLearned
        case configShow, keyNone, keyFromEnv, keyPrompt, keySaved, keyDeleted, configSaved
        case rulesOK, rulesWarnMissingFolder, rulesWarnProtectedUnmatched, rulesInboxProtected, rulesDuplicatesProtected
        case suggestionsEmpty, suggestionLine, suggestionApplied, suggestionDiscarded, suggestionNotFound
        case analyzing, nothingToDo, inUse, ignoredFolders, itemProposal, itemConfidence, itemDoubt
        case itemDuplicate, itemPending, itemUndone, confHigh, confMedium, confLow
        case pendUnreadable, pendUnsupported, pendEncrypted, pendRefused, pendOffline, pendPaused, pendInvalid, pendProvider, pendHeld
        case interrupted, costLine, costUnknown, chooseAction, reviewProposal, reviewDuplicate
        case editFolder, editName, editInvalid, applied, failedMove, pendingLeftOne, pendingLeft, suggestionOffer
        case suggestionSaved
        case statusUnprocessed, statusInUse, statusDuplicate, statusProposed, statusPending
        case undoDone, undoNothing, undoSkippedMissing, undoSkippedModified, undoSkippedUnsafe, undoSkippedFailed
        case logEmpty, logBatch, logOperation
        case evalNeedsArchive, evalEstimate, evalFolder, evalFilename, evalPending, evalByConfidence
        case evalRunning, evalDoneOne, evalDoneMany, learnRunning, learnDone
        case evalSaved, evalRegressed, evalNoRegression, evalInterrupted, evalBaselineSkipped
        case evalBaselineUnreadable, evalBaselineInvalid
        case summaryReadyOne, summaryReadyMany, summaryDoubt, summaryDuplicateOne, summaryDuplicateMany
        case summaryPendingOne, summaryPendingMany
        case scanning, readDoneOne, readDoneMany, readCached, thinkingRule
        case rulesAskEstimate, rulesAskThinking, rulesAskDone, rulesAskOffer, rulesAskApplied, rulesAskDiscarded
        case rulesAskRefused, rulesAskCreateFolder, rulesAskHeader, rulesAskCannot, rulesAskInvalid
        case rulesChangeChanged, rulesChangeLocked
        case rulesWhyRules, rulesWhyInbox, rulesWhyDuplicates, rulesWhyUnsafe, rulesWhyExists, rulesWhyRepeated
        case rulesWhyInboxProtected, rulesWhyDuplicatesProtected, rulesWhyProtectedFolder
        case screenConfidence, screenTrash, screenEdited, screenUndone, screenHelp, screenHelpShort
    }

    public static func text(_ key: Key, _ lang: Lang, _ args: [String]) -> String {
        let entry = table(key)
        var text: String
        switch lang {
        case .ca: text = entry.ca
        case .es: text = entry.es
        case .en: text = entry.en
        }
        for (index, value) in args.enumerated() { text = text.replacingOccurrences(of: "{\(index)}", with: value) }
        return text
    }

    public static func isYes(_ answer: String?) -> Bool {
        ["s", "si", "sí", "y", "yes"].contains(answer?.trimmingCharacters(in: .whitespaces).lowercased() ?? "")
    }

    /// Singular o plural según `count`. El primer marcador es la cifra; `args` son los siguientes.
    public static func count(_ count: Int, _ one: Key, _ many: Key, _ lang: Lang, _ args: String...) -> String {
        text(count == 1 ? one : many, lang, [String(count)] + args)
    }

    public static func percent(_ value: Double, _ lang: Lang) -> String {
        let text = String(format: "%.1f", value * 100)
        return lang == .en ? "\(text)%" : text.replacingOccurrences(of: ".", with: ",") + " %"
    }

    public static func money(_ value: Double?, _ lang: Lang) -> String {
        guard let value else { return text(.costUnknown, lang, []) }
        let amount = String(format: "%.4f", value)
        return (lang == .en ? amount : amount.replacingOccurrences(of: ".", with: ",")) + " USD"
    }

    public static func describe(_ error: RulesError, _ lang: Lang) -> String {
        switch error {
        case .missingFrontmatter: return text(.rulesMissingFrontmatter, lang, [])
        case .invalidYAML(let detail): return text(.rulesInvalidYAML, lang, [detail])
        case .missingKey(let key): return text(.rulesMissingKey, lang, [key])
        case .invalidValue(let key, let value): return text(.rulesInvalidValue, lang, [key, value])
        case .unsafePath(let key, let value): return text(.rulesUnsafePath, lang, [key, value])
        case .overlappingFolders: return text(.rulesOverlapping, lang, [])
        }
    }

    public static func describe(_ error: ProfileError, _ lang: Lang) -> String {
        func at(_ line: Int?) -> String { line.map { text(.profileLine, lang, [String($0)]) } ?? "" }
        switch error {
        case .missingFrontmatter: return text(.profileMissingFrontmatter, lang, [])
        case .invalidYAML(let line, let detail): return at(line) + text(.profileInvalidYAML, lang, [detail])
        case .missingKind: return text(.profileMissingKind, lang, [])
        case .unknownKind(let value, let line): return at(line) + text(.profileUnknownKind, lang, [value])
        case .invalidValue(let key, let line): return at(line) + text(.profileInvalidValue, lang, [key])
        }
    }

    /// Por qué no se propone un cambio pedido a Tria: lo que se puede arreglar pidiéndolo de otra forma, «No puedo hacer
    /// ese cambio: …»; una respuesta que no se entiende, «Vuelve a probar».
    public static func describe(_ error: RulesAskError, _ lang: Lang) -> String {
        func cannot(_ key: Key, _ args: String...) -> String { text(.rulesAskCannot, lang, [text(key, lang, args)]) }
        // Las carpetas las nombra el modelo: en una línea y sin órdenes para el terminal, como el resto de lo suyo.
        let folder = TextWidth.singleLine
        switch error {
        case .invalidResponse, .unknownSection, .repeatedSection, .notOneSection, .noChange:
            return text(.rulesAskInvalid, lang, [])
        case .invalidRules(let rules): return cannot(.rulesWhyRules, describe(rules, lang))
        case .inboxChanged: return cannot(.rulesWhyInbox)
        case .duplicatesChanged: return cannot(.rulesWhyDuplicates)
        case .inboxProtected: return cannot(.rulesWhyInboxProtected)
        case .duplicatesProtected: return cannot(.rulesWhyDuplicatesProtected)
        case .unsafeFolder(let path): return cannot(.rulesWhyUnsafe, folder(path))
        case .protectedFolder(let path): return cannot(.rulesWhyProtectedFolder, folder(path))
        case .folderExists(let path): return cannot(.rulesWhyExists, folder(path))
        case .repeatedFolder(let path): return cannot(.rulesWhyRepeated, folder(path))
        }
    }

    public static func describe(_ error: RulesChangeError, _ lang: Lang) -> String {
        switch error {
        case .changedOnDisk: return text(.rulesChangeChanged, lang, [])
        case .locked, .lockedByThisProcess: return text(.rulesChangeLocked, lang, [])
        case .invalidRules(let rules): return text(.invalidRules, lang, [describe(rules, lang)])
        case .unsafeFolder(let path):
            return text(.rulesAskCannot, lang, [text(.rulesWhyUnsafe, lang, [TextWidth.singleLine(path)])])
        case .inboxProtected: return text(.rulesInboxProtected, lang, [])
        case .duplicatesProtected: return text(.rulesDuplicatesProtected, lang, [])
        case .unknownSection, .emptySection, .missingTitle, .notOneSection, .unclosedCodeBlock, .noChange:
            return text(.rulesAskInvalid, lang, [])
        }
    }

    /// «el nombre y el NIF»: lo que falta del perfil, para los avisos.
    public static func fields(_ fields: [ProfileField], _ lang: Lang) -> String {
        let names = fields.map { field -> String in
            switch field {
            case .name: return text(.fieldName, lang, [])
            case .taxID: return text(.fieldTaxID, lang, [])
            case .members: return text(.fieldMembers, lang, [])
            default: return field.rawValue
            }
        }
        let and = lang == .ca ? " i " : lang == .es ? " y " : " and "
        return names.joined(separator: and)
    }

    private static func table(_ key: Key) -> (ca: String, es: String, en: String) {
        switch key {
        case .noWorkspace: return ("No hi ha cap TRIA.md a {0} ni a les carpetes superiors. Crea l'espai amb `tria init`.",
                                   "No hay ningún TRIA.md en {0} ni en sus carpetas superiores. Crea el espacio con `tria init`.",
                                   "No TRIA.md found in {0} or its parent folders. Create the workspace with `tria init`.")
        case .invalidRules: return ("TRIA.md no és vàlid: {0}", "TRIA.md no es válido: {0}", "TRIA.md is not valid: {0}")
        case .invalidProfile: return ("PERFIL.md no és vàlid: {0}", "PERFIL.md no es válido: {0}", "PERFIL.md is not valid: {0}")
        case .profileLine: return ("línia {0}: ", "línea {0}: ", "line {0}: ")
        case .profileMissingFrontmatter: return ("falta la capçalera entre línies ---", "falta la cabecera entre líneas ---",
                                                 "the header between --- lines is missing")
        case .profileInvalidYAML: return ("la capçalera no és YAML vàlid ({0})", "la cabecera no es YAML válido ({0})",
                                          "the header is not valid YAML ({0})")
        case .profileMissingKind: return ("falta «kind» (autonomo, sl o hogar)", "falta «kind» (autonomo, sl u hogar)",
                                          "'kind' is missing (autonomo, sl or hogar)")
        case .profileUnknownKind: return ("el tipus «{0}» no existeix; fes servir autonomo, sl o hogar",
                                          "el tipo «{0}» no existe; usa autonomo, sl u hogar",
                                          "the kind '{0}' does not exist; use autonomo, sl or hogar")
        case .profileInvalidValue: return ("«{0}» no té el format esperat", "«{0}» no tiene el formato esperado",
                                           "'{0}' does not have the expected format")
        case .locked: return ("Un altre procés està ordenant aquest espai ({0}, pid {1}). Torna-ho a provar quan acabi.",
                              "Otro proceso está ordenando este espacio ({0}, pid {1}). Inténtalo de nuevo cuando termine.",
                              "Another process is sorting this workspace ({0}, pid {1}). Try again when it finishes.")
        case .noKey: return ("Falta la API key de {0}. Desa-la amb `tria config --set-key` o fes servir la variable {1}.",
                             "Falta la API key de {0}. Guárdala con `tria config --set-key` o usa la variable {1}.",
                             "Missing {0} API key. Save it with `tria config --set-key` or set {1}.")
        case .invalidKey: return ("La API key no és vàlida. Canvia-la amb `tria config --set-key`.",
                                  "La API key no es válida. Cámbiala con `tria config --set-key`.",
                                  "The API key is not valid. Change it with `tria config --set-key`.")
        case .keyWithoutWorkspace: return ("Aquesta clau d'Anthropic no pertany a cap workspace. Crea una clau dins d'un workspace a la consola d'Anthropic i desa-la amb `tria config --set-key`.",
                                           "Esta clave de Anthropic no pertenece a ningún workspace. Crea una clave dentro de un workspace en la consola de Anthropic y guárdala con `tria config --set-key`.",
                                           "This Anthropic key doesn't belong to any workspace. Create a key inside a workspace in the Anthropic console and save it with `tria config --set-key`.")
        case .quota: return ("El teu compte del proveïdor no té saldo o quota: {0}",
                             "Tu cuenta del proveedor no tiene saldo o cuota: {0}",
                             "Your provider account has no credit or quota left: {0}")
        case .providerError: return ("Error del proveïdor d'IA: {0}", "Error del proveedor de IA: {0}", "AI provider error: {0}")
        case .learnFailed: return ("No s'ha pogut generar l'esborrany: {0}", "No se ha podido generar el borrador: {0}",
                                   "Could not generate the draft: {0}")
        case .nonInteractive: return ("Sense terminal interactiu: fes servir --yes, --auto, --dry-run o --json segons l'ordre.",
                                      "Sin terminal interactiva: usa --yes, --auto, --dry-run o --json según el comando.",
                                      "No interactive terminal: use --yes, --auto, --dry-run or --json depending on the command.")
        case .cancelled: return ("Cancel·lat.", "Cancelado.", "Cancelled.")
        case .rulesMissingFrontmatter: return ("falta la capçalera entre línies ---", "falta la cabecera entre líneas ---",
                                               "the header between --- lines is missing")
        case .rulesInvalidYAML: return ("la capçalera no és YAML vàlid ({0})", "la cabecera no es YAML válido ({0})",
                                        "the header is not valid YAML ({0})")
        case .rulesMissingKey: return ("falta la clau «{0}»", "falta la clave «{0}»", "missing key '{0}'")
        case .rulesInvalidValue: return ("valor no vàlid per a «{0}»: {1}", "valor no válido para «{0}»: {1}",
                                         "invalid value for '{0}': {1}")
        case .rulesUnsafePath: return ("la ruta de «{0}» ha de ser relativa i sense «..»: {1}",
                                       "la ruta de «{0}» debe ser relativa y sin «..»: {1}",
                                       "the path for '{0}' must be relative and without '..': {1}")
        case .rulesOverlapping: return ("la safata i la carpeta de duplicats no poden estar una dins de l'altra",
                                        "la bandeja y la carpeta de duplicados no pueden estar una dentro de la otra",
                                        "the inbox and the duplicates folder cannot be inside each other")
        case .initExists: return ("Ja hi ha un TRIA.md a {0}; es manté. Estructura comprovada.",
                                  "Ya hay un TRIA.md en {0}; se mantiene. Estructura comprobada.",
                                  "There is already a TRIA.md in {0}; keeping it. Structure checked.")
        case .initExistsShort: return ("Ja existeix un TRIA.md.", "Ya existe un TRIA.md.", "A TRIA.md already exists.")
        case .initCreated: return ("Espai creat a {0} ({1}).", "Espacio creado en {0} ({1}).", "Workspace created in {0} ({1}).")
        case .initChooseTemplate: return ("Quina plantilla? [1] Autònom · [2] SL/pime · [3] Llar: ",
                                          "¿Qué plantilla? [1] Autónomo · [2] SL/pyme · [3] Hogar: ",
                                          "Which template? [1] Freelancer · [2] Company · [3] Home: ")
        case .initOfferLearn: return ("La carpeta ja té contingut. Vols aprendre les regles de la seva estructura? [s/N]: ",
                                      "La carpeta ya tiene contenido. ¿Aprender las reglas de su estructura? [s/N]: ",
                                      "The folder already has content. Learn the rules from its structure? [y/N]: ")
        case .learnEstimate: return ("S'analitzaran {0} documents de mostra. Cost estimat: {1}. Vols continuar? [s/N]: ",
                                     "Se analizarán {0} documentos de muestra. Coste estimado: {1}. ¿Continuar? [s/N]: ",
                                     "{0} sample documents will be analysed. Estimated cost: {1}. Continue? [y/N]: ")
        case .learnConfirmSave: return ("Vols desar aquest esborrany com a TRIA.md? [s/N]: ",
                                        "¿Guardar este borrador como TRIA.md? [s/N]: ", "Save this draft as TRIA.md? [y/N]: ")
        case .learnDraftSaved: return ("Esborrany desat a {0}. Revisa'l i canvia-li el nom a TRIA.md quan et convenci.",
                                       "Borrador guardado en {0}. Revísalo y renómbralo a TRIA.md cuando te convenza.",
                                       "Draft saved to {0}. Review it and rename it to TRIA.md when you are happy with it.")
        case .templateAutonomo: return ("plantilla Autònom", "plantilla Autónomo", "Freelancer template")
        case .templateSL: return ("plantilla SL/pime", "plantilla SL/pyme", "Company template")
        case .templateHogar: return ("plantilla Llar", "plantilla Hogar", "Home template")
        case .templateLearned: return ("regles apreses de la carpeta", "reglas aprendidas de la carpeta", "rules learned from the folder")
        case .configShow: return ("Proveïdor: {0} · model: {1} · key: {2}", "Proveedor: {0} · modelo: {1} · key: {2}",
                                  "Provider: {0} · model: {1} · key: {2}")
        case .keyNone: return ("sense configurar", "sin configurar", "not set")
        case .keyFromEnv: return ("des de {0}", "desde {0}", "from {0}")
        case .keyPrompt: return ("Enganxa la API key de {0} (no es mostrarà): ", "Pega la API key de {0} (no se mostrará): ",
                                 "Paste the {0} API key (it will not be shown): ")
        case .keySaved: return ("Key desada al Clauer.", "Key guardada en el Llavero.", "Key saved in the Keychain.")
        case .keyDeleted: return ("Key esborrada del Clauer.", "Key borrada del Llavero.", "Key removed from the Keychain.")
        case .configSaved: return ("Configuració desada a {0}.", "Configuración guardada en {0}.", "Configuration saved to {0}.")
        case .initAskName: return ("Nom i cognoms del titular (Intro per deixar-ho en blanc): ",
                                   "Nombre y apellidos del titular (Intro para dejarlo en blanco): ",
                                   "Owner's full name (Enter to leave blank): ")
        case .initAskCompany: return ("Raó social (Intro per deixar-ho en blanc): ",
                                      "Razón social (Intro para dejarlo en blanco): ",
                                      "Company name (Enter to leave blank): ")
        case .initAskTaxID: return ("NIF del titular (Intro per deixar-ho en blanc): ",
                                    "NIF del titular (Intro para dejarlo en blanco): ",
                                    "Owner's tax ID (NIF) (Enter to leave blank): ")
        case .initAskMember: return ("Nom d'un membre de la llar (Intro per deixar-ho en blanc): ",
                                     "Nombre de un miembro del hogar (Intro para dejarlo en blanco): ",
                                     "Name of a household member (Enter to leave blank): ")
        case .initProfileCreated: return ("PERFIL.md creat: Tria ja sap qui és el titular.",
                                          "PERFIL.md creado: Tria ya sabe quién es el titular.",
                                          "PERFIL.md created: Tria now knows who the owner is.")
        case .initProfileToFill: return ("PERFIL.md creat: omple'l perquè Tria sàpiga qui és el titular (el valida «tria rules check»).",
                                         "PERFIL.md creado: rellénalo para que Tria sepa quién es el titular (lo valida «tria rules check»).",
                                         "PERFIL.md created: fill it in so Tria knows who the owner is ('tria rules check' validates it).")
        case .profileKept: return ("Es manté el PERFIL.md que ja hi havia.",
                                    "Se mantiene el PERFIL.md que ya había.",
                                    "Keeping the PERFIL.md that was already there.")
        case .profileNone: return ("Avís: no hi ha PERFIL.md; Tria no sap qui és el titular. Crea'l amb «tria init --template autonomo|sl|hogar».",
                                   "Aviso: no hay PERFIL.md; Tria no sabe quién es el titular. Créalo con «tria init --template autonomo|sl|hogar».",
                                   "Warning: there is no PERFIL.md; Tria does not know who the owner is. Create it with 'tria init --template autonomo|sl|hogar'.")
        case .profileWarnMissing: return ("Avís: a PERFIL.md li falta {0}; sense això, Tria endevina qui és el titular.",
                                          "Aviso: a PERFIL.md le falta {0}; sin eso, Tria adivina quién es el titular.",
                                          "Warning: PERFIL.md is missing {0}; without it, Tria guesses who the owner is.")
        case .profileWarnUnknownKey: return ("Avís: PERFIL.md té la clau «{0}», que Tria no coneix; s'envia igualment.",
                                             "Aviso: PERFIL.md tiene la clave «{0}», que Tria no conoce; se envía igualmente.",
                                             "Warning: PERFIL.md has the key '{0}', which Tria does not know; it is sent anyway.")
        case .profileWarnNotForKind: return ("Avís: la clau «{0}» no és del tipus «{1}»; s'envia igualment.",
                                             "Aviso: la clave «{0}» no es del tipo «{1}»; se envía igualmente.",
                                             "Warning: the key '{0}' is not part of the '{1}' kind; it is sent anyway.")
        case .profileWarnTaxID: return ("Avís: el NIF «{0}» no sembla correcte (la lletra o el dígit de control no quadren).",
                                        "Aviso: el NIF «{0}» no parece correcto (la letra o el dígito de control no cuadran).",
                                        "Warning: the tax ID '{0}' does not look right (its check letter or digit does not match).")
        case .rulesOKWithProfile: return ("TRIA.md i PERFIL.md són vàlids.", "TRIA.md y PERFIL.md son válidos.",
                                          "TRIA.md and PERFIL.md are valid.")
        case .fieldName: return ("el nom", "el nombre", "the name")
        case .fieldTaxID: return ("el NIF", "el NIF", "the tax ID")
        case .fieldMembers: return ("algun membre", "algún miembro", "a member")
        case .rulesOK: return ("TRIA.md és vàlid.", "TRIA.md es válido.", "TRIA.md is valid.")
        case .rulesWarnMissingFolder: return ("Avís: la carpeta {0} no existeix; es crearà en ordenar.",
                                              "Aviso: la carpeta {0} no existe; se creará al ordenar.",
                                              "Warning: folder {0} does not exist; it will be created when sorting.")
        case .rulesWarnProtectedUnmatched: return ("Avís: el patró protegit «{0}» no coincideix amb cap carpeta.",
                                                   "Aviso: el patrón protegido «{0}» no coincide con ninguna carpeta.",
                                                   "Warning: protected pattern '{0}' does not match any folder.")
        case .rulesInboxProtected: return ("La safata és dins d'una ruta protegida.", "La bandeja está dentro de una ruta protegida.",
                                           "The inbox is inside a protected path.")
        case .rulesDuplicatesProtected: return ("La carpeta de duplicats és dins d'una ruta protegida.",
                                                "La carpeta de duplicados está dentro de una ruta protegida.",
                                                "The duplicates folder is inside a protected path.")
        case .suggestionsEmpty: return ("No hi ha regles suggerides pendents.", "No hay reglas sugeridas pendientes.",
                                        "No pending rule suggestions.")
        case .suggestionLine: return ("{0} · {1} · {2} ({3})", "{0} · {1} · {2} ({3})", "{0} · {1} · {2} ({3})")
        case .suggestionApplied: return ("Regla afegida a TRIA.md: {0}", "Regla añadida a TRIA.md: {0}", "Rule added to TRIA.md: {0}")
        case .suggestionDiscarded: return ("Suggeriment descartat.", "Sugerencia descartada.", "Suggestion discarded.")
        case .suggestionNotFound: return ("No hi ha cap suggeriment amb id {0}.", "No hay ninguna sugerencia con id {0}.",
                                          "No suggestion with id {0}.")
        case .analyzing: return ("Analitzant {0} documents de {1}…", "Analizando {0} documentos de {1}…", "Analysing {0} documents in {1}…")
        case .nothingToDo: return ("La safata és buida.", "La bandeja está vacía.", "The inbox is empty.")
        case .inUse: return ("{0} documents encara s'estan copiant; es processaran la propera vegada.",
                             "{0} documentos aún se están copiando; se procesarán la próxima vez.",
                             "{0} documents are still being copied; they will be processed next time.")
        case .ignoredFolders: return ("S'ignoren les subcarpetes de la safata: {0}", "Se ignoran las subcarpetas de la bandeja: {0}",
                                      "Inbox subfolders are ignored: {0}")
        case .itemProposal: return ("→ {0}", "→ {0}", "→ {0}")
        case .itemConfidence: return ("Confiança {0} · {1}", "Confianza {0} · {1}", "Confidence {0} · {1}")
        case .itemDoubt: return ("Dubte: {0}", "Duda: {0}", "Doubt: {0}")
        case .itemDuplicate: return ("DUPLICAT de {0} → {1}", "DUPLICADO de {0} → {1}", "DUPLICATE of {0} → {1}")
        case .itemPending: return ("PENDENT: {0}", "PENDIENTE: {0}", "PENDING: {0}")
        case .itemUndone: return ("Ja ho vas desfer una vegada: en mode automàtic no s'aplica.",
                                  "Ya lo deshiciste una vez: en modo automático no se aplica.",
                                  "You undid this once: automatic mode leaves it alone.")
        case .confHigh: return ("alta", "alta", "high")
        case .confMedium: return ("mitjana", "media", "medium")
        case .confLow: return ("baixa", "baja", "low")
        case .pendUnreadable: return ("no s'ha pogut llegir ({0})", "no se ha podido leer ({0})", "could not be read ({0})")
        case .pendUnsupported: return ("format no compatible (.{0})", "formato no soportado (.{0})", "unsupported format (.{0})")
        case .pendEncrypted: return ("PDF protegit amb contrasenya", "PDF protegido con contraseña", "password-protected PDF")
        case .pendRefused: return ("el model ha rebutjat el document", "el modelo ha rechazado el documento", "the model refused the document")
        case .pendOffline: return ("sense connexió", "sin conexión", "offline")
        case .pendHeld: return ("en espera", "en espera", "on hold")
        case .pendPaused: return ("lot aturat ({0})", "lote pausado ({0})", "batch paused ({0})")
        case .pendInvalid: return ("proposta no vàlida: {0}", "propuesta no válida: {0}", "invalid proposal: {0}")
        case .pendProvider: return ("el proveïdor d'IA l'ha rebutjat ({0})", "el proveedor de IA lo ha rechazado ({0})",
                                    "the AI provider rejected it ({0})")
        case .interrupted: return ("El lot s'ha aturat ({0}). El que falta continua a la safata.",
                                   "El lote se ha pausado ({0}). Lo que falta sigue en la bandeja.",
                                   "The batch was paused ({0}). The rest stays in the inbox.")
        case .costLine: return ("Tokens: {0} d'entrada · {1} de sortida · {2} de memòria cau · cost aproximat: {3}",
                                "Tokens: {0} de entrada · {1} de salida · {2} de caché · coste aproximado: {3}",
                                "Tokens: {0} input · {1} output · {2} cached · approximate cost: {3}")
        case .costUnknown: return ("desconegut", "desconocido", "unknown")
        case .chooseAction: return ("Què fem? [t] aplicar-ho tot · [a] només confiança alta · [r] revisar un a un · [n] res: ",
                                    "¿Qué hacemos? [t] aplicar todo · [a] solo confianza alta · [r] revisar uno a uno · [n] nada: ",
                                    "What now? [t] apply all · [a] high confidence only · [r] review one by one · [n] nothing: ")
        case .reviewProposal: return ("[s] aplicar · [e] editar · [o] ometre · [q] acabar: ",
                                      "[s] aplicar · [e] editar · [o] omitir · [q] terminar: ",
                                      "[s] apply · [e] edit · [o] skip · [q] quit: ")
        case .reviewDuplicate: return ("[s] moure a duplicats · [p] paperera · [o] ometre · [q] acabar: ",
                                       "[s] mover a duplicados · [p] papelera · [o] omitir · [q] terminar: ",
                                       "[s] move to duplicates · [p] trash · [o] skip · [q] quit: ")
        case .editFolder: return ("Carpeta [{0}]: ", "Carpeta [{0}]: ", "Folder [{0}]: ")
        case .editName: return ("Nom [{0}]: ", "Nombre [{0}]: ", "Name [{0}]: ")
        case .editInvalid: return ("No es pot fer servir: {0}", "No se puede usar: {0}", "Cannot use it: {0}")
        case .applied: return ("Moguts: {0} · fallits: {1} · lot {2} (desfer: tria undo --last)",
                               "Movidos: {0} · fallidos: {1} · lote {2} (deshacer: tria undo --last)",
                               "Moved: {0} · failed: {1} · batch {2} (undo: tria undo --last)")
        case .failedMove: return ("No s'ha pogut moure {0}: {1}", "No se ha podido mover {0}: {1}", "Could not move {0}: {1}")
        case .pendingLeftOne: return ("Queda {0} pendent a la safata.", "Queda {0} pendiente en la bandeja.",
                                      "{0} document remains in the inbox.")
        case .pendingLeft: return ("Queden {0} pendents a la safata.", "Quedan {0} pendientes en la bandeja.",
                                   "{0} documents remain in the inbox.")
        case .suggestionOffer: return ("Vols afegir aquesta regla a TRIA.md? [a] afegir · [l] després (Retorn) · [d] descartar: ",
                                       "¿Añadir esta regla a TRIA.md? [a] añadir · [l] luego (Intro) · [d] descartar: ",
                                       "Add this rule to TRIA.md? [a] add · [l] later (Return) · [d] discard: ")
        case .suggestionSaved: return ("Suggeriment desat; el veuràs amb `tria rules suggestions`.",
                                       "Sugerencia guardada; la verás con `tria rules suggestions`.",
                                       "Suggestion saved; see it with `tria rules suggestions`.")
        case .statusUnprocessed: return ("sense processar", "sin procesar", "not processed")
        case .statusInUse: return ("copiant-se", "copiándose", "being copied")
        case .statusDuplicate: return ("duplicat de {0}", "duplicado de {0}", "duplicate of {0}")
        case .statusProposed: return ("proposta: {0} (confiança {1})", "propuesta: {0} (confianza {1})", "proposal: {0} ({1} confidence)")
        case .statusPending: return ("pendent: {0}", "pendiente: {0}", "pending: {0}")
        case .undoDone: return ("Restaurats: {0} · omesos: {1}.", "Restaurados: {0} · omitidos: {1}.", "Restored: {0} · skipped: {1}.")
        case .undoNothing: return ("No hi ha res per desfer.", "No hay nada que deshacer.", "Nothing to undo.")
        case .undoSkippedMissing: return ("  {0}: ja no és on la Tria el va deixar", "  {0}: ya no está donde Tria lo dejó",
                                          "  {0}: no longer where Tria left it")
        case .undoSkippedModified: return ("  {0}: ha canviat des que es va moure", "  {0}: ha cambiado desde que se movió",
                                           "  {0}: changed since it was moved")
        case .undoSkippedUnsafe: return ("  {0}: el registre no és fiable (ruta fora de l'espai o sense empremta); no es toca",
                                         "  {0}: el registro no es fiable (ruta fuera del espacio o sin huella); no se toca",
                                         "  {0}: untrustworthy journal entry (path outside the workspace or no hash); left alone")
        case .undoSkippedFailed: return ("  {0}: no s'ha pogut tornar ({1})", "  {0}: no se ha podido devolver ({1})",
                                         "  {0}: could not be moved back ({1})")
        case .logEmpty: return ("Encara no hi ha moviments.", "Aún no hay movimientos.", "No moves yet.")
        case .logBatch: return ("{0} · {1} · {2} moguts · {3} desfets · {4} fallits",
                                "{0} · {1} · {2} movidos · {3} deshechos · {4} fallidos",
                                "{0} · {1} · {2} moved · {3} undone · {4} failed")
        case .logOperation: return ("  {0} {1} → {2}", "  {0} {1} → {2}", "  {0} {1} → {2}")
        case .evalNeedsArchive: return ("Indica la carpeta ja ordenada o fes servir --synthetic.",
                                        "Indica la carpeta ya ordenada o usa --synthetic.",
                                        "Give an already sorted folder or use --synthetic.")
        case .evalEstimate: return ("S'avaluaran {0} documents amb {1}. Cost estimat: {2}. Vols continuar? [s/N]: ",
                                    "Se evaluarán {0} documentos con {1}. Coste estimado: {2}. ¿Continuar? [s/N]: ",
                                    "{0} documents will be evaluated with {1}. Estimated cost: {2}. Continue? [y/N]: ")
        case .evalFolder: return ("Encert de carpeta: {0}", "Acierto de carpeta: {0}", "Folder accuracy: {0}")
        case .evalFilename: return ("Nom exacte: {0} · semblant: {1}", "Nombre exacto: {0} · parecido: {1}", "Exact name: {0} · similar: {1}")
        case .evalPending: return ("Pendents: {0} · il·legibles: {1}", "Pendientes: {0} · ilegibles: {1}", "Pending: {0} · unreadable: {1}")
        case .evalByConfidence: return ("  Confiança {0}: {1} documents, {2} d'encert", "  Confianza {0}: {1} documentos, {2} de acierto",
                                        "  {0} confidence: {1} documents, {2} accuracy")
        case .evalSaved: return ("Informe desat a {0}.", "Informe guardado en {0}.", "Report saved to {0}.")
        case .evalRegressed: return ("REGRESSIÓ: l'encert de carpeta baixa {0} punts respecte de la referència.",
                                     "REGRESIÓN: el acierto de carpeta baja {0} puntos respecto a la referencia.",
                                     "REGRESSION: folder accuracy drops {0} points against the baseline.")
        case .evalInterrupted: return ("Avaluació incompleta: {0} de {1} documents ({2}). L'encert només compta els acabats.",
                                       "Evaluación incompleta: {0} de {1} documentos ({2}). El acierto solo cuenta los terminados.",
                                       "Incomplete evaluation: {0} of {1} documents ({2}). Accuracy only counts the finished ones.")
        case .evalBaselineSkipped: return ("No es compara amb la referència: l'avaluació és incompleta.",
                                           "No se compara con la referencia: la evaluación está incompleta.",
                                           "Not compared with the baseline: the evaluation is incomplete.")
        case .evalBaselineUnreadable: return ("No es pot llegir l'informe de referència {0}.",
                                              "No se puede leer el informe de referencia {0}.",
                                              "Cannot read the baseline report {0}.")
        case .evalBaselineInvalid: return ("{0} no és un informe de `tria eval --out`.",
                                           "{0} no es un informe de `tria eval --out`.",
                                           "{0} is not a `tria eval --out` report.")
        case .evalNoRegression: return ("Sense regressió respecte de la referència ({0}).", "Sin regresión respecto a la referencia ({0}).",
                                        "No regression against the baseline ({0}).")
        case .summaryReadyOne: return ("{0} llest", "{0} listo", "{0} ready")
        case .summaryReadyMany: return ("{0} llestos", "{0} listos", "{0} ready")
        case .summaryDoubt: return ("{0} amb dubte", "{0} con duda", "{0} in doubt")
        case .summaryDuplicateOne: return ("{0} duplicat", "{0} duplicado", "{0} duplicate")
        case .summaryDuplicateMany: return ("{0} duplicats", "{0} duplicados", "{0} duplicates")
        case .summaryPendingOne: return ("{0} pendent", "{0} pendiente", "{0} pending")
        case .summaryPendingMany: return ("{0} pendents", "{0} pendientes", "{0} pending")
        case .scanning: return ("Cercant documents a {0}…", "Buscando documentos en {0}…", "Looking for documents in {0}…")
        case .readDoneOne: return ("{0} document llegit en {1} s", "{0} documento leído en {1} s",
                                   "{0} document read in {1} s")
        case .readDoneMany: return ("{0} documents llegits en {1} s", "{0} documentos leídos en {1} s",
                                    "{0} documents read in {1} s")
        case .readCached: return ("({0} sense gastar: ja estaven llegits)", "({0} sin gastar: ya estaban leídos)",
                                  "({0} at no cost: already read)")
        case .thinkingRule: return ("Pensant una regla per a {0}…", "Pensando una regla para {0}…",
                                    "Thinking of a rule for {0}…")
        case .rulesAskEstimate: return ("Demanar el canvi costarà uns {0} amb {1}.", "Pedir el cambio costará unos {0} con {1}.",
                                        "Asking for the change will cost about {0} with {1}.")
        case .rulesAskThinking: return ("La Tria està pensant el canvi…", "Tria está pensando el cambio…",
                                        "Tria is working out the change…")
        case .rulesAskDone: return ("Canvi a punt en {0} s", "Cambio listo en {0} s", "Change ready in {0} s")
        case .rulesAskOffer: return ("[a] aplicar · [d] descartar: ", "[a] aplicar · [d] descartar: ",
                                     "[a] apply · [d] discard: ")
        case .rulesAskApplied: return ("TRIA.md actualitzat. La versió anterior queda a .tria/rules-history/.",
                                       "TRIA.md actualizado. La versión anterior queda en .tria/rules-history/.",
                                       "TRIA.md updated. The previous version is in .tria/rules-history/.")
        case .rulesAskDiscarded: return ("Canvi descartat: TRIA.md no canvia.", "Cambio descartado: TRIA.md sigue igual.",
                                         "Change discarded: TRIA.md stays the same.")
        case .rulesAskRefused: return ("La Tria no fa aquest canvi: {0}", "Tria no hace este cambio: {0}",
                                       "Tria won't make this change: {0}")
        case .rulesAskCreateFolder: return ("Es crearà la carpeta {0}", "Se creará la carpeta {0}",
                                            "The folder {0} will be created")
        case .rulesAskHeader: return ("Capçalera", "Cabecera", "Header")
        case .rulesAskCannot: return ("No puc fer aquest canvi: {0}.", "No puedo hacer ese cambio: {0}.",
                                      "I can't make that change: {0}.")
        case .rulesAskInvalid: return ("La Tria no ha retornat un canvi que es pugui aplicar. Torna-ho a provar.",
                                       "Tria no ha devuelto un cambio que se pueda aplicar. Vuelve a probar.",
                                       "Tria didn't return a change that can be applied. Try again.")
        case .rulesChangeChanged: return ("TRIA.md ha canviat des que ho vas demanar. Torna-ho a demanar.",
                                          "TRIA.md ha cambiado desde que lo pediste. Vuelve a pedirlo.",
                                          "TRIA.md has changed since you asked. Ask again.")
        case .rulesChangeLocked: return ("S'està ordenant des d'un altre lloc (el CLI o un altre Mac). Torna-ho a provar d'aquí a un moment.",
                                         "Ordenando desde otro sitio (el CLI u otro Mac). Vuelve a probar en un momento.",
                                         "Sorting from somewhere else (the CLI or another Mac). Try again in a moment.")
        case .rulesWhyRules: return ("TRIA.md no seria vàlid ({0})", "TRIA.md no sería válido ({0})",
                                     "TRIA.md would not be valid ({0})")
        case .rulesWhyInbox: return ("canviaria la carpeta de la safata", "cambiaría la carpeta de la bandeja",
                                     "it would change the inbox folder")
        case .rulesWhyDuplicates: return ("canviaria la carpeta de duplicats", "cambiaría la carpeta de duplicados",
                                          "it would change the duplicates folder")
        case .rulesWhyUnsafe: return ("«{0}» no és una carpeta vàlida dins de l'espai",
                                      "«{0}» no es una carpeta válida dentro del espacio",
                                      "'{0}' is not a valid folder inside the workspace")
        case .rulesWhyExists: return ("la carpeta «{0}» ja existeix", "la carpeta «{0}» ya existe",
                                      "the folder '{0}' already exists")
        case .rulesWhyRepeated: return ("la carpeta «{0}» surt dues vegades", "la carpeta «{0}» sale dos veces",
                                        "the folder '{0}' appears twice")
        case .rulesWhyInboxProtected: return ("la safata quedaria dins d'una ruta protegida",
                                              "la bandeja quedaría dentro de una ruta protegida",
                                              "the inbox would be inside a protected path")
        case .rulesWhyDuplicatesProtected: return ("la carpeta de duplicats quedaria dins d'una ruta protegida",
                                                   "la carpeta de duplicados quedaría dentro de una ruta protegida",
                                                   "the duplicates folder would be inside a protected path")
        case .rulesWhyProtectedFolder: return ("la carpeta «{0}» és dins d'una ruta protegida",
                                               "la carpeta «{0}» está dentro de una ruta protegida",
                                               "the folder '{0}' is inside a protected path")
        case .screenConfidence: return ("confiança {0}", "confianza {0}", "{0} confidence")
        case .screenTrash: return ("Paperera", "Papelera", "Trash")
        case .screenEdited: return ("editat", "editado", "edited")
        case .screenUndone: return ("ja ho vas desfer una vegada", "ya lo deshiciste una vez", "undone once before")
        case .screenHelp: return ("↑↓ moure't  espai marcar  a només alta  e editar  p paperera  ↩ aplicar {0}  q sortir",
                                  "↑↓ moverse  espacio marcar  a solo alta  e editar  p papelera  ↩ aplicar {0}  q salir",
                                  "↑↓ move  space mark  a high only  e edit  p trash  ↩ apply {0}  q quit")
        case .screenHelpShort: return ("↑↓ · espai · a · e · p · ↩ aplicar {0} · q sortir",
                                       "↑↓ · espacio · a · e · p · ↩ aplicar {0} · q salir",
                                       "↑↓ · space · a · e · p · ↩ apply {0} · q quit")
        case .evalRunning: return ("Avaluant la mostra ({0}) amb {1}…", "Evaluando la muestra ({0}) con {1}…",
                                   "Evaluating the sample ({0}) with {1}…")
        case .evalDoneOne: return ("{0} document avaluat en {1} s", "{0} documento evaluado en {1} s",
                                   "{0} document evaluated in {1} s")
        case .evalDoneMany: return ("{0} documents avaluats en {1} s", "{0} documentos evaluados en {1} s",
                                    "{0} documents evaluated in {1} s")
        case .learnRunning: return ("Llegint la mostra ({0})…", "Leyendo la muestra ({0})…", "Reading the sample ({0})…")
        case .learnDone: return ("Esborrany llest en {0} s", "Borrador listo en {0} s", "Draft ready in {0} s")
        }
    }
}
