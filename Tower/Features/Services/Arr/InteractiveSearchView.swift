import SwiftUI
import TowerCore

/// The release list, built once for every *arr and every scope.
struct InteractiveSearchView: View {
  @Bindable var store: InteractiveSearchStore

  @Environment(\.dismiss) private var dismiss
  @State private var pendingGrab: ArrRelease?

  var body: some View {
    NavigationStack {
      content
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        .task {
          guard store.state.value == nil else { return }
          await store.load()
        }
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Done") { dismiss() }
              .accessibilityIdentifier("search.done")
          }
          ToolbarItem(placement: .topBarTrailing) {
            // **Wrapped in a `Menu`.** A
            // `.menu`-styled `Picker` placed straight into a toolbar item
            // expands to fill the trailing width, rendering as a capsule
            // running most of the navigation bar with the selected value
            // pushed to its far edge — it reads as broken layout and crowds
            // the title. The `Menu` keeps it to an icon; the `Picker` inside
            // still supplies the options and the checkmark on the current one.
            Menu("Sort", systemImage: "arrow.up.arrow.down") {
              Picker("Sort", selection: $store.sort) {
                ForEach(ReleaseSort.allCases) { option in
                  Text(option.displayName).tag(option)
                }
              }
            }
            .accessibilityIdentifier("search.sort")
            .accessibilityValue(store.sort.displayName)
          }
        }
        .confirmationDialog(
          pendingGrab.map { "Grab \($0.title)?" } ?? "Grab release?",
          isPresented: Binding(
            get: { pendingGrab != nil },
            set: { if !$0 { pendingGrab = nil } }),
          titleVisibility: .visible
        ) {
          Button("Grab") {
            if let pendingGrab { grab(pendingGrab) }
            pendingGrab = nil
          }
          .accessibilityIdentifier("search.confirmGrab")
          Button("Cancel", role: .cancel) { pendingGrab = nil }
        } message: {
          if let pendingGrab, !pendingGrab.rejections.isEmpty {
            // Grabbing a rejected release is allowed — it is an *override*, and
            // the user needs to see what they are overriding.
            Text(pendingGrab.rejections.joined(separator: "\n"))
          } else {
            Text("This sends the release to your download client.")
          }
        }
        .sensoryFeedback(.success, trigger: store.grabCount)
    }
  }

  @ViewBuilder
  private var content: some View {
    switch store.state {
    case .idle, .loading:
      ProgressView("Searching indexers…")
        .accessibilityIdentifier("search.loading")
    case .failed(let error):
      VStack(spacing: 16) {
        ContentUnavailableView {
          Label(error.message, systemImage: "exclamationmark.triangle")
        } description: {
          if let suggestion = error.serviceRecoverySuggestion { Text(suggestion) }
        }
        .accessibilityIdentifier("search.error")
        Button("Try Again") { Task { await store.load() } }
          .accessibilityIdentifier("search.retry")
      }
    case .loaded(let releases), .actionFailed(let releases, _):
      if releases.isEmpty {
        ContentUnavailableView(
          "No Releases", systemImage: "magnifyingglass",
          description: Text("No indexer had anything for \(store.scope.title).")
        )
        .accessibilityIdentifier("search.empty")
      } else {
        list
      }
    }
  }

  private var list: some View {
    List {
      if let error = store.grabError {
        Text(error.message)
          .font(.caption)
          .foregroundStyle(.red)
          .accessibilityIdentifier("search.grabError")
      }
      ForEach(store.releases) { release in
        Button {
          pendingGrab = release
        } label: {
          ReleaseRow(release: release, isGrabbing: store.isGrabbing(release))
        }
        .buttonStyle(.plain)
      }
    }
  }

  private func grab(_ release: ArrRelease) {
    Task { await store.grab(release) }
  }
}

/// One release: title, quality, size, age, indexer, and why the *arr
/// wouldn't have taken it.
struct ReleaseRow: View {
  let release: ArrRelease
  let isGrabbing: Bool

  var body: some View {
    DashboardRow(showsChevron: false) {
      VStack(alignment: .leading, spacing: 4) {
        Text(release.title)
          .font(.callout)
          .lineLimit(2)

        HStack(spacing: 6) {
          if let quality = release.quality {
            Text(quality)
              .font(.caption2.weight(.medium))
              .padding(.horizontal, 5)
              .padding(.vertical, 1)
              .background(.quaternary, in: Capsule())
          }
          Text(Formatters.bytes(release.sizeBytes))
          if let age = release.ageHours {
            Text("·")
            Text(ageText(age))
          }
        }
        .font(.caption)
        .foregroundStyle(.secondary)

        let source = [release.downloadProtocol.displayName, release.indexer]
          .compactMap { $0 }
          .joined(separator: " · ")
        if !source.isEmpty {
          Text(source)
            .font(.caption2)
            .foregroundStyle(.secondary)
        }

        if !release.rejections.isEmpty {
          // The service's own words, verbatim: they explain the rejection
          // better than any rewording here could, and they are the reason a
          // user either overrides or moves on.
          Text(release.rejections.joined(separator: " · "))
            .font(.caption2)
            .foregroundStyle(.orange)
            .lineLimit(3)
        }
      }

      Spacer(minLength: 4)

      if isGrabbing {
        ProgressView()
      } else if release.isApproved {
        Image(systemName: "checkmark.circle")
          .foregroundStyle(.green)
          .accessibilityHidden(true)
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilityLabel)
    .accessibilityIdentifier("search.release.\(release.id)")
  }

  private func ageText(_ hours: Double) -> String {
    hours < 24
      ? "\(Int(hours.rounded()))h"
      : "\(Int((hours / 24).rounded()))d"
  }

  private var accessibilityLabel: String {
    var parts = [release.title]
    if let quality = release.quality { parts.append(quality) }
    parts.append(Formatters.bytes(release.sizeBytes))
    if let indexer = release.indexer { parts.append(indexer) }
    parts.append(release.isApproved ? "Approved" : "Rejected")
    parts.append(contentsOf: release.rejections)
    return parts.joined(separator: ", ")
  }
}
