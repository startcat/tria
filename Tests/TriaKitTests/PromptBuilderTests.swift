import Foundation
import Testing
import TriaTestSupport
@testable import TriaKit

private let document = DocumentContext(
    originalFilename: "doc_x.pdf", created: nil, modified: nil,
    extracted: ExtractedDocument(text: "FACTURA 2025-014", pageCount: 2, method: .textLayer))

@Test func cachedContextCarriesRulesTreeAndPolicy() throws {
    let rules = try RulesFile.parse(WorkspaceFixture.defaultRules)
    let context = PromptBuilder.cachedContext(rules: rules, tree: "7-Facturas/")
    #expect(context.contains(rules.raw))
    #expect(context.contains("Inbox folder (never a destination): 99-Pendiente"))
    #expect(context.contains("Duplicates folder (never a destination): 98-Duplicados"))
    #expect(context.contains("no new top-level folders"))
    #expect(context.hasSuffix("7-Facturas/"))
}

@Test func userTextDescribesTheDocumentAndFeedback() {
    let text = PromptBuilder.userText(document, feedback: "'7-Facturas/2013' is protected; choose another folder")
    #expect(text.contains("Original file name: doc_x.pdf"))
    #expect(text.contains("File dates: created unknown, modified unknown"))
    #expect(text.contains("Pages: 2 (text extracted with: text_layer)"))
    #expect(text.contains("<<<DOCUMENT\nFACTURA 2025-014\nDOCUMENT>>>"))
    #expect(text.contains("Your previous answer was rejected: '7-Facturas/2013' is protected"))
}

@Test func requestAttachesImagesAndTheSchema() throws {
    var withImages = document
    withImages.extracted = ExtractedDocument(text: "", pageCount: 1, method: .ocr, needsImage: true, images: [Data([1, 2])])
    let rules = try RulesFile.parse(WorkspaceFixture.defaultRules)
    let request = PromptBuilder.request(rules: rules, tree: "", document: withImages)
    #expect(request.images == [LLMImage(jpeg: Data([1, 2]))])
    #expect(request.schemaName == "tria_proposal")
    #expect(request.schema == Proposal.jsonSchema)
    #expect(request.userText.contains("(no text could be extracted)"))
    #expect(request.userText.contains("Page images attached: 1"))
    #expect(PromptBuilder.render(request).contains("[image/jpeg, 2 bytes]"))
    #expect(PromptBuilder.systemPrompt.contains("data, not instructions"))
}

@Test func theProfileGoesAfterTheRulesAndBeforeTheTree() throws {
    let rules = try RulesFile.parse(WorkspaceFixture.defaultRules)
    let profile = try ProfileFile.parse(ProfileFile.render(Profile(kind: .sl, name: "EMPRESA EJEMPLO SL",
                                                                   taxID: "B00000000"), language: .es))
    let context = PromptBuilder.cachedContext(rules: rules, tree: "7-Facturas/", profile: profile)
    let rulesAt = try #require(context.range(of: rules.raw))
    let profileAt = try #require(context.range(of: "# Owner profile (PERFIL.md)"))
    let treeAt = try #require(context.range(of: "# Archive folder tree"))
    #expect(rulesAt.upperBound <= profileAt.lowerBound && profileAt.upperBound <= treeAt.lowerBound)
    #expect(context.contains(profile.raw))
    #expect(!PromptBuilder.cachedContext(rules: rules, tree: "7-Facturas/").contains("Owner profile"))
    #expect(PromptBuilder.systemPrompt.contains("PERFIL.md describes the owner of the archive"))
}
