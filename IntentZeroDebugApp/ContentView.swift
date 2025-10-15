import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct ContentView: View {
    @EnvironmentObject private var viewModel: ChatViewModel
    @State private var input: String = ""
    @State private var selectedMilestoneKey: String?
    @State private var editingQuestionKey: String?
    @State private var pendingScrollTarget: UUID?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            chatArea
        }
        .frame(minWidth: 840, minHeight: 520)
        .onAppear {
            viewModel.bootstrapIfNeeded()
        }
        .onChange(of: viewModel.session?.currentQuestion?.key) { key in
            guard editingQuestionKey == nil else { return }
            selectedMilestoneKey = key
        }
        .onChange(of: viewModel.milestones.count) { count in
            if count == 0 {
                selectedMilestoneKey = nil
            }
        }
    }

    private var sidebar: some View {
        let coreMilestones = viewModel.milestones.filter { $0.stage == .core }
        let optionalMilestones = viewModel.milestones.filter { $0.stage == .optional }

        return ZStack {
            sidebarBackgroundColor.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("인터뷰 진행")
                        .font(.headline)
                    Text("질문 흐름을 한눈에 확인하고 답변을 다듬을 수 있어요.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)

                Divider()

                if viewModel.milestones.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "list.bullet.rectangle")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("인터뷰가 시작되면\n질문 목록이 여기에 표시됩니다.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if !coreMilestones.isEmpty {
                                sectionHeader("핵심 질문")
                                VStack(spacing: 6) {
                                    ForEach(coreMilestones) { milestone in
                                        sidebarRow(for: milestone)
                                    }
                                }
                            }
                            if !optionalMilestones.isEmpty {
                                sectionHeader("심화 질문 (옵션)")
                                VStack(spacing: 6) {
                                    ForEach(optionalMilestones) { milestone in
                                        sidebarRow(for: milestone)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 18)
                        .padding(.horizontal, 12)
                    }
                }
            }
        }
        .frame(width: 300)
    }

    private func sidebarRow(for milestone: QuestionMilestone) -> some View {
        let isSelected = selectedMilestoneKey == milestone.id
        let isDisabled = milestone.status == .pending
        return Button {
            handleMilestoneSelection(milestone)
        } label: {
            milestoneRow(for: milestone, isSelected: isSelected, isDisabled: isDisabled)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    private func milestoneRow(for milestone: QuestionMilestone, isSelected: Bool, isDisabled: Bool) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : rowBackgroundColor)
            HStack(alignment: .top, spacing: 10) {
                statusIndicator(for: milestone.status)
                    .padding(.top, 4)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("질문 \(milestone.index + 1)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if milestone.stage == .optional {
                            Text("옵션")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                    Text(milestoneTitle(for: milestone))
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    if let answer = milestone.answer, !answer.isEmpty {
                        Text(answerSnippet(answer))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    } else {
                        Text(statusDescription(for: milestone.status))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if isDisabled {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .overlay(alignment: .leading) {
            if isSelected {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: 3)
                    .padding(.vertical, 6)
            }
        }
        .opacity(isDisabled ? 0.5 : 1)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(.secondary)
            .padding(.horizontal, 4)
    }

    private var sidebarBackgroundColor: Color {
#if os(macOS)
        return Color(nsColor: .windowBackgroundColor)
#else
        return Color(uiColor: .systemGroupedBackground)
#endif
    }

    private var rowBackgroundColor: Color {
#if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
#else
        return Color(uiColor: .secondarySystemGroupedBackground)
#endif
    }

    private func milestoneTitle(for milestone: QuestionMilestone) -> String {
        let condensed = milestone.title.replacingOccurrences(of: "\n", with: " ")
        if let range = condensed.range(of: "예:") {
            let prefix = condensed[..<range.lowerBound]
            let value = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? condensed : value
        }
        return condensed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func answerSnippet(_ answer: String, limit: Int = 70) -> String {
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        let endIndex = trimmed.index(trimmed.startIndex, offsetBy: limit)
        return String(trimmed[..<endIndex]) + "…"
    }

    private func statusIndicator(for status: MilestoneStatus) -> some View {
        Circle()
            .fill(color(for: status))
            .frame(width: 10, height: 10)
    }

    private func color(for status: MilestoneStatus) -> Color {
        switch status {
        case .answered: return .green
        case .current: return .blue
        case .pending: return .gray.opacity(0.4)
        }
    }

    private func statusDescription(for status: MilestoneStatus) -> String {
        switch status {
        case .answered: return "답변 완료"
        case .current: return "현재 진행 중"
        case .pending: return "아직 답변하지 않았습니다"
        }
    }

    private var chatArea: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(viewModel.messages) { message in
                            MessageBubble(
                                message: message,
                                isHighlighted: message.questionKey == selectedMilestoneKey
                            )
                            .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages) { _ in
                    if let id = viewModel.messages.last?.id {
                        DispatchQueue.main.async {
                            withAnimation {
                                proxy.scrollTo(id, anchor: .bottom)
                            }
                        }
                    }
                }
                .onChange(of: pendingScrollTarget) { target in
                    guard let target else { return }
                    DispatchQueue.main.async {
                        withAnimation {
                            proxy.scrollTo(target, anchor: .center)
                        }
                        pendingScrollTarget = nil
                    }
                }
            }
            Divider()
            inputBar
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 20))
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Intent Zero-Debug Studio")
                    .font(.headline)
                Text(viewModel.headerStatus)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if let phase = viewModel.pipelinePhase {
                PhaseBadge(phase: phase)
            }
        }
        .padding()
    }

    private var inputBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let editingKey = editingQuestionKey,
               let milestone = viewModel.milestones.first(where: { $0.id == editingKey }) {
                HStack(alignment: .firstTextBaseline) {
                    Text("답변 수정 중 • 질문 \(milestone.index + 1)")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                    Spacer()
                    Button("취소") {
                        cancelEditing()
                    }
                    .buttonStyle(.borderless)
                }
            }

            HStack(spacing: 12) {
                SendableTextView(text: $input, isEnabled: !viewModel.isBusy, onSubmit: submitFromKeyboard)
                    .frame(minHeight: 70)
                    .background(Color.clear)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))

                VStack(spacing: 8) {
                    Button(action: submit) {
                        Label(editingQuestionKey == nil ? "보내기" : "수정",
                              systemImage: editingQuestionKey == nil ? "paperplane.fill" : "pencil.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isBusy || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button(action: {
                        cancelEditing()
                        selectedMilestoneKey = nil
                        pendingScrollTarget = nil
                        viewModel.resetConversation()
                    }) {
                        Label("초기화", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isBusy)
                }
            }
        }
        .padding()
    }

    private func cancelEditing() {
        editingQuestionKey = nil
        input = ""
    }

    private func handleMilestoneSelection(_ milestone: QuestionMilestone) {
        guard milestone.status != .pending else { return }
        let wasEditing = editingQuestionKey != nil
        selectedMilestoneKey = milestone.id
        if milestone.status == .answered, let answer = milestone.answer {
            editingQuestionKey = milestone.id
            input = answer
        } else {
            if wasEditing {
                input = ""
            }
            editingQuestionKey = nil
        }

        if let target = viewModel.messageID(forQuestionKey: milestone.id) {
            pendingScrollTarget = target
        }
    }

    private func submit() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let editingKey = editingQuestionKey
        input = ""
        viewModel.process(userInput: text, editingQuestionKey: editingKey)

        if editingKey != nil {
            if let key = editingKey,
               let target = viewModel.messageID(forQuestionKey: key) {
                pendingScrollTarget = target
            }
            editingQuestionKey = nil
        }
    }

    private func submitFromKeyboard() {
        submit()
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    let isHighlighted: Bool

    init(message: ChatMessage, isHighlighted: Bool = false) {
        self.message = message
        self.isHighlighted = isHighlighted
    }

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
            Text(message.role == .user ? "사용자" : message.role.displayName)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(message.text)
                .textSelection(.enabled)
                .padding(12)
                .background(message.role.backgroundColor)
                .foregroundColor(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isHighlighted ? Color.accentColor : Color.clear, lineWidth: 2)
                )
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }
}

struct PhaseBadge: View {
    let phase: PipelinePhase

    var body: some View {
        Label(phase.title, systemImage: phase.iconName)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(phase.color.opacity(0.15))
            .clipShape(Capsule())
    }
}

extension ChatRole {
    var displayName: String {
        switch self {
        case .user: return "사용자"
        case .assistant: return "IntelliAgent"
        case .system: return "시스템"
        case .pipeline(let label): return label
        }
    }

    var backgroundColor: Color {
        switch self {
        case .user: return Color.blue.opacity(0.15)
        case .assistant: return Color.green.opacity(0.15)
        case .system: return Color.gray.opacity(0.12)
        case .pipeline: return Color.orange.opacity(0.15)
        }
    }
}
