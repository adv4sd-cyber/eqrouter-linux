import Foundation

public enum RouteActivityTransition: Equatable {
    case none
    case autoPause
    case autoResume
}

public enum RouteActivityPolicy {
    public static func transition(
        currentHealth: RouteHealth,
        isLive: Bool,
        isRunningOutput: Bool
    ) -> RouteActivityTransition {
        if isLive && !isRunningOutput {
            return .autoPause
        }

        if !isLive && currentHealth == .paused && isRunningOutput {
            return .autoResume
        }

        return .none
    }
}
