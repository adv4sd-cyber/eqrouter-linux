import Foundation

public enum RouteDSPStage: Equatable {
    case capture
    case render
}

public enum RouteRealtimeWorkStrategy {
    public static let defaultDSPStage: RouteDSPStage = .capture
}
