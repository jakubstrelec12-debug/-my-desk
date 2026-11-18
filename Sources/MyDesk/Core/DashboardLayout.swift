import Foundation

/// Geometry is expressed in macOS points, including when the window is on Sidecar.
struct DashboardLayout {
    let width: CGFloat
    let height: CGFloat
    let compact: Bool
    var gap: CGFloat { compact ? 10 : 14 }
    var inset: CGFloat { compact ? 12 : 24 }
    var headerHeight: CGFloat { compact ? 42 : 52 }
    var contentWidth: CGFloat { max(0, width - inset * 2) }
    var contentHeight: CGFloat { max(compact ? 590 : 720, height - inset * 2 - headerHeight - gap) }
    var columns: Int { width >= 960 ? 3 : width >= 680 ? 2 : 1 }
    var leftWidth: CGFloat { columns == 1 ? contentWidth : (contentWidth - gap * CGFloat(columns - 1)) * (columns == 3 ? 0.25 : 0.34) }
    var centerWidth: CGFloat { columns == 1 ? contentWidth : (contentWidth - gap * CGFloat(columns - 1)) * (columns == 3 ? 0.48 : 0.66) }
    var rightWidth: CGFloat { columns == 3 ? (contentWidth - gap * 2) * 0.27 : contentWidth }
    init(width: CGFloat, height: CGFloat, mode: String = "auto") {
        self.width = width; self.height = height
        compact = mode == "compact" || (mode == "auto" && (width < 1280 || height < 820))
    }
    func panelHeight(_ key: String, weights: [(String, CGFloat)], visible: Set<String>) -> CGFloat {
        let enabled = weights.filter { visible.contains($0.0) }
        let total = enabled.reduce(CGFloat.zero) { $0 + $1.1 }
        guard let weight = enabled.first(where: { $0.0 == key })?.1, total > 0 else { return 0 }
        return max(0, contentHeight - CGFloat(max(0, enabled.count - 1)) * gap) * weight / total
    }
}
