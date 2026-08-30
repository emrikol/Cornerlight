#import <AppKit/AppKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <dlfcn.h>

static Method classMethodForSelector(Class cls, SEL selector) {
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    if (methods == NULL) return NULL;
    Method found = NULL;
    for (unsigned int index = 0; index < count; index++) {
        if (method_getName(methods[index]) == selector) {
            found = methods[index];
            break;
        }
    }
    free(methods);
    return found;
}

static void printMethodsForClass(Class cls) {
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    printf("methods[%s]=%u\n", class_getName(cls), count);
    for (unsigned int index = 0; index < count; index++) {
        printf("  -%s %s\n",
               sel_getName(method_getName(methods[index])),
               method_getTypeEncoding(methods[index]));
    }
    free(methods);
}

static void printCollection(NSString *name, id collection) {
    printf("%s.class=%s\n", name.UTF8String, collection == nil ? "nil" : object_getClassName(collection));
    if (![collection isKindOfClass:NSArray.class]) return;

    NSArray *items = collection;
    printf("%s.count=%lu\n", name.UTF8String, (unsigned long)items.count);
    for (NSUInteger index = 0; index < MIN(items.count, 3); index++) {
        id item = items[index];
        printf("%s[%lu].class=%s\n", name.UTF8String, (unsigned long)index, object_getClassName(item));
        printMethodsForClass(object_getClass(item));
        for (NSString *key in @[@"bundleIdentifier", @"bundleId", @"displayName", @"localizedName"] ) {
            @try {
                id value = [item valueForKey:key];
                printf("%s[%lu].%s=%s\n",
                       name.UTF8String,
                       (unsigned long)index,
                       key.UTF8String,
                       [[value description] UTF8String]);
            } @catch (__unused NSException *exception) {
                printf("%s[%lu].%s=<undefined>\n",
                       name.UTF8String,
                       (unsigned long)index,
                       key.UTF8String);
            }
        }
    }
}

static int printATXCache(void) {
    Class clientClass = NSClassFromString(@"ATXAppDirectoryClient");
    SEL sharedSelector = NSSelectorFromString(@"sharedInstance");
    SEL cachedSelector = NSSelectorFromString(@"getDirectoryResponseFromCacheWithMaxNumberOfAppsToPredict:");
    if (clientClass == Nil || ![clientClass respondsToSelector:sharedSelector]) return 3;

    id (*shared)(id, SEL) = (void *)objc_msgSend;
    id client = shared(clientClass, sharedSelector);
    if (![client respondsToSelector:cachedSelector]) return 4;

    id (*cached)(id, SEL, NSUInteger) = (void *)objc_msgSend;
    id response = cached(client, cachedSelector, 7);
    printf("response.class=%s\n", response == nil ? "nil" : object_getClassName(response));
    printMethodsForClass(object_getClass(response));
    for (NSString *key in @[
        @"predictedApps",
        @"recentApps",
        @"predictedAppIdentities",
        @"recentAppIdentities",
    ]) {
        @try {
            printCollection(key, [response valueForKey:key]);
        } @catch (NSException *exception) {
            printf("%s.error=%s\n", key.UTF8String, exception.reason.UTF8String);
        }
    }
    return 0;
}

static void printValue(id object, NSString *key) {
    @try {
        id value = [object valueForKey:key];
        printf("section.%s.class=%s\n",
               key.UTF8String,
               value == nil ? "nil" : object_getClassName(value));
        printf("section.%s=%s\n", key.UTF8String, [[value description] UTF8String]);
    } @catch (__unused NSException *exception) {
        printf("section.%s=<undefined>\n", key.UTF8String);
    }
}

static int printBrowseSection(int style, NSString *identityValue) {
    Class identityClass = NSClassFromString(@"ATXAppIdentity");
    BOOL isPath = [identityValue containsString:@"/"];
    SEL identitySelector = NSSelectorFromString(
        isPath ? @"initWithBundleURL:" : @"initWithBundleIdentifier:"
    );
    id (*identityInitializer)(id, SEL, id) = (void *)objc_msgSend;
    id argument = isPath ? [NSURL fileURLWithPath:identityValue] : identityValue;
    id identity = identityInitializer([identityClass alloc], identitySelector, argument);

    Class builderClass = NSClassFromString(@"SPUISAppBrowseSectionBuilder");
    SEL builderSelector = NSSelectorFromString(@"appSectionWithTitle:identifier:style:appIdentities:");
    if (identity == nil || builderClass == Nil || ![builderClass respondsToSelector:builderSelector]) return 5;

    id (*build)(id, SEL, id, id, int, id) = (void *)objc_msgSend;
    id section = build(
        builderClass,
        builderSelector,
        @"",
        @"com.openai.launch.applications",
        style,
        @[identity]
    );
    printf("section.class=%s\n", section == nil ? "nil" : object_getClassName(section));
    if (section == nil) return 6;
    printMethodsForClass(object_getClass(section));
    for (NSString *key in @[
        @"title",
        @"identifier",
        @"results",
        @"resultItems",
        @"displayStyle",
        @"sectionType",
    ]) {
        printValue(section, key);
    }
    NSArray *results = [section valueForKey:@"results"];
    id result = results.firstObject;
    printf("result.class=%s\n", result == nil ? "nil" : object_getClassName(result));
    if (result != nil) {
        printMethodsForClass(object_getClass(result));
        for (NSString *key in @[
            @"displayName",
            @"title",
            @"bundleIdentifier",
            @"url",
            @"object",
            @"contentType",
            @"applicationBundleIdentifier",
            @"resultType",
            @"queryId",
            @"sectionIdentifier",
        ]) {
            printValue(result, key);
        }
    }


    Class snapshotBuilderClass = NSClassFromString(@"SearchUIDataSourceSnapshotBuilder");
    id snapshotBuilder = [[snapshotBuilderClass alloc] init];
    SEL rowModelsSelector = NSSelectorFromString(@"buildRowModelsFromResultSections:queryId:");
    id (*buildRowModels)(id, SEL, id, NSUInteger) = (void *)objc_msgSend;
    id rowModels = buildRowModels(snapshotBuilder, rowModelsSelector, @[section], 1);
    printf("rowModels.class=%s\n", rowModels == nil ? "nil" : object_getClassName(rowModels));
    printf("rowModels=%s\n", [[rowModels description] UTF8String]);
    if ([rowModels isKindOfClass:NSArray.class] && [rowModels count] > 0) {
        id rowModel = [rowModels firstObject];
        printf("rowModel.class=%s\n", object_getClassName(rowModel));
        printMethodsForClass(object_getClass(rowModel));
    }

    SEL snapshotSelector = NSSelectorFromString(@"buildSnapshotFromResultSections:queryId:");
    id (*buildSnapshot)(id, SEL, id, NSUInteger) = (void *)objc_msgSend;
    id snapshot = buildSnapshot(snapshotBuilder, snapshotSelector, @[section], 1);
    printf("snapshot.class=%s\n", snapshot == nil ? "nil" : object_getClassName(snapshot));
    printf("snapshot=%s\n", [[snapshot description] UTF8String]);
    if (snapshot != nil) printMethodsForClass(object_getClass(snapshot));
    return 0;
}

static int printClass(NSString *name) {
    Class cls = NSClassFromString(name);
    if (cls == Nil) return 7;
    for (Class current = cls; current != Nil; current = class_getSuperclass(current)) {
        printf("class=%s superclass=%s\n",
               class_getName(current),
               class_getSuperclass(current) == Nil ? "nil" : class_getName(class_getSuperclass(current)));
        printMethodsForClass(current);
        unsigned int protocolCount = 0;
        __unsafe_unretained Protocol **protocols = class_copyProtocolList(current, &protocolCount);
        for (unsigned int index = 0; index < protocolCount; index++) {
            printf("  protocol=%s\n", protocol_getName(protocols[index]));
        }
        free(protocols);
    }
    printf("class-methods[%s]\n", class_getName(cls));
    printMethodsForClass(object_getClass(cls));
    return 0;
}

static int printMethodAddress(NSString *className, NSString *selectorName) {
    Class cls = NSClassFromString(className);
    SEL selector = NSSelectorFromString(selectorName);
    Method method = cls == Nil ? NULL : class_getInstanceMethod(cls, selector);
    if (method == NULL) return 9;

    IMP implementation = method_getImplementation(method);
    Dl_info image = {0};
    if (dladdr((const void *)implementation, &image) == 0) return 10;
    uintptr_t offset = (uintptr_t)implementation - (uintptr_t)image.dli_fbase;
    printf("method=-[%s %s] implementation=%p image=%s imageBase=%p imageOffset=0x%lx\n",
           className.UTF8String,
           selectorName.UTF8String,
           implementation,
           image.dli_fname,
           image.dli_fbase,
           (unsigned long)offset);
    return 0;
}

static int printSharedApplicationClass(void) {
    Class applicationClass = NSClassFromString(@"SPApplication");
    SEL sharedSelector = NSSelectorFromString(@"sharedApplication");
    if (applicationClass == Nil || ![applicationClass respondsToSelector:sharedSelector]) return 11;

    id (*sharedApplication)(id, SEL) = (void *)objc_msgSend;
    id application = sharedApplication(applicationClass, sharedSelector);
    printf("requested.class=%s\n", class_getName(applicationClass));
    printf("shared.class=%s\n", application == nil ? "nil" : object_getClassName(application));
    printf("NSApp.class=%s\n", NSApp == nil ? "nil" : object_getClassName(NSApp));
    return [application isKindOfClass:applicationClass] ? 0 : 12;
}

static void printViewTree(NSView *view, NSUInteger depth) {
    printf("%*s%s frame=%s\n",
           (int)(depth * 2),
           "",
           object_getClassName(view),
           NSStringFromRect(view.frame).UTF8String);
    for (NSView *child in view.subviews) {
        printViewTree(child, depth + 1);
    }
}

static int printCollectionController(int style) {
    [NSApplication sharedApplication];
    Class controllerClass = NSClassFromString(@"SearchUICollectionViewController");
    SEL initializer = NSSelectorFromString(@"initForAboveFilterResults:");
    id (*initialize)(id, SEL, BOOL) = (void *)objc_msgSend;
    NSViewController *controller = initialize([controllerClass alloc], initializer, NO);
    if (controller == nil) return 8;

    NSView *view = controller.view;
    view.frame = NSMakeRect(0, 0, 844, 475);
    [view layoutSubtreeIfNeeded];
    printf("controller.class=%s\n", object_getClassName(controller));
    printViewTree(view, 0);
    for (NSString *key in @[@"collectionView", @"searchUICollectionView", @"dataSource"]) {
        @try {
            id value = [controller valueForKey:key];
            printf("controller.%s.class=%s\n",
                   key.UTF8String,
                   value == nil ? "nil" : object_getClassName(value));
        } @catch (__unused NSException *exception) {
            printf("controller.%s=<undefined>\n", key.UTF8String);
        }
    }


    Class identityClass = NSClassFromString(@"ATXAppIdentity");
    SEL identitySelector = NSSelectorFromString(@"initWithBundleURL:");
    id (*identityInitializer)(id, SEL, id) = (void *)objc_msgSend;
    NSMutableArray *identities = [NSMutableArray array];
    for (NSString *path in @[
        @"/System/Applications/App Store.app",
        @"/System/Applications/Calendar.app",
        @"/System/Applications/Chess.app",
    ]) {
        id identity = identityInitializer(
            [identityClass alloc],
            identitySelector,
            [NSURL fileURLWithPath:path]
        );
        if (identity != nil) [identities addObject:identity];
    }
    Class builderClass = NSClassFromString(@"SPUISAppBrowseSectionBuilder");
    SEL builderSelector = NSSelectorFromString(@"appSectionWithTitle:identifier:style:appIdentities:");
    id (*buildSection)(id, SEL, id, id, int, id) = (void *)objc_msgSend;
    id suggestionSection = buildSection(
        builderClass,
        builderSelector,
        @"",
        @"com.apple.spotlight.zkw.apps.suggestions",
        style == 3 ? 3 : 1,
        [identities subarrayWithRange:NSMakeRange(0, 1)]
    );
    for (id result in [suggestionSection results]) {
        [result setValue:@"com.apple.spotlight.zkw" forKey:@"sectionBundleIdentifier"];
    }
    id applicationSection = buildSection(
        builderClass,
        builderSelector,
        @"",
        @"com.apple.spotlight.zkw.alphabetic",
        style,
        [identities subarrayWithRange:NSMakeRange(1, identities.count - 1)]
    );
    id snapshotBuilder = [[NSClassFromString(@"SearchUIDataSourceSnapshotBuilder") alloc] init];
    SEL snapshotSelector = NSSelectorFromString(@"buildSnapshotFromResultSections:queryId:");
    id (*buildSnapshot)(id, SEL, id, NSUInteger) = (void *)objc_msgSend;
    id snapshot = buildSnapshot(
        snapshotBuilder,
        snapshotSelector,
        @[suggestionSection, applicationSection],
        1
    );
    SEL updateSelector = NSSelectorFromString(@"updateWithSnapshot:queryId:animated:completion:");
    void (*update)(id, SEL, id, NSUInteger, BOOL, id) = (void *)objc_msgSend;
    __block BOOL finished = NO;
    update(controller, updateSelector, snapshot, 1, NO, ^{ finished = YES; });
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:1];
    while (!finished && deadline.timeIntervalSinceNow > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    [view layoutSubtreeIfNeeded];
    NSCollectionView *collectionView = nil;
    @try {
        collectionView = [controller valueForKey:@"collectionView"];
    } @catch (__unused NSException *exception) {}
    printf("controller.updated=%s sections=%ld\n",
           finished ? "yes" : "no",
           (long)collectionView.numberOfSections);
    printViewTree(view, 0);
    return 0;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 2 && argc != 3 && argc != 4) {
            fprintf(stderr, "Usage: SpotlightRuntimeProbe selector|--atx-cache|--shared-application|--collection-controller|--class class-name|--method-address class selector|--browse-section style bundle-id\n");
            return 2;
        }

        const char *frameworks[] = {
            "/System/Library/PrivateFrameworks/SearchFoundation.framework/Versions/A/SearchFoundation",
            "/System/Library/PrivateFrameworks/SearchUI.framework/Versions/A/SearchUI",
            "/System/Library/PrivateFrameworks/SpotlightUIShared.framework/Versions/A/SpotlightUIShared",
            "/System/Library/PrivateFrameworks/SpotlightUIServices.framework/Versions/A/SpotlightUIServices",
            "/System/Library/PrivateFrameworks/AppPredictionClient.framework/Versions/A/AppPredictionClient",
        };
        for (unsigned int index = 0; index < sizeof(frameworks) / sizeof(frameworks[0]); index++) {
            dlopen(frameworks[index], RTLD_LAZY | RTLD_LOCAL);
        }
        dlopen(
            "/System/Library/CoreServices/Spotlight.app/Contents/MacOS/Spotlight",
            RTLD_LAZY | RTLD_LOCAL
        );

        if (strcmp(argv[1], "--atx-cache") == 0) {
            return printATXCache();
        }
        if (strcmp(argv[1], "--shared-application") == 0) {
            return printSharedApplicationClass();
        }
        if (strcmp(argv[1], "--browse-section") == 0 && argc == 4) {
            return printBrowseSection(atoi(argv[2]), [NSString stringWithUTF8String:argv[3]]);
        }
        if (strcmp(argv[1], "--class") == 0 && argc == 3) {
            return printClass([NSString stringWithUTF8String:argv[2]]);
        }
        if (strcmp(argv[1], "--method-address") == 0 && argc == 4) {
            return printMethodAddress(
                [NSString stringWithUTF8String:argv[2]],
                [NSString stringWithUTF8String:argv[3]]
            );
        }
        if (strcmp(argv[1], "--collection-controller") == 0) {
            return printCollectionController(argc == 3 ? atoi(argv[2]) : 3);
        }

        SEL selector = sel_registerName(argv[1]);
        int count = objc_getClassList(NULL, 0);
        Class *classes = (__unsafe_unretained Class *)calloc((size_t)count, sizeof(Class));
        count = objc_getClassList(classes, count);
        for (int index = 0; index < count; index++) {
            Class cls = classes[index];
            Method instanceMethod = classMethodForSelector(cls, selector);
            if (instanceMethod != NULL) {
                printf("- [%s %s] %s\n", class_getName(cls), argv[1], method_getTypeEncoding(instanceMethod));
            }
            Class metaclass = object_getClass(cls);
            Method classMethod = metaclass == Nil ? NULL : classMethodForSelector(metaclass, selector);
            if (classMethod != NULL) {
                printf("+ [%s %s] %s\n", class_getName(cls), argv[1], method_getTypeEncoding(classMethod));
            }
        }
        free(classes);
    }
    return 0;
}
