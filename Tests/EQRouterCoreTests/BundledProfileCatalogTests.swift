import Testing
@testable import EQRouterCore

struct BundledProfileCatalogTests {
    @Test func bundledCatalogLoadsExpectedProfiles() {
        let profiles = HeadphoneProfile.allBundled

        #expect(profiles.count > 2000)
        #expect(profiles.contains(where: { $0.id == HeadphoneProfile.orivetiOD200.id }))
        #expect(profiles.contains(where: { $0.modelName == "Sennheiser HD 600" }))
        #expect(profiles.contains(where: { $0.modelName == "Sony WH-1000XM5" }))
    }

    @Test func featuredProfilesStayReachable() {
        let featured = HeadphoneProfile.featuredBundledProfiles

        #expect(featured.count >= 20)
        #expect(featured.contains(where: { $0.modelName == "Apple AirPods Max" }))
        #expect(featured.contains(where: { $0.modelName == "AKG K371" }))
    }

    @Test func bundledLookupFindsGeneratedProfileByID() {
        let hd600 = HeadphoneProfile.allBundled.first(where: { $0.modelName == "Sennheiser HD 600" })
        #expect(hd600 != nil)
        #expect(HeadphoneProfile.bundled(id: hd600?.id ?? "") == hd600)
    }
}
