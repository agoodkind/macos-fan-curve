import AppKit

enum AppVisibilityState: Equatable {
    case interactive
    case passiveVisible
    case occluded
}

@MainActor
func currentAppVisibilityState(app: NSApplication = .shared) -> AppVisibilityState {
    guard !app.isHidden else { return .occluded }

    let visibleWindows = app.windows.filter { window in
        guard window.isVisible, !window.isMiniaturized else { return false }
        return window.occlusionState.contains(.visible) || window.isKeyWindow || window.isMainWindow
    }

    guard !visibleWindows.isEmpty else { return .occluded }

    if visibleWindows.contains(where: { $0.isKeyWindow || $0.isMainWindow }) {
        return .interactive
    }

    return .passiveVisible
}
