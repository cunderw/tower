import SwiftUI
import TowerCore

/// Health, disk space, system status, and manual commands.
struct ArrMoreView: View {
  @Bindable var store: ArrMoreStore

  var body: some View {
    List {
      if let error = store.loadError {
        Section {
          ContentUnavailableView {
            Label(error.message, systemImage: "exclamationmark.triangle")
          } description: {
            if let suggestion = error.serviceRecoverySuggestion { Text(suggestion) }
          }
          .accessibilityIdentifier("more.error")
        }
      }

      healthSection
      diskSection
      statusSection
      commandSection
    }
    .task {
      guard !store.hasLoaded else { return }
      await store.load()
    }
    .refreshable { await store.load() }
    .sensoryFeedback(.success, trigger: store.completedCommands)
    .accessibilityIdentifier("more")
  }

  @ViewBuilder
  private var healthSection: some View {
    Section("Health") {
      if store.health.isEmpty {
        Label("No warnings", systemImage: "checkmark.circle")
          .foregroundStyle(.green)
          .accessibilityIdentifier("more.health.clear")
      } else {
        ForEach(store.health) { check in
          VStack(alignment: .leading, spacing: 3) {
            Label(check.message, systemImage: icon(for: check.severity))
              .font(.callout)
              .foregroundStyle(color(for: check.severity))
            if let source = check.source {
              Text(source)
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            // The service links its own explanation; a warning a user can't act
            // on is a warning that just worries them.
            //
            // **The hit area matters more than the link.** A bare `.caption`
            // `Link` is about 60x14pt of tappable text in a dense row, well
            // under the 44pt minimum. It works when hit and does nothing when
            // missed, and a miss is silent, so it reads as a broken link
            // rather than a near miss. The padding and
            // `contentShape` give it a real target without moving it or
            // turning the whole warning into a link.
            if let wiki = check.wikiURL {
              Link(destination: wiki) {
                HStack(spacing: 3) {
                  Text("Read more")
                  Image(systemName: "arrow.up.right")
                    .imageScale(.small)
                }
                .font(.caption)
                .padding(.vertical, 8)
                .padding(.trailing, 12)
                .contentShape(Rectangle())
              }
              .accessibilityIdentifier("more.health.\(check.id).wiki")
            }
          }
          .accessibilityElement(children: .combine)
          .accessibilityIdentifier("more.health.\(check.id)")
        }
      }
    }
  }

  @ViewBuilder
  private var diskSection: some View {
    if !store.disks.isEmpty {
      Section("Disk Space") {
        ForEach(store.disks) { disk in
          VStack(alignment: .leading, spacing: 4) {
            HStack {
              Text(disk.label ?? disk.path)
                .font(.callout)
              Spacer()
              // Multi-TB figures, formatted by the same helper the array card
              // uses — this is the screen where a wrong unit is most obvious.
              Text("\(Formatters.bytes(disk.freeBytes)) free")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if let fraction = disk.usedFraction {
              ProgressView(value: fraction)
                .accessibilityHidden(true)
            }
            Text("\(Formatters.bytes(disk.usedBytes)) of \(Formatters.bytes(disk.totalBytes))")
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
          .accessibilityElement(children: .combine)
          .accessibilityIdentifier("more.disk.\(disk.path)")
        }
      }
    }
  }

  @ViewBuilder
  private var statusSection: some View {
    if let status = store.status {
      Section("System") {
        if let version = status.version {
          LabeledContent("Version", value: version)
        }
        if let app = status.appName {
          LabeledContent("Application", value: app)
        }
        if let os = status.osName {
          LabeledContent("Operating system", value: [os, status.osVersion].compactMap { $0 }.joined(separator: " "))
        }
        LabeledContent("Container", value: status.isDocker ? "Docker" : "Native")
        if let start = status.startTime {
          LabeledContent("Uptime", value: Formatters.uptime(since: start))
        }
      }
      .accessibilityIdentifier("more.status")
    }
  }

  private var commandSection: some View {
    Section("Commands") {
      ForEach(ArrMoreStore.offeredCommands, id: \.name) { command in
        Button {
          Task { await store.run(command.name) }
        } label: {
          HStack {
            Label(command.title, systemImage: command.systemImage)
            Spacer()
            // In-progress state, because a command that reports nothing looks
            // exactly like a button that does nothing.
            if store.isRunning(command.name) {
              ProgressView()
            }
          }
        }
        .disabled(store.runningCommand != nil)
        .accessibilityIdentifier("more.command.\(command.name)")
      }

      if let result = store.lastCommandResult {
        Label(
          result.succeeded ? "\(title(for: result.name)) queued" : (result.error?.message ?? "Failed"),
          systemImage: result.succeeded ? "checkmark.circle" : "exclamationmark.triangle"
        )
        .font(.caption)
        .foregroundStyle(result.succeeded ? .green : .red)
        .accessibilityIdentifier("more.commandResult")
      }
    }
  }

  private func title(for command: String) -> String {
    ArrMoreStore.offeredCommands.first { $0.name == command }?.title ?? command
  }

  private func icon(for severity: ArrHealthSeverity) -> String {
    switch severity {
    case .error: "xmark.octagon"
    case .warning: "exclamationmark.triangle"
    case .notice: "info.circle"
    case .unknown: "questionmark.circle"
    }
  }

  private func color(for severity: ArrHealthSeverity) -> Color {
    switch severity {
    case .error: .red
    case .warning: .orange
    case .notice: .secondary
    case .unknown: .secondary
    }
  }
}
