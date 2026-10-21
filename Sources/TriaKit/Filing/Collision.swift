import Foundation

public enum Collision {
    /// Primera ruta libre: "nombre.ext", "nombre (2).ext", "nombre (3).ext"… Nunca se sobrescribe.
    public static func uniqueRelativePath(_ relative: String, root: URL, reserved: Set<String> = []) -> String {
        let taken = Set(reserved.map { $0.normalizedRelativePath.lowercased() })
        let path = relative.normalizedRelativePath
        func isFree(_ candidate: String) -> Bool {
            !taken.contains(candidate.lowercased())
                && !FileManager.default.fileExists(atPath: root.appendingPathComponent(candidate).path)
        }
        if isFree(path) { return path }
        let ext = (path as NSString).pathExtension
        let base = (path as NSString).deletingPathExtension
        let folder = (base as NSString).deletingLastPathComponent
        var counter = 2
        while true {
            // El nombre se recorta para que, con el sufijo, siga cabiendo en 255 bytes.
            let suffix = ext.isEmpty ? " (\(counter))" : " (\(counter)).\(ext)"
            var name = (base as NSString).lastPathComponent
            while (name + suffix).utf8.count > FilenameSanitizer.maxBytes && !name.isEmpty { name.removeLast() }
            let candidate = folder.isEmpty ? name + suffix : "\(folder)/\(name)\(suffix)"
            if isFree(candidate) { return candidate }
            counter += 1
        }
    }
}
