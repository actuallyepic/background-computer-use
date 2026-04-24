import AppKit
import Foundation

enum RuntimePermissionPresenter {
    static func showIfNeeded(permissions: RuntimePermissionsDTO, instructions: BootstrapInstructionsDTO) {
        guard instructions.ready == false else {
            return
        }

        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "BackgroundComputerUse needs permissions"
            alert.informativeText = instructions.user.joined(separator: "\n\n")
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open Privacy Settings")
            alert.addButton(withTitle: "OK")

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                if permissions.accessibility.granted == false {
                    openPrivacyPane("Privacy_Accessibility")
                } else if permissions.screenRecording.granted == false {
                    openPrivacyPane("Privacy_ScreenCapture")
                }
            }
        }
    }

    private static func openPrivacyPane(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}
