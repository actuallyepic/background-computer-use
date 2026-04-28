import Foundation

public extension String {
    /// Returns a copy of `self` with ANSI CSI escape sequences (e.g. color/style codes
    /// emitted by codex when `RUST_LOG` is set) removed.
    ///
    /// Strips the standard `ESC [ <params> <intermediates> <final>` form. Other less
    /// common escape forms (OSC, single-character sequences) are left intact —
    /// `tracing-subscriber`'s ANSI output uses CSI exclusively.
    var strippingAnsiEscapes: String {
        guard contains("\u{001B}") else { return self }
        let pattern = "\u{001B}\\[[0-?]*[ -/]*[@-~]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return self }
        let range = NSRange(startIndex..., in: self)
        return regex.stringByReplacingMatches(in: self, range: range, withTemplate: "")
    }
}
