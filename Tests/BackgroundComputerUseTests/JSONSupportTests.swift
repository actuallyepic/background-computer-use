import Foundation
import Testing
@testable import BackgroundComputerUse

@Suite
struct JSONSupportTests {
    @Test
    func decodesDatesEncodedBySharedEncoder() throws {
        let capturedAt = Date(timeIntervalSince1970: 1_777_354_343)
        let contract = try ScreenshotCoordinateContract.make(
            capturedAt: capturedAt,
            stateToken: "bst_fixture",
            targetWindow: TargetWindowIdentity(
                bundleID: "com.example.fixture",
                pid: 123,
                windowNumber: 456,
                title: "Fixture",
                logicalFrameTopLeft: GlobalEventTapTopLeftRect(
                    x: 10,
                    y: 20,
                    width: 640,
                    height: 480
                )
            ),
            modelFacingPath: "/tmp/model.png",
            modelFacingPixelSize: PixelSize(width: 640, height: 480),
            rawPath: nil,
            rawPixelSize: nil
        )

        let encoded = try JSONSupport.encoder.encode(contract)
        let json = try #require(String(data: encoded, encoding: .utf8))
        #expect(json.contains(#""capturedAt" : "2026-"#))

        let decoded = try JSONSupport.decoder.decode(ScreenshotCoordinateContract.self, from: encoded)
        #expect(decoded.capturedAt == capturedAt)
    }
}
