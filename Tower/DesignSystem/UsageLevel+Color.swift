import SwiftUI
import TowerCore

extension Color {
  /// The single place a `UsageLevel` becomes a colour. Semantic colours only —
  /// `.accentColor` follows the system accent (no custom `AccentColor` asset
  /// is defined), which is the whole point.
  ///
  /// Not `.tint`: `Color` has no static `tint` member — only
  /// `ShapeStyle.tint`, which returns the opaque `TintShapeStyle`, not a
  /// `Color`, so it does not satisfy this initializer's `Color` return type
  /// (`.tint` here fails to type-check with "member 'tint' expects argument
  /// of type 'Color'"). `.accentColor` is the `Color`-typed equivalent: still
  /// semantic, still un-hardcoded, and still the system default absent a
  /// custom `AccentColor` asset.
  ///
  /// Trade-off worth knowing: `.accentColor` is fixed to the app-wide
  /// accent and does **not** pick up an ancestor `.tint(_:)` modifier the
  /// way `ShapeStyle.tint` does, because it isn't environment-aware the
  /// way a `ShapeStyle` resolved at draw time is. Use `.usage(_:)` below
  /// wherever a `some ShapeStyle` is accepted in a *direct-paint* context
  /// (`Shape.stroke(_:)`, `.foregroundStyle(_:)`) — but **use this
  /// initializer, never `.usage(_:)`, as the argument to the `.tint(_:)`
  /// view modifier itself.** `.tint(_:)` *sets* the environment's tint for
  /// a subtree; `.usage(.normal)` resolves to `AnyShapeStyle(.tint)`, i.e.
  /// "whatever the ambient tint already is", so passing it to `.tint(_:)`
  /// installs the ambient tint as its own new value. SwiftUI resolves that
  /// lazily, so it compiles fine and then crashes the instant the view
  /// lays out: `TintShapeStyle._apply(to:)` recurses into itself forever,
  /// and the process dies with `EXC_BAD_ACCESS` ("Thread stack size
  /// exceeded due to excessive recursion") — reproduced via `MetricGauge`,
  /// at default Dynamic Type size, not merely at accessibility sizes. This
  /// initializer's `Color` is a concrete value with nothing left to
  /// resolve, so it can't recurse; that's why `MetricGauge.tint(_:)` uses
  /// it instead of `.usage(_:)`.
  init(usageLevel level: UsageLevel) {
    self = switch level {
    case .normal: .accentColor
    case .warning: .orange
    case .critical: .red
    case .unknown: .secondary
    }
  }
}

extension ShapeStyle where Self == AnyShapeStyle {
  /// Hierarchy-aware counterpart to `Color(usageLevel:)`. `ShapeStyle.tint`
  /// (unlike `Color.accentColor`) picks up an ancestor's `.tint(_:)`
  /// modifier rather than always resolving to the app-wide accent, so this
  /// is the right choice in *direct-paint* contexts such as
  /// `Shape.stroke(_:style:)` or `.foregroundStyle(_:)`, which read the
  /// current resolved tint rather than redefining it for descendants.
  ///
  /// **Never pass this to the `.tint(_:)` view modifier.** That modifier
  /// sets the environment's tint for a subtree, and `.usage(.normal)` is
  /// `AnyShapeStyle(.tint)` — "whatever the ambient tint already is" —
  /// so using it there makes the tint circularly refer to itself.
  /// Confirmed by crash: `TintShapeStyle._apply(to:)` recurses forever and
  /// the app dies with a stack-overflow `EXC_BAD_ACCESS`, reproducibly, at
  /// default Dynamic Type size. Use `Color(usageLevel:)` for `.tint(_:)`
  /// instead (see `MetricGauge`) — see its doc comment for the full story.
  static func usage(_ level: UsageLevel) -> AnyShapeStyle {
    switch level {
    case .normal: AnyShapeStyle(.tint)
    case .warning: AnyShapeStyle(.orange)
    case .critical: AnyShapeStyle(.red)
    case .unknown: AnyShapeStyle(.secondary)
    }
  }
}
