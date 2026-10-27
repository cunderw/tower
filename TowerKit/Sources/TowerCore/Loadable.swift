public enum Loadable<Value: Sendable>: Sendable {
  case idle
  case loading
  case loaded(Value)
  case failed(AppError)
  /// A mutation failed but previously loaded data is still valid — show the
  /// data and surface the error transiently.
  case actionFailed(Value, AppError)

  public var value: Value? {
    switch self {
    case .loaded(let value), .actionFailed(let value, _): value
    case .idle, .loading, .failed: nil
    }
  }

  public var error: AppError? {
    switch self {
    case .failed(let error), .actionFailed(_, let error): error
    case .idle, .loading, .loaded: nil
    }
  }

  public var isLoading: Bool {
    if case .loading = self { return true }
    return false
  }
}

extension Loadable: Equatable where Value: Equatable {}
