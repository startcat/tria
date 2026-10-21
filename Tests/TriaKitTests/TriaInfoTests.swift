import Testing
@testable import TriaKit

@Test func versionLineCarriesStartcatCredit() {
    #expect(TriaInfo.versionLine == "tria 1.0.0 — Un producto de Start.cat · https://start.cat")
}
