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

enum QuestionInputKind: String, Codable {
    case freeText
    case multiSelect
    case multiSelectWithOther
}

struct QuestionOption: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String?

    init(id: String, title: String, detail: String? = nil) {
        self.id = id
        self.title = title
        self.detail = detail
    }
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
    let inputKind: QuestionInputKind
    let options: [QuestionOption]
    let allowsMultipleSelection: Bool
    let allowsOtherEntry: Bool
}

struct InterviewSession {
    let domain: String
    let questions: [InterviewQuestion]
    let coreQuestionCount: Int
    private(set) var answers: [String: String] = [:]
    var draftSelections: [String: Set<String>] = [:]
    var draftOtherText: [String: String] = [:]

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
    private let questionOverrides: [String: QuestionMeta] = {
        let personas: [QuestionOption] = [
            QuestionOption(id: "traveler", title: "해외/국내 여행자"),
            QuestionOption(id: "business", title: "비즈니스 출장자"),
            QuestionOption(id: "resident", title: "재외 거주자"),
            QuestionOption(id: "guide", title: "현지 가이드/통역사"),
            QuestionOption(id: "support", title: "외국인 고객 지원 상담사")
        ]
        let coreFeatures: [QuestionOption] = [
            QuestionOption(id: "voice", title: "실시간 음성 통역"),
            QuestionOption(id: "camera", title: "카메라/OCR 번역"),
            QuestionOption(id: "conversation", title: "대화 기록 저장 및 검색"),
            QuestionOption(id: "favorites", title: "즐겨찾기/자주 쓰는 문구 관리"),
            QuestionOption(id: "offline", title: "오프라인 번역 모드")
        ]
        let mustHave: [QuestionOption] = [
            QuestionOption(id: "stable_voice", title: "음성 통역 안정화"),
            QuestionOption(id: "camera_accuracy", title: "카메라 번역 정확도 확보"),
            QuestionOption(id: "conversation_log", title: "대화 로그 저장"),
            QuestionOption(id: "favorites_feature", title: "즐겨찾기 문구 관리"),
            QuestionOption(id: "tts_quality", title: "자연스러운 TTS 음성")
        ]
        let postpone: [QuestionOption] = [
            QuestionOption(id: "offline_mode", title: "완전 오프라인 지원"),
            QuestionOption(id: "wearable", title: "웨어러블 연동"),
            QuestionOption(id: "analytics", title: "고급 분석 리포트"),
            QuestionOption(id: "community", title: "사용자 커뮤니티 기능")
        ]
        let iosVersions: [QuestionOption] = [
            QuestionOption(id: "ios18", title: "iOS 18.0"),
            QuestionOption(id: "ios17", title: "iOS 17.0"),
            QuestionOption(id: "ios16", title: "iOS 16.4"),
            QuestionOption(id: "ios15", title: "iOS 15.7")
        ]
        let langStack: [QuestionOption] = [
            QuestionOption(id: "swift", title: "Swift 5.8 이상"),
            QuestionOption(id: "swiftui", title: "SwiftUI"),
            QuestionOption(id: "architecture", title: "MVVM + Clean Architecture")
        ]
        let sensingStack: [QuestionOption] = [
            QuestionOption(id: "vision", title: "Vision Framework"),
            QuestionOption(id: "avfoundation", title: "AVFoundation (카메라)"),
            QuestionOption(id: "speech", title: "Speech Framework"),
            QuestionOption(id: "translation", title: "Translation Framework"),
            QuestionOption(id: "tts", title: "AVSpeechSynthesizer")
        ]
        let infraStack: [QuestionOption] = [
            QuestionOption(id: "coredata", title: "Core Data"),
            QuestionOption(id: "networking", title: "URLSession + Combine"),
            QuestionOption(id: "security", title: "Keychain Services")
        ]

        return [
            "project_name": .freeText(prompt: "프로젝트를 소개해 주세요!", hint: "한 줄로 프로젝트를 요약해 주세요."),
            "job1_when": .freeText(prompt: "언제/어디서 이 서비스가 필요했나요?", hint: "실제로 겪은 상황을 떠올려 보세요."),
            "core_value": .freeText(prompt: "사용자가 느끼는 핵심 가치는 무엇인가요?", hint: "사용자가 느끼는 변화 한 문장"),
            "in_scope_items": .multiSelect(prompt: "누가 이 서비스를 사용하나요?", hint: "해당하는 사용자를 모두 선택하거나 기타로 적어주세요.", allowsOther: true, options: personas),
            "primary_flow": .freeText(prompt: "앱의 사용자 플로우를 알려주세요!", hint: "핵심 플로우를 단계 순서로 작성"),
            "session_types": .multiSelect(prompt: "핵심 기능을 골라주세요.", hint: "우선 제공할 기능을 선택하세요.", allowsOther: true, options: coreFeatures),
            "cycle_goal": .multiSelect(prompt: "이번에 꼭 할 3가지 체크", hint: "이번 스프린트에서 반드시 끝낼 항목", allowsOther: true, options: mustHave),
            "out_scope_items": .multiSelect(prompt: "지금은 안 할 기능을 고르세요.", hint: "후순위 기능 또는 제외할 항목", allowsOther: true, options: postpone),
            "bounds": .singleSelect(prompt: "최소 지원 iOS 버전을 선택해 주세요.", allowsOther: true, options: iosVersions),
            "recordable_operator": .multiSelect(prompt: "개발 언어 및 아키텍처를 확정해 주세요.", allowsOther: true, options: langStack),
            "recordable_threshold_sec": .multiSelect(prompt: "센싱/번역 관련 프레임워크 선택", allowsOther: true, options: sensingStack),
            "session_types_rule": .multiSelect(prompt: "인프라 및 보안 구성", allowsOther: true, options: infraStack)
        ]
    }()

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
        let questions = payload.groups.enumerated().flatMap { index, group in
            let stage: QuestionStage
            if let title = group.title, title.contains("필요") {
                stage = .optional
            } else {
                stage = index <= 1 ? .core : .optional
            }
            return group.questions.map { item in
                let override = questionOverrides[item.key]
                let prompt = override?.prompt ?? item.prompt
                let hint = override?.hint ?? item.hint
                let example = override?.example ?? item.example
                let inputKind = override?.inputKind ?? .freeText
                let options = override?.options ?? []
                let allowsMultiple = override?.allowsMultiple ?? (inputKind != .freeText)
                let allowsOther = override?.allowsOther ?? false

                return InterviewQuestion(
                    key: item.key,
                    text: prompt,
                    hint: hint,
                    example: example,
                    required: item.required ?? (stage == .core),
                    defaultAnswer: item.defaultValue,
                    groupTitle: group.title,
                    stage: stage,
                    inputKind: inputKind,
                    options: options,
                    allowsMultipleSelection: allowsMultiple,
                    allowsOtherEntry: allowsOther
                )
            }
        }
        let desiredOrder = [
            "project_name",
            "job1_when",
            "core_value",
            "in_scope_items",
            "primary_flow",
            "session_types",
            "cycle_goal",
            "out_scope_items",
            "bounds",
            "recordable_operator",
            "recordable_threshold_sec",
            "session_types_rule"
        ]
        let orderLookup = Dictionary(uniqueKeysWithValues: desiredOrder.enumerated().map { ($0.element, $0.offset) })
        let filtered = questions.filter { orderLookup[$0.key] != nil }
            .sorted { (orderLookup[$0.key] ?? Int.max) < (orderLookup[$1.key] ?? Int.max) }
        return filtered
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

private struct QuestionMeta {
    let prompt: String?
    let hint: String?
    let example: String?
    let inputKind: QuestionInputKind
    let options: [QuestionOption]
    let allowsMultiple: Bool
    let allowsOther: Bool

    static func freeText(prompt: String? = nil, hint: String? = nil, example: String? = nil) -> QuestionMeta {
        QuestionMeta(prompt: prompt, hint: hint, example: example, inputKind: .freeText, options: [], allowsMultiple: false, allowsOther: false)
    }

    static func multiSelect(prompt: String? = nil,
                             hint: String? = nil,
                             example: String? = nil,
                             allowsOther: Bool = false,
                             options: [QuestionOption]) -> QuestionMeta {
        QuestionMeta(prompt: prompt, hint: hint, example: example, inputKind: allowsOther ? .multiSelectWithOther : .multiSelect, options: options, allowsMultiple: true, allowsOther: allowsOther)
    }

    static func singleSelect(prompt: String? = nil,
                              hint: String? = nil,
                              example: String? = nil,
                              allowsOther: Bool = false,
                              options: [QuestionOption]) -> QuestionMeta {
        QuestionMeta(prompt: prompt, hint: hint, example: example, inputKind: allowsOther ? .multiSelectWithOther : .multiSelect, options: options, allowsMultiple: false, allowsOther: allowsOther)
    }
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
