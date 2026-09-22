#ifndef CORNERLIGHT_SPOTLIGHT_BRIDGE_H
#define CORNERLIGHT_SPOTLIGHT_BRIDGE_H

#include <stdbool.h>

bool CornerlightSpotlightBootstrap(void *windowManager);
bool CornerlightSpotlightDismissAll(void *windowManager);
bool CornerlightSpotlightClearSearch(void *searchViewController);

#endif
