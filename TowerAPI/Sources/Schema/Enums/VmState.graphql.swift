// @generated
// This file was automatically generated and should not be edited.

@_spi(Internal) import ApolloAPI

/// The state of a virtual machine
nonisolated public enum VmState: String, EnumType {
  case nostate = "NOSTATE"
  case running = "RUNNING"
  case idle = "IDLE"
  case paused = "PAUSED"
  case shutdown = "SHUTDOWN"
  case shutoff = "SHUTOFF"
  case crashed = "CRASHED"
  case pmsuspended = "PMSUSPENDED"
}
