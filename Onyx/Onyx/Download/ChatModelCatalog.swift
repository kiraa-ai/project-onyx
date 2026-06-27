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

import Foundation

// MARK: - ChatModelCatalog
//
// PURPOSE: Single Llama 3.2 1B model shown in the Models tab.

// MARK: - ChatModelFamily

/// Which model family this descriptor belongs to.
///
/// Used to pick SF Symbol icons and apply family-specific colour coding in
/// the UI. Has no effect on inference — the model's chat template handles
/// any family-specific formatting automatically.
public enum ChatModelFamily: String, Sendable, Codable, CaseIterable {
    case llama
    case qwen
    case gemma
    case other

    public var symbolName: String {
        switch self {
        case .llama: return "l.circle.fill"
        case .qwen: return "q.circle.fill"
        case .gemma:return "g.circle.fill"
        case .other: return "cpu"
        }
    }
}

// MARK: - ChatModelDescriptor

/// Metadata for a downloadable MLX chat model.
///
/// Every field is used by the Models tab UI. Add a new model by creating a
/// `ChatModelDescriptor` and appending it to `ChatModelCatalog.all`.
public struct ChatModelDescriptor: Sendable, Hashable, Identifiable {

    /// HuggingFace repo id, e.g. `"mlx-community/Qwen2.5-3B-Instruct-4bit"`.
    ///
    /// This id is also used as the directory name under the model store:
    /// `OnyxPaths.modelDirectory(for: id)`.
    public let id: String

    /// Short human-readable name displayed in the UI, e.g. `"Qwen 2.5 3B (4-bit)"`.
    public let displayName: String

    /// Model family, used for icons and colour coding.
    public let family: ChatModelFamily

    /// Approximate download size in bytes. Shown as "≈ 2 GB" before download
    /// starts. The actual download may differ slightly.
    public let approxSizeBytes: Int64

    /// Glob patterns passed to `HubApi.snapshot(matching:)`. The defaults
    /// cover all files needed by MLX models from `mlx-community`.
    public let filePatterns: [String]

    /// One-line description shown beneath the model name in the list.
    public let summary: String

    public init(id: String, displayName: String, family: ChatModelFamily,
                approxSizeBytes: Int64, filePatterns: [String], summary: String) {
        self.id = id; self.displayName = displayName; self.family = family
        self.approxSizeBytes = approxSizeBytes
        self.filePatterns = filePatterns; self.summary = summary
    }
}

// MARK: - ChatModelCatalog

/// The curated catalog of downloadable chat models.
public enum ChatModelCatalog {

    /// Glob patterns that cover every file type needed by 4-bit MLX models
    /// from `mlx-community`. Reused by all catalog entries.
    public nonisolated static let defaultFilePatterns: [String] = [
        "*.json",
        "*.safetensors",
        "*.txt",
        "*.jinja",
        "tokenizer.model"
    ]

    // swiftlint:disable line_length
    /// All available models, in display order within each device class.
    ///
    /// The first entry is treated as the recommended default by the
    /// Models tab (shown with a "Recommended" badge).
    ///
    /// - Note: To add a model, append a `ChatModelDescriptor` here. All
    ///   other subsystems (downloader, registry, UI) pick it up automatically.
    public nonisolated static let all: [ChatModelDescriptor] = [
        ChatModelDescriptor(
            id: "mlx-community/Llama-3.2-1B-Instruct-4bit",
            displayName: "Llama 3.2 1B Instruct (4-bit)",
            family: .llama,
            approxSizeBytes: 858_993_459,   // ≈ 0.8 GB
            filePatterns: defaultFilePatterns,
            summary: "Meta's compact on-device model. Under 1 GB — fast load times."
        ),
        ChatModelDescriptor(
            id: "LiquidAI/LFM2.5-1.2B-Instruct-MLX-4bit",
            displayName: "LFM 2.5 1.2B (4-bit)",
            family: .other,
            approxSizeBytes: Int64(0.7 * 1_073_741_824),   // ≈ 700 MB
            filePatterns: defaultFilePatterns,
            summary: "LiquidAI model."
        ),
        ChatModelDescriptor(
            id: "mlx-community/VibeThinker-3B-4bit",
            displayName: "VibeThinker 3B (4-bit)",
            family: .qwen,
            approxSizeBytes: Int64(2 * 1_073_741_824),   // ≈ 2 GB
            filePatterns: defaultFilePatterns,
            summary: "WeiboAI compact model, based on Qwen2.5-Coder."
        ),
        ChatModelDescriptor(
            id: "lmstudio-community/Qwen3.5-4B-MLX-4bit",
            displayName: "Qwen 3.5 4B (4-bit)",
            family: .qwen,
            approxSizeBytes: Int64(3.1 * 1_073_741_824),   // ≈ 3.1 GB
            filePatterns: defaultFilePatterns,
            summary: "Qwen compact model."
        ),
   ]
    // swiftlint:enable line_length

    /// Look up a descriptor by its HuggingFace id.
    ///
    /// Returns `nil` for unknown ids — avoids crashing when the user
    /// manually drops extra directories into the model store.
    public nonisolated static func descriptor(forId id: String) -> ChatModelDescriptor? {
        all.first { $0.id == id }
    }
}
