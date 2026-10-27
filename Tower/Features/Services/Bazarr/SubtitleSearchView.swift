import SwiftUI
import TowerCore

/// Find subtitles for one wanted item: let Bazarr choose, or pick from scored
/// results.
struct SubtitleSearchView: View {
  @Bindable var store: BazarrStore
  let item: WantedSubtitle

  @Environment(\.dismiss) private var dismiss
  @State private var pendingPick: SubtitleCandidate?

  var body: some View {
    NavigationStack {
      List {
        automaticSection
        manualSection
      }
      .navigationTitle(item.title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") { dismiss() }
        }
      }
      .task { await store.searchCandidates(for: item) }
      .confirmationDialog(
        pendingPick.map { "Download from \($0.provider)?" } ?? "Download subtitle?",
        isPresented: Binding(
          get: { pendingPick != nil },
          set: { if !$0 { pendingPick = nil } }),
        titleVisibility: .visible
      ) {
        if let candidate = pendingPick {
          Button("Download") {
            Task {
              await store.download(candidate, for: item)
              // Closed only after the wanted list has been re-read, so the
              // screen behind is already correct.
              dismiss()
            }
            pendingPick = nil
          }
          .accessibilityIdentifier("bazarr.confirmDownload")
        }
        Button("Cancel", role: .cancel) { pendingPick = nil }
      } message: {
        if let candidate = pendingPick {
          Text("\(candidate.language.displayName) · score \(candidate.score).")
        }
      }
    }
  }

  /// One button per wanted language, because "download the best" only means
  /// anything for a specific language — an item missing English and French
  /// needs two searches, not one.
  @ViewBuilder
  private var automaticSection: some View {
    Section {
      ForEach(item.missing) { language in
        Button {
          Task {
            await store.downloadBest(language, for: item)
            dismiss()
          }
        } label: {
          Label("Best match for \(language.displayName)", systemImage: "wand.and.stars")
        }
        .disabled(store.isDownloading(item))
        .accessibilityIdentifier("bazarr.auto.\(language.id)")
      }
    } header: {
      Text("Let Bazarr choose")
    } footer: {
      Text("Bazarr picks the highest-scoring match from your enabled providers.")
    }
  }

  @ViewBuilder
  private var manualSection: some View {
    Section {
      switch store.candidates(for: item) {
      case .idle, .loading:
        HStack {
          ProgressView()
          Text("Searching providers…")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      case .failed(let error):
        Text(error.message)
          .font(.caption)
          .foregroundStyle(.red)
          .accessibilityIdentifier("bazarr.search.error")
      case .loaded(let candidates), .actionFailed(let candidates, _):
        if candidates.isEmpty {
          Text("No provider had a subtitle for this.")
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("bazarr.search.empty")
        }
        ForEach(candidates) { candidate in
          Button {
            pendingPick = candidate
          } label: {
            CandidateRow(candidate: candidate)
          }
          .buttonStyle(.plain)
          .disabled(store.isDownloading(item))
          .accessibilityIdentifier("bazarr.candidate.\(candidate.id)")
        }
      }
    } header: {
      HStack {
        Text("Or pick one")
        Spacer()
        Button("Search Again") {
          Task { await store.searchCandidates(for: item, force: true) }
        }
        .font(.caption)
        .accessibilityIdentifier("bazarr.search.again")
      }
    }
  }
}

/// One scored candidate.
struct CandidateRow: View {
  let candidate: SubtitleCandidate

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(spacing: 6) {
        Text(candidate.provider)
          .font(.callout)
        Spacer(minLength: 4)
        // The score as a number *and* a band: 96 means nothing to someone who
        // hasn't learned Bazarr's scale.
        Text("\(candidate.score)")
          .font(.caption.weight(.semibold).monospacedDigit())
          .foregroundStyle(tint)
      }

      HStack(spacing: 6) {
        Text(candidate.language.displayName)
        Text("·")
        Text(candidate.confidence.displayName)
          .foregroundStyle(tint)
        if let uploader = candidate.uploader {
          Text("·")
          Text(uploader)
        }
      }
      .font(.caption2)
      .foregroundStyle(.secondary)
      .lineLimit(1)

      if let release = candidate.releaseInfo.first {
        Text(release)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      // Matching the release file is the difference between a subtitle that is
      // in sync and one that merely has the right name.
      if candidate.matchedBy.contains("release_group")
        || candidate.matchedBy.contains("hash")
      {
        Label("Matches this release", systemImage: "checkmark.seal")
          .font(.caption2)
          .foregroundStyle(.green)
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilityLabel)
  }

  private var tint: Color {
    switch candidate.confidence {
    case .high: .green
    case .medium: .orange
    case .low: .secondary
    }
  }

  private var accessibilityLabel: String {
    var parts = [
      candidate.provider, candidate.language.displayName,
      "score \(candidate.score)", candidate.confidence.displayName,
    ]
    if let release = candidate.releaseInfo.first { parts.append(release) }
    return parts.joined(separator: ", ")
  }
}
