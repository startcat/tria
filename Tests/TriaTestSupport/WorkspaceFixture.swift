import Foundation
import TriaKit

public enum WorkspaceFixture {
    public static let defaultRules = """
    ---
    inbox: 99-Pendiente
    duplicates: 98-Duplicados
    protected:
      - "7-Facturas/20*/"
    new_folders: subfolders_only
    ---
    # Reglas de prueba

    ## Carpetas
    | Carpeta | Contenido |
    |---|---|
    | 1-Modelos Tributarios/ | Modelos de la AEAT, una subcarpeta por modelo |
    | 7-Facturas/ | Facturas; los paquetes AAAA/ son intocables |

    ## Nomenclatura
    | Tipo | Formato | Ejemplo |
    |---|---|---|
    | Modelo | `Modelo XXX - AAAA - TT.pdf` | `Modelo 303 - 2023 - 1T.pdf` |
    """

    public static let defaultFolders = [
        "1-Modelos Tributarios/Modelo 303 - IVA",
        "7-Facturas/Recibidas",
        "7-Facturas/2013/1T",
    ]

    public static func make(in dir: TempDir, rules: String = defaultRules,
                            folders: [String] = defaultFolders) throws -> Workspace {
        let workspace = try Workspace.initialize(at: dir.url, rulesText: rules)
        for folder in folders { try dir.mkdir(folder) }
        return workspace
    }
}
