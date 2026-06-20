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

// MARK: - ChatMessage
//
// PURPOSE: Value-type message model for the chat scroll view.
//
// This is intentionally lightweight — no CoreData, no SwiftData,
// no persistence. Conversations reset on app restart. To add persistence,
// encode this to JSON and write to OnyxPaths.baseDirectory().

/// A single message in a chat conversation.
///
/// `id` is stable — use it as the `ForEach` id so SwiftUI can animate
/// individual rows without re-rendering the whole list.
struct ChatMessage: Identifiable {
    let id = UUID()
    var role: Role
    var text: String

    enum Role { case user, assistant }
}

// MARK: - MessageBubble
//
// PURPOSE: Renders one message in the chat scroll view.
//
// LAYOUT:
//   User messages:    right-aligned, teal/accent background, white text.
//   Assistant messages: left-aligned, secondary system background, primary text.
//
// MARKDOWN:
//   Assistant messages are rendered by `MarkdownMessageView` which handles
//   fenced code blocks, ATX headings, bullet/ordered lists, and inline
//   Markdown (bold, italic, `code`). Link attributes are stripped to prevent
//   model-injected tappable URLs. User messages are displayed as plain text.
//
// ACCESSIBILITY:
//   Each bubble gets an accessibility label combining the speaker name and
//   content, so VoiceOver users hear "You: [text]" or "Assistant: [text]".

/// A single chat message row.
///
/// Pass a `ChatMessage` and this view handles alignment, colour, and
/// Markdown rendering automatically.
///
/// ## Example
/// ```swift
/// ForEach(messages) { message in
///     MessageBubble(message: message)
/// }
/// ```
struct MessageBubble: View {

    let message: ChatMessage

    /// True while streaming; shows `ThinkingDotsView` if text is empty.
    var isStreaming: Bool = false

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .bottom) {
            if isUser { Spacer(minLength: 48) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                bubbleContent
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(isUser ? Color.accentColor : Color(.secondarySystemBackground))
                    .foregroundStyle(isUser ? Color(uiColor: .systemBackground) : Color.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    // Subtle border on assistant bubbles for definition on
                    // pure-white backgrounds in light mode.
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(isUser ? .clear : Color(.separator),
                                          lineWidth: 0.5)
                    )
                    .accessibilityLabel(isUser ? "You" : "Assistant")
                    .accessibilityValue(message.text.isEmpty ? "Thinking" : message.text)
            }

            if !isUser { Spacer(minLength: 48) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var bubbleContent: some View {
        if isStreaming && message.text.isEmpty {
            ThinkingDotsView()
        } else if isUser {
            // User text: plain, no Markdown parsing.
            Text(sanitized(message.text))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            // Assistant text: full block-level Markdown via MarkdownMessageView.
            MarkdownMessageView(text: message.text)
        }
    }

    /// Strip ASCII control characters (0x00–0x1F) except tab, LF, and CR.
    /// All non-ASCII (emoji, CJK, accented characters) passes through unchanged.
    private func sanitized(_ text: String) -> String {
        text.filter { ch in
            guard ch.isASCII, let v = ch.asciiValue else { return true }
            return v >= 0x20 || v == 0x09 || v == 0x0A || v == 0x0D
        }
    }
}

// MARK: - Preview

#Preview("Message Bubbles") {
    ScrollView {
        VStack(spacing: 0) {
            MessageBubble(message: ChatMessage(role: .user,
                text: "What is 2 + 2?"))
            MessageBubble(message: ChatMessage(role: .assistant,
                text: "The answer is **4**. Simple arithmetic!"))
            MessageBubble(message: ChatMessage(role: .user,
                text: "Can you write a haiku about Swift?"))
            MessageBubble(message: ChatMessage(role: .assistant,
                text: ""), isStreaming: true)
        }
        .padding(.vertical, 8)
    }
}
