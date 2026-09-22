#include "SpotlightBridge.h"

#include <dlfcn.h>
#include <stddef.h>

typedef void __attribute__((swiftcall)) (*SwiftInstanceMethod)(
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
