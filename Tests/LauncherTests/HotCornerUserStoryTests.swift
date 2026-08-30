import AppKit
@testable import Cornerlight
import Testing

struct HotCornerUserStoryTests {
    @Test
    func `settings offers only corners not assigned by macOS`() {
        let available = LauncherHotCornerAvailability.availableCorners(
            systemActions: [
                .topLeft: 0,
                .topRight: 1,
                .bottomLeft: 11,
                .bottomRight: 4,
            ],
        )

        #expect(available == [.topLeft, .topRight])
    }

    @Test
    func `a persisted corner survives relaunch and falls back if macOS claims it`() throws {
        let suiteName = "LauncherTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = LauncherHotCornerStore(defaults: defaults)
        store.selectedCorner = .topRight
        #expect(LauncherHotCornerStore(defaults: defaults).selectedCorner == .topRight)

        #expect(
            LauncherHotCornerAvailability.effectiveCorner(
                preferred: .topRight,
                available: [.topLeft, .bottomRight],
            ) == .topLeft,
        )
        #expect(
            LauncherHotCornerAvailability.effectiveCorner(
                preferred: .topRight,
                available: [],
            ) == nil,
        )
    }

    @Test
    func `entering the hot corner invokes once until the pointer exits`() {
        var gate = HotCornerEntryGate()

        let firstEntry = gate.consume(eventType: HotCornerEntryGate.enteredEventType)
        let repeatedEntry = gate.consume(eventType: HotCornerEntryGate.enteredEventType)
        let exit = gate.consume(eventType: HotCornerEntryGate.exitedEventType)
        let secondEntry = gate.consume(eventType: HotCornerEntryGate.enteredEventType)

        #expect(firstEntry)
        #expect(!repeatedEntry)
        #expect(!exit)
        #expect(secondEntry)
    }

    @Test
    func `unrelated WindowServer events do not disarm the corner`() {
        var gate = HotCornerEntryGate()

        let unrelatedEvent = gate.consume(eventType: 1)
        #expect(!unrelatedEvent)
        #expect(gate.isArmed)
        let entry = gate.consume(eventType: HotCornerEntryGate.enteredEventType)
        #expect(entry)
    }

    @Test
    func `rebuilding the corner preserves whether the pointer is already inside`() {
        var gate = HotCornerEntryGate()

        gate.rebuild(pointerIsInside: true)
        #expect(!gate.isArmed)
        let repeatedEntry = gate.consume(eventType: HotCornerEntryGate.enteredEventType)
        #expect(!repeatedEntry)

        gate.rebuild(pointerIsInside: false)
        #expect(gate.isArmed)
    }

    @Test
    func `an exit event only rearms after the pointer really leaves the region`() {
        var gate = HotCornerEntryGate()
        _ = gate.consume(eventType: HotCornerEntryGate.enteredEventType)

        _ = gate.consume(
            eventType: HotCornerEntryGate.exitedEventType,
            pointerIsInside: true,
        )
        #expect(!gate.isArmed)

        _ = gate.consume(
            eventType: HotCornerEntryGate.exitedEventType,
            pointerIsInside: false,
        )
        #expect(gate.isArmed)
    }

    @Test
    func `locked sessions and pressed mouse buttons suppress invocation`() {
        #expect(!HotCornerInvocationPolicy.shouldInvoke(screenLocked: true, mouseButtonPressed: false))
        #expect(!HotCornerInvocationPolicy.shouldInvoke(screenLocked: false, mouseButtonPressed: true))
        #expect(HotCornerInvocationPolicy.shouldInvoke(screenLocked: false, mouseButtonPressed: false))
    }
}
