import TowerCore

/// `Share` is genuinely ambiguous inside any test file that imports both
/// `TowerCore` and `TowerAPITestMocks`: Apollo generates a top-level mock class
/// named `Share` for the GraphQL type of the same name, and the domain model is
/// also `Share`.
///
/// `TowerCore.Share` does **not** disambiguate it, because `TowerCore` is also
/// the name of an enum *inside* that module, so the compiler resolves the prefix
/// to the enum and reports "'Share' is not a member type of enum
/// 'TowerCore.TowerCore'". This file imports only `TowerCore`, so the name
/// resolves cleanly here and the alias is usable from the files where it does
/// not.
///
/// Only `Share` needs this today — `Container`, `VMDomain`, and the rest have no
/// same-named generated mock.
typealias DomainShare = Share
