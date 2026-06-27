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

// MARK: - DownloadRow
//
// PURPOSE: One model card in the Models tab. Manages its own download-state
//          subscription and surfaces the correct action button for each
//          lifecycle stage.
//
// SUBSCRIPTION DESIGN:
//   Two paths subscribe to download progress:
//   1. `.task(id: descriptor.id)` — if a download is already in progress when
//      the view appears (e.g. app relaunch mid-download), this task subscribes
//      and picks up live updates.
//   2. `startDownload()` — after the user taps Download, the download is
//      started and this function immediately subscribes to the resulting stream.
//
//   Both paths feed into the same `downloadState` @State property, which
//   drives the progress bar and button rendering.
//
// EXTENDING THIS:
//   To show ETA or bytes/sec, add computed properties on
//   `ChatModelDownloader.State` in ChatModelDownloader.swift.

/// One model card in the Models tab.
///
/// Renders model metadata, download progress, and contextual action buttons
/// (Download / Cancel / Activate / Uninstall). State is driven by a
/// `ChatModelDownloader` subscription rather than polling.
struct DownloadRow: View {

    let descriptor: ChatModelDescriptor

    /// The currently active model id. Used to highlight the active row.
    var activeModelId: String?
    /// Set of installed model ids (from `ChatModelRegistry.installedIds()`).
    var installedIds: Set<String>
    /// Called when the user taps Activate. Parent updates `activeModelId`.
    var onActivate: (String) async -> Void
    /// Called when the user confirms Uninstall. Parent updates `installedIds`.
    var onUninstall: (String) async -> Void

    @State private var downloadState: ChatModelDownloader.State? = nil
    @State private var diskBytes: Int64 = 0
    @State private var showUninstallConfirm = false

    /// What the progress bar actually renders. A 4 Hz ticker eases this
    /// toward `State.overallFraction` and adds a slow creep while waiting
    /// for the next real update, so the bar visibly never stops moving.
    @State private var displayedFraction: Double = 0

    private var isInstalled: Bool { installedIds.contains(descriptor.id) }
    private var isActive: Bool { activeModelId == descriptor.id }
    private var isDownloading: Bool {
        guard let s = downloadState else { return false }
        return !s.isTerminal
    }
    private var isFirstInCatalog: Bool {
        ChatModelCatalog.all.first?.id == descriptor.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            Text(descriptor.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
            metaChips
            if let state = downloadState, !state.isTerminal || state.phase == .failed {
                progressSection(state)
            }
            actionButtons
        }
        .padding(.vertical, 4)
        // Subscribe if a download for this model is already running when the view appears.
        .task(id: descriptor.id) {
            await listenToDownloadStream()
        }
        // Smoothing ticker: runs only while a download is in flight.
        .task(id: isDownloading) {
            guard isDownloading else { return }
            while !Task.isCancelled {
                tickProgress()
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        // Load disk usage for already-installed models.
        .task {
            if isInstalled {
                diskBytes = await ChatModelRegistry.shared.diskBytes(for: descriptor.id)
            }
        }
        .confirmationDialog(
            "Uninstall \(descriptor.displayName)?",
            isPresented: $showUninstallConfirm,
            titleVisibility: .visible
        ) {
            Button("Uninstall", role: .destructive) {
                Task { await onUninstall(descriptor.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The model files will be deleted from this device. You can re-download them at any time.")
        }
    }

    // MARK: - Sub-views

    private var headerRow: some View {
        HStack(spacing: 10) {
            Image(systemName: descriptor.family.symbolName)
                .foregroundStyle(familyColor)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(descriptor.displayName)
                        .font(.headline)
                    if isActive {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.subheadline)
                            .accessibilityLabel("Active model")
                    }
                    if isFirstInCatalog && !isInstalled {
                        Text("Recommended")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(Capsule())
                    }
                }
                // Monospaced HuggingFace repo path for copy-paste convenience.
                Text(descriptor.id)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()
        }
    }

    private var metaChips: some View {
        HStack(spacing: 8) {
            sizeChip
            if isInstalled && diskBytes > 0 {
                chip(label: diskLabel, icon: "internaldrive")
            }
            chip(label: descriptor.family.rawValue.capitalized, icon: descriptor.family.symbolName)
            if !HardwareProfile.default.canLoadModel(approxSizeBytes: descriptor.approxSizeBytes) {
                incompatibleChip
            }
        }
    }

    private var incompatibleChip: some View {
        Label("Requires more RAM", systemImage: "exclamationmark.triangle")
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.orange.opacity(0.12))
            .clipShape(Capsule())
            .foregroundStyle(.orange)
    }

    private var sizeChip: some View {
        let gb = Double(descriptor.approxSizeBytes) / 1_073_741_824
        return chip(label: String(format: "≈ %.0f GB", gb), icon: "arrow.down.circle")
    }

    private func chip(label: String, icon: String) -> some View {
        Label(label, systemImage: icon)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(.tertiarySystemBackground))
            .clipShape(Capsule())
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func progressSection(_ state: ChatModelDownloader.State) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(state.phase.displayLabel)
                    .font(.caption.weight(.medium))
                Spacer()
                Text("\(Int(displayedFraction * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(1.0, displayedFraction))
                .tint(state.phase == .failed ? Color.red : Color.accentColor)
                .animation(.linear(duration: 0.25), value: displayedFraction)
            if state.phase == .downloading, state.bytesTotal > 0 {
                Text("\(ChatModelDownloader.formatBytes(state.bytesDownloaded)) of \(ChatModelDownloader.formatBytes(state.bytesTotal))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            if let err = state.error {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
    }

    /// One 250 ms smoothing step: ease toward the real pipeline fraction,
    /// and creep slightly ahead of it while downloading so the bar never
    /// sits still between progress updates. The creep is capped 2% ahead of
    /// reality and never passes 95%.
    private func tickProgress() {
        guard let state = downloadState else { return }
        let target = state.overallFraction
        if displayedFraction < target {
            displayedFraction = min(target, displayedFraction + max(0.002, (target - displayedFraction) * 0.25))
        } else if state.phase == .downloading {
            displayedFraction = min(displayedFraction + 0.0008, min(target + 0.02, 0.95))
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 12) {
            if isInstalled {
                if isActive {
                    Label("Active", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.green)
                } else {
                    Button {
                        Task { await onActivate(descriptor.id) }
                    } label: {
                        Label("Activate", systemImage: "checkmark.circle")
                            .font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                Spacer()

                Button(role: .destructive) {
                    showUninstallConfirm = true
                } label: {
                    Label("Uninstall", systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red.opacity(0.8))

            } else if isDownloading {
                Button {
                    Task { await ChatModelDownloader.shared.cancel(descriptor.id) }
                } label: {
                    Label("Cancel", systemImage: "xmark.circle")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.secondary)

                Spacer()

            } else {
                Button {
                    Task { await startDownload() }
                } label: {
                    Label("Download", systemImage: "arrow.down.circle")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Spacer()
            }
        }
    }

    // MARK: - Download lifecycle

    /// Start a fresh download and immediately subscribe to its progress stream.
    @MainActor
    private func startDownload() async {
        displayedFraction = 0
        let installPath = OnyxPaths.modelDirectory(for: descriptor.id)
        ChatModelDownloader.log(modelId: descriptor.id, "👆 user tapped Download (UI) install=\(installPath.lastPathComponent)")
        do {
            try await ChatModelDownloader.shared.start(
                modelId: descriptor.id,
                revision: "main",
                matching: descriptor.filePatterns,
                installPath: installPath,
                approxSizeBytes: descriptor.approxSizeBytes
            )
        } catch {
            ChatModelDownloader.log(modelId: descriptor.id, "❌ UI start() threw: \(error.localizedDescription)")
            downloadState = ChatModelDownloader.State(
                id: descriptor.id,
                phase: .failed,
                bytesDownloaded: 0,
                bytesTotal: descriptor.approxSizeBytes,
                error: error.localizedDescription
            )
            return
        }
        await listenToDownloadStream()
    }

    /// Subscribe to `ChatModelDownloader` progress updates for this model.
    ///
    /// Returns immediately if no download is in progress. Called both on
    /// view appear (to resume a download that was already running) and after
    /// `startDownload()` triggers a new one.
    private func listenToDownloadStream() async {
        guard let stream = await ChatModelDownloader.shared.subscribe(id: descriptor.id) else {
            ChatModelDownloader.log(modelId: descriptor.id, "👀 UI subscribe() returned nil (no active download)")
            return
        }
        ChatModelDownloader.log(modelId: descriptor.id, "👀 UI began listening to progress stream")
        for await state in stream {
            downloadState = state
            if state.phase == .done {
                displayedFraction = 1.0
                diskBytes = await ChatModelRegistry.shared.diskBytes(for: descriptor.id)
                await onActivate(descriptor.id)
            }
        }
        ChatModelDownloader.log(modelId: descriptor.id, "👀 UI progress stream finished phase=\(downloadState?.phase.rawValue ?? "nil")")
    }

    // MARK: - Helpers

    private var diskLabel: String {
        let gb = Double(diskBytes) / 1_073_741_824
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        let mb = Double(diskBytes) / 1_048_576
        return String(format: "%.0f MB", mb)
    }

    private var familyColor: Color {
        switch descriptor.family {
        case .llama: return .orange
        case .qwen: return .red
        case .gemma: return .green
        case .other: return .secondary
        }
    }
}

// MARK: - Phase display

private extension ChatModelDownloader.Phase {
    var displayLabel: String {
        switch self {
        case .resolving:   return "Resolving…"
        case .preparing:   return "Preparing…"
        case .downloading: return "Downloading…"
        case .verifying:   return "Verifying…"
        case .done:        return "Done"
        case .failed:      return "Failed"
        case .cancelled:   return "Cancelled"
        }
    }
}
