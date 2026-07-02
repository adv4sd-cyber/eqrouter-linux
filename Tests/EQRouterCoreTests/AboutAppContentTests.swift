import Testing
@testable import EQRouterCore

struct AboutAppContentTests {
    @Test func autoEqNoticeIncludesRequiredAttribution() {
        let notices = AboutAppContent.thirdPartyNotices
        let autoEq = notices.first(where: { $0.name == "AutoEq" })

        #expect(autoEq != nil)
        #expect(autoEq?.author == "Jaakko Pasanen")
        #expect(autoEq?.licenseName == "MIT License")
        #expect(autoEq?.summary.contains("AutoEq") == true)
    }

    @Test func correctionSectionAttributionMentionsOnlyAutoEq() {
        #expect(AboutAppContent.correctionSectionAttribution == "Bundled correction library: AutoEq")
    }
}
