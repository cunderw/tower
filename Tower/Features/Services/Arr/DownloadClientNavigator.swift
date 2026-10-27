import Foundation
import SwiftUI
import TowerCore
import TowerData

/// Turns an *arr queue row into a way into the download client that is actually
/// fetching it.
///
/// **A value, not an environment key.** The *arr shell already threads
/// `openMedia` down the same path for history rows, and one more explicit
/// parameter keeps the rule visible at the call site — an environment lookup
/// would make "does this row link anywhere?" depend on something invisible in
/// the view that renders it. A row stays plain when `link(for:)` finds no
/// client, which is the case for the UI-test fakes and any stack without a
/// configured download client.
struct DownloadClientNavigator: Sendable {
  /// Everything Tower has configured, including the *arrs — `DownloadClientLink`
  /// filters to the clients itself so the rule lives in one place.
  let instances: [ServiceInstance]
  let makeRepository: ServiceRepositoryFactory

  /// The client this row points at, or `nil` when no link should be offered.
  ///
  /// **A match is not enough — the factory has to be able to build it.** An
  /// instance can be configured while Tower has no client for its kind, and
  /// offering a link there would put an affordance on the row that dead-ends on
  /// "Tower has no client for this service", which is worse than no affordance.
  func link(for item: ArrQueueItem) -> DownloadClientLink? {
    guard
      let link = DownloadClientLink.match(
        downloadProtocol: item.downloadProtocol,
        downloadClient: item.downloadClient,
        downloadID: item.downloadID,
        in: instances)
    else { return nil }
    guard makeRepository(link.instance) != nil else { return nil }
    return link
  }
}

/// The screen a queue row opens: the matched client's own screen.
///
/// Presented as a **sheet** rather than pushed, following the history row's
/// precedent in `RadarrServiceView` — the *arr shell's sections have no
/// navigation stack of their own, and this destination belongs to a different
/// service entirely.
struct DownloadClientLinkSheet: View {
  let link: DownloadClientLink
  let makeRepository: ServiceRepositoryFactory

  @Environment(\.dismiss) private var dismiss

  /// **Built once, in `@State`.** A store created inside `body` is recreated on
  /// every re-render, which resets its `Loadable` to `.idle` and restarts the
  /// `.task` that was about to finish, so the sheet's list never arrives.
  @State private var destination: Destination?

  private enum Destination {
    case nzb(NZBGetStore)
    case unsupported
  }

  var body: some View {
    NavigationStack {
      content
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Done") { dismiss() }
          }
        }
    }
    .task {
      guard destination == nil else { return }
      destination = Self.makeDestination(for: link, makeRepository: makeRepository)
    }
  }

  @ViewBuilder
  private var content: some View {
    switch destination {
    case .nzb(let store):
      // NZBGet has no per-item detail screen — the queue *is* the detail.
      NZBGetServiceView(instance: link.instance, store: store)
    case .unsupported:
      // The client is configured but Tower has no repository for it. Reachable
      // only if the factory changes under a stale link.
      ContentUnavailableView(
        "Can't Open \(link.instance.name)", systemImage: "questionmark.circle",
        description: Text("Tower has no client for this service.")
      )
      .accessibilityIdentifier("queue.link.unavailable")
    case nil:
      ProgressView()
    }
  }

  private static func makeDestination(
    for link: DownloadClientLink, makeRepository: ServiceRepositoryFactory
  ) -> Destination {
    switch makeRepository(link.instance) {
    case let nzbget as any NZBGetRepositoryProtocol:
      .nzb(NZBGetStore(repository: nzbget))
    default:
      .unsupported
    }
  }
}

