// @generated
// This file was automatically generated and can be edited to
// implement advanced custom scalar functionality.
//
// Any changes to this file will not be overwritten by future
// code generation execution.

@_spi(Internal) @_spi(Execution) import ApolloAPI

/// ### Description:
///
/// ID scalar type that prefixes the underlying ID with the server identifier on output and strips it on input.
///
/// We use this scalar type to ensure that the ID is unique across all servers,
/// allowing the same underlying resource ID to be used across different server instances.
///
/// #### Input Behavior:
///
/// When providing an ID as input (e.g., in arguments or input objects), the server
/// identifier prefix ('<serverId>:') is optional.
///
/// - If the prefix is present (e.g., '123:456'), it will be automatically stripped,
/// and only the underlying ID ('456') will be used internally.
/// - If the prefix is absent (e.g., '456'), the ID will be used as-is.
///
/// This makes it flexible for clients, as they don't strictly need to know or provide the server ID.
///
/// #### Output Behavior:
///
/// When an ID is returned in the response (output), it will *always* be prefixed
/// with the current server's unique identifier (e.g., '123:456').
///
/// #### Example:
///
/// Note: The server identifier is '123' in this example.
///
/// ##### Input (Prefix Optional):
/// ```graphql
/// # Both of these are valid inputs resolving to internal ID '456'
/// {
///   someQuery(id: "123:456") { ... }
///   anotherQuery(id: "456") { ... }
/// }
/// ```
///
/// ##### Output (Prefix Always Added):
/// ```graphql
/// # Assuming internal ID is '456'
/// {
///   "data": {
///     "someResource": {
///       "id": "123:456" 
///     }
///   }
/// }
/// ```
///
/// **Stays `String`.** It is an opaque `<serverId>:<id>` pair that nothing computes on;
/// a wrapper struct would add an unwrapping accessor at every mapping site and buy
/// no safety, since `String` cannot fail to decode. Models that want the human-readable half
/// derive it themselves — see `VMDomain.displayName` and `Share.displayName`.
public typealias PrefixedID = String
