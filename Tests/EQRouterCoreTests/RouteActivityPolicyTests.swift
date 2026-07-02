import Testing
@testable import EQRouterCore

struct RouteActivityPolicyTests {
    @Test func liveRouteWithStoppedOutputAutoPauses() {
        let action = RouteActivityPolicy.transition(
            currentHealth: .verified,
            isLive: true,
            isRunningOutput: false
        )
        #expect(action == .autoPause)
    }

    @Test func pausedRouteWithResumedOutputAutoResumes() {
        let action = RouteActivityPolicy.transition(
            currentHealth: .paused,
            isLive: false,
            isRunningOutput: true
        )
        #expect(action == .autoResume)
    }

    @Test func idleRouteWithResumedOutputDoesNotAutoStart() {
        let action = RouteActivityPolicy.transition(
            currentHealth: .idle,
            isLive: false,
            isRunningOutput: true
        )
        #expect(action == .none)
    }
}
