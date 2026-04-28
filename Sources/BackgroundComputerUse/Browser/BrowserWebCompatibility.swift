import AppKit
import Foundation
@preconcurrency import WebKit

public enum BrowserWebCompatibility {
    public static let desktopSafariUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.6 Safari/605.1.15"
}

public enum BrowserWebViewGeometry {
    @MainActor
    public static func appKitPoint(forViewportPoint point: PointDTO, in webView: WKWebView) -> CGPoint {
        let viewportHeight = max(webView.bounds.height, 1)
        let localPoint = NSPoint(
            x: CGFloat(point.x),
            y: webView.isFlipped ? CGFloat(point.y) : viewportHeight - CGFloat(point.y)
        )
        let windowPoint = webView.convert(localPoint, to: nil)
        return webView.window?.convertPoint(toScreen: windowPoint) ?? windowPoint
    }

    @MainActor
    public static func appKitRect(forViewportRect rect: RectDTO, in webView: WKWebView) -> CGRect {
        let topLeft = appKitPoint(forViewportPoint: PointDTO(x: rect.x, y: rect.y), in: webView)
        let bottomRight = appKitPoint(
            forViewportPoint: PointDTO(x: rect.x + rect.width, y: rect.y + rect.height),
            in: webView
        )
        return CGRect(
            x: min(topLeft.x, bottomRight.x),
            y: min(topLeft.y, bottomRight.y),
            width: abs(bottomRight.x - topLeft.x),
            height: abs(bottomRight.y - topLeft.y)
        )
    }
}
