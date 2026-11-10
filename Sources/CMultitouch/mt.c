#include "CMultitouch.h"
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <stdlib.h>

// ---- MultitouchSupport.framework 的私有結構（逆向工程而來，社群廣泛使用的版本）----
typedef struct { float x, y; } MTPoint;
typedef struct { MTPoint position, velocity; } MTVector;

typedef struct {
    int frame;
    double timestamp;
    int identifier;
    int state;
    int fingerID;
    int handID;
    MTVector normalized;
    float size;
    int zero1;
    float angle;
    float majorAxis;
    float minorAxis;
    MTVector mm;
    int zero2[2];
    float zDensity;
} MTFinger;

typedef void *MTDeviceRef;
typedef int (*MTContactCallbackFunction)(MTDeviceRef, MTFinger *, int, double, int);

typedef CFMutableArrayRef (*MTDeviceCreateListFn)(void);
typedef void (*MTRegisterContactFrameCallbackFn)(MTDeviceRef, MTContactCallbackFunction);
typedef void (*MTUnregisterContactFrameCallbackFn)(MTDeviceRef, MTContactCallbackFunction);
typedef void (*MTDeviceStartFn)(MTDeviceRef, int);
typedef void (*MTDeviceStopFn)(MTDeviceRef);

static MTFrameCallback g_callback = NULL;
static CFMutableArrayRef g_devices = NULL;
static MTRegisterContactFrameCallbackFn p_register = NULL;
static MTUnregisterContactFrameCallbackFn p_unregister = NULL;
static MTDeviceStartFn p_start = NULL;
static MTDeviceStopFn p_stop = NULL;

#define MAX_TOUCHES 16

static int contact_callback(MTDeviceRef device, MTFinger *fingers, int count, double timestamp, int frame) {
    (void)device; (void)frame;
    if (!g_callback) return 0;
    MTTouchPoint pts[MAX_TOUCHES];
    int n = count < MAX_TOUCHES ? count : MAX_TOUCHES;
    for (int i = 0; i < n; i++) {
        pts[i].identifier = fingers[i].identifier;
        pts[i].state = fingers[i].state;
        pts[i].x = fingers[i].normalized.position.x;
        pts[i].y = fingers[i].normalized.position.y;
        pts[i].size = fingers[i].size;
    }
    g_callback(pts, n, timestamp);
    return 0;
}

int mt_start(MTFrameCallback callback) {
    void *handle = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW);
    if (!handle) return -1;

    MTDeviceCreateListFn p_list = (MTDeviceCreateListFn)dlsym(handle, "MTDeviceCreateList");
    p_register = (MTRegisterContactFrameCallbackFn)dlsym(handle, "MTRegisterContactFrameCallback");
    p_unregister = (MTUnregisterContactFrameCallbackFn)dlsym(handle, "MTUnregisterContactFrameCallback");
    p_start = (MTDeviceStartFn)dlsym(handle, "MTDeviceStart");
    p_stop = (MTDeviceStopFn)dlsym(handle, "MTDeviceStop");
    if (!p_list || !p_register || !p_start) return -1;

    g_callback = callback;
    g_devices = p_list();
    if (!g_devices) return -1;

    CFIndex n = CFArrayGetCount(g_devices);
    for (CFIndex i = 0; i < n; i++) {
        MTDeviceRef dev = (MTDeviceRef)CFArrayGetValueAtIndex(g_devices, i);
        p_register(dev, contact_callback);
        p_start(dev, 0);
    }
    return (int)n;
}

void mt_stop(void) {
    if (!g_devices) return;
    CFIndex n = CFArrayGetCount(g_devices);
    for (CFIndex i = 0; i < n; i++) {
        MTDeviceRef dev = (MTDeviceRef)CFArrayGetValueAtIndex(g_devices, i);
        if (p_unregister) p_unregister(dev, contact_callback);
        if (p_stop) p_stop(dev);
    }
    g_callback = NULL;
}
