import Foundation
import Testing
@testable import TriaCLI
@testable import TriaKit

private func makeState(_ items: [SortItem] = UIFixtures.mockup) -> ReviewState {
    ReviewState(plan: UIFixtures.plan(items))
}

private func press(_ state: inout ReviewState, _ keys: KeyPress...) {
    for key in keys { _ = state.handle(key) }
}

struct ReviewStateTests {
    @Test func theReviewStartsWithWhatAutoWouldApply() {
        let plan = UIFixtures.plan(UIFixtures.mockup)
        let review = ReviewState(plan: plan)
        #expect(review.marked == ["99-Pendiente/scan_0012.pdf", "99-Pendiente/scan_0013.pdf",
                                  "99-Pendiente/descarga (2).pdf"])
        #expect(review.approved() == SortPipeline.automaticItems(plan))
    }

    @Test func somethingUndoneBeforeStartsUnmarked() {
        let review = makeState([UIFixtures.proposal("alta.pdf", "7-Facturas/Recibidas/A.pdf", undone: true)])
        #expect(review.marked.isEmpty)
    }

    @Test func arrowsAndVimKeysMoveTheCursorWithinTheList() {
        var review = makeState()
        #expect(review.handle(.up) == .none && review.cursor == 0)
        press(&review, .down, .character("j"))
        #expect(review.cursor == 2)
        press(&review, .character("K"))
        #expect(review.cursor == 1)
        for _ in 0..<10 { press(&review, .down) }
        #expect(review.cursor == 4)
    }

    @Test func spaceMarksAndUnmarksButPendingStaysOut() {
        var review = makeState()
        press(&review, .down, .down, .space)                       // nota.pdf
        #expect(review.marked.contains("99-Pendiente/nota.pdf"))
        press(&review, .space)
        #expect(!review.marked.contains("99-Pendiente/nota.pdf"))
        press(&review, .down, .down, .space)                       // IMG_4471.jpg, pendiente
        #expect(!review.marked.contains("99-Pendiente/IMG_4471.jpg"))
    }

    @Test func aKeepsOnlyHighConfidence() {
        var review = makeState()
        press(&review, .down, .down, .space, .character("a"))
        #expect(review.marked == ["99-Pendiente/scan_0012.pdf", "99-Pendiente/scan_0013.pdf"])
    }

    @Test func pSendsADuplicateToTheTrashAndBack() {
        var review = makeState()
        #expect(review.handle(.character("p")) == .none)          // en una propuesta no hace nada
        #expect(review.trashed.isEmpty)
        press(&review, .down, .down, .down, .character("p"))       // descarga (2).pdf
        #expect(review.trashed == ["99-Pendiente/descarga (2).pdf"])
        #expect(review.approved().contains { $0.action.kind == .trash && $0.action.source == "99-Pendiente/descarga (2).pdf" })
        press(&review, .character("p"))
        #expect(review.trashed.isEmpty && review.marked.contains("99-Pendiente/descarga (2).pdf"))
        press(&review, .character("p"), .space)                    // desmarcar también la saca de la Papelera
        #expect(review.trashed.isEmpty && !review.marked.contains("99-Pendiente/descarga (2).pdf"))
    }

    @Test func eAsksTheSessionToEditOnlyProposals() {
        var review = makeState()
        #expect(review.handle(.character("e")) == .edit(UIFixtures.mockup[0]))
        press(&review, .down, .down, .down)
        #expect(review.handle(.character("e")) == .none)
    }

    @Test func anEditIsMarkedAppliedAndRemembered() throws {
        var review = makeState()
        let item = UIFixtures.mockup[2]
        guard case .proposal(let proposal, _) = item.kind else { Issue.record("no es una propuesta"); return }
        let approved = ApprovedItem(action: FilingAction(kind: .file, source: item.relativePath,
                                                         destination: "6-Varios/Notas/Nota Ejemplo.pdf"),
                                    sha256: item.sha256)
        let correction = SortCorrection(item: item, original: proposal, folder: "6-Varios/Notas", filename: "Nota Ejemplo.pdf")
        review.applyEdit(SortEdit(approved: approved, correction: correction), to: item.id)
        #expect(review.marked.contains(item.id))
        #expect(review.approved().contains(approved))
        #expect(review.corrections() == [correction])
        #expect(review.reservedDestinations(excluding: "otro").contains("6-Varios/Notas/Nota Ejemplo.pdf"))
        #expect(!review.reservedDestinations(excluding: item.id).contains("6-Varios/Notas/Nota Ejemplo.pdf"))
        #expect(review.reservedDestinations(excluding: item.id)
                .contains("2-Facturas Recibidas/2026/4T/Factura Papeleria Mar - 2026-10-05.pdf"))
    }

    @Test func enterAppliesQAndEscapeQuitAndCtrlCInterrupts() {
        var review = makeState()
        #expect(review.handle(.enter) == .apply)
        #expect(review.handle(.character("q")) == .quit)
        #expect(review.handle(.escape) == .quit)
        #expect(review.handle(.end) == .quit)
        #expect(review.handle(.interrupt) == .interrupt)
    }

    @Test func theListScrollsWithTheCursor() {
        let many = (1...30).map { UIFixtures.proposal("doc \($0).pdf", "7-Facturas/Recibidas/Doc \($0).pdf") }
        var review = makeState(many)
        for _ in 0..<10 { press(&review, .down) }
        review.scroll(visibleRows: 4)
        #expect(review.top == 7)
        for _ in 0..<10 { press(&review, .up) }
        review.scroll(visibleRows: 4)
        #expect(review.top == 0)
    }

    @Test func anEmptyStateIgnoresEveryKeySafely() {
        var review = makeState([])
        for key in [KeyPress.space, .character("e"), .character("p"), .character("j"), .character("k"),
                    .character("a"), .down, .up] {
            #expect(review.handle(key) == .none)
        }
        #expect(review.handle(.enter) == .apply)
        #expect(review.approved().isEmpty && review.current == nil && review.cursor == 0)
        review.scroll(visibleRows: 4)
        #expect(review.top == 0)
    }
}
