import CryptoKit
import Foundation

enum BrowserStateToken {
    private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    static func make(target: BrowserTargetSummaryDTO, window: ResolvedWindowDTO, dom: BrowserDOMSnapshotDTO) -> String {
        let interactableComponent = dom.interactables
            .prefix(250)
            .map { item in
                [
                    String(item.displayIndex),
                    item.nodeID,
                    item.role,
                    item.text ?? "",
                    rectComponent(item.rectViewport)
                ].joined(separator: ":")
            }
            .joined(separator: ";")
        let payload = [
            target.targetID,
            target.url ?? "",
            target.title,
            rectComponent(window.frameAppKit),
            String(dom.viewport.scrollX),
            String(dom.viewport.scrollY),
            dom.focusedElement?.nodeID ?? "",
            interactableComponent
        ].joined(separator: "|")
        let digest = SHA256.hash(data: Data(payload.utf8))

        var value: UInt64 = 0
        for byte in digest.prefix(8) {
            value = (value << 8) | UInt64(byte)
        }

        var characters = Array(repeating: Character("0"), count: 13)
        for index in stride(from: 12, through: 0, by: -1) {
            characters[index] = alphabet[Int(value & 31)]
            value >>= 5
        }

        return "bst_\(String(characters))"
    }

    private static func rectComponent(_ rect: RectDTO) -> String {
        [
            stableNumber(rect.x),
            stableNumber(rect.y),
            stableNumber(rect.width),
            stableNumber(rect.height)
        ].joined(separator: ",")
    }

    private static func stableNumber(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
}
