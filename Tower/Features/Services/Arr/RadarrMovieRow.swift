import SwiftUI
import TowerCore

/// One row in the Radarr library: poster, title, year, availability, profile,
/// size, and monitored state.
struct RadarrMovieRow: View {
  let movie: RadarrMovie
  let qualityProfile: String?

  var body: some View {
    DashboardRow(showsChevron: false) {
      MediaPoster(url: movie.posterURL, fallbackSystemImage: "film")

      VStack(alignment: .leading, spacing: 3) {
        Text(movie.title)
          .font(.body)
          .lineLimit(2)

        HStack(spacing: 6) {
          AvailabilityBadge(state: movie.libraryState)
          if let year = movie.year {
            Text(String(year))
          }
          if let qualityProfile {
            Text("·")
            Text(qualityProfile)
          }
        }
        .font(.caption)
        .foregroundStyle(.secondary)

        HStack(spacing: 6) {
          if movie.sizeOnDiskBytes > 0 {
            Text(Formatters.bytes(movie.sizeOnDiskBytes))
          }
          if !movie.isMonitored {
            if movie.sizeOnDiskBytes > 0 { Text("·") }
            // Words, not just a dimmed glyph: colour is never the only signal.
            Text("Unmonitored")
          }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
      }

      Spacer(minLength: 4)
    }
    // One VoiceOver stop per row, carrying every fact the row shows.
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilityLabel)
    .accessibilityIdentifier("radarr.row.\(movie.id)")
  }

  private var accessibilityLabel: String {
    var parts = [movie.title]
    if let year = movie.year { parts.append(String(year)) }
    parts.append(movie.libraryState.displayName)
    if let qualityProfile { parts.append(qualityProfile) }
    if movie.sizeOnDiskBytes > 0 { parts.append(Formatters.bytes(movie.sizeOnDiskBytes)) }
    if !movie.isMonitored { parts.append("Unmonitored") }
    return parts.joined(separator: ", ")
  }
}

/// Downloaded / Missing / Unreleased, as a coloured pill *and* a word — the
/// three states a user acts on differently, and colour is never the only signal
/// that tells them apart.
struct AvailabilityBadge: View {
  let state: RadarrMovie.LibraryState

  var body: some View {
    Text(state.displayName)
      .font(.caption2.weight(.medium))
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(color.opacity(0.15), in: Capsule())
      .foregroundStyle(color)
  }

  private var color: Color {
    switch state {
    case .downloaded: .green
    case .missing: .orange
    case .unreleased: .secondary
    }
  }
}

/// A poster thumbnail with a glyph placeholder.
///
/// `AsyncImage` sends no API key, which is why the URLs mapped into the domain
/// are the absolute `remoteUrl` of the metadata source's artwork rather than
/// the service-relative one — a poster that silently fails to load is worse
/// than one that never tries.
struct MediaPoster: View {
  let url: URL?
  let fallbackSystemImage: String
  var width: CGFloat = 46

  var body: some View {
    AsyncImage(url: url) { image in
      image.resizable().aspectRatio(contentMode: .fill)
    } placeholder: {
      ZStack {
        Rectangle().fill(.quaternary)
        Image(systemName: fallbackSystemImage)
          .foregroundStyle(.secondary)
      }
    }
    .frame(width: width, height: width * 1.5)
    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    .accessibilityHidden(true)
  }
}
