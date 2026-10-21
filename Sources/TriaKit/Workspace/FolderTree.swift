import Foundation

public struct FolderTreeOptions: Sendable, Equatable {
    public var maxDepth: Int
    public var examplesPerFolder: Int
    public var maxLines: Int
    /// Rutas relativas de ficheros que no se muestran como ejemplo (lo usa `tria eval`).
    public var excludedFiles: Set<String>

    public init(maxDepth: Int = 4, examplesPerFolder: Int = 3, maxLines: Int = 1500,
                excludedFiles: Set<String> = []) {
        self.maxDepth = maxDepth
        self.examplesPerFolder = examplesPerFolder
        self.maxLines = maxLines
        self.excludedFiles = Set(excludedFiles.map(\.normalizedRelativePath))
    }
}

/// Árbol de carpetas que se envía al modelo como contexto (spec §6.3).
public enum FolderTree {
    private struct Node {
        var name: String
        var isProtected: Bool
        var children: [Node]
        var examples: [String]
    }

    public static func render(root: URL, skipping: [String], protected: ProtectedPaths,
                              options: FolderTreeOptions = .init()) throws -> String {
        let skipped = Set(skipping.map { $0.normalizedRelativePath.lowercased() })
        let nodes = try scan(root, relative: "", depth: 1, skipped: skipped, protected: protected, options: options)

        var attempts = [(options.examplesPerFolder, options.maxDepth)]
        for depth in stride(from: options.maxDepth, through: 1, by: -1) { attempts.append((0, depth)) }
        var lines: [String] = []
        for (examples, depth) in attempts {
            lines = []
            for node in nodes { emit(node, level: 1, maxDepth: depth, examples: examples, into: &lines) }
            if lines.count <= options.maxLines { return lines.joined(separator: "\n") }
        }
        return (lines.prefix(options.maxLines - 1) + ["… (truncated)"]).joined(separator: "\n")
    }

    private static func scan(_ url: URL, relative: String, depth: Int, skipped: Set<String>,
                             protected: ProtectedPaths, options: FolderTreeOptions) throws -> [Node] {
        guard depth <= options.maxDepth else { return [] }
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey]
        // Una carpeta ilegible (sin permiso) se muestra sin contenido: no impide ordenar el resto (spec §10).
        let items = (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        var nodes: [Node] = []
        for item in items where (try? item.resourceValues(forKeys: Set(keys)))?.isDirectory == true {
            let name = item.lastPathComponent.nfc
            let path = relative.isEmpty ? name : "\(relative)/\(name)"
            if depth == 1 && skipped.contains(path.lowercased()) { continue }
            if protected.contains(path) {
                nodes.append(Node(name: name, isProtected: true, children: [], examples: []))
                continue
            }
            let children = try scan(item, relative: path, depth: depth + 1, skipped: skipped,
                                    protected: protected, options: options)
            nodes.append(Node(name: name, isProtected: false, children: children,
                              examples: examples(in: item, relative: path, options: options)))
        }
        return nodes.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func examples(in url: URL, relative: String, options: FolderTreeOptions) -> [String] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
        return ((try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? [])
            .compactMap { item -> (String, Date)? in
                guard let values = try? item.resourceValues(forKeys: Set(keys)) else { return nil }
                let name = item.lastPathComponent.nfc
                guard values.isRegularFile == true, !options.excludedFiles.contains("\(relative)/\(name)") else { return nil }
                return (name, values.contentModificationDate ?? .distantPast)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(options.examplesPerFolder)
            .map { $0.0 }
    }

    private static func emit(_ node: Node, level: Int, maxDepth: Int, examples: Int, into lines: inout [String]) {
        guard level <= maxDepth else { return }
        let indent = String(repeating: "  ", count: level - 1)
        lines.append("\(indent)\(node.name)/" + (node.isProtected ? " [protected]" : ""))
        for example in node.examples.prefix(examples) { lines.append("\(indent)  · \(example)") }
        for child in node.children { emit(child, level: level + 1, maxDepth: maxDepth, examples: examples, into: &lines) }
    }
}

extension Workspace {
    public func folderTree(options: FolderTreeOptions = .init()) throws -> String {
        try FolderTree.render(root: root, skipping: [rules.header.inbox, rules.header.duplicates],
                              protected: protectedPaths, options: options)
    }
}
