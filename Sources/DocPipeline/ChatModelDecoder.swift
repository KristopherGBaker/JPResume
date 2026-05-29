import Foundation
import Shikisha

/// Bridge that lets callers run `asStructuredOutput` against an `any ChatModel` existential.
/// Swift can't open the existential when the result type embeds `Self` (as
/// `StructuredOutputRunnable<Self, T>` does), so we route through this generic helper —
/// `model` is taken by value, `M` is opened, and only `T` appears in the return type.
public enum ChatModelDecoder {
    public static func decode<T: Decodable & Sendable>(
        _ type: T.Type,
        model: any ChatModel,
        messages: [any Message],
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> T {
        try await invoke(type, model: model, messages: messages, decoder: decoder)
    }

    private static func invoke<T: Decodable & Sendable, M: ChatModel>(
        _ type: T.Type,
        model: M,
        messages: [any Message],
        decoder: JSONDecoder
    ) async throws -> T {
        try await model.asStructuredOutput(T.self, decoder: decoder).invoke(messages)
    }
}
