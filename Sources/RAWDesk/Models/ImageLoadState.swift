import Foundation

public enum ImageLoadState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed(reason: String)
    case unsupported(reason: String)

    public var isTerminal: Bool {
        switch self {
        case .loaded, .failed, .unsupported: return true
        case .idle, .loading: return false
        }
    }
}
