#if DEBUG
import Foundation
import os

/// La Papelera de la tanda QA: con `folder` puesto, lo que Tria manda a la Papelera va a esa carpeta y no a la del Mac,
/// y desde ahí se puede deshacer igual. Solo existe en Debug. La ponen el CLI con `TRIA_QA=1` (`<raíz>/papelera/`) y
/// el modo de prueba de la app QA; sin ponerla, la Papelera es la de siempre.
public enum QATrash {
    private static let storage = OSAllocatedUnfairLock<URL?>(initialState: nil)

    /// Una carpeta (o `nil`, la Papelera del Mac) solo para la tarea en curso y las que lance. Es para las pruebas:
    /// así ninguna toca `folder`, que es de todo el proceso, y varias pueden correr a la vez sin pisarse ni mandar nada
    /// a la Papelera de verdad. `.none` (por defecto) es que no hay override.
    @TaskLocal static var override: URL??

    /// La carpeta que hace de Papelera. `nil`, la del Mac. Es de todo el proceso: se pone al arrancar. Lo que
    /// cuenta primero es `override`, si la tarea lo tiene.
    public static var folder: URL? {
        get {
            if let scoped = override { return scoped }
            return storage.withLock { $0 }
        }
        set { storage.withLock { $0 = newValue } }
    }

    /// La Papelera que monta el CLI con `TRIA_QA=1`: `<TRIA_QA_ROOT>/papelera/`, o una carpeta temporal si no hay
    /// raíz, nunca la del Mac. Sin `TRIA_QA=1`, `nil`. No toca `folder`: eso lo hace quien arranca el proceso.
    public static func folder(forEnvironment environment: [String: String]) -> URL? {
        guard environment["TRIA_QA"] == "1" else { return nil }
        let root = environment["TRIA_QA_ROOT"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
        let base = root ?? FileManager.default.temporaryDirectory.appendingPathComponent("tria-qa", isDirectory: true)
        return base.appendingPathComponent("papelera", isDirectory: true)
    }

    /// Mueve `url` a `folder` sin pisar nada («basura (2).pdf», como la Papelera del Mac) y devuelve dónde ha quedado.
    static func move(_ url: URL, into folder: URL) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = Collision.uniqueRelativePath(url.lastPathComponent, root: folder)
        let target = folder.appendingPathComponent(name)
        try FileManager.default.moveItem(at: url, to: target)
        return target
    }

    /// `path` está dentro de `folder`: para deshacer, cuenta como la Papelera.
    static func contains(_ path: String) -> Bool {
        guard let folder else { return false }
        return path.hasPrefix(folder.path.hasSuffix("/") ? folder.path : folder.path + "/")
    }
}
#endif
