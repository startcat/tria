/// Identidad del producto. La firma, en castellano, es la de la app; `tria --version` usa la traducida
/// (`L10n.versionLine`).
public enum TriaInfo {
    public static let version = "1.0.0"
    public static let credit = "Un producto de Start.cat · https://start.cat"
    public static var versionLine: String { "tria \(version) — \(credit)" }
}
