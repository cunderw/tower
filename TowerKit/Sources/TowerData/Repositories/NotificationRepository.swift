import Apollo
import Foundation
import TowerAPI
import TowerCore

/// Reads Unraid's notifications and moves them between buckets. Apollo's
/// generated types never escape this module.
///
/// Two read methods rather than one, because the API splits them and they
/// refresh on different schedules: the badge needs `overview()` on every poll,
/// while `page(kind:offset:limit:)` is only fetched while the sheet is open, one
/// page at a time.
public protocol NotificationRepositoryProtocol: Sendable {
  func overview() async throws -> NotificationOverview

  /// One page of a bucket. `limit` is a maximum, not an exact count — the same
  /// caution `DockerRepositoryProtocol.logs(id:tail:since:)` documents.
  func page(kind: NotificationKind, offset: Int, limit: Int) async throws -> NotificationPage

  /// Moves one notification to the archive. Returns the recomputed overview so a
  /// caller can update the badge without a second round trip.
  func archive(id: String) async throws -> NotificationOverview

  /// Moves one notification back to unread — the inverse of `archive(id:)`, and
  /// the reason archiving is safe to offer as a swipe action while deleting
  /// needs a confirmation.
  func markUnread(id: String) async throws -> NotificationOverview

  /// Deletes one notification permanently. Irreversible; the UI confirms.
  func delete(id: String, kind: NotificationKind) async throws -> NotificationOverview

  /// Archives every unread notification. Reversible one at a time via
  /// `markUnread(id:)`.
  ///
  /// Deliberately the only bulk operation exposed: `deleteArchivedNotifications`
  /// exists in the schema and is **not** wired up, because it is bulk *and*
  /// irreversible.
  func archiveAll() async throws -> NotificationOverview
}

public struct LiveNotificationRepository: NotificationRepositoryProtocol {
  private let provider: ApolloClientProvider

  public init(provider: ApolloClientProvider) {
    self.provider = provider
  }

  public func overview() async throws -> NotificationOverview {
    let response = try await provider.client.fetch(
      query: NotificationOverviewQuery(),
      cachePolicy: .networkOnly
    )
    if let errors = response.errors, !errors.isEmpty {
      throw AppError.from(graphQLErrors: errors)
    }
    guard let data = response.data else {
      throw AppError.decoding("Empty response for NotificationOverview.")
    }
    return NotificationOverview(from: data.notifications.overview)
  }

  /// `Int32(clamping:)`, not a trapping conversion: `offset`/`limit` come from a
  /// paging caller, and a value outside `Int32` should clamp to something the
  /// server can answer rather than crash the app. Clamping is safe here in a way
  /// it wouldn't be for a size — the worst outcome is a page boundary that isn't
  /// where the caller expected.
  public func page(kind: NotificationKind, offset: Int, limit: Int) async throws -> NotificationPage {
    let filter = TowerAPI.NotificationFilter(
      type: .case(kind.wireValue),
      offset: Int32(clamping: max(0, offset)),
      limit: Int32(clamping: max(1, limit))
    )
    let response = try await provider.client.fetch(
      query: NotificationListQuery(filter: filter),
      cachePolicy: .networkOnly
    )
    if let errors = response.errors, !errors.isEmpty {
      throw AppError.from(graphQLErrors: errors)
    }
    guard let data = response.data else {
      throw AppError.decoding("Empty response for NotificationList.")
    }
    // Not re-sorted: the server returns newest-first, which is the order a
    // notification list is read in, and `offset` paging only makes sense against
    // the server's own ordering. Sorting client-side would shuffle rows between
    // pages.
    return NotificationPage(
      notifications: data.notifications.list.map(ServerNotification.init(from:)),
      requestedLimit: max(1, limit)
    )
  }

  public func archive(id: String) async throws -> NotificationOverview {
    // `archiveNotification` returns the `Notification`, not the overview, so the
    // counts have to be re-read. Deliberately a second request rather than
    // decrementing locally: the badge is a claim about the server's state, and a
    // locally-adjusted count silently drifts from it the first time something
    // else archives a notification (Unraid's own web UI, a script, another
    // device).
    _ = try await perform(ArchiveNotificationMutation(id: id))
    return try await overview()
  }

  public func markUnread(id: String) async throws -> NotificationOverview {
    _ = try await perform(UnreadNotificationMutation(id: id))
    return try await overview()
  }

  public func delete(id: String, kind: NotificationKind) async throws -> NotificationOverview {
    let data = try await perform(DeleteNotificationMutation(id: id, type: .case(kind.wireValue)))
    // This one *does* return the recomputed overview, so no second round trip.
    return NotificationOverview(from: data.deleteNotification)
  }

  public func archiveAll() async throws -> NotificationOverview {
    let data = try await perform(ArchiveAllNotificationsMutation())
    return NotificationOverview(from: data.archiveAll)
  }

  /// Shared errors-then-nil-data guard for the four mutations. Returns the
  /// `Data` so callers that need a field from it can read one, and callers that
  /// only need "it worked" can discard it.
  private func perform<Mutation: GraphQLMutation>(
    _ mutation: Mutation
  ) async throws -> Mutation.Data where Mutation.ResponseFormat == SingleResponseFormat {
    let response = try await provider.client.perform(mutation: mutation)
    if let errors = response.errors, !errors.isEmpty {
      throw AppError.from(graphQLErrors: errors)
    }
    guard let data = response.data else {
      throw AppError.decoding("Empty response for \(Mutation.operationName).")
    }
    return data
  }
}

extension NotificationKind {
  /// The generated enum case for this kind.
  ///
  /// `.unknown` maps to `.unread` because a request has to name one of the two
  /// buckets the server knows about, and unread is the non-destructive choice —
  /// `.unknown` only ever arises from *reading* a bucket name Tower doesn't
  /// recognize, never from a user choosing one, so this path is unreachable in
  /// practice and picks the harmless answer if it ever is not.
  fileprivate var wireValue: TowerAPI.NotificationType {
    switch self {
    case .unread, .unknown: .unread
    case .archive: .archive
    }
  }
}

extension NotificationCounts {
  /// Not public — its parameter is an Apollo-generated type. A structural
  /// protocol rather than one initializer per call site: four different
  /// generated types (the overview query's two, and each mutation's) carry the
  /// identical `info`/`warning`/`alert`/`total` shape as distinct nominal types,
  /// the same situation `DockerActionFields` handles.
  fileprivate init(from counts: some NotificationCountFields) {
    self.init(
      info: counts.info,
      warning: counts.warning,
      alert: counts.alert,
      total: counts.total
    )
  }
}

/// The `NotificationCounts` selection shape, shared by every operation that
/// selects it. Deliberately **not** public: Apollo-generated types must not
/// appear in this module's public surface.
private protocol NotificationCountFields {
  var info: Int { get }
  var warning: Int { get }
  var alert: Int { get }
  var total: Int { get }
}

/// Likewise for the `{ unread, archive }` pair, which four operations return as
/// four distinct nominal types.
/// **Two** associated types, not one: Apollo generates a *separate* nested type
/// per selected field, so `Overview.Unread` and `Overview.Archive` are distinct
/// nominal types despite having identical shapes. A single `associatedtype
/// Counts` fails to conform for exactly that reason. They happen to be named
/// `Unread`/`Archive` in the generated code, so conformance is inferred.
private protocol NotificationOverviewFields {
  associatedtype Unread: NotificationCountFields
  associatedtype Archive: NotificationCountFields
  var unread: Unread { get }
  var archive: Archive { get }
}

extension NotificationOverviewQuery.Data.Notifications.Overview.Unread: NotificationCountFields {}
extension NotificationOverviewQuery.Data.Notifications.Overview.Archive: NotificationCountFields {}
extension DeleteNotificationMutation.Data.DeleteNotification.Unread: NotificationCountFields {}
extension DeleteNotificationMutation.Data.DeleteNotification.Archive: NotificationCountFields {}
extension ArchiveAllNotificationsMutation.Data.ArchiveAll.Unread: NotificationCountFields {}
extension ArchiveAllNotificationsMutation.Data.ArchiveAll.Archive: NotificationCountFields {}

extension NotificationOverviewQuery.Data.Notifications.Overview: NotificationOverviewFields {}
extension DeleteNotificationMutation.Data.DeleteNotification: NotificationOverviewFields {}
extension ArchiveAllNotificationsMutation.Data.ArchiveAll: NotificationOverviewFields {}

extension NotificationOverview {
  /// Not public — see `NotificationCounts.init(from:)`.
  fileprivate init(from overview: some NotificationOverviewFields) {
    self.init(
      unread: NotificationCounts(from: overview.unread),
      archive: NotificationCounts(from: overview.archive)
    )
  }
}

extension ServerNotification {
  /// Maps Apollo's generated `NotificationListQuery.Data.Notifications.List` into
  /// the domain model. Not public — see `Container.init(from:)` for why.
  ///
  /// `timestamp` goes through `Formatters.parseTimestamp`, which degrades an
  /// unreadable value to `nil` rather than throwing. That is the whole reason
  /// `DateTime` stays a `String` on the wire: a notification's content is
  /// the payload, its timestamp is metadata, and a bad timestamp must never cost
  /// the notification.
  ///
  /// `link` maps `""` to `nil` — the wire's way of saying "no link" — so the UI
  /// omits the affordance rather than offering one that goes nowhere.
  init(from notification: NotificationListQuery.Data.Notifications.List) {
    self.init(
      id: notification.id,
      title: notification.title,
      subject: notification.subject,
      description: notification.description,
      importance: NotificationImportance(rawValue: notification.importance.rawValue),
      kind: NotificationKind(rawValue: notification.type.rawValue),
      linkPath: notification.link?.isEmpty == true ? nil : notification.link,
      timestamp: notification.timestamp.flatMap(Formatters.parseTimestamp)
    )
  }
}
