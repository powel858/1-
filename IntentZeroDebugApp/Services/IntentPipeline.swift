import Foundation

struct DomainDetectionResult {
    let domain: String
    let confidence: Double
    let scores: [String: Double]
}

enum QuestionStage: String, Codable {
    case core
    case optional
}

struct InterviewQuestion: Identifiable {
    let id = UUID()
    let key: String
    let text: String
    let hint: String?
    let example: String?
    let required: Bool
    let defaultAnswer: String?
    let groupTitle: String?
    let stage: QuestionStage
}

struct InterviewSession {
    let domain: String
    let questions: [InterviewQuestion]
    let coreQuestionCount: Int
    private(set) var answers: [String: String] = [:]

    var currentIndex: Int = 0

    var isCompleted: Bool {
        currentIndex >= questions.count
    }

    var currentQuestion: InterviewQuestion? {
        guard currentIndex < questions.count else { return nil }
        return questions[currentIndex]
    }

    mutating func recordAnswer(_ answer: String) {
        guard let question = currentQuestion else { return }
        answers[question.key] = answer
        currentIndex += 1
    }

    mutating func updateAnswer(_ answer: String, for key: String) {
        answers[key] = answer
    }

    mutating func skipCurrentQuestion() {
        currentIndex += 1
    }

    func exportedAnswers() -> [String: String] {
        answers
    }
}

struct SpecGenerationSummary {
    let outputDirectory: URL
    let generatedFiles: [URL]
    let todoCount: Int
}

final class IntentPipeline {
    private let fileManager: FileManager
    private let supportRoot: URL
    private var serviceRoot: URL
    private let resourceZipURL: URL?
    private let fallbackDomainKeywords: [(domain: String, keywords: [String])] = [
        (domain: "communication", keywords: ["번역", "통역", "대화", "언어", "translation", "translator", "interpret"]),
        (domain: "education", keywords: ["학습", "교육", "study", "lesson", "학생", "강의"])
    ]

    init(resourceZipURL: URL? = nil,
         fileManager: FileManager = .default,
         bundle: Bundle = .main,
         overrideSupportRoot: URL? = nil) {
        self.fileManager = fileManager
        self.resourceZipURL = resourceZipURL ?? bundle.url(forResource: "IntentZeroDebugService", withExtension: "zip")
        if let overrideSupportRoot {
            supportRoot = overrideSupportRoot
        } else {
            let appSupport = try! fileManager.url(for: .applicationSupportDirectory,
                                                  in: .userDomainMask,
                                                  appropriateFor: nil,
                                                  create: true)
            supportRoot = appSupport.appendingPathComponent("IntentZeroDebugStudio", isDirectory: true)
        }
        serviceRoot = supportRoot.appendingPathComponent("IntentZeroDebugService", isDirectory: true)
        prepareBaselineResources()
    }

    func detectDomain(for idea: String) throws -> DomainDetectionResult {
        let catalogURL = serviceRoot
            .appendingPathComponent("SpecAgent", isDirectory: true)
            .appendingPathComponent("domain_catalog.json")
        let data = try Data(contentsOf: catalogURL)
        let catalog = try JSONDecoder().decode([String: DomainCatalogEntry].self, from: data)

        var scores: [String: Double] = [:]
        let lower = idea.lowercased()

        for (domain, entry) in catalog {
            var score: Double = 0
            for keyword in entry.keywords {
                let trimmed = keyword.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                if lower.contains(trimmed) {
                    score += 1
                }
            }
            scores[domain] = score
        }

        let bestEntry = scores.max { a, b in a.value < b.value }
        let total = scores.values.reduce(0, +)
        let bestScore = bestEntry?.value ?? 0
        let confidence = total > 0 && bestScore > 0 ? bestScore / total : 0
        let resolvedDomain: String
        if bestScore > 0, let candidate = bestEntry?.key {
            resolvedDomain = candidate
        } else if let fallback = fallbackDomain(for: lower) {
            resolvedDomain = fallback
        } else {
            resolvedDomain = "generic"
        }
        return DomainDetectionResult(domain: resolvedDomain, confidence: confidence, scores: scores)
    }

    private func fallbackDomain(for idea: String) -> String? {
        for entry in fallbackDomainKeywords {
            for keyword in entry.keywords {
                if idea.contains(keyword.lowercased()) {
                    return entry.domain
                }
            }
        }
        return nil
    }

    func loadQuestions(for domain: String) throws -> [InterviewQuestion] {
        let fileName = "questions_\(domain)_ko.json"
        let fallback = "questions_generic_ko.json"
        let agentDir = serviceRoot.appendingPathComponent("SpecAgent", isDirectory: true)
        let url: URL
        if fileManager.fileExists(atPath: agentDir.appendingPathComponent(fileName).path) {
            url = agentDir.appendingPathComponent(fileName)
        } else {
            url = agentDir.appendingPathComponent(fallback)
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let payload = try decoder.decode(InterviewQuestionPayload.self, from: data)
        return payload.groups.enumerated().flatMap { index, group in
            let stage: QuestionStage
            if let title = group.title, title.contains("필요") {
                stage = .optional
            } else {
                stage = index <= 1 ? .core : .optional
            }
            return group.questions.map { item in
                InterviewQuestion(
                    key: item.key,
                    text: item.prompt,
                    hint: item.hint,
                    example: item.example,
                    required: item.required ?? (stage == .core),
                    defaultAnswer: item.defaultValue,
                    groupTitle: group.title,
                    stage: stage
                )
            }
        }
    }

    func startInterview(for detection: DomainDetectionResult) throws -> InterviewSession {
        let questions = try loadQuestions(for: detection.domain)
        let coreCount = questions.filter { $0.stage == .core }.count
        return InterviewSession(domain: detection.domain, questions: questions, coreQuestionCount: coreCount)
    }

    func saveAnswers(_ answers: [String: String], domain: String, languageCode: String) throws -> URL {
        let output = serviceRoot
            .appendingPathComponent("output", isDirectory: true)
            .appendingPathComponent(domain, isDirectory: true)
        try fileManager.createDirectory(at: output, withIntermediateDirectories: true)
        let answersURL = output.appendingPathComponent("answers_\(languageCode).json")
        let data = try JSONSerialization.data(withJSONObject: answers, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: answersURL, options: .atomic)
        return answersURL
    }

    func generateSpecs(from answers: [String: String], domain: String, languageCode: String = "ko") throws -> SpecGenerationSummary {
        let answersURL = try saveAnswers(answers, domain: domain, languageCode: languageCode)
        let process = Process()
        process.currentDirectoryURL = serviceRoot
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", serviceRoot.appendingPathComponent("scripts/generate_specs.py").path,
                             "--answers", answersURL.path,
                             "--lang", languageCode]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if process.terminationStatus != 0 {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw PipelineError.specGenerationFailed(message)
        }

        let generatedDir = serviceRoot.appendingPathComponent("GeneratedSpecs-\(languageCode)", isDirectory: true)
        let files = try fileManager.contentsOfDirectory(at: generatedDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "md" }
        let todoCount = try files.reduce(0) { partial, url in
            let text = try String(contentsOf: url, encoding: .utf8)
            return partial + text.components(separatedBy: "TODO(").count - 1
        }
        return SpecGenerationSummary(outputDirectory: generatedDir, generatedFiles: files, todoCount: todoCount)
    }

    private func prepareBaselineResources() {
        do {
            try fileManager.createDirectory(at: supportRoot, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: serviceRoot.path) { return }
            guard let zipURL = resourceZipURL else {
                throw PipelineError.missingResource
            }
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            task.arguments = ["-o", zipURL.path, "-d", supportRoot.path]
            try task.run()
            task.waitUntilExit()
            if task.terminationStatus != 0 {
                throw PipelineError.unzipFailed
            }
            if !fileManager.fileExists(atPath: serviceRoot.path) {
                let fallbackRoot = supportRoot
                let specAgentDir = fallbackRoot.appendingPathComponent("SpecAgent", isDirectory: true)
                if fileManager.fileExists(atPath: specAgentDir.path) {
                    serviceRoot = fallbackRoot
                } else {
                    throw PipelineError.unzipFailed
                }
            }
        } catch {
            print("[IntentPipeline] Resource preparation failed: \(error)")
        }
    }
}

private struct DomainCatalogEntry: Decodable {
    let keywords: [String]
}

private struct InterviewQuestionPayload: Decodable {
    struct Group: Decodable {
        struct Item: Decodable {
            let key: String
            let prompt: String
            let hint: String?
            let example: String?
            let required: Bool?
            let defaultValue: String?

            enum CodingKeys: String, CodingKey {
                case key
                case prompt
                case hint
                case example
                case required
                case defaultValue = "default"
            }
        }
        let title: String?
        let questions: [Item]
    }
    let groups: [Group]
}

enum PipelineError: LocalizedError {
    case missingResource
    case unzipFailed
    case specGenerationFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingResource:
            return "앱 번들에서 리소스를 찾을 수 없습니다."
        case .unzipFailed:
            return "리소스 압축 해제에 실패했습니다."
        case .specGenerationFailed(let message):
            return "명세 생성 중 오류: \(message)"
        }
    }
}
