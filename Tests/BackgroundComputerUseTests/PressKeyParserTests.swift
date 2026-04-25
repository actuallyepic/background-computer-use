import XCTest
@testable import BackgroundComputerUse

final class PressKeyParserTests: XCTestCase {
    func testParserMatchesDocumentedBackspaceParity() throws {
        let accepted = try PressKeyParser.parse("BackSpace")
        XCTAssertEqual(accepted.key, "backspace")
        XCTAssertEqual(Int(accepted.keyCode), 51)

        XCTAssertThrowsError(try PressKeyParser.parse("Backspace"))
        XCTAssertThrowsError(try PressKeyParser.parse("backspace"))
    }

    func testParserRejectsRawSlashButAcceptsSlashToken() throws {
        XCTAssertThrowsError(try PressKeyParser.parse("/"))

        let accepted = try PressKeyParser.parse("slash")
        XCTAssertEqual(accepted.key, "/")
        XCTAssertEqual(Int(accepted.keyCode), 44)
    }

    func testParserAcceptsKeypadDigits() throws {
        let zero = try PressKeyParser.parse("KP_0")
        XCTAssertEqual(zero.key, "kp_0")
        XCTAssertEqual(Int(zero.keyCode), 82)

        let nine = try PressKeyParser.parse("KP_9")
        XCTAssertEqual(nine.key, "kp_9")
        XCTAssertEqual(Int(nine.keyCode), 92)
    }

    func testParserRejectsEnterButAcceptsReturn() throws {
        XCTAssertThrowsError(try PressKeyParser.parse("Enter"))

        let accepted = try PressKeyParser.parse("Return")
        XCTAssertEqual(accepted.key, "return")
        XCTAssertEqual(Int(accepted.keyCode), 36)
    }

    func testParserNormalizesCommandFIntent() throws {
        let parsed = try PressKeyParser.parse("super+f")
        XCTAssertEqual(parsed.dto.normalized, "command+f")
        XCTAssertEqual(parsed.intent, .openFindOrSearch)
    }

    func testNativeCommandFRequiresSearchEvidenceBeyondVisualChange() throws {
        let service = PressKeyRouteService()
        let parsed = try PressKeyParser.parse("super+f")
        let search = PressKeySearchVerificationDTO(
            beforeSearchFieldCount: 0,
            afterSearchFieldCount: 0,
            focusedSearchFieldVerified: false,
            targetWindowNumberBefore: 1,
            targetWindowNumberAfter: 1,
            targetWindowTitleBefore: "Before",
            targetWindowTitleAfter: "After",
            frontmostBundleIDBefore: nil,
            frontmostBundleIDAfter: nil
        )

        XCTAssertFalse(service.nativeEffectVerified(
            dispatchSucceeded: true,
            parsed: parsed,
            renderedChanged: false,
            focusedChanged: false,
            textStateChanged: false,
            selectionChanged: false,
            visualChanged: true,
            search: search
        ))
    }

    func testNativeCommandFVerifiesSearchFieldAppearing() throws {
        let service = PressKeyRouteService()
        let parsed = try PressKeyParser.parse("super+f")
        let search = PressKeySearchVerificationDTO(
            beforeSearchFieldCount: 0,
            afterSearchFieldCount: 1,
            focusedSearchFieldVerified: false,
            targetWindowNumberBefore: 1,
            targetWindowNumberAfter: 1,
            targetWindowTitleBefore: "Before",
            targetWindowTitleAfter: "After",
            frontmostBundleIDBefore: nil,
            frontmostBundleIDAfter: nil
        )

        XCTAssertTrue(service.nativeEffectVerified(
            dispatchSucceeded: true,
            parsed: parsed,
            renderedChanged: false,
            focusedChanged: false,
            textStateChanged: false,
            selectionChanged: false,
            visualChanged: false,
            search: search
        ))
    }

    func testNativeCommandChordDoesNotVerifyVisualOnlyChange() throws {
        let service = PressKeyRouteService()
        let parsed = try PressKeyParser.parse("super+shift+p")

        XCTAssertFalse(service.nativeEffectVerified(
            dispatchSucceeded: true,
            parsed: parsed,
            renderedChanged: false,
            focusedChanged: false,
            textStateChanged: false,
            selectionChanged: false,
            visualChanged: true,
            search: nil
        ))
    }

    func testWindowServerPreparationRequiresSuccessfulTargetFocusAndKeyWindowRecordsForKeys() {
        let preparedForClick = NativeWindowServerPreparationResult(
            psnStatus: 0,
            targetFocusStatus: 0,
            keyWindowStatuses: [],
            notes: [],
            warnings: []
        )
        XCTAssertTrue(preparedForClick.preparedTargetWindow(requireKeyWindowRecords: false))
        XCTAssertFalse(preparedForClick.preparedTargetWindow(requireKeyWindowRecords: true))

        let preparedForKeys = NativeWindowServerPreparationResult(
            psnStatus: 0,
            targetFocusStatus: 0,
            keyWindowStatuses: [0, 0],
            notes: [],
            warnings: []
        )
        XCTAssertTrue(preparedForKeys.preparedTargetWindow(requireKeyWindowRecords: true))

        let skipped = NativeWindowServerPreparationResult(
            psnStatus: nil,
            targetFocusStatus: nil,
            keyWindowStatuses: [],
            notes: [],
            warnings: []
        )
        XCTAssertFalse(skipped.preparedTargetWindow(requireKeyWindowRecords: false))

        let partialKeyWindow = NativeWindowServerPreparationResult(
            psnStatus: 0,
            targetFocusStatus: 0,
            keyWindowStatuses: [0],
            notes: [],
            warnings: []
        )
        XCTAssertFalse(partialKeyWindow.preparedTargetWindow(requireKeyWindowRecords: true))

        let nonZeroKeyWindow = NativeWindowServerPreparationResult(
            psnStatus: 0,
            targetFocusStatus: 0,
            keyWindowStatuses: [0, 1],
            notes: [],
            warnings: []
        )
        XCTAssertFalse(nonZeroKeyWindow.preparedTargetWindow(requireKeyWindowRecords: true))
    }
}
