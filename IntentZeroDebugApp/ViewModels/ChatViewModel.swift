import Foundation
import SwiftUI

@MainActor
final class ChatViewModel: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []
    @Published var pipelinePhase: PipelinePhase? = nil
    @Published var isBusy: Bool = false
    @Published private(set) var session: InterviewSession? = nil

    private let pipeline = IntentPipeline()
    private var bootstraped = false
    private var detection: DomainDetectionResult?
    private var initialIdea: String?
    private var languageCode: String = "ko"
    private var questionMessageIDs: [String: UUID] = [:]
    private var answerMessageIDs: [String: UUID] = [:]
    private var awaitingOptionalDecision: Bool = false

    var headerStatus: String {
        if isBusy {
            return "작업 중…"
        }
        if let phase = pipelinePhase {
            return phase.subtitle
        }
        if session != nil {
            return "질문에 답변해 주세요."
        }
        return "아이디어를 입력하면 인터뷰가 시작됩니다."
    }

    func bootstrapIfNeeded() {
        guard !bootstraped else { return }
        bootstraped = true
        messages.append(ChatMessage(role: .system, text: "안녕하세요! 만들고 싶은 제품 아이디어를 한 줄로 적어주세요."))
    }

    func process(userInput: String, editingQuestionKey: String? = nil) {
        let trimmed = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if awaitingOptionalDecision {
            appendUserMessage(trimmed, questionKey: nil)
            handleOptionalDecisionInput(trimmed)
            return
        }

        if let editingKey = editingQuestionKey {
            updateAnswer(for: editingKey, to: trimmed)
            return
        }

        let activeQuestionKey = session?.currentQuestion?.key
        appendUserMessage(trimmed, questionKey: activeQuestionKey)

        if session == nil {
            initialIdea = trimmed
            startPipeline(with: trimmed)
        } else {
            handleAnswer(trimmed)
        }
    }

    func resetConversation() {
        messages.removeAll()
        pipelinePhase = nil
        detection = nil
        session = nil
        initialIdea = nil
        questionMessageIDs.removeAll()
        answerMessageIDs.removeAll()
        awaitingOptionalDecision = false
        bootstraped = false
        bootstrapIfNeeded()
    }

    private func startPipeline(with idea: String) {
        isBusy = true
        let pipeline = self.pipeline
        Task.detached { [weak self, pipeline] in
            guard let self else { return }
            await MainActor.run {
                self.pipelinePhase = .interview
            }
            do {
                let defaultDetection = DomainDetectionResult(domain: "generic", confidence: 0, scores: [:])
                let interview = try pipeline.startInterview(for: defaultDetection)
                await MainActor.run {
                    self.detection = defaultDetection
                    self.session = interview
                    self.askNextQuestion()
                }
            } catch {
                await MainActor.run {
                    self.appendPipelineMessage("도메인 감지 또는 질문 준비 중 오류: \(error.localizedDescription)")
                    self.pipelinePhase = nil
                }
            }
            await MainActor.run {
                self.isBusy = false
            }
        }
    }

    private func handleAnswer(_ answer: String) {
        guard var currentSession = session else { return }
        guard currentSession.currentQuestion != nil else {
            appendPipelineMessage("추가 질문은 없습니다. 새로운 아이디어를 입력하려면 '초기화'를 눌러주세요.")
            return
        }

        currentSession.recordAnswer(answer)
        session = currentSession

        if currentSession.isCompleted {
            finalizeInterview()
            return
        }

        if currentSession.currentIndex == currentSession.coreQuestionCount,
           currentSession.coreQuestionCount < currentSession.questions.count {
            promptOptionalQuestionDecision()
        } else {
            askNextQuestion()
        }
    }

    private func askNextQuestion() {
        guard let question = session?.currentQuestion else {
            appendAssistantMessage("모든 질문에 답해 주셨어요! 명세서를 생성합니다.")
            finalizeInterview()
            return
        }

        let prompt = makeQuestionPrompt(for: question)
        appendAssistantMessage(prompt, questionKey: question.key)
    }

    private func finalizeInterview() {
        guard let session = session else { return }
        let currentLanguage = languageCode
        pipelinePhase = .specGeneration
        isBusy = true
        awaitingOptionalDecision = false
        let pipeline = self.pipeline
        Task.detached { [weak self, session, pipeline] in
            guard let self else { return }
            do {
                let summary = try pipeline.generateSpecs(from: session.exportedAnswers(), domain: session.domain, languageCode: currentLanguage)
                let lines = summary.generatedFiles.map { "• \($0.lastPathComponent)" }.joined(separator: "\n")
                await MainActor.run {
                    self.appendPipelineMessage("명세서 5종 생성 완료 (TODO: \(summary.todoCount)개)\n출력 위치: \(summary.outputDirectory.path)\n\(lines)")
                    self.appendAssistantMessage("agents/commands/3_coding_agent.prompt에 생성된 명세서를 전달하면 코딩 에이전트가 구현을 이어갈 수 있습니다.")
                }
            } catch {
                await MainActor.run {
                    self.appendPipelineMessage("명세 생성 중 오류: \(error.localizedDescription)")
                }
            }
            await MainActor.run {
                self.pipelinePhase = nil
                self.isBusy = false
            }
        }
    }

    var milestones: [QuestionMilestone] {
        guard let session = session else { return [] }
        return session.questions.enumerated().map { index, question in
            let answer = session.answers[question.key]
            let status: MilestoneStatus
            if index < session.currentIndex {
                status = .answered
            } else if index == session.currentIndex {
                status = .current
            } else {
                status = .pending
            }
            return QuestionMilestone(id: question.key,
                                     index: index,
                                     title: question.text,
                                     status: status,
                                     answer: answer,
                                     stage: question.stage)
        }
    }

    func answer(for questionKey: String) -> String? {
        session?.answers[questionKey]
    }

    func messageID(forQuestionKey questionKey: String) -> UUID? {
        questionMessageIDs[questionKey] ?? answerMessageIDs[questionKey]
    }

    private func appendUserMessage(_ text: String, questionKey: String?) {
        let message = ChatMessage(role: .user, text: text, questionKey: questionKey)
        messages.append(message)
        if let key = questionKey {
            answerMessageIDs[key] = message.id
        }
    }

    private func updateAnswer(for questionKey: String, to newText: String) {
        guard var currentSession = session else { return }
        guard currentSession.questions.contains(where: { $0.key == questionKey }) else { return }
        currentSession.updateAnswer(newText, for: questionKey)
        session = currentSession

        if let messageID = answerMessageIDs[questionKey],
           let index = messages.firstIndex(where: { $0.id == messageID }) {
            messages[index].text = newText
        } else {
            appendUserMessage(newText, questionKey: questionKey)
        }
    }

    private func makeQuestionPrompt(for question: InterviewQuestion) -> String {
        let promptText = sanitizedQuestionText(for: question)
        var components: [String] = [promptText]
        if let hint = question.hint, !hint.isEmpty {
            components.append("힌트: \(hint)")
        }
        if let ideaExample = exampleLine(for: question) {
            components.append(ideaExample)
        }
        components.append("추가적인 부연 설명을 해드릴까요?")
        return components.joined(separator: "\n")
    }

    private func exampleLine(for question: InterviewQuestion) -> String? {
        if let idea = initialIdea, !idea.isEmpty {
            return generateIdeaSpecificExample(for: question, idea: idea)
        }
        if let example = question.example, !example.isEmpty {
            return example
        }
        if let defaultAnswer = question.defaultAnswer, !defaultAnswer.isEmpty {
            return "예시: \(defaultAnswer)"
        }
        return nil
    }

    private func generateIdeaSpecificExample(for question: InterviewQuestion, idea: String) -> String {
        let snippetRaw = ideaSnippet(from: idea)
        let snippet = snippetRaw.isEmpty ? idea : snippetRaw
        switch question.key {
        case "project_name":
            let name = suggestedName(from: idea)
            return "예시: \"\(name)\" — \(snippet)에 바로 떠오르는 이름"
        case "one_liner":
            return "예시: \(snippet)을 한 문장으로 요약하면 \"\(snippet) 이용자를 위한 즉시 통역 도우미\"처럼 표현할 수 있어요."
        case "main_pain":
            return "예시: \(snippet) 상황에서 겪는 대표적인 불편 한 가지를 구체적으로 적어보세요."
        default:
            if let defaultAnswer = question.defaultAnswer, !defaultAnswer.isEmpty {
                return "예시: \(defaultAnswer) — \(snippet)을(를) 염두에 둔 답변"
            } else if let example = question.example, !example.isEmpty {
                return "\(snippet)을(를) 떠올리며 \(example)"
            } else {
                return "\"\(snippet)\" 맥락을 떠올리며 구체적으로 설명해보세요."
            }
        }
    }

    private func ideaSnippet(from idea: String, limit: Int = 18) -> String {
        let trimmed = idea.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        let endIndex = trimmed.index(trimmed.startIndex, offsetBy: limit)
        let prefix = String(trimmed[..<endIndex])
        return prefix + "…"
    }

    private func suggestedName(from idea: String) -> String {
        let lower = idea.lowercased()
        let translationKeywords = ["번역", "통역", "translator", "translation", "언어", "language"]
        if translationKeywords.contains(where: { lower.contains($0) }) {
            return "LinguaBridge"
        }

        let words = idea
            .components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            .filter { !$0.isEmpty }
        if words.isEmpty {
            return "IdeaBridge"
        }
        let base = words.prefix(2).joined()
        var cleaned = base.isEmpty ? ideaSnippet(from: idea, limit: 6) : base
        cleaned = cleaned.replacingOccurrences(of: "…", with: "")
        if cleaned.count > 10 {
            let endIndex = cleaned.index(cleaned.startIndex, offsetBy: 10)
            cleaned = String(cleaned[..<endIndex])
        }
        return cleaned + "Talk"
    }

    private func sanitizedQuestionText(for question: InterviewQuestion) -> String {
        var text = question.text.replacingOccurrences(of: "\n", with: " ")
        if let range = text.range(of: "예:" ) {
            text = String(text[..<range.lowerBound])
        } else if let range = text.range(of: "예시:" ) {
            text = String(text[..<range.lowerBound])
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func promptOptionalQuestionDecision() {
        awaitingOptionalDecision = true
        appendAssistantMessage("핵심 질문이 모두 완료됐어요. 지금 바로 '명세 생성'을 입력하면 결과를 받고, '계속'이라고 입력하면 심화 질문을 이어갈게요.")
    }

    private func handleOptionalDecisionInput(_ input: String) {
        let normalized = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let generateKeywords = ["명세 생성", "생성", "generate", "spec", "finish"]
        let continueKeywords = ["계속", "심화", "continue", "more", "추가"]

        if generateKeywords.contains(where: { normalized.contains($0) }) {
            awaitingOptionalDecision = false
            finalizeInterview()
        } else if continueKeywords.contains(where: { normalized.contains($0) }) {
            awaitingOptionalDecision = false
            appendAssistantMessage("좋아요! 심화 질문을 이어갈게요.")
            askNextQuestion()
        } else {
            appendAssistantMessage("'명세 생성' 또는 '계속'이라고 입력해 주세요.")
        }
    }

    private func appendAssistantMessage(_ text: String, questionKey: String? = nil) {
        let message = ChatMessage(role: .assistant, text: text, questionKey: questionKey)
        messages.append(message)
        if let key = questionKey {
            questionMessageIDs[key] = message.id
        }
    }

    private func appendPipelineMessage(_ text: String) {
        messages.append(ChatMessage(role: .pipeline("파이프라인"), text: text))
    }
}

struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let role: ChatRole
    var text: String
    let questionKey: String?

    init(id: UUID = UUID(), role: ChatRole, text: String, questionKey: String? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.questionKey = questionKey
    }
}

enum ChatRole: Equatable {
    case user
    case assistant
    case system
    case pipeline(String)
}

enum PipelinePhase {
    case domainDetection
    case interview
    case specGeneration
    case coding

    var title: String {
        switch self {
        case .domainDetection: return "도메인 감지"
        case .interview: return "인터뷰 진행"
        case .specGeneration: return "명세 생성"
        case .coding: return "코딩 준비"
        }
    }

    var subtitle: String {
        switch self {
        case .domainDetection: return "아이디어에서 도메인 추론 중"
        case .interview: return "질문을 통해 의도를 정리합니다"
        case .specGeneration: return "명세서를 자동 작성 중"
        case .coding: return "코딩 에이전트에게 핸드오프 준비"
        }
    }

    var iconName: String {
        switch self {
        case .domainDetection: return "magnifyingglass"
        case .interview: return "text.bubble"
        case .specGeneration: return "doc.plaintext"
        case .coding: return "hammer"
        }
    }

    var color: Color {
        switch self {
        case .domainDetection: return .purple
        case .interview: return .blue
        case .specGeneration: return .green
        case .coding: return .orange
        }
    }
}

struct QuestionMilestone: Identifiable, Equatable {
    let id: String
    let index: Int
    let title: String
    let status: MilestoneStatus
    let answer: String?
    let stage: QuestionStage
}

enum MilestoneStatus: Equatable {
    case pending
    case current
    case answered
}
