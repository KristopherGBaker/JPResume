import Foundation
import Testing
@testable import jpresume

// MARK: - URL protocol stub

/// Minimal URLProtocol that intercepts URLSession.shared and returns canned
/// responses or errors. Tests must register/unregister it and reset the stubs
/// dictionary; the suite below runs serially to avoid cross-test interference.
private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var stubs: [URL: (Data, HTTPURLResponse)] = [:]
    nonisolated(unsafe) static var transportError: URLError?

    static func reset() {
        stubs = [:]
        transportError = nil
    }

    static func stub(url: URL, status: Int, body: Data) {
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        stubs[url] = (body, response)
    }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        if let err = Self.transportError {
            client?.urlProtocol(self, didFailWithError: err)
            return
        }
        guard let url = request.url, let (data, response) = Self.stubs[url] else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}

// MARK: - Tests

@Suite("HTTPJSONClient + provider response shapes", .serialized)
struct HTTPJSONClientTests {
    init() {
        URLProtocol.registerClass(StubURLProtocol.self)
        StubURLProtocol.reset()
    }

    private func unregister() {
        URLProtocol.unregisterClass(StubURLProtocol.self)
        StubURLProtocol.reset()
    }

    // MARK: HTTPJSONClient

    @Test func returnsParsedDictOnSuccess() async throws {
        defer { unregister() }
        let url = URL(string: "https://example.test/echo")!
        StubURLProtocol.stub(url: url, status: 200, body: Data(#"{"hello":"world","count":2}"#.utf8))

        let json = try await HTTPJSONClient.postJSON(url: url, body: ["x": 1])
        #expect(json["hello"] as? String == "world")
        #expect(json["count"] as? Int == 2)
    }

    @Test func mapsNon200ToRequestFailedWithStatusAndBody() async throws {
        defer { unregister() }
        let url = URL(string: "https://example.test/forbidden")!
        StubURLProtocol.stub(url: url, status: 401, body: Data(#"{"error":"bad key"}"#.utf8))

        await #expect(throws: AIProviderError.self) {
            _ = try await HTTPJSONClient.postJSON(url: url, body: [:])
        }
        do {
            _ = try await HTTPJSONClient.postJSON(url: url, body: [:])
            Issue.record("expected throw")
        } catch let AIProviderError.requestFailed(msg, underlying) {
            #expect(msg.contains("HTTP 401"))
            #expect(msg.contains("bad key"))
            #expect(underlying == nil)
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    @Test func mapsNonJSONBodyToRequestFailedWithUnderlying() async throws {
        defer { unregister() }
        let url = URL(string: "https://example.test/garbage")!
        StubURLProtocol.stub(url: url, status: 200, body: Data("not json at all".utf8))

        do {
            _ = try await HTTPJSONClient.postJSON(url: url, body: [:])
            Issue.record("expected throw")
        } catch let AIProviderError.requestFailed(msg, underlying) {
            #expect(msg.contains("not valid JSON"))
            #expect(underlying != nil)
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    @Test func mapsJSONArrayBodyToInvalidResponse() async throws {
        defer { unregister() }
        let url = URL(string: "https://example.test/array")!
        StubURLProtocol.stub(url: url, status: 200, body: Data("[1,2,3]".utf8))

        do {
            _ = try await HTTPJSONClient.postJSON(url: url, body: [:])
            Issue.record("expected throw")
        } catch let AIProviderError.invalidResponse(msg) {
            #expect(msg.contains("not a JSON object"))
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    @Test func mapsTransportErrorToRequestFailedWithUnderlying() async throws {
        defer { unregister() }
        StubURLProtocol.transportError = URLError(.notConnectedToInternet)

        do {
            _ = try await HTTPJSONClient.postJSON(url: URL(string: "https://example.test/x")!, body: [:])
            Issue.record("expected throw")
        } catch let AIProviderError.requestFailed(msg, underlying) {
            #expect(msg.contains("transport error"))
            #expect(underlying is URLError)
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    // MARK: Provider response-shape extraction
    //
    // Each provider only owns body shape and response-key extraction; the HTTP
    // path is HTTPJSONClient. These tests exercise the extraction half against
    // a stubbed valid response and against a missing/wrong-shape response.

    @Test func anthropicExtractsTextFromContentArray() async throws {
        defer { unregister() }
        setenv("ANTHROPIC_API_KEY", "test-key", 1)
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        let body = Data(#"{"content":[{"type":"text","text":"hello from claude"}]}"#.utf8)
        StubURLProtocol.stub(url: url, status: 200, body: body)

        let provider = try AnthropicProvider(model: "claude-test")
        let reply = try await provider.chat(system: "s", user: "u", temperature: 0.2)
        #expect(reply == "hello from claude")
    }

    @Test func anthropicMissingTextThrowsInvalidResponse() async throws {
        defer { unregister() }
        setenv("ANTHROPIC_API_KEY", "test-key", 1)
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        StubURLProtocol.stub(url: url, status: 200, body: Data(#"{"content":[]}"#.utf8))

        let provider = try AnthropicProvider(model: "claude-test")
        do {
            _ = try await provider.chat(system: "s", user: "u", temperature: 0.2)
            Issue.record("expected throw")
        } catch let AIProviderError.invalidResponse(msg) {
            #expect(msg.contains("No text"))
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    @Test func openAIExtractsContentFromChoicesMessage() async throws {
        defer { unregister() }
        setenv("OPENAI_API_KEY", "test-key", 1)
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        let body = Data(#"{"choices":[{"message":{"role":"assistant","content":"openai reply"}}]}"#.utf8)
        StubURLProtocol.stub(url: url, status: 200, body: body)

        let provider = try OpenAIProvider(model: "gpt-test")
        let reply = try await provider.chat(system: "s", user: "u", temperature: 0.2)
        #expect(reply == "openai reply")
    }

    @Test func openAIMissingContentThrowsInvalidResponse() async throws {
        defer { unregister() }
        setenv("OPENAI_API_KEY", "test-key", 1)
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        StubURLProtocol.stub(url: url, status: 200, body: Data(#"{"choices":[]}"#.utf8))

        let provider = try OpenAIProvider(model: "gpt-test")
        do {
            _ = try await provider.chat(system: "s", user: "u", temperature: 0.2)
            Issue.record("expected throw")
        } catch let AIProviderError.invalidResponse(msg) {
            #expect(msg.contains("No content"))
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    @Test func ollamaExtractsContentFromMessage() async throws {
        defer { unregister() }
        let url = URL(string: "http://localhost:11434/api/chat")!
        let body = Data(#"{"message":{"role":"assistant","content":"ollama reply"}}"#.utf8)
        StubURLProtocol.stub(url: url, status: 200, body: body)

        let provider = OllamaProvider(model: "llama-test")
        let reply = try await provider.chat(system: "s", user: "u", temperature: 0.2)
        #expect(reply == "ollama reply")
    }

    @Test func ollamaMissingContentThrowsInvalidResponse() async throws {
        defer { unregister() }
        let url = URL(string: "http://localhost:11434/api/chat")!
        StubURLProtocol.stub(url: url, status: 200, body: Data(#"{"message":{}}"#.utf8))

        let provider = OllamaProvider(model: "llama-test")
        do {
            _ = try await provider.chat(system: "s", user: "u", temperature: 0.2)
            Issue.record("expected throw")
        } catch let AIProviderError.invalidResponse(msg) {
            #expect(msg.contains("No content"))
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    @Test func providerSurfacesNon200AsRequestFailed() async throws {
        defer { unregister() }
        setenv("OPENAI_API_KEY", "test-key", 1)
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        StubURLProtocol.stub(url: url, status: 500, body: Data(#"{"error":"server down"}"#.utf8))

        let provider = try OpenAIProvider(model: "gpt-test")
        do {
            _ = try await provider.chat(system: "s", user: "u", temperature: 0.2)
            Issue.record("expected throw")
        } catch let AIProviderError.requestFailed(msg, _) {
            #expect(msg.contains("HTTP 500"))
            #expect(msg.contains("server down"))
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }
}
