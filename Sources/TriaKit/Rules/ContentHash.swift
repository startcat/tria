import TriaCore

// La huella usa CryptoKit, que solo existe en Apple: por eso vive en TriaKit y no en TriaCore.
extension RulesFile {
    public var hash: String { Hashing.sha256(raw) }
}

extension ProfileFile {
    public var hash: String { Hashing.sha256(raw) }
}
