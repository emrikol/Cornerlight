@testable import Cornerlight
import Testing

struct SpotlightResultsPresentationPrimingTests {
    @Test
    func `macOS 27 primes its results host exactly once`() {
        var state = SpotlightResultsPresentationPrimingState()

        let firstAttempt = state.beginIfNeeded(
            isRequired: true,
            supportsNativeTransition: true,
        )
        let secondAttempt = state.beginIfNeeded(
            isRequired: true,
            supportsNativeTransition: true,
        )

        #expect(firstAttempt)
        #expect(state.hasPrimed)
        #expect(!secondAttempt)
    }

    @Test
    func `older Spotlight does not use the macOS 27 transition`() {
        var state = SpotlightResultsPresentationPrimingState()

        let attempt = state.beginIfNeeded(
            isRequired: false,
            supportsNativeTransition: true,
        )

        #expect(!attempt)
        #expect(!state.hasPrimed)
    }

    @Test
    func `an unavailable native transition is never claimed`() {
        var state = SpotlightResultsPresentationPrimingState()

        let attempt = state.beginIfNeeded(
            isRequired: true,
            supportsNativeTransition: false,
        )

        #expect(!attempt)
        #expect(!state.hasPrimed)
    }
}
