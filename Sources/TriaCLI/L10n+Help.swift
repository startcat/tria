import ArgumentParser
import TriaKit

/// La ayuda de los comandos (`--help`) en catalán, castellano e inglés. ArgumentParser la pide antes de que el comando
/// tenga su entorno, así que el idioma sale de `CLIEnvironment.current`, que en el proceso real lo detecta igual que
/// los mensajes (`Lang.detect`). Las cabeceras («OVERVIEW», «USAGE», «OPTIONS») son de ArgumentParser y no se traducen.
public enum HelpKey: String, CaseIterable, Sendable {
    case triaAbstract, credit
    case configAbstract, configProvider, configModel, configSetKey, configDeleteKey, evalAbstract
    case evalArchive, evalRules, evalSynthetic, evalSample, evalSeed, evalOutput
    case evalBaseline, evalJSON, evalYes, initAbstract, initTemplate, initLearn
    case initLang, initRoot, noConfirm, root, logAbstract, logBatch
    case rulesAbstract, rulesCheckAbstract, rulesLearnAbstract, rulesLearnLang, rulesSuggestionsAbstract, rulesSuggestionsApply
    case rulesSuggestionsDiscard, rulesAskAbstract, rulesAskRequest, applyWithoutAsking, sortAbstract, sortAuto
    case sortDryRun, sortJSON, sortShowPrompt, sortNoCache, statusAbstract, undoAbstract
    case undoBatch, undoLast
}

extension L10n {
    public static func help(_ key: HelpKey, _ lang: Lang = CLIEnvironment.current.lang) -> String {
        let entry = helpTable(key)
        switch lang {
        case .ca: return entry.ca
        case .es: return entry.es
        case .en: return entry.en
        }
    }

    /// `tria --version`: la versión y la firma de Start.cat en el idioma del usuario.
    public static func versionLine(_ lang: Lang) -> String {
        "tria \(TriaInfo.version) — \(help(.credit, lang))"
    }

    private static func helpTable(_ key: HelpKey) -> (ca: String, es: String, en: String) {
        switch key {
        case .triaAbstract: return ("Lyncat Tria: ordena documents amb IA, sense esborrar ni sobreescriure mai res.",
                                    "Lyncat Tria: ordena documentos con IA, sin borrar ni sobrescribir nunca.",
                                    "Lyncat Tria: sorts documents with AI, never deleting or overwriting anything.")
        case .credit: return ("Un producte de Start.cat · https://start.cat", "Un producto de Start.cat · https://start.cat",
                              "A Start.cat product · https://start.cat")
        case .configAbstract: return ("Mostra o canvia el proveïdor, el model i la API key (al Clauer).",
                          "Muestra o cambia el proveedor, el modelo y la API key (en el Llavero).",
                          "Shows or changes the provider, the model and the API key (in the Keychain).")
        case .configProvider: return ("Proveïdor: anthropic o openai.",
                          "Proveedor: anthropic u openai.",
                          "Provider: anthropic or openai.")
        case .configModel: return ("Model; buit per tornar al predeterminat.",
                          "Modelo; vacío para volver al de por defecto.",
                          "Model; empty to go back to the default.")
        case .configSetKey: return ("Desar la API key al Clauer (es demana sense mostrar-la).",
                          "Guardar la API key en el Llavero (se pide sin mostrarla).",
                          "Save the API key in the Keychain (asked for without showing it).")
        case .configDeleteKey: return ("Esborrar la API key del Clauer.",
                          "Borrar la API key del Llavero.",
                          "Delete the API key from the Keychain.")
        case .evalAbstract: return ("Mesura l'encert amb un arxiu ja ordenat. Treballa sobre còpies: mai no toca els originals.",
                          "Mide el acierto contra un archivo ya ordenado. Trabaja sobre copias: nunca toca los originales.",
                          "Measures accuracy against an already sorted archive. Works on copies: never touches the originals.")
        case .evalArchive: return ("Carpeta ja ordenada.",
                          "Carpeta ya ordenada.",
                          "Already sorted folder.")
        case .evalRules: return ("Fitxer de regles que s'ha de fer servir en lloc del TRIA.md de la carpeta.",
                          "Fichero de reglas a usar en lugar del TRIA.md de la carpeta.",
                          "Rules file to use instead of the folder's TRIA.md.")
        case .evalSynthetic: return ("Fer servir l'arxiu sintètic inclòs (documents inventats).",
                          "Usar el archivo sintético incluido (documentos inventados).",
                          "Use the bundled synthetic archive (made-up documents).")
        case .evalSample: return ("Mida de la mostra.",
                          "Tamaño de la muestra.",
                          "Sample size.")
        case .evalSeed: return ("Llavor de la mostra (mateixa llavor, mateixa mostra).",
                          "Semilla de la muestra (misma semilla, misma muestra).",
                          "Sample seed (same seed, same sample).")
        case .evalOutput: return ("Desar l'informe JSON en aquest fitxer.",
                          "Guardar el informe JSON en este fichero.",
                          "Save the JSON report to this file.")
        case .evalBaseline: return ("Informe JSON de referència: surt amb 1 si l'encert baixa.",
                          "Informe JSON de referencia: sale con 1 si el acierto baja.",
                          "Reference JSON report: exits with 1 if accuracy drops.")
        case .evalJSON: return ("Imprimir l'informe en JSON.",
                          "Imprimir el informe en JSON.",
                          "Print the report as JSON.")
        case .evalYes: return ("No demanar confirmació del cost.",
                          "No pedir confirmación del coste.",
                          "Don't ask to confirm the cost.")
        case .initAbstract: return ("Crea un espai de treball: TRIA.md, safata i carpeta de duplicats.",
                          "Crea un espacio de trabajo: TRIA.md, bandeja y carpeta de duplicados.",
                          "Creates a workspace: TRIA.md, inbox and duplicates folder.")
        case .initTemplate: return ("Plantilla: autonomo, sl o hogar.",
                          "Plantilla: autonomo, sl u hogar.",
                          "Template: autonomo, sl or hogar.")
        case .initLearn: return ("Aprendre les regles de l'estructura actual de la carpeta.",
                          "Aprender las reglas de la estructura actual de la carpeta.",
                          "Learn the rules from the folder's current structure.")
        case .initLang: return ("Idioma de la plantilla: es o ca.",
                          "Idioma de la plantilla: es o ca.",
                          "Template language: es or ca.")
        case .initRoot: return ("Carpeta de l'espai (per defecte, l'actual).",
                          "Carpeta del espacio (por defecto, la actual).",
                          "Workspace folder (the current one by default).")
        case .noConfirm: return ("No demanar confirmació.",
                          "No pedir confirmación.",
                          "Don't ask for confirmation.")
        case .root: return ("Carpeta de l'espai.",
                          "Carpeta del espacio.",
                          "Workspace folder.")
        case .logAbstract: return ("Historial de lots i moviments.",
                          "Historial de lotes y movimientos.",
                          "History of batches and moves.")
        case .logBatch: return ("Id d'un lot per veure'n els moviments.",
                          "Id de un lote para ver sus movimientos.",
                          "A batch id, to see its moves.")
        case .rulesAbstract: return ("Valida TRIA.md, aprèn regles de la carpeta, gestiona les suggerides i demana canvis a la Tria.",
                          "Valida TRIA.md, aprende reglas de la carpeta, gestiona las sugeridas y pide cambios a Tria.",
                          "Validates TRIA.md, learns rules from the folder, manages suggested ones and asks Tria for changes.")
        case .rulesCheckAbstract: return ("Valida TRIA.md i avisa dels problemes.",
                          "Valida TRIA.md y avisa de problemas.",
                          "Validates TRIA.md and warns about problems.")
        case .rulesLearnAbstract: return ("Genera un esborrany de regles (TRIA.draft.md) a partir de la carpeta.",
                          "Genera un borrador de reglas (TRIA.draft.md) a partir de la carpeta.",
                          "Generates a draft of rules (TRIA.draft.md) from the folder.")
        case .rulesLearnLang: return ("Idioma de l'esborrany: es o ca.",
                          "Idioma del borrador: es o ca.",
                          "Draft language: es or ca.")
        case .rulesSuggestionsAbstract: return ("Llista, aplica o descarta les regles suggerides per les teves correccions.",
                          "Lista, aplica o descarta las reglas sugeridas por tus correcciones.",
                          "Lists, applies or discards the rules suggested by your corrections.")
        case .rulesSuggestionsApply: return ("Id del suggeriment que s'afegeix a TRIA.md.",
                          "Id de la sugerencia que se añade a TRIA.md.",
                          "Id of the suggestion to add to TRIA.md.")
        case .rulesSuggestionsDiscard: return ("Id del suggeriment que es descarta.",
                          "Id de la sugerencia que se descarta.",
                          "Id of the suggestion to discard.")
        case .rulesAskAbstract: return ("Demana a la Tria un canvi de TRIA.md en una frase, i te'l mostra abans d'aplicar-lo.",
                          "Pide a Tria un cambio de TRIA.md en una frase y lo enseña antes de aplicarlo.",
                          "Asks Tria for a TRIA.md change in one sentence and shows it before applying it.")
        case .rulesAskRequest: return ("El que vols canviar, en una frase.",
                          "Lo que quieres cambiar, en una frase.",
                          "What you want to change, in one sentence.")
        case .applyWithoutAsking: return ("Aplicar sense preguntar.",
                          "Aplicar sin preguntar.",
                          "Apply without asking.")
        case .sortAbstract: return ("Processa la safata: proposa destinació i nom, i aplica el que aprovis.",
                          "Procesa la bandeja: propone destino y nombre, y aplica lo que apruebes.",
                          "Processes the inbox: proposes a destination and a name, and applies what you approve.")
        case .sortAuto: return ("Aplicar sense preguntar la confiança alta i els duplicats exactes.",
                          "Aplicar sin preguntar la confianza alta y los duplicados exactos.",
                          "Apply high-confidence proposals and exact duplicates without asking.")
        case .sortDryRun: return ("Només proposar; no moure res.",
                          "Solo proponer; no mover nada.",
                          "Only propose; don't move anything.")
        case .sortJSON: return ("Sortida en JSON (per a scripts).",
                          "Salida en JSON (para scripts).",
                          "JSON output (for scripts).")
        case .sortShowPrompt: return ("Mostrar exactament el que s'envia al proveïdor d'IA.",
                          "Mostrar exactamente lo que se envía al proveedor de IA.",
                          "Show exactly what is sent to the AI provider.")
        case .sortNoCache: return ("Tornar a preguntar a la IA encara que hi hagi una proposta desada a la memòria cau.",
                          "Volver a preguntar a la IA aunque haya una propuesta guardada en la caché.",
                          "Ask the AI again even if a proposal is cached.")
        case .statusAbstract: return ("Mostra la safata i l'estat de cada document, sense cridar la IA.",
                          "Muestra la bandeja y el estado de cada documento, sin llamar a la IA.",
                          "Shows the inbox and the status of each document, without calling the AI.")
        case .undoAbstract: return ("Desfà l'últim lot o un de concret.",
                          "Deshace el último lote o uno concreto.",
                          "Undoes the last batch or a specific one.")
        case .undoBatch: return ("Id del lot (mira `tria log`). Sense id, l'últim.",
                          "Id del lote (ver `tria log`). Sin id, el último.",
                          "Batch id (see `tria log`). Without an id, the last one.")
        case .undoLast: return ("Desfer l'últim lot (és el que es fa per defecte).",
                          "Deshacer el último lote (es lo que se hace por defecto).",
                          "Undo the last batch (the default).")
        }
    }
}

extension ArgumentHelp {
    /// La ayuda de una opción, del catálogo: `@Option(help: .catalog(.root))`.
    static func catalog(_ key: HelpKey) -> ArgumentHelp { ArgumentHelp(L10n.help(key)) }
}
