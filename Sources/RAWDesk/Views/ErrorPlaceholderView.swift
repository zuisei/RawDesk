import SwiftUI

struct ErrorPlaceholderView: View {
    enum Kind {
        case unsupported(String)
        case failed(String)
        case empty(String)
        case loading
    }
    let kind: Kind

    var body: some View {
        RAWEmptyState(
            title: title,
            indicator: indicator,
            message: detail ?? ""
        )
    }

    private var indicator: RAWEmptyStateIndicator {
        if case .loading = kind {
            return .progress
        }
        return .symbol(iconName)
    }

    private var iconName: String {
        switch kind {
        case .unsupported: return "questionmark.square.dashed"
        case .failed: return "exclamationmark.triangle"
        case .empty: return "photo.on.rectangle.angled"
        case .loading: return "hourglass"
        }
    }
    private var title: String {
        switch kind {
        case .unsupported: return "Unsupported or undecodable file"
        case .failed: return "Could not load image"
        case .empty(let s): return s
        case .loading: return "Loading…"
        }
    }
    private var detail: String? {
        switch kind {
        case .unsupported(let s), .failed(let s): return s
        default: return nil
        }
    }
}
