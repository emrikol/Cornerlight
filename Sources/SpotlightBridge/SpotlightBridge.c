#include "SpotlightBridge.h"

#include <dlfcn.h>
#include <stddef.h>

typedef void __attribute__((swiftcall)) (*SwiftInstanceMethod)(
    void *self __attribute__((swift_context))
);

typedef void *__attribute__((swiftcall)) (*SwiftObjectInstanceMethod)(
    void *self __attribute__((swift_context))
);

// macOS 27's SearchNavigationStackItem is a resilient Swift value with an 840-byte ABI layout.
// Cornerlight's runtime compatibility guard prevents this bridge from loading on later major
// versions, where Apple may change that private layout.
typedef struct __attribute__((aligned(8))) {
    unsigned char storage[840];
} SearchNavigationStackItem;

_Static_assert(sizeof(SearchNavigationStackItem) == 840, "unexpected navigation item layout");

typedef SearchNavigationStackItem __attribute__((swiftcall)) (*SwiftStackItemGetter)(
    void *self __attribute__((swift_context))
);

typedef void __attribute__((swiftcall)) (*SwiftStackItemInstanceMethod)(
    SearchNavigationStackItem item,
    void *self __attribute__((swift_context))
);

static SearchNavigationStackItem capturedNavigationRoot;
static bool hasCapturedNavigationRoot;

typedef void __attribute__((swiftcall)) (*SwiftOptionalCompletionInstanceMethod)(
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

static void *navigationStackForSearchViewController(void *searchViewController) {
    static SwiftObjectInstanceMethod getter;
    if (getter == NULL) {
        getter = (SwiftObjectInstanceMethod)dlsym(
            RTLD_DEFAULT,
            "$s19SpotlightUIInternal26SearchNavigationControllerC15navigationStackAA0cdG0Cvg"
        );
    }
    if (getter == NULL || searchViewController == NULL) {
        return NULL;
    }
    return getter(searchViewController);
}

bool CornerlightSpotlightCaptureSearchResultsRoot(void *searchViewController) {
    static SwiftStackItemGetter rootGetter;
    if (rootGetter == NULL) {
        rootGetter = (SwiftStackItemGetter)dlsym(
            RTLD_DEFAULT,
            "$s19SpotlightUIInternal21SearchNavigationStackC4rootAA0cdE4ItemVvgTj"
        );
    }
    void *navigationStack = navigationStackForSearchViewController(searchViewController);
    if (rootGetter == NULL || navigationStack == NULL) {
        return false;
    }
    capturedNavigationRoot = rootGetter(navigationStack);
    hasCapturedNavigationRoot = true;
    return true;
}

bool CornerlightSpotlightRestoreSearchResultsRoot(void *searchViewController) {
    static SwiftStackItemInstanceMethod replaceRoot;
    if (replaceRoot == NULL) {
        replaceRoot = (SwiftStackItemInstanceMethod)dlsym(
            RTLD_DEFAULT,
            "$s19SpotlightUIInternal21SearchNavigationStackC11replaceRoot4withyAA0cdE4ItemV_tFTj"
        );
    }
    void *navigationStack = navigationStackForSearchViewController(searchViewController);
    if (replaceRoot == NULL || navigationStack == NULL || !hasCapturedNavigationRoot) {
        return false;
    }
    replaceRoot(capturedNavigationRoot, navigationStack);
    return true;
}
