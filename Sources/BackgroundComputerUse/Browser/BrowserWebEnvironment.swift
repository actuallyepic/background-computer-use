import AppKit
import Foundation
@preconcurrency import WebKit

@MainActor
struct BrowserWebEnvironment {
    static func makeConfiguration(dataStore: WKWebsiteDataStore) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        let userContentController = WKUserContentController()
        userContentController.addUserScript(bootstrapScript())
        configuration.userContentController = userContentController
        configuration.websiteDataStore = dataStore
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        return configuration
    }

    static func installBootstrap(on controller: WKUserContentController) {
        controller.addUserScript(bootstrapScript())
    }

    private static func bootstrapScript() -> WKUserScript {
        WKUserScript(
            source: BrowserBootstrapScript.source,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
    }
}
