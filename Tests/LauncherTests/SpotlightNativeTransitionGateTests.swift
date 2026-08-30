@testable import Cornerlight
import Testing

struct SpotlightNativeTransitionGateTests {
    @Test
    func `a toggle waits for the active native transition to finish`() throws {
        var gate = SpotlightNativeTransitionGate()
        let firstToken = try startToken(from: gate.requestToggle())

        #expect(gate.requestToggle() == .queued)
        let secondToken = try queuedToken(from: gate.complete(firstToken))
        #expect(gate.isCurrent(secondToken))
        #expect(gate.complete(secondToken) == .idle)
    }

    @Test
    func `two queued toggles cancel by parity`() throws {
        var gate = SpotlightNativeTransitionGate()
        let token = try startToken(from: gate.requestToggle())

        #expect(gate.requestToggle() == .queued)
        #expect(gate.requestToggle() == .queued)

        #expect(gate.complete(token) == .idle)
    }

    @Test
    func `dismissal supersedes an opening transition and ignores its stale completion`() throws {
        var gate = SpotlightNativeTransitionGate()
        let openingToken = try startToken(from: gate.requestToggle())
        let dismissalToken = gate.supersedeWithDismissal()

        #expect(gate.complete(openingToken) == .stale)
        #expect(gate.isCurrent(dismissalToken))
        #expect(gate.complete(dismissalToken) == .idle)
    }

    @Test
    func `a toggle during dismissal starts only after dismissal completion`() throws {
        var gate = SpotlightNativeTransitionGate()
        let dismissalToken = gate.supersedeWithDismissal()

        #expect(gate.hasActiveTransition)
        #expect(gate.requestToggle() == .queued)
        let toggleToken = try queuedToken(from: gate.complete(dismissalToken))
        #expect(gate.isCurrent(toggleToken))
    }

    @Test
    func `click outside dismissal becomes idle only after native lifecycle completion`() {
        var gate = SpotlightNativeTransitionGate()
        let dismissalToken = gate.supersedeWithDismissal()

        #expect(gate.hasActiveTransition)
        #expect(gate.complete(dismissalToken) == .idle)
        #expect(!gate.hasActiveTransition)
    }

    @Test
    func `launching an app completes the native invocation lifecycle lease`() {
        var lease = SpotlightNativeLifecycleLease()
        lease.begin(42)

        #expect(lease.takeDismissalToken() == 42)
        #expect(lease.takeDismissalToken() == nil)
    }

    @Test
    func `a stale completion cannot clear a replacement lifecycle lease`() {
        var lease = SpotlightNativeLifecycleLease()
        lease.begin(1)
        lease.begin(2)

        lease.completeNativeInvocation(1)

        #expect(lease.token == 2)
    }

    private func startToken(
        from request: SpotlightNativeTransitionGate.ToggleRequest,
    ) throws -> SpotlightNativeTransitionGate.Token {
        guard case let .start(token) = request else {
            Issue.record("Expected a native transition to start")
            throw GateTestError.unexpectedState
        }
        return token
    }

    private func queuedToken(
        from completion: SpotlightNativeTransitionGate.Completion,
    ) throws -> SpotlightNativeTransitionGate.Token {
        guard case let .startQueuedToggle(token) = completion else {
            Issue.record("Expected a queued toggle to start")
            throw GateTestError.unexpectedState
        }
        return token
    }

    private enum GateTestError: Error {
        case unexpectedState
    }
}
