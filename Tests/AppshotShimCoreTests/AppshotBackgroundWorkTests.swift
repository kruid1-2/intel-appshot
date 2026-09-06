import Dispatch
import Testing
@testable import AppshotShimCore

@Test("background work starts immediately and returns its result when joined")
func backgroundWorkStartsBeforeJoin() throws {
    let started = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    let work = AppshotBackgroundWork<Int> {
        started.signal()
        _ = release.wait(timeout: .now() + 1)
        return 42
    }

    #expect(started.wait(timeout: .now() + 1) == .success)
    release.signal()

    #expect(try work.wait() == 42)
}

@Test("background work preserves operation failures")
func backgroundWorkPreservesFailure() {
    enum ExpectedFailure: Error {
        case failed
    }
    let work = AppshotBackgroundWork<Int> {
        throw ExpectedFailure.failed
    }

    #expect(throws: ExpectedFailure.self) {
        _ = try work.wait()
    }
}
