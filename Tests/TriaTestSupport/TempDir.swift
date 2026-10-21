import Foundation

/// Directorio temporal que se borra al liberarse. Resuelve enlaces simbólicos (/var → /private/var)
/// para que las comparaciones de rutas con la raíz del espacio sean fiables.
public final class TempDir: @unchecked Sendable {
    public let url: URL

    public init(_ name: String = "tria-test") throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        url = base.resolvingSymlinksInPath()
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    @discardableResult
    public func write(_ relative: String, _ contents: String = "x") throws -> URL {
        let target = url.appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: target)
        return target
    }

    @discardableResult
    public func mkdir(_ relative: String) throws -> URL {
        let target = url.appendingPathComponent(relative, isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        return target
    }
}
