import Dispatch
import Foundation

private final class AppshotBackgroundOperationBox<Value>: @unchecked Sendable {
    let operation: () throws -> Value

    init(operation: @escaping () throws -> Value) {
        self.operation = operation
    }
}

private final class AppshotBackgroundResultBox<Value>: @unchecked Sendable {
    private enum State {
        case pending
        case completed(Result<Value, Error>)
    }

    private let condition = NSCondition()
    private var state = State.pending

    func complete(with result: Result<Value, Error>) {
        condition.lock()
        state = .completed(result)
        condition.broadcast()
        condition.unlock()
    }

    func wait() throws -> Value {
        condition.lock()
        defer { condition.unlock() }
        while case .pending = state {
            condition.wait()
        }
        guard case let .completed(result) = state else {
            preconditionFailure("background work left the pending state without a result")
        }
        return try result.get()
    }
}

public final class AppshotBackgroundWork<Value>: @unchecked Sendable {
    private let resultBox: AppshotBackgroundResultBox<Value>

    public init(
        queue: DispatchQueue = .global(qos: .userInitiated),
        operation: @escaping () throws -> Value
    ) {
        let resultBox = AppshotBackgroundResultBox<Value>()
        let operationBox = AppshotBackgroundOperationBox(operation: operation)
        self.resultBox = resultBox
        queue.async {
            resultBox.complete(with: Result {
                try operationBox.operation()
            })
        }
    }

    public func wait() throws -> Value {
        try resultBox.wait()
    }
}
