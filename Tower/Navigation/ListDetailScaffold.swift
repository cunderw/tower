import SwiftUI

/// The list/detail shell the Docker, VMs, Shares and Services tabs share: two
/// columns side by side in a regular width class, and a push-based
/// `NavigationStack` in a compact one.
///
/// **Why a size-class branch rather than `NavigationSplitView` alone.** A split
/// view does collapse to a stack on its own, but its collapsed form pushes the
/// detail column — including that column's own `NavigationStack` — onto the
/// sidebar's stack. Docker's detail pushes a second screen (the log viewer), so
/// the collapsed form would nest a stack inside a pushed view on iPhone, where
/// nothing today does. Branching keeps the compact path a plain push-based
/// stack and confines the split machinery to iPad.
///
/// **Selection lives in the caller**, as `@State` on the list view, not here:
/// this scaffold's `body` picks a different branch when the width class
/// changes, and state owned by a branch would die with it. The list view's own
/// identity is stable across that switch, so a selection made in one layout is
/// still there in the other, through rotation, Split View, and Stage Manager.
///
/// **The identifier rule is unaffected.** What crosses this is a `SelectionID`,
/// never an entity: `detail` receives the identifier and re-resolves the entity
/// from its store on every render, so a poll or a mutation still reaches the
/// detail column exactly as it reaches a pushed detail screen.
struct ListDetailScaffold<SelectionID: Hashable, Sidebar: View, Detail: View>: View {
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  /// Owned by the caller — see the note above on why it can't live here.
  @Binding var selection: SelectionID?
  /// What the detail column shows before anything is selected. Only ever
  /// rendered in the split layout; the compact one has no empty detail column.
  let placeholder: ListDetailPlaceholder
  /// The list column. The `Bool` is `isSplit`: rows push a `NavigationLink` in
  /// the compact layout and set `selection` in the split one, and only the row
  /// knows how to build itself either way.
  @ViewBuilder let sidebar: (_ isSplit: Bool) -> Sidebar
  /// Built from the identifier alone. Anything this view pushes
  /// declares its own `navigationDestination` here, which registers with
  /// whichever stack ends up hosting it — the detail column's in the split
  /// layout, the single stack's in the compact one.
  @ViewBuilder let detail: (SelectionID) -> Detail

  /// `.all` rather than `.automatic` so the list is visible in iPad portrait
  /// too, instead of collapsing behind a toggle on the iPad this layout is
  /// for. Still a `@State` binding, so hiding the column by hand works.
  @State private var columnVisibility: NavigationSplitViewVisibility = .all

  /// The compact stack's path.
  ///
  /// **`NavigationPath`, not `[SelectionID]`.**
  /// `NavigationStack(path: Binding<[SelectionID]>)` is *homogeneous*: it can
  /// only ever push a `SelectionID`. Every deeper screen these stacks host — a
  /// movie detail pushed from a Radarr library, Docker's log viewer — pushes a
  /// value of some other type, and those pushes are **silently dropped**.
  /// Anything a detail pushes registers its destination with whichever stack
  /// is hosting it, and a type-erased path can carry all of them.
  ///
  /// The compact layout tracks selection at all so the stack can be driven from
  /// outside — the cross-link opens a container from a service, and without
  /// this it would have no way to open anything on iPhone. Row taps still push
  /// themselves via `NavigationLink(value:)`; this only adds a way *in*.
  @State private var compactPath = NavigationPath()

  var body: some View {
    if horizontalSizeClass == .compact {
      NavigationStack(path: $compactPath) {
        sidebar(false)
          .navigationDestination(for: SelectionID.self) { id in
            detail(id)
          }
      }
      // Selection set from outside opens that screen, replacing whatever the
      // stack was showing.
      //
      // **`task(id:)`, not `onChange`.** A cross-link sets the *other* tab's
      // selection and then switches to it, and `TabView` builds a tab's content
      // lazily — so the change happens before this view exists and `onChange`
      // never fires for it. `task(id:)` also runs on first appearance with the
      // current value, which is exactly that case.
      .task(id: selection) {
        guard let selection else { return }
        compactPath = NavigationPath([selection])
      }
      // Popping back to the list clears the selection, so selecting the *same*
      // row again still pushes rather than looking like no change at all.
      .onChange(of: compactPath.isEmpty) { _, isEmpty in
        if isEmpty { selection = nil }
      }
    } else {
      NavigationSplitView(columnVisibility: $columnVisibility) {
        sidebar(true)
      } detail: {
        NavigationStack {
          if let selection {
            detail(selection)
          } else {
            ContentUnavailableView(
              placeholder.title,
              systemImage: placeholder.systemImage,
              description: Text(placeholder.description)
            )
            .accessibilityIdentifier(placeholder.identifier)
          }
        }
        // Resets the detail column's stack when the selection changes:
        // selecting another container while its log viewer is pushed should
        // land on the new container's detail, not leave the previous
        // container's logs on screen.
        .id(selection)
      }
      .navigationSplitViewStyle(.balanced)
    }
  }
}

/// The detail column's "nothing selected yet" copy. A struct rather than four
/// loose parameters so the four call sites can't get the order wrong.
struct ListDetailPlaceholder {
  let title: String
  let systemImage: String
  let description: String
  let identifier: String
}

extension View {
  /// Wraps a row for whichever layout it is in: a `NavigationLink` that pushes
  /// in the compact stack, or a plain, `tag`-ed row that drives the split
  /// view's selection.
  ///
  /// `.buttonStyle(.plain)` on the link half keeps a row's own styling. Its
  /// swipe actions, context menu, and confirmation dialogs live inside its
  /// body and are unaffected either way.
  @ViewBuilder
  func listDetailRow<SelectionID: Hashable>(id: SelectionID, isSplit: Bool) -> some View {
    if isSplit {
      self.tag(id)
    } else {
      NavigationLink(value: id) { self }
        .buttonStyle(.plain)
    }
  }
}
