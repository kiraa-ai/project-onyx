// Copyright 2026 Onyx Contributors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import SwiftUI

// MARK: - ChatView
//
// PURPOSE: Full-screen iPhone chat UI. This is the "Chat" tab of the app.
//
// LAYOUT:
//   ┌─────────────────────────────────────┐
//   │  Onyx   [model picker]   ● [⟳]  │  ← NavigationBar
//   ├─────────────────────────────────────┤
//   │                                     │
//   │    ┌──────────────────────────┐     │
//   │    │ User message             │ ←   │  User bubble (right-aligned)
//   │    └──────────────────────────┘     │
//   │  ┌──────────────────────────┐       │
//   │  │ Assistant reply          │       │  Assistant bubble (left-aligned)
//   │  └──────────────────────────┘       │
//   │         [● ● ●]                     │  ThinkingDotsView while waiting
//   │                                     │
//   ├─────────────────────────────────────┤
//   │  [  Type a message…          ] [▶] │  ← Input bar
//   └─────────────────────────────────────┘
//
// ERROR STATES:
//   • No model active:       CTA pointing to the Models tab
//   • Metal unavailable:     Banner ("Unavailable in Simulator")
//   • Load failed:           Inline error with retry option
//
// STREAM CONSUMPTION:
//   Tokens arrive via `AsyncStream<String>` from `ChatProvider.respond()`.
//   They are appended to the last `ChatMessage` (the streaming assistant bubble)
//   inside a `for await` loop running in a `.task` modifier.

/// The main chat interface.
///
/// Shows a scrollable message list, an input bar, and a model-status indicator.
/// Connects to `ChatProvider.shared` for inference and `ChatModelRegistry` for
/// the active model name.
///
/// ## Adding to a TabView
/// ```swift
/// TabView {
///     ChatView()
///         .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }
/// }
/// ```
struct ChatView: View {

    // MARK: - State

    @State private var provider = ChatProvider.shared
    @State private var messages: [ChatMessage] = []
    @State private var inputText: String = ""
    @State private var activeModelName: String? = nil
    @State private var modelStatus: String = "Idle"
    @State private var streamTask: Task<Void, Never>? = nil
    @State private var errorMessage: String? = nil

    /// The ID of the in-progress assistant message, used to scroll to it.
    @State private var streamingMessageId: UUID? = nil

    @AppStorage("messageFontSize") private var messageFontSize: Double = 32
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                messageList
                Divider()
                inputBar
            }
            .navigationTitle("Onyx")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
        }
        .task { await refreshModelInfo() }
    }

    // MARK: - Message list

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if messages.isEmpty {
                        emptyState
                    }
                    ForEach(messages) { message in
                        MessageBubble(
                            message: message,
                            isStreaming: provider.isGenerating && message.id == streamingMessageId
                        )
                        .id(message.id)
                    }
                }
                .padding(.vertical, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            // Auto-scroll to the streaming message as tokens arrive.
            .onChange(of: messages.last?.text) { _, _ in
                if let id = streamingMessageId {
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(id, anchor: .bottom)
                    }
                }
            }
            .font(.system(size: messageFontSize, weight: .bold))
        }
    }

    // MARK: - Empty state

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 60)
            Image(systemName: "brain.head.profile")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            if activeModelName == nil {
                // No model activated — direct user to Models tab.
                VStack(spacing: 8) {
                    Text("No model selected")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("Go to the Models tab to download and activate a model.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            } else if !provider.isAvailable {
                // Running in the iOS Simulator — no Metal GPU.
                VStack(spacing: 8) {
                    Text("Unavailable in Simulator")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("On-device inference requires a physical iPhone or iPad with Apple Silicon.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            } else {
                VStack(spacing: 8) {
                    Text("Say something")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    if let name = activeModelName {
                        Text("Using **\(name)**")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer().frame(height: 40)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Input bar

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            // Multi-line text input that grows up to ~5 lines.
            TextField("Message…", text: $inputText, axis: .vertical)
                .lineLimit(1...5)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .disabled(provider.isGenerating)
                .onSubmit { sendIfReady() }

            // Send / Stop button — toggles based on `isGenerating`.
            Button(action: provider.isGenerating ? stopGeneration : sendIfReady) {
                Image(systemName: provider.isGenerating ? "stop.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(canSend ? Color.accentColor : Color.secondary)
            }
            .disabled(!canSend && !provider.isGenerating)
            .accessibilityLabel(provider.isGenerating ? "Stop generation" : "Send message")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && activeModelName != nil
            && provider.isAvailable
            && !provider.isGenerating
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Model name picker (left side).
        ToolbarItem(placement: .topBarLeading) {
            modelPickerMenu
        }
        
        ToolbarItemGroup {
            viewMenu
        }
        
        // Status dot + clear button (right side).
        ToolbarItemGroup(placement: .topBarTrailing) {
            statusDot
            Button {
                Task { await clearChat() }
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .accessibilityLabel("Clear conversation")
            .disabled(messages.isEmpty && !provider.isGenerating)
        }
    }

    @ViewBuilder
    private var modelPickerMenu: some View {
        Menu {
            ForEach(ChatModelCatalog.all) { descriptor in
                Button {
                    Task { await activateModel(descriptor.id) }
                } label: {
                    HStack {
                        Text(descriptor.displayName)
                        if activeModelName == descriptor.displayName {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            Divider()
            // Quick-link to Models tab (handled by ContentView's TabView selection).
            Button {
                // This triggers a notification that ContentView listens to.
                NotificationCenter.default.post(name: .switchToModelsTab, object: nil)
            } label: {
                Label("Manage Models…", systemImage: "arrow.down.circle")
            }
        } label: {
            HStack(spacing: 4) {
                Text(activeModelName.map { shortModelName($0) } ?? "No model")
                    .font(.subheadline)
                    .foregroundStyle(activeModelName == nil ? .secondary : .primary)
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
            .overlay(
                // Pulsing ring while generating.
                provider.isGenerating
                ? Circle().strokeBorder(statusColor.opacity(0.4), lineWidth: 2)
                    .scaleEffect(1.6)
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                                value: provider.isGenerating)
                : nil
            )
            .accessibilityLabel("Status: \(modelStatus)")
    }

    @ViewBuilder
    private var viewMenu: some View {
        ControlGroup {
            Button("Decrease Font Size", systemImage: "minus") {
                messageFontSize -= 1
            }

            Button("Increase Font Size", systemImage: "plus") {
                messageFontSize += 1
            }
        }
    }
    
    private var statusColor: Color {
        if provider.isGenerating { return .green }
        if modelStatus.starts(with: "Error") { return .red }
        if modelStatus == "Ready" { return .green.opacity(0.7) }
        if modelStatus == "Loading…" { return .orange }
        return .secondary
    }

    // MARK: - Actions

    private func sendIfReady() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, canSend else { return }
        inputText = ""

        let userMessage = ChatMessage(role: .user, text: text)
        messages.append(userMessage)

        // Add a placeholder assistant bubble that shows ThinkingDotsView
        // until the first token arrives.
        let assistantMessage = ChatMessage(role: .assistant, text: "")
        messages.append(assistantMessage)
        streamingMessageId = assistantMessage.id

        streamTask = Task {
            do {
                let stream = try await provider.respond(to: text)
                let lastIdx = messages.count - 1
                for await chunk in stream {
                    if Task.isCancelled { break }
                    messages[lastIdx].text += chunk
                }
            } catch MLXError.modelNotInstalled {
                replaceLastMessage(with: "_(No model installed. Go to the **Models** tab to download one.)_")
            } catch MLXError.metalUnavailable {
                replaceLastMessage(with: "_(On-device inference is unavailable in the iOS Simulator.)_")
            } catch {
                replaceLastMessage(with: "_(Error: \(error.localizedDescription))_")
            }
            streamingMessageId = nil
            await refreshModelInfo()
        }
    }

    private func stopGeneration() {
        provider.cancel()
        streamTask?.cancel()
        streamTask = nil
        streamingMessageId = nil
    }

    private func clearChat() async {
        stopGeneration()
        await provider.clearHistory()
        messages.removeAll()
    }

    private func activateModel(_ id: String) async {
        do {
            try await ChatModelRegistry.shared.setActive(id)
            await refreshModelInfo()
        } catch {
            print("[Onyx] Activate failed: \(error.localizedDescription)")
        }
    }

    private func replaceLastMessage(with text: String) {
        guard !messages.isEmpty else { return }
        messages[messages.count - 1].text = text
    }

    private func refreshModelInfo() async {
        activeModelId: do {
            guard let id = await ChatModelRegistry.shared.activeId(),
                  let descriptor = ChatModelCatalog.descriptor(forId: id) else {
                activeModelName = nil
                break activeModelId
            }
            activeModelName = descriptor.displayName
        }
        modelStatus = await provider.modelStatusLabel()
    }

    // MARK: - Helpers

    /// Shorten a long model name for the narrow toolbar slot.
    ///
    /// "Qwen 2.5 3B Instruct (4-bit)" → "Qwen 2.5 3B"
    private func shortModelName(_ name: String) -> String {
        let words = name.split(separator: " ").map(String.init)
        let trimmed = words.filter {
            !$0.hasPrefix("(") && !$0.lowercased().contains("instruct")
        }
        return trimmed.prefix(3).joined(separator: " ")
    }
}

// MARK: - Tab-switch notification

extension Notification.Name {
    /// Posted by ChatView when the user taps "Manage Models…" in the picker.
    /// ContentView listens and switches the TabView to the Models tab.
    static let switchToModelsTab = Notification.Name("onyx.switchToModelsTab")
}

// MARK: - Preview

#Preview("Chat — empty") {
    ChatView()
}
