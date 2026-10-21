import Foundation

public enum ValidationError: Error, Equatable, Sendable {
    case emptyDestination
    case unsafePath(String)
    case outsideRoot(String)
    case protectedPath(String)
    case intoInbox
    case intoDuplicates
    case folderMissing(String)
    case newTopLevelFolder(String)
    case blockedByFile(String)
    case emptyFilename
    /// El destino acaba en algo con aspecto de fichero ("…/Factura.pdf"): el nombre va en `filename`.
    case fileNameInDestination(String)

    /// Explicación para devolver al modelo en el reintento (spec §6.3, paso 5).
    public var feedback: String {
        switch self {
        case .emptyDestination: return "destination is empty; give a folder path relative to the archive root"
        case .unsafePath(let path): return "destination '\(path)' must be relative, without '..' and outside .tria"
        case .outsideRoot(let path): return "destination '\(path)' resolves outside the archive"
        case .protectedPath(let path): return "'\(path)' is protected; choose another folder"
        case .intoInbox: return "the inbox folder is not a valid destination"
        case .intoDuplicates: return "the duplicates folder is not a valid destination"
        case .folderMissing(let path):
            return "folder '\(path)' does not exist and new folders are not allowed; use an existing folder from the tree"
        case .newTopLevelFolder(let name):
            return "new top-level folder '\(name)' is not allowed; use an existing top-level folder"
        case .blockedByFile(let path): return "'\(path)' is a file, not a folder"
        case .emptyFilename: return "filename is empty"
        case .fileNameInDestination(let name):
            return "destination ends in '\(name)', which looks like a file name; give only the folder path and put the name in filename"
        }
    }
}

/// Invariantes deterministas (spec §6.5). La IA propone; esto decide.
public struct Validator: Sendable {
    public let workspace: Workspace

    public init(workspace: Workspace) { self.workspace = workspace }

    public func validate(_ proposal: Proposal, originalFilename: String,
                         reserved: Set<String> = []) -> Result<String, ValidationError> {
        let raw = proposal.destination.trimmingCharacters(in: .whitespacesAndNewlines)
        // Sin espacios alrededor de cada componente: "7-Facturas / Recibidas" es la carpeta existente, no una gemela.
        let cleaned = raw.split(separator: "/", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "/")
        if cleaned.hasPrefix("/") || cleaned.hasPrefix("~") || cleaned.split(separator: "/").contains("..") {
            return .failure(.unsafePath(raw))
        }
        let normalized = cleaned.normalizedRelativePath
        guard !normalized.isEmpty else { return .failure(.emptyDestination) }
        // Nada oculto: ni `.tria` (en cualquier forma: "./.tria", ".TRIA") ni carpetas ocultas.
        guard PathSafety.isSafeRelative(normalized) else { return .failure(.unsafePath(raw)) }

        let resolved = PathResolver.resolve(normalized, root: workspace.root)
        if let blocked = resolved.blockedBy { return .failure(.blockedByFile(blocked)) }
        let canonical = resolved.relative
        let components = canonical.split(separator: "/").map(String.init)
        if let error = destinationError(canonical) { return .failure(error) }
        if resolved.missingComponents > 0, let last = components.last, FilenameSanitizer.hasDocumentExtension(last) {
            return .failure(.fileNameInDestination(last))
        }

        if resolved.missingComponents > 0 {
            switch workspace.rules.header.newFolders {
            case .never: return .failure(.folderMissing(canonical))
            case .subfoldersOnly where resolved.missingComponents == components.count:
                return .failure(.newTopLevelFolder(components[0]))
            default: break
            }
        }

        guard let filename = FilenameSanitizer.sanitize(proposal.filename, originalFilename: originalFilename) else {
            return .failure(.emptyFilename)
        }
        return .success(Collision.uniqueRelativePath("\(canonical)/\(filename)", root: workspace.root, reserved: reserved))
    }

    /// Invariantes 1-3 sobre una ruta relativa (carpeta o fichero), tal cual y con los enlaces simbólicos resueltos:
    /// un enlace no puede llevar a una carpeta protegida, a la bandeja ni fuera de la raíz. El Executor lo repite
    /// justo antes de mover.
    public func destinationError(_ relative: String, allowDuplicates: Bool = false) -> ValidationError? {
        guard PathSafety.isSafeRelative(relative) else { return .unsafePath(relative) }
        guard let effective = workspace.resolvedRelativePath(relative) else { return .outsideRoot(relative) }
        if !effective.isEmpty && !PathSafety.isSafeRelative(effective) { return .unsafePath(relative) }
        for path in [relative.normalizedRelativePath, effective] {
            if workspace.protectedPaths.contains(path) { return .protectedPath(path) }
            if Self.isInside(path, workspace.rules.header.inbox) { return .intoInbox }
            if !allowDuplicates && Self.isInside(path, workspace.rules.header.duplicates) { return .intoDuplicates }
        }
        return nil
    }

    public func duplicateDestination(originalFilename: String, reserved: Set<String> = []) -> String {
        Collision.uniqueRelativePath("\(workspace.rules.header.duplicates)/\(originalFilename.nfc)",
                                     root: workspace.root, reserved: reserved)
    }

    private static func isInside(_ path: String, _ folder: String) -> Bool {
        let lhs = path.lowercased(), rhs = folder.normalizedRelativePath.lowercased()
        return lhs == rhs || lhs.hasPrefix(rhs + "/")
    }
}
