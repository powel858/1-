import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct ContentView: View {
    @EnvironmentObject private var viewModel: ChatViewModel
    @State private var initialIdeaDraft: String = ""
    @State private var freeTextDraft: String = ""
    @State private var selectedMilestoneKey: String?
    @State private var pendingScrollTarget: UUID?

    var body: some View {
        Group {
            if viewModel.hasCapturedInitialIdea {
                mainInterviewLayout
            } else {
                InitialIdeaCaptureView(draft: $initialIdeaDraft,
                                       isBusy: viewModel.isBusy,
                                       onSubmit: { idea in
                                           viewModel.captureInitialIdea(idea)
                                           initialIdeaDraft = ""
                                       })
            }
        }
        .frame(minWidth: 840, minHeight: 520)
        .onAppear { viewModel.bootstrapIfNeeded() }
        .onChange(of: viewModel.session?.currentQuestion?.key) { key in
            selectedMilestoneKey = key
            freeTextDraft = ""
        }
        .onChange(of: viewModel.milestones.count) { count in
            if count == 0 {
                selectedMilestoneKey = nil
            }
        }
    }

    private var mainInterviewLayout: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            chatArea
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
        if let range = condensed.range(of: "예:" ) {
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
                QuestionInputPanel(state: viewModel.currentQuestionState,
                                   freeText: $freeTextDraft,
                                   isBusy: viewModel.isBusy,
                                   onToggle: { viewModel.toggleCurrentOption($0) },
                                   onOtherChange: { viewModel.updateCurrentOtherText($0) },
                               onSubmitSelection: {
                                   viewModel.submitCurrentSelection()
                               },
                               onSubmitFreeText: {
                                   viewModel.submitFreeTextResponse(freeTextDraft)
                                   freeTextDraft = ""
                               })
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

    private func handleMilestoneSelection(_ milestone: QuestionMilestone) {
        guard milestone.status != .pending else { return }
        selectedMilestoneKey = milestone.id

        if let target = viewModel.messageID(forQuestionKey: milestone.id) {
            pendingScrollTarget = target
        }
    }
}

private struct InitialIdeaCaptureView: View {
    @Binding var draft: String
    let isBusy: Bool
    let onSubmit: (String) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            VStack(spacing: 12) {
                Text("아이디어 한 줄을 입력해보세요!")
                    .font(.title2).bold()
                Text("처음 아이디어를 입력하면 인터뷰가 시작됩니다.")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
            TextField("예: 외국인과 대화할 때 도와줄 번역 앱", text: $draft)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .frame(maxWidth: 480)
                .disabled(isBusy)
                .onSubmit(submit)
            Button(action: submit) {
                Label("시작하기", systemImage: "paperplane.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isBusy || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Spacer()
        }
        .padding()
    }

    private func submit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSubmit(trimmed)
    }
}

private struct QuestionInputPanel: View {
    let state: QuestionInputState?
    @Binding var freeText: String
    let isBusy: Bool
    let onToggle: (String) -> Void
    let onOtherChange: (String) -> Void
    let onSubmitSelection: () -> Void
    let onSubmitFreeText: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let state {
                switch state.question.inputKind {
                case .freeText:
                    freeTextArea
                case .multiSelect, .multiSelectWithOther:
                    selectionArea(state: state)
                }
            } else {
                freeTextArea
            }
        }
        .padding()
    }

    private var freeTextArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            SendableTextView(text: $freeText, isEnabled: !isBusy, onSubmit: onSubmitFreeText)
                .frame(minHeight: 70)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
            HStack {
                Spacer()
                Button(action: {
                    onSubmitFreeText()
                }) {
                    Label("보내기", systemImage: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBusy || freeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func selectionArea(state: QuestionInputState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(state.question.options) { option in
                        OptionRow(option: option,
                                  isSelected: state.selectedOptionIDs.contains(option.id),
                                  onTap: { onToggle(option.id) })
                    }
                }
            }
            .frame(minHeight: 120, maxHeight: 220)

            if state.question.allowsOtherEntry {
                TextField("기타 의견을 입력하세요", text: Binding(get: { state.otherText }, set: onOtherChange))
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button(action: onSubmitSelection) {
                    Label("선택 완료", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBusy || !state.canSubmit)
            }
        }
    }

    private struct OptionRow: View {
        let option: QuestionOption
        let isSelected: Bool
        let onTap: () -> Void

        var body: some View {
            Button(action: onTap) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(option.title)
                            .font(.body)
                        if let detail = option.detail, !detail.isEmpty {
                            Text(detail)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.2)))
            }
            .buttonStyle(.plain)
        }
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
