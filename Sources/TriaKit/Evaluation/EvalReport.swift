import Foundation

public struct EvalCase: Codable, Sendable, Equatable {
    public var source: String
    public var expectedFolder: String
    public var expectedFilename: String
    public var outcome: String
    public var proposedFolder: String?
    public var proposedFilename: String?
    public var confidence: Confidence?
    public var folderCorrect: Bool
    public var filenameExact: Bool
    public var filenameSimilarity: Double
    public var detail: String?
}

public struct ConfidenceStats: Codable, Sendable, Equatable {
    public var count: Int
    public var folderCorrect: Int
    public var accuracy: Double { count == 0 ? 0 : Double(folderCorrect) / Double(count) }
}

public struct EvalReport: Codable, Sendable, Equatable {
    public var date: Date
    public var provider: String
    public var model: String
    public var sampleSize: Int
    public var folderAccuracy: Double
    public var filenameExactRate: Double
    public var filenameFuzzyRate: Double
    public var pendingRate: Double
    public var unreadableCount: Int
    public var byConfidence: [String: ConfidenceStats]
    public var usage: TokenUsage
    public var cost: Double?
    public var cases: [EvalCase]
    /// La ejecución se cortó (cuota, límite de peticiones…): el informe solo cubre los casos terminados.
    public var interruption: String?

    public static func build(cases: [EvalCase], provider: String, model: String, usage: TokenUsage, date: Date) -> EvalReport {
        let total = Double(max(cases.count, 1))
        let filed = cases.filter { $0.outcome == "filed" }
        var byConfidence: [String: ConfidenceStats] = [:]
        for item in filed {
            let key = item.confidence?.rawValue ?? "unknown"
            var stats = byConfidence[key] ?? ConfidenceStats(count: 0, folderCorrect: 0)
            stats.count += 1
            if item.folderCorrect { stats.folderCorrect += 1 }
            byConfidence[key] = stats
        }
        return EvalReport(
            date: date, provider: provider, model: model, sampleSize: cases.count,
            folderAccuracy: Double(filed.filter(\.folderCorrect).count) / total,
            filenameExactRate: Double(filed.filter(\.filenameExact).count) / total,
            filenameFuzzyRate: Double(filed.filter { $0.filenameSimilarity >= 0.8 }.count) / total,
            pendingRate: Double(cases.filter { $0.outcome == "pending" }.count) / total,
            unreadableCount: cases.filter { $0.outcome == "unreadable" }.count,
            byConfidence: byConfidence, usage: usage, cost: Pricing.cost(usage, model: model), cases: cases)
    }
}

public struct EvalComparison: Sendable, Equatable {
    public var folderDelta: Double
    public var filenameDelta: Double
    public var regressed: Bool
}
