import AppKit
import Foundation

enum BrowserCursorTargeting {
    static func notAttempted(
        requested: CursorRequestDTO?,
        reason: String,
        options: ActionExecutionOptions
    ) -> ActionCursorTargetResponseDTO {
        let session = CursorRuntime.resolve(requested: requested)
        return ActionCursorTargetResponseDTO(
            session: session,
            targetPointAppKit: nil,
            targetPointSource: nil,
            moved: false,
            moveDurationMs: nil,
            movement: options.visualCursorEnabled ? "not_attempted" : "disabled",
            warnings: [reason]
        )
    }

    static func prepareClick(
        requested: CursorRequestDTO?,
        point: CGPoint,
        pointSource: String,
        windowNumber: Int,
        options: ActionExecutionOptions
    ) -> ActionCursorTargetResponseDTO {
        guard options.visualCursorEnabled else {
            return disabledCursor(requested: requested, point: point, pointSource: pointSource)
        }

        let session = CursorRuntime.resolve(requested: requested)
        let duration = CursorRuntime.approach(
            to: point,
            attachedWindowNumber: windowNumber,
            cursorID: session.id
        )
        CursorRuntime.waitUntilSettled(cursorID: session.id, timeout: duration + 0.35)
        CursorRuntime.setPressed(true, cursorID: session.id, attachedWindowNumber: windowNumber)
        sleepRunLoop(CursorRuntime.pressLeadDuration())

        return ActionCursorTargetResponseDTO(
            session: session,
            targetPointAppKit: PointDTO(x: point.x, y: point.y),
            targetPointSource: pointSource,
            moved: true,
            moveDurationMs: sanitizedJSONDouble(duration * 1_000),
            movement: "approach_click_choreography",
            warnings: []
        )
    }

    static func finishClick(cursor: ActionCursorTargetResponseDTO) {
        guard cursor.moved else { return }
        CursorRuntime.finishClick(cursorID: cursor.session.id, afterHold: CursorRuntime.releaseHoldDuration())
    }

    static func prepareTypeText(
        requested: CursorRequestDTO?,
        point: CGPoint,
        pointSource: String,
        windowNumber: Int,
        options: ActionExecutionOptions
    ) -> ActionCursorTargetResponseDTO {
        guard options.visualCursorEnabled else {
            return disabledCursor(requested: requested, point: point, pointSource: pointSource)
        }

        let session = CursorRuntime.resolve(requested: requested)
        let duration = CursorRuntime.prepareTypeText(
            to: point,
            attachedWindowNumber: windowNumber,
            cursorID: session.id
        )
        return ActionCursorTargetResponseDTO(
            session: session,
            targetPointAppKit: PointDTO(x: point.x, y: point.y),
            targetPointSource: pointSource,
            moved: true,
            moveDurationMs: sanitizedJSONDouble(duration * 1_000),
            movement: "approach_type_text_choreography",
            warnings: []
        )
    }

    static func finishTypeText(cursor: ActionCursorTargetResponseDTO, text: String) {
        guard cursor.moved else { return }
        CursorRuntime.finishTypeText(cursorID: cursor.session.id, text: text)
    }

    static func prepareScroll(
        requested: CursorRequestDTO?,
        point: CGPoint,
        pointSource: String,
        direction: ScrollDirectionDTO,
        windowNumber: Int,
        options: ActionExecutionOptions
    ) -> ActionCursorTargetResponseDTO {
        guard options.visualCursorEnabled else {
            return disabledCursor(requested: requested, point: point, pointSource: pointSource)
        }

        let mapped = cursorScrollMapping(for: direction)
        let session = CursorRuntime.resolve(requested: requested)
        let duration = CursorRuntime.prepareScroll(
            to: point,
            axis: mapped.axis,
            direction: mapped.direction,
            attachedWindowNumber: windowNumber,
            cursorID: session.id
        )
        return ActionCursorTargetResponseDTO(
            session: session,
            targetPointAppKit: PointDTO(x: point.x, y: point.y),
            targetPointSource: pointSource,
            moved: true,
            moveDurationMs: sanitizedJSONDouble(duration * 1_000),
            movement: "approach_scroll_choreography",
            warnings: []
        )
    }

    static func finishScroll(cursor: ActionCursorTargetResponseDTO) {
        guard cursor.moved else { return }
        CursorRuntime.finishScroll(cursorID: cursor.session.id)
    }

    private static func disabledCursor(
        requested: CursorRequestDTO?,
        point: CGPoint,
        pointSource: String
    ) -> ActionCursorTargetResponseDTO {
        let session = CursorRuntime.resolve(requested: requested)
        return ActionCursorTargetResponseDTO(
            session: session,
            targetPointAppKit: PointDTO(x: point.x, y: point.y),
            targetPointSource: pointSource,
            moved: false,
            moveDurationMs: nil,
            movement: "disabled",
            warnings: []
        )
    }

    private static func cursorScrollMapping(for direction: ScrollDirectionDTO) -> (axis: CursorScrollAxis, direction: CursorScrollDirection) {
        switch direction {
        case .up:
            return (.vertical, .positive)
        case .down:
            return (.vertical, .negative)
        case .left:
            return (.horizontal, .negative)
        case .right:
            return (.horizontal, .positive)
        }
    }
}
