import AppKit
@testable import Cornerlight
import Testing

struct LauncherFocusUserStoryTests {
    private final class NotificationProbe: NSObject {
        private(set) var deliveryCount = 0

        @objc func receive(_: Notification) {
            deliveryCount += 1
        }
    }

    @Test @MainActor
    func `spotlights application class owns the complete focus lifecycle`() throws {
        #expect(SpotlightExecutableRuntime.isLoaded)
        let applicationClass: AnyClass = try #require(NSClassFromString("SPApplication"))
        #expect(class_getSuperclass(applicationClass) == NSApplication.self)

        for selectorName in [
            "_stealKeyFocusWithOptions:",
            "_releaseKeyFocus",
            "sendEvent:",
        ] {
            let selector = NSSelectorFromString(selectorName)
            let nativeMethod = try #require(class_getInstanceMethod(applicationClass, selector))
            let appKitMethod = try #require(class_getInstanceMethod(NSApplication.self, selector))
            #expect(method_getImplementation(nativeMethod) != method_getImplementation(appKitMethod))
        }
    }

    @Test
    func `the hot corner owner opts out of automatic process termination`() {
        var reasons: [String] = []

        LauncherProcessLifetimePolicy.makeResident { reasons.append($0) }

        #expect(reasons == ["Cornerlight owns the Hot Corner event source"])
    }

    @Test
    func `stock spotlight toggles cannot invoke the hosted native menu item`() {
        let center = NotificationCenter()
        let probe = NotificationProbe()
        center.addObserver(
            probe,
            selector: #selector(NotificationProbe.receive(_:)),
            name: SpotlightSystemToggleIsolation.notificationName,
            object: nil,
        )

        SpotlightSystemToggleIsolation.removeNativeToggleObserver(probe, from: center)
        center.post(name: SpotlightSystemToggleIsolation.notificationName, object: nil)

        #expect(probe.deliveryCount == 0)
    }

    @Test
    func `system spotlight preemption drains every native focus claim before deactivating`() {
        var remainingClaims = 3
        var deactivateCount = 0

        let releaseCount = SpotlightNativeFocusReleaseDrain.perform(
            release: {
                guard remainingClaims > 0 else { return false }
                remainingClaims -= 1
                return true
            },
            deactivate: {
                deactivateCount += 1
            },
        )

        #expect(releaseCount == 3)
        #expect(remainingClaims == 0)
        #expect(deactivateCount == 1)
    }

    @Test
    func `system spotlight preemption does not deactivate without a native focus claim`() {
        var deactivateCount = 0

        let releaseCount = SpotlightNativeFocusReleaseDrain.perform(
            release: { false },
            deactivate: { deactivateCount += 1 },
        )

        #expect(releaseCount == 0)
        #expect(deactivateCount == 0)
    }
}
