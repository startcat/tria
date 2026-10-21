public enum StringSimilarity {
    public static func normalized(_ text: String) -> String {
        text.nfc.lowercased().trimmingCharacters(in: .whitespaces)
    }

    public static func levenshtein(_ a: String, _ b: String) -> Int {
        let lhs = Array(a), rhs = Array(b)
        guard !lhs.isEmpty else { return rhs.count }
        guard !rhs.isEmpty else { return lhs.count }
        var previous = Array(0...rhs.count)
        for i in 1...lhs.count {
            var current = [i] + Array(repeating: 0, count: rhs.count)
            for j in 1...rhs.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (lhs[i - 1] == rhs[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return previous[rhs.count]
    }

    /// 1 = iguales (sin distinguir mayúsculas), 0 = nada en común.
    public static func ratio(_ a: String, _ b: String) -> Double {
        let lhs = normalized(a), rhs = normalized(b)
        let longest = max(lhs.count, rhs.count)
        guard longest > 0 else { return 1 }
        return 1 - Double(levenshtein(lhs, rhs)) / Double(longest)
    }
}
