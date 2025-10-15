import Foundation

enum LLMProvider: String {
    case openAI
    case anthropic
}

struct LLMConfiguration {
    let provider: LLMProvider
    let apiKey: String
    let model: String
    let baseURL: URL?

    static func fromEnvironment() -> LLMConfiguration? {
        guard let providerRaw = ProcessInfo.processInfo.environment["LLM_PROVIDER"]?.lowercased(),
              let key = ProcessInfo.processInfo.environment["LLM_API_KEY"],
              !key.isEmpty else { return nil }

        let provider: LLMProvider
        switch providerRaw {
        case "openai", "gpt":
            provider = .openAI
        case "anthropic", "claude":
            provider = .anthropic
        default:
            provider = .openAI
        }
        let model = ProcessInfo.processInfo.environment["LLM_MODEL"] ?? {
            switch provider {
            case .openAI: return "gpt-4o-mini"
            case .anthropic: return "claude-3-5-sonnet-20240620"
            }
        }()

        let baseURLString = ProcessInfo.processInfo.environment["LLM_BASE_URL"]
        let baseURL = baseURLString.flatMap(URL.init(string:))
        return LLMConfiguration(provider: provider, apiKey: key, model: model, baseURL: baseURL)
    }
}

final class LLMClient {
    private let configuration: LLMConfiguration
    private let session: URLSession = .shared

    init?(configuration: LLMConfiguration? = LLMConfiguration.fromEnvironment()) {
        guard let config = configuration else { return nil }
        self.configuration = config
    }

    func generateResponse(prompt: String) async throws -> String {
        switch configuration.provider {
        case .openAI:
            return try await callOpenAI(prompt: prompt)
        case .anthropic:
            return try await callAnthropic(prompt: prompt)
        }
    }

    private func callOpenAI(prompt: String) async throws -> String {
        let url = configuration.baseURL ?? URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")

        let payload: [String: Any] = [
            "model": configuration.model,
            "messages": [["role": "user", "content": prompt]],
            "max_tokens": 600,
            "temperature": 0.2
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? ""
            throw LLMError.apiFailure("OpenAI 응답 오류: \(message)")
        }
        let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        if let choices = json?["choices"] as? [[String: Any]],
           let message = choices.first?["message"] as? [String: Any],
           let content = message["content"] as? String {
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        throw LLMError.parsingFailure
    }

    private func callAnthropic(prompt: String) async throws -> String {
        let url = configuration.baseURL ?? URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(configuration.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let payload: [String: Any] = [
            "model": configuration.model,
            "max_tokens": 800,
            "temperature": 0.2,
            "messages": [["role": "user", "content": prompt]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? ""
            throw LLMError.apiFailure("Claude 응답 오류: \(message)")
        }
        let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        if let content = json?["content"] as? [[String: Any]],
           let text = content.first?["text"] as? String {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        throw LLMError.parsingFailure
    }
}

enum LLMError: LocalizedError {
    case apiFailure(String)
    case parsingFailure

    var errorDescription: String? {
        switch self {
        case .apiFailure(let message):
            return message
        case .parsingFailure:
            return "LLM 응답을 해석할 수 없습니다."
        }
    }
}
