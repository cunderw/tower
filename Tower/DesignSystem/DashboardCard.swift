import SwiftUI

/// The card chrome every dashboard section is built from. Reads as a
/// standard grouped-list section — 16pt continuous corners, the secondary
/// grouped background, no shadow, no border — so the dashboard looks like a
/// system screen rather than a custom one.
struct DashboardCard<Content: View, Accessory: View>: View {
  let title: String
  let systemImage: String?
  @ViewBuilder let content: () -> Content
  @ViewBuilder let accessory: () -> Accessory

  // At accessibility text sizes, a title and a trailing accessory (a status
  // pill, a chevron) sharing one `HStack` compete for width — observed on
  // `ArrayHeroCard` as the title wrapping mid-word ("Ar-ray") at AX5. Every
  // card built on this type shares an accessory, so the fix belongs here
  // once rather than in each card: stack vertically once the size crosses
  // into the accessibility range, same mechanism `ArrayHeroCard`'s
  // `capacitySection` already uses for its ring/details layout.
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  init(
    _ title: String,
    systemImage: String? = nil,
    @ViewBuilder content: @escaping () -> Content,
    @ViewBuilder accessory: @escaping () -> Accessory
  ) {
    self.title = title
    self.systemImage = systemImage
    self.content = content
    self.accessory = accessory
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      headerRow
      content()
    }
    .padding(16)
    .background(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(Color(.secondarySystemGroupedBackground))
    )
  }

  @ViewBuilder
  private var headerRow: some View {
    if dynamicTypeSize.isAccessibilitySize {
      VStack(alignment: .leading, spacing: 8) {
        header
        accessory()
      }
    } else {
      HStack {
        header
        Spacer()
        accessory()
      }
    }
  }

  @ViewBuilder
  private var header: some View {
    if let systemImage {
      Label(title, systemImage: systemImage)
        .font(.headline)
        .foregroundStyle(.secondary)
    } else {
      Text(title)
        .font(.headline)
        .foregroundStyle(.secondary)
    }
  }
}

extension DashboardCard where Accessory == EmptyView {
  init(
    _ title: String,
    systemImage: String? = nil,
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.init(title, systemImage: systemImage, content: content, accessory: { EmptyView() })
  }
}

#Preview {
  ZStack {
    Color(.systemGroupedBackground).ignoresSafeArea()
    ScrollView {
      DashboardCard("Array", systemImage: "externaldrive.fill") {
        LabeledContent("State", value: "Started")
        LabeledContent("Free", value: "42.1 TB")
      }
      .padding()
    }
  }
}
