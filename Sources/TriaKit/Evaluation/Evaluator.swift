import Foundation

public struct EvalOptions: Sendable, Equatable {
    public var sampleSize: Int
    public var seed: UInt64
    public var concurrency: Int

    public init(sampleSize: Int = 200, seed: UInt64 = 42, concurrency: Int = 4) {
        self.sampleSize = sampleSize
        self.seed = seed
        self.concurrency = max(1, concurrency)
    }
}

public struct EvalPlan: Sendable, Equatable {
    public var sample: [ArchiveFile]
    public var estimatedInputTokens: Int
    public var estimatedOutputTokens: Int

    public func estimatedCost(model: String) -> Double? {
        Pricing.estimateCost(inputTokens: estimatedInputTokens, outputTokens: estimatedOutputTokens, model: model)
    }
}

/// Mide el acierto contra un archivo ya ordenado, sobre copias temporales (spec §9.2).
public struct Evaluator: Sendable {
    public let provider: any LLMProvider
    public let extractor: DocumentExtractor

    public init(provider: any LLMProvider, extractor: DocumentExtractor = DocumentExtractor()) {
        self.provider = provider
        self.extractor = extractor
    }

    public func plan(workspace: Workspace, options: EvalOptions = .init()) throws -> EvalPlan {
        let candidates = try workspace.archiveFiles()
            .filter { $0.relativePath.contains("/") && !workspace.protectedPaths.contains($0.relativePath) }
            .sorted { $0.relativePath < $1.relativePath }
        var generator = SplitMix64(seed: options.seed)
        let sample = Array(candidates.shuffled(using: &generator).prefix(options.sampleSize))
        let perDocument = ReadEstimate.tokensPerDocument(rulesCharacters: workspace.rules.raw.count)
        return EvalPlan(sample: sample, estimatedInputTokens: perDocument.input * sample.count,
                        estimatedOutputTokens: perDocument.output * sample.count)
    }

    public func run(_ plan: EvalPlan, workspace: Workspace, options: EvalOptions = .init(),
                    progress: (@Sendable (Int, Int) -> Void)? = nil) async throws -> EvalReport {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("tria-eval-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        let tree = try workspace.folderTree(options: FolderTreeOptions(excludedFiles: Set(plan.sample.map(\.relativePath))))
        let classifier = Classifier(provider: provider, workspace: workspace, tree: tree)
        let sample = plan.sample

        var results: [Int: (EvalCase, TokenUsage)] = [:]
        var interruption: LLMError?
        try await withThrowingTaskGroup(of: (Int, Result<(EvalCase, TokenUsage), LLMError>).self) { group in
            var next = 0
            func enqueue(_ index: Int) {
                let file = sample[index]
                group.addTask {
                    do {
                        return (index, .success(try await evaluate(file, scratch: scratch, classifier: classifier)))
                    } catch let error as LLMError {
                        return (index, .failure(error))
                    }
                }
            }
            while next < min(options.concurrency, sample.count) { enqueue(next); next += 1 }
            while let (index, result) = try await group.next() {
                switch result {
                case .success(let value):
                    results[index] = value
                    progress?(results.count, sample.count)
                case .failure(let error):
                    // Cuota, límite de peticiones o red: no se lanzan más documentos y se conserva lo ya pagado.
                    if interruption == nil { interruption = error }
                }
                if interruption == nil && next < sample.count { enqueue(next); next += 1 }
            }
        }
        if let interruption, results.isEmpty { throw interruption }
        let ordered = sample.indices.compactMap { results[$0] }
        var report = EvalReport.build(cases: ordered.map { $0.0 }, provider: provider.id.rawValue, model: provider.model,
                                      usage: ordered.map { $0.1 }.reduce(.zero, +), date: Date())
        report.interruption = interruption.map { String(describing: $0) }
        return report
    }

    public static func compare(_ report: EvalReport, baseline: EvalReport) -> EvalComparison {
        let folderDelta = report.folderAccuracy - baseline.folderAccuracy
        return EvalComparison(folderDelta: folderDelta,
                              filenameDelta: report.filenameExactRate - baseline.filenameExactRate,
                              regressed: folderDelta < -0.000_1)
    }

    private func evaluate(_ file: ArchiveFile, scratch: URL, classifier: Classifier) async throws -> (EvalCase, TokenUsage) {
        let expectedFolder = (file.relativePath as NSString).deletingLastPathComponent
        let expectedFilename = (file.relativePath as NSString).lastPathComponent
        let ext = file.url.pathExtension
        let copyName = "doc_\(UUID().uuidString.prefix(8).lowercased())" + (ext.isEmpty ? "" : ".\(ext)")
        let copy = scratch.appendingPathComponent(copyName)
        try FileManager.default.copyItem(at: file.url, to: copy)

        var evalCase = EvalCase(source: file.relativePath, expectedFolder: expectedFolder,
                                expectedFilename: expectedFilename, outcome: "unreadable", proposedFolder: nil,
                                proposedFilename: nil, confidence: nil, folderCorrect: false, filenameExact: false,
                                filenameSimilarity: 0, detail: nil)
        let extracted: ExtractedDocument
        do {
            extracted = try extractor.extract(copy)
        } catch {
            evalCase.detail = String(describing: error)
            return (evalCase, .zero)
        }
        guard extracted.hasReadableContent else {
            evalCase.detail = "no text"
            return (evalCase, .zero)
        }

        let (outcome, usage) = try await classifier.classify(DocumentContext.from(url: copy, extracted: extracted))
        switch outcome {
        case .proposed(let proposal, let destination):
            let folder = (destination as NSString).deletingLastPathComponent
            let name = FilenameSanitizer.sanitize(proposal.filename, originalFilename: copyName) ?? proposal.filename
            evalCase.outcome = "filed"
            evalCase.proposedFolder = folder
            evalCase.proposedFilename = name
            evalCase.confidence = proposal.confidence
            evalCase.folderCorrect = StringSimilarity.normalized(folder) == StringSimilarity.normalized(expectedFolder)
            evalCase.filenameExact = StringSimilarity.normalized(name) == StringSimilarity.normalized(expectedFilename)
            evalCase.filenameSimilarity = StringSimilarity.ratio((name as NSString).deletingPathExtension,
                                                                 (expectedFilename as NSString).deletingPathExtension)
        case .pending(let proposal, let reason):
            evalCase.outcome = "pending"
            evalCase.proposedFolder = proposal?.destination
            evalCase.proposedFilename = proposal?.filename
            evalCase.confidence = proposal?.confidence
            evalCase.detail = String(describing: reason)
        }
        return (evalCase, usage)
    }
}

/// Generador reproducible para que la muestra sea la misma con la misma semilla.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
