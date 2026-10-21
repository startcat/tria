import Foundation
import Testing
@testable import TriaCLI
@testable import TriaKit

private func review(env: CLIEnvironment,
                    edit: @escaping (SortItem, Set<String>) throws -> SortEdit? = { _, _ in nil }) -> FullScreenReview {
    FullScreenReview(plan: UIFixtures.plan(UIFixtures.mockup),
                     header: ReviewHeader(workspace: "Despacho", model: "claude-haiku-5-5", cost: nil),
                     env: env, style: .plain, edit: edit)
}

struct FullScreenReviewTests {
    @Test func enterAppliesWhatIsMarked() throws {
        let env = try CLIHarness().env
        let screen = FakeScreen(keys: [.down, .down, .space, .enter])
        guard case .apply(let approved, let corrections) = try review(env: env).run(on: screen) else {
            Issue.record("no aplica")
            return
        }
        #expect(approved.map(\.action.source) == ["99-Pendiente/scan_0012.pdf", "99-Pendiente/scan_0013.pdf",
                                                  "99-Pendiente/nota.pdf", "99-Pendiente/descarga (2).pdf"])
        #expect(corrections.isEmpty)
        #expect(screen.events == ["enter", "leave"])
        #expect(screen.frames.last?.last?.contains("aplicar 4") == true)
    }

    @Test func qLeavesWithoutMovingAnything() throws {
        let env = try CLIHarness().env
        let screen = FakeScreen(keys: [.space, .character("q")])
        #expect(try review(env: env).run(on: screen) == .cancelled)
        #expect(screen.events == ["enter", "leave"])
    }

    @Test func ctrlCInTheFullScreenLeavesItAndAppliesNothing() throws {
        let env = try CLIHarness().env
        let screen = FakeScreen(keys: [.interrupt])
        #expect(throws: TerminalInterrupt.self) { try review(env: env).run(on: screen) }
        #expect(screen.events == ["enter", "leave"])
    }

    @Test func aResizeRedrawsWithTheNewSize() throws {
        let env = try CLIHarness().env
        let screen = FakeScreen(keys: [nil, nil, .character("q")],
                                sizes: [TerminalSize(columns: 100, rows: 30), TerminalSize(columns: 100, rows: 30),
                                        TerminalSize(columns: 70, rows: 14)])
        _ = try review(env: env).run(on: screen)
        #expect(screen.frames.count == 2)                           // el mismo tamaño no redibuja
        #expect(screen.frames[1].allSatisfy { TextWidth.columns($0) < 70 })
        #expect(TextWidth.columns(screen.frames[1][1]) == 69)       // la raya ocupa el ancho nuevo
    }

    @Test func eLeavesTheScreenToEditAndComesBack() throws {
        let env = try CLIHarness().env
        let item = UIFixtures.mockup[2]
        let edited = SortEdit(approved: ApprovedItem(action: FilingAction(kind: .file, source: item.relativePath,
                                                                          destination: "6-Varios/Notas/Nota.pdf"),
                                                     sha256: item.sha256),
                              correction: nil)
        var asked: (SortItem, Set<String>)?
        let screen = FakeScreen(keys: [.down, .down, .character("e"), .enter])
        let outcome = try review(env: env, edit: { item, reserved in
            asked = (item, reserved)
            return edited
        }).run(on: screen)
        #expect(asked?.0 == item)
        #expect(asked?.1.contains("2-Facturas Recibidas/2026/4T/Factura Papeleria Mar - 2026-10-05.pdf") == true)
        #expect(screen.events == ["enter", "leave", "enter", "leave"])
        guard case .apply(let approved, _) = outcome else {
            Issue.record("no aplica")
            return
        }
        #expect(approved.contains(edited.approved))
    }

    @Test func anEditWithoutAnswersChangesNothing() throws {
        let env = try CLIHarness().env
        let screen = FakeScreen(keys: [.down, .down, .character("e"), .enter])
        guard case .apply(let approved, _) = try review(env: env).run(on: screen) else {
            Issue.record("no aplica")
            return
        }
        #expect(!approved.contains { $0.action.source == "99-Pendiente/nota.pdf" })
    }
}
