import Foundation
import SwiftUI

/// The five top-level destinations. `CaseIterable` order is tab-bar order.
///
/// `services` is last on purpose: the four Unraid tabs are what a user opens
/// the app for, and inserting another tab among them would move every one of
/// them under the reader's thumb.
enum TowerTab: String, Hashable, CaseIterable, Identifiable {
  case dashboard, docker, vms, shares, services

  var id: String { rawValue }

  var title: String {
    switch self {
    case .dashboard: "Dashboard"
    case .docker: "Docker"
    case .vms: "VMs"
    case .shares: "Shares"
    case .services: "Services"
    }
  }

  var systemImage: String {
    switch self {
    case .dashboard: "square.grid.2x2"
    case .docker: "shippingbox"
    case .vms: "desktopcomputer"
    case .shares: "folder"
    case .services: "square.stack.3d.up"
    }
  }
}

/// What the shell's `TabView` selection can point at.
///
/// Not just `TowerTab` because the iPad sidebar lists each configured service
/// instance as its own tab (`TabSection`), and a `TabView` with a selection
/// binding needs one type that can name every selectable destination. The four
/// Unraid tabs and the Services hub are `.tab`; each instance in the sidebar is
/// `.service`.
enum TowerDestination: Hashable {
  case tab(TowerTab)
  case service(UUID)
}
