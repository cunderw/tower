import SwiftUI
import TowerCore

/// One hub row: the service's glyph, the instance's name, and a status line.
///
/// The status line is text, not just a coloured dot — "Credentials rejected"
/// and "Unreachable" send the user to two different screens, and a red dot says
/// neither (colour is never the only signal).
struct ServiceInstanceRow: View {
  let instance: ServiceInstance
  /// `nil` while the check is still in flight.
  let status: ServiceStatus?

  var body: some View {
    DashboardRow(showsChevron: false) {
      Image(systemName: instance.kind.systemImage)
        .font(.body)
        .foregroundStyle(.secondary)
        .frame(width: 24)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 2) {
        Text(instance.name)
          .font(.body)
        Text(statusLine)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer(minLength: 8)

      if let status, status.isProblem {
        // A badge as well as the words: the hub is a glanceable screen and the
        // point of the red mark is to be findable without reading four rows.
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.red)
          .accessibilityHidden(true)
      }
    }
    // One VoiceOver stop per row, and the spoken text carries the
    // kind, the name, and the state — none of which are conveyed by the glyph
    // or the badge colour on their own.
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(instance.kind.displayName), \(instance.name), \(statusLine)")
    .accessibilityIdentifier("services.row.\(instance.id.uuidString)")
  }

  private var statusLine: String {
    guard let status else { return "Checking…" }
    return status.summary
  }
}

#Preview {
  let radarr = ServiceInstance(
    kind: .radarr, name: "Radarr", baseURL: URL(string: "http://192.0.2.10:7878")!,
    credentials: .apiKey("k"))
  let sonarr = ServiceInstance(
    kind: .sonarr, name: "Sonarr 4K", baseURL: URL(string: "http://192.0.2.10:8989")!,
    credentials: .apiKey("k"))
  let nzbget = ServiceInstance(
    kind: .nzbget, name: "NZBGet", baseURL: URL(string: "http://192.0.2.10:6789")!,
    credentials: .usernamePassword(username: "admin", password: "admin"))

  return ZStack {
    Color(.systemGroupedBackground).ignoresSafeArea()
    VStack(spacing: 0) {
      ServiceInstanceRow(instance: radarr, status: .reachable(version: "5.14.0.9383"))
      Divider()
      ServiceInstanceRow(instance: sonarr, status: .unauthorized)
      Divider()
      ServiceInstanceRow(instance: nzbget, status: .unreachable(.serverUnreachable))
      Divider()
      ServiceInstanceRow(instance: radarr, status: nil)
    }
    .padding()
    .background(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(Color(.secondarySystemGroupedBackground))
    )
    .padding()
  }
}
