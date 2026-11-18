import Foundation

/// The operation did not finish within its deadline.
enum DeadlineError: Error, Equatable {
    case exceeded
}

/// Runs `operation` and throws `DeadlineError.exceeded` if it takes longer than `duration`.
///
/// When the deadline passes, the operation is cancelled. Cancelling the caller still
/// cancels the operation and throws `CancellationError`, as usual. Use this for work
/// that may never finish, such as a MapKit request that never calls back.
@MainActor
func withDeadline<Value>(
    _ duration: Duration,
    operation: @escaping @MainActor () async throws -> Value
) async throws -> Value {
    try await withThrowingTaskGroup(of: Value?.self) { group in
        // Cancel the loser when we return, so an operation that is still running
        // does not hold the caller until it finishes.
        defer { group.cancelAll() }
        group.addTask { @MainActor in try await operation() }
        group.addTask { @MainActor in
            try await Task.sleep(for: duration)
            return nil
        }
        // The first child to finish decides: a value, or nil when the timer won.
        guard let first = try await group.next(), let value = first else {
            throw DeadlineError.exceeded
        }
        return value
    }
}
