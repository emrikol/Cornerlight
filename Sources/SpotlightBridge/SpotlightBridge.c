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
