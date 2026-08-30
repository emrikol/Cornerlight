import AppKit
@testable import Cornerlight
import Testing

struct LauncherPresentationUserStoryTests {
    @Test @MainActor
    func `repeated open requests reuse the visible launcher`() {
        var created: [PresenterSpy] = []
        let coordinator = LauncherPresentationCoordinator {
            let presenter = PresenterSpy()
            created.append(presenter)
            return presenter
        }

        coordinator.showLauncher()
        coordinator.showLauncher()

        #expect(created.count == 1)
        #expect(created.first?.showCount == 1)
        #expect(coordinator.hasLauncher)
        #expect(coordinator.isLauncherPresented)
    }

    @Test @MainActor
    func `the hot corner toggles the retained launcher`() {
        var created: [PresenterSpy] = []
        var events: [String] = []
        let coordinator = LauncherPresentationCoordinator {
            let presenter = PresenterSpy { events.append($0) }
            created.append(presenter)
            return presenter
        }

        coordinator.toggleLauncher()
        #expect(created.count == 1)
        #expect(created[0].toggleCount == 1)
        #expect(coordinator.hasLauncher)
        #expect(events == ["spotlight.launchAppsBrowsing"])

        coordinator.toggleLauncher()
        #expect(created[0].toggleCount == 2)
        #expect(created.count == 1)
        #expect(coordinator.hasLauncher)
        #expect(!coordinator.isLauncherPresented)
        #expect(events == ["spotlight.launchAppsBrowsing", "spotlight.launchAppsBrowsing"])

        coordinator.toggleLauncher()
        #expect(created.count == 1)
        #expect(created[0].toggleCount == 3)
        #expect(coordinator.isLauncherPresented)
        #expect(events == [
            "spotlight.launchAppsBrowsing",
            "spotlight.launchAppsBrowsing",
            "spotlight.launchAppsBrowsing",
        ])
    }

    @Test @MainActor
    func `closing retains Spotlights controller and can open it again`() {
        var creationCount = 0
        let coordinator = LauncherPresentationCoordinator {
            creationCount += 1
            return PresenterSpy()
        }
        coordinator.showLauncher()

        coordinator.dismissLauncher()

        #expect(coordinator.hasLauncher)
        #expect(!coordinator.isLauncherPresented)

        coordinator.showLauncher()

        #expect(creationCount == 1)
        #expect(coordinator.hasLauncher)
        #expect(coordinator.isLauncherPresented)
    }

    @Test
    func `a completed dismissal cannot clear content prepared for a queued reopen`() {
        var contentLease = LauncherContentLease()
        contentLease.prepare()

        let releasedDuringReopen = contentLease.finishDismissal(
            retainsForQueuedPresentation: true,
        )
        #expect(!releasedDuringReopen)
        #expect(contentLease.isLoaded)

        let releasedAfterFinalDismissal = contentLease.finishDismissal(
            retainsForQueuedPresentation: false,
        )
        #expect(releasedAfterFinalDismissal)
        #expect(!contentLease.isLoaded)
    }

    @Test @MainActor
    func `application focus loss reaches the visible launcher`() {
        let presenter = PresenterSpy()
        let coordinator = LauncherPresentationCoordinator { presenter }
        coordinator.showLauncher()

        coordinator.applicationLostFocus()

        #expect(presenter.lostFocusCount == 1)
    }

    @Test @MainActor
    func `application focus loss reaches the launcher until native dismissal is confirmed`() {
        let presenter = PresenterSpy()
        let coordinator = LauncherPresentationCoordinator { presenter }
        coordinator.showLauncher()
        presenter.reportNativeVisibility(false)

        coordinator.applicationLostFocus()

        #expect(presenter.lostFocusCount == 1)
    }

    @Test @MainActor
    func `window server dismissal completion waits for Spotlights native close`() {
        let presenter = PresenterSpy()
        let coordinator = LauncherPresentationCoordinator { presenter }
        var completionCount = 0
        coordinator.showLauncher()

        coordinator.dismissLauncher(reason: 18) {
            completionCount += 1
        }

        #expect(presenter.reasonedDismissCount == 1)
        #expect(presenter.lastDismissReason == 18)
        #expect(completionCount == 0)

        presenter.completeReasonedDismissal()

        #expect(completionCount == 1)
        #expect(coordinator.hasLauncher)
        #expect(!coordinator.isLauncherPresented)
    }

    @MainActor
    private final class PresenterSpy: LauncherPresenting {
        private(set) var isPresented = false
        private(set) var showCount = 0
        private(set) var toggleCount = 0
        private(set) var dismissCount = 0
        private(set) var reasonedDismissCount = 0
        private(set) var lastDismissReason: Int?
        private(set) var lostFocusCount = 0
        private var reasonedDismissCompletion: (() -> Void)?
        private let record: (String) -> Void

        init(record: @escaping (String) -> Void = { _ in }) {
            self.record = record
        }

        func show() {
            isPresented = true
            showCount += 1
            record("launcher.show")
        }

        func toggle() {
            isPresented.toggle()
            toggleCount += 1
            record("spotlight.launchAppsBrowsing")
        }

        func applicationLostFocus() {
            lostFocusCount += 1
        }

        func dismiss() {
            isPresented = false
            dismissCount += 1
            record("launcher.dismiss")
        }

        func dismiss(reason: Int, completion: (() -> Void)?) {
            reasonedDismissCount += 1
            lastDismissReason = reason
            reasonedDismissCompletion = completion
        }

        func completeReasonedDismissal() {
            isPresented = false
            let completion = reasonedDismissCompletion
            reasonedDismissCompletion = nil
            completion?()
        }

        func reportNativeVisibility(_ isPresented: Bool) {
            self.isPresented = isPresented
        }
    }
}
