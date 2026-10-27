// @generated
// This file was automatically generated and can be edited to
// implement advanced custom scalar functionality.
//
// Any changes to this file will not be overwritten by future
// code generation execution.

@_spi(Internal) @_spi(Execution) import ApolloAPI

/// A date-time string at UTC, such as 2019-12-03T09:54:33Z, compliant with the date-time format.
///
/// **Deliberately left as `String`.** A `CustomScalarType` initializer that throws fails the
/// *entire* query, not one field: `DockerContainerLogs.lines[].timestamp` is a non-null
/// `DateTime`, and mapping this to `Date` would mean one malformed timestamp in a 400-line
/// tail shows the user no log at all. `ContainerLogLine` documents the opposite rule — the
/// message is the payload, the timestamp is decoration — and `Formatters.parseTimestamp`
/// implements it by degrading to `nil` at the repository boundary, where a bad value costs
/// one field.
///
/// `info.os.uptime` is also a `DateTime`, and is a boot *timestamp* rather than an uptime, which
/// is its own argument for keeping the raw value reachable.
public typealias DateTime = String
