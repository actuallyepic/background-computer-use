import Foundation

/// Typed convenience factories for building ``UserInput`` values.
///
/// `UserInput` is a single struct with optional `text`, `url`, `path`, `name`,
/// and `textElements` fields plus a `type` discriminator — the right
/// combination per `type` case is not enforced by the type system and is not
/// documented in upstream JSON Schema. These factories encode the correct
/// field combinations so callers can construct an input without guessing
/// (and without writing runtime-error-prone literal initialisers).
///
/// ```swift
/// let prompt = try await client.call(RPC.TurnStart.self, params: TurnStartParams(
///     input: [
///         .text("describe this image"),
///         .localFile(url: imageURL),
///     ],
///     threadId: thread.id
/// ))
/// ```
extension UserInput {
    /// Build a plain text input.
    public static func text(_ text: String) -> UserInput {
        UserInput(
            text: text,
            textElements: nil,
            type: .text,
            url: nil,
            path: nil,
            name: nil
        )
    }

    /// Build an input that references a local file by absolute path.
    ///
    /// Use for image attachments living on the user's filesystem. `name`
    /// defaults to the file's last path component.
    public static func localFile(url: URL, name: String? = nil) -> UserInput {
        UserInput(
            text: nil,
            textElements: nil,
            type: .localImage,
            url: nil,
            path: url.path,
            name: name ?? url.lastPathComponent
        )
    }

    /// Build an input from inline image bytes encoded as a `data:` URL.
    ///
    /// Use when you already have raw image bytes in memory and don't want to
    /// stage a temp file. The data is base64-encoded into the URL field.
    public static func dataURL(mimeType: String, data: Data, name: String? = nil) -> UserInput {
        let base64 = data.base64EncodedString()
        return UserInput(
            text: nil,
            textElements: nil,
            type: .image,
            url: "data:\(mimeType);base64,\(base64)",
            path: nil,
            name: name
        )
    }

    /// Build an input that references an image at a remote URL (`http`, `https`, etc.).
    public static func image(url: URL, name: String? = nil) -> UserInput {
        UserInput(
            text: nil,
            textElements: nil,
            type: .image,
            url: url.absoluteString,
            path: nil,
            name: name
        )
    }
}
