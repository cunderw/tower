// @generated
// This file was automatically generated and can be edited to
// implement advanced custom scalar functionality.
//
// Any changes to this file will not be overwritten by future
// code generation execution.

@_spi(Internal) @_spi(Execution) import ApolloAPI

/// A field whose value is a valid TCP port within the range of 0 to 65535:
/// https://en.wikipedia.org/wiki/Transmission_Control_Protocol#TCP_ports
///
/// **Deliberately left as `String`**, despite the range promise above. A throwing scalar
/// initializer fails the whole query, so `Port = Int` would let one container publishing an
/// unreadable port take out the entire Docker list. `ContainerPort.init(from:)` converts with
/// `Int.init` at the repository boundary instead, degrading to `nil` — and
/// `ContainerPort.summary` already renders every combination of missing halves.
public typealias Port = String
