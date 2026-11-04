#include "SpotlightBridge.h"

#include <dlfcn.h>
#include <string.h>
#include <stddef.h>
#include <sys/sysctl.h>

typedef void __attribute__((swiftcall)) (*SwiftInstanceMethod)(
    void *self __attribute__((swift_context))
);

typedef void __attribute__((swiftcall)) (*SwiftScreenInstanceMethod)(
    void *screen,
    void *self __attribute__((swift_context))
);

typedef void __attribute__((swiftcall)) (*SwiftOptionalCompletionInstanceMethod)(
    void *completion,
    void *completionContext,
    void *self __attribute__((swift_context))
);

typedef struct __attribute__((aligned(8))) {
    unsigned char storage[232];
} ResultPlatterBehavior;

_Static_assert(sizeof(ResultPlatterBehavior) == 232, "unexpected platter behavior layout");

typedef ResultPlatterBehavior __attribute__((swiftcall)) (*SwiftBehaviorGetter)(void);
typedef bool __attribute__((swiftcall)) (*SwiftBoolGetter)(void);

typedef void __attribute__((swiftcall)) (*SwiftWindowSizeInvalidator)(
    ResultPlatterBehavior behavior,
    bool animated,
    bool immediately,
    void *completion,
    void *completionContext,
    void *self __attribute__((swift_context))
);

bool CornerlightSpotlightBootstrap(void *windowManager) {
    static SwiftInstanceMethod bootstrap;
    if (bootstrap == NULL) {
        bootstrap = (SwiftInstanceMethod)dlsym(
            RTLD_DEFAULT,
            "$s19SpotlightUIInternal13WindowManagerC9bootstrapyyFTj"
        );
    }
    if (bootstrap == NULL || windowManager == NULL) {
        return false;
    }
    bootstrap(windowManager);
    return true;
}

bool CornerlightSpotlightUsesEnhancedSiri(void) {
    static SwiftBoolGetter getter;
    if (getter == NULL) {
        getter = (SwiftBoolGetter)dlsym(
            RTLD_DEFAULT,
            "$s16GenerativeModels0aB12AvailabilityV22shouldShowEnhancedSiriSbvgZ"
        );
    }
    return getter != NULL && getter();
}

bool CornerlightSpotlightSwitchScreen(void *windowManager, void *screen) {
    static SwiftScreenInstanceMethod switchScreen;
    if (switchScreen == NULL) {
        switchScreen = (SwiftScreenInstanceMethod)dlsym(
            RTLD_DEFAULT,
            "$s19SpotlightUIInternal13WindowManagerC6switchyySo8NSScreenCFTj"
        );
    }
    if (switchScreen == NULL || windowManager == NULL || screen == NULL) {
        return false;
    }
    switchScreen(screen, windowManager);
    return true;
}

bool CornerlightSpotlightLaunchAppsBrowsing(void *windowManager) {
    static SwiftOptionalCompletionInstanceMethod launch;
    if (launch == NULL) {
        launch = (SwiftOptionalCompletionInstanceMethod)dlsym(
            RTLD_DEFAULT,
            "$s19SpotlightUIInternal13WindowManagerC18launchAppsBrowsing10completionyyycSg_tF"
        );
    }
    if (launch == NULL || windowManager == NULL) {
        return false;
    }
    launch(NULL, NULL, windowManager);
    return true;
}

bool CornerlightSpotlightDismissAll(void *windowManager) {
    static SwiftInstanceMethod dismiss;
    if (dismiss == NULL) {
        dismiss = (SwiftInstanceMethod)dlsym(
            RTLD_DEFAULT,
            "$s19SpotlightUIInternal13WindowManagerC10dismissAllyyFTj"
        );
    }
    if (dismiss == NULL || windowManager == NULL) {
        return false;
    }
    dismiss(windowManager);
    return true;
}

bool CornerlightSpotlightClearSearch(void *searchViewController) {
    static SwiftInstanceMethod clearSearch;
    if (clearSearch == NULL) {
        clearSearch = (SwiftInstanceMethod)dlsym(
            RTLD_DEFAULT,
            "$s19SpotlightUIInternal20SearchViewControllerC05clearC0yyF"
        );
    }
    if (clearSearch == NULL || searchViewController == NULL) {
        return false;
    }
    clearSearch(searchViewController);
    return true;
}

bool CornerlightSpotlightApplyGridBrowseWindowBehavior(void *windowSize) {
    static SwiftBehaviorGetter gridBrowseGetter;
    static SwiftWindowSizeInvalidator invalidate;
    static ResultPlatterBehavior gridBrowseBehavior;
    static bool hasGridBrowseBehavior;

    if (gridBrowseGetter == NULL) {
        gridBrowseGetter = (SwiftBehaviorGetter)dlsym(
            RTLD_DEFAULT,
            "$s17SpotlightUIShared21ResultPlatterBehaviorV10gridBrowseACvgZ"
        );
    }
    if (invalidate == NULL) {
        invalidate = (SwiftWindowSizeInvalidator)dlsym(
            RTLD_DEFAULT,
            "$s19SpotlightUIInternal20ObservableWindowSizeC10invalidate4with8animated11immediately10completiony0A8UIShared21ResultPlatterBehaviorV_S2byycSgtFTj"
        );
    }
    if (gridBrowseGetter == NULL || invalidate == NULL || windowSize == NULL) {
        return false;
    }
    if (!hasGridBrowseBehavior) {
        gridBrowseBehavior = gridBrowseGetter();
        hasGridBrowseBehavior = true;
    }
    invalidate(gridBrowseBehavior, false, true, NULL, NULL, windowSize);
    return true;
}

typedef void __attribute__((swiftcall)) (*SwiftAnimatedSizeSetter)(
    double value,
    void *self __attribute__((swift_context))
);

/*
 * macOS 27.2's Siri island draws its results accessory from WindowAnimationCoordinator's
 * animated width and height. Nothing copies the immediate size into them when the results are
 * supplied directly instead of through Spotlight's query pipeline, so the accessory stays a
 * 113 x 40 pill. The setters have no exported symbols and no Objective-C entry points. Reach them
 * relative to the exported launchAppsBrowsing symbol in the same image, only on builds whose
 * offsets were measured, and only after the target's opening instructions match.
 */
static const struct {
    const char *build;
    long widthSetterOffset;
    long heightSetterOffset;
} supportedAnimatedSizeBuilds[] = {
    {"26B123", -0x1181f0, -0x118328},
};

static bool animatedSizeSetterLooksValid(const unsigned int *code) {
    /* ldr x8, [x20] followed by an adrp. */
    return code[0] == 0xf9400288u && (code[1] & 0x9f000000u) == 0x90000000u;
}

bool CornerlightSpotlightSyncAnimatedWindowSize(
    void *animationCoordinator,
    double width,
    double height
) {
    static bool resolved;
    static SwiftAnimatedSizeSetter setWidth;
    static SwiftAnimatedSizeSetter setHeight;

    if (animationCoordinator == NULL) {
        return false;
    }
    if (!resolved) {
        resolved = true;
        char build[32] = {0};
        size_t length = sizeof build;
        void *anchor = dlsym(
            RTLD_DEFAULT,
            "$s19SpotlightUIInternal13WindowManagerC18launchAppsBrowsing10completionyyycSg_tF"
        );
        if (anchor == NULL || sysctlbyname("kern.osversion", build, &length, NULL, 0) != 0) {
            return false;
        }
        for (size_t index = 0;
             index < sizeof supportedAnimatedSizeBuilds / sizeof supportedAnimatedSizeBuilds[0];
             index++) {
            if (strcmp(build, supportedAnimatedSizeBuilds[index].build) != 0) {
                continue;
            }
            const char *widthTarget = (const char *)anchor + supportedAnimatedSizeBuilds[index].widthSetterOffset;
            const char *heightTarget = (const char *)anchor + supportedAnimatedSizeBuilds[index].heightSetterOffset;
            if (animatedSizeSetterLooksValid((const unsigned int *)widthTarget) &&
                animatedSizeSetterLooksValid((const unsigned int *)heightTarget)) {
                setWidth = (SwiftAnimatedSizeSetter)widthTarget;
                setHeight = (SwiftAnimatedSizeSetter)heightTarget;
            }
        }
    }
    if (setWidth == NULL || setHeight == NULL) {
        return false;
    }
    setWidth(width, animationCoordinator);
    setHeight(height, animationCoordinator);
    return true;
}
