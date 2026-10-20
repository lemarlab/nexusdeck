// NexusDeck Audio — AudioServerPlugIn exposing named stereo devices for the controller's mixer.
//
// Each visible device has a hidden "bridge" twin in the opposite direction; they share a ring buffer.
// NexusDeck moves audio between the bridges and the physical USB audio device.
//
// Per-app routing: NexusDeck sets a table "bundleID=pair" on the plug-in object (custom property 'ndrt').
// The audio of a matching client of an output device is taken before the device mix (ProcessOutput) and
// added to the side ring of the chosen pair, which its bridge reads together with the pair's own ring.

#include <CoreAudio/AudioServerPlugIn.h>
#include <CoreFoundation/CoreFoundation.h>
#include <mach/mach_time.h>
#include <pthread.h>
#include <stdatomic.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>

#pragma mark - Configuration

#define kRate48            48000.0
#define kRate96            96000.0
#define kChannels          2
#define kRingFrames        16384u          // power of two
#define kZeroPeriod        kRingFrames
#define kLatencyFrames     0
#define kSafetyOffset      0

enum { kPlugInID = 1 };

typedef struct {
    const char* name;       // shown to the user
    const char* uid;
    bool        input;      // direction of this device
    bool        hidden;
    int         pair;       // ring buffer index
} DeviceDef;

static const DeviceDef kDevices[] = {
    // Visible devices
    { "Creator Mix",  "NexusDeck.CreatorMix",  true,  false, 0 },
    { "Audience Mix", "NexusDeck.AudienceMix", true,  false, 1 },
    { "Chat Mic",     "NexusDeck.ChatMic",     true,  false, 2 },
    { "System",       "NexusDeck.System",      false, false, 3 },
    { "Game",         "NexusDeck.Game",        false, false, 4 },
    { "Chat",         "NexusDeck.Chat",        false, false, 5 },
    { "Line In",      "NexusDeck.LineIn",      false, false, 6 },
    { "Console",      "NexusDeck.Console",     false, false, 7 },
    // Hidden bridges used by NexusDeck
    { "Creator Mix Bridge",  "NexusDeck.Bridge.CreatorMix",  false, true, 0 },
    { "Audience Mix Bridge", "NexusDeck.Bridge.AudienceMix", false, true, 1 },
    { "Chat Mic Bridge",     "NexusDeck.Bridge.ChatMic",     false, true, 2 },
    { "System Bridge",       "NexusDeck.Bridge.System",      true,  true, 3 },
    { "Game Bridge",         "NexusDeck.Bridge.Game",        true,  true, 4 },
    { "Chat Bridge",         "NexusDeck.Bridge.Chat",        true,  true, 5 },
    { "Line In Bridge",      "NexusDeck.Bridge.LineIn",      true,  true, 6 },
    { "Console Bridge",      "NexusDeck.Bridge.Console",     true,  true, 7 },
    // Capture inputs for OBS: a copy of each channel (filled by NexusDeck through the hidden bridges below)
    { "System",   "NexusDeck.Capture.System",  true,  false, 8 },
    { "Game",     "NexusDeck.Capture.Game",    true,  false, 9 },
    { "Chat",     "NexusDeck.Capture.Chat",    true,  false, 10 },
    { "Line In",  "NexusDeck.Capture.LineIn",  true,  false, 11 },
    { "Console",  "NexusDeck.Capture.Console", true,  false, 12 },
    { "System Capture Bridge",  "NexusDeck.Bridge.Cap.System",  false, true, 8 },
    { "Game Capture Bridge",    "NexusDeck.Bridge.Cap.Game",    false, true, 9 },
    { "Chat Capture Bridge",    "NexusDeck.Bridge.Cap.Chat",    false, true, 10 },
    { "Line In Capture Bridge", "NexusDeck.Bridge.Cap.LineIn",  false, true, 11 },
    { "Console Capture Bridge", "NexusDeck.Bridge.Cap.Console", false, true, 12 },
};
#define kDeviceCount ((UInt32)(sizeof(kDevices) / sizeof(kDevices[0])))
#define kPairCount 13

// Object IDs: device i -> 2 + 2i, its stream -> 3 + 2i
static inline AudioObjectID DeviceID(UInt32 i) { return 2 + 2 * i; }
static inline AudioObjectID StreamID(UInt32 i) { return 3 + 2 * i; }
static inline int DeviceIndex(AudioObjectID o) { return (o >= 2 && o < 2 + 2 * kDeviceCount && (o % 2) == 0) ? (int)((o - 2) / 2) : -1; }
static inline int StreamIndex(AudioObjectID o) { return (o >= 3 && o < 3 + 2 * kDeviceCount && (o % 2) == 1) ? (int)((o - 3) / 2) : -1; }

#pragma mark - State

static AudioServerPlugInHostRef gHost = NULL;
static UInt32 gRefCount = 0;
static pthread_mutex_t gMutex = PTHREAD_MUTEX_INITIALIZER;

static UInt32 gIOCount[kDeviceCount];
static Float64 gHostTicksPerFrame = 0;
static Float64 gHostClockFrequency = 0;
/// Shared by all devices (they mirror the controller's USB interface, which runs at 48 or 96 kHz).
static Float64 gSampleRate = kRate48;
static UInt64 gAnchorHostTime = 0;
static UInt32 gRunningDevices = 0;
static UInt64 gTimestampCounter[kDeviceCount];

static float* gRings[kPairCount];
/// Audio routed here from clients of other devices (see ProcessOutput).
static float* gSide[kPairCount];

#pragma mark - Per-app routing

#define kRouteSelector   'ndrt'
/// Visible devices currently published (bit = device index). Hidden bridges are always published.
#define kVisibleSelector 'ndvm'
// Until NexusDeck says otherwise (mixer connected) no visible device is published.
static _Atomic UInt32 gVisibleMask = 0;
static inline bool IsPublished(UInt32 i) { return kDevices[i].hidden || ((atomic_load(&gVisibleMask) >> i) & 1u); }
/// Custom device names set by NexusDeck ('ndnm': "index=name\n..."); empty = default name.
#define kNamesSelector 'ndnm'
static char gNames[64][128];
static CFStringRef gNamesString = NULL;

static UInt32 PublishedCount(void) { UInt32 n = 0; for (UInt32 i = 0; i < kDeviceCount; i++) if (IsPublished(i)) n++; return n; }
#define kMaxClients      256
#define kMaxRoutes       64

typedef struct { UInt32 device; UInt32 client; char bundle[256]; _Atomic int target; } ClientEntry;
static ClientEntry gClients[kMaxClients];
static UInt32 gClientCount = 0;
typedef struct { char bundle[256]; int pair; } RouteEntry;
static RouteEntry gRoutes[kMaxRoutes];
static UInt32 gRouteCount = 0;
static CFStringRef gRouteString = NULL;

/// Pair a bundle is routed to, or -1. "com.app" also matches its helpers "com.app.*".
static int RouteFor(const char* bundle) {
    if (!bundle[0]) return -1;
    for (UInt32 i = 0; i < gRouteCount; i++) {
        size_t n = strlen(gRoutes[i].bundle);
        if (n && strncmp(bundle, gRoutes[i].bundle, n) == 0 && (bundle[n] == 0 || bundle[n] == '.')) return gRoutes[i].pair;
    }
    return -1;
}

/// Parses "bundle=pair\n..." (called with gMutex held) and re-targets the known clients.
static void ApplyRoutes(CFStringRef str) {
    if (gRouteString) CFRelease(gRouteString);
    gRouteString = str ? CFStringCreateCopy(NULL, str) : NULL;
    gRouteCount = 0;
    char buf[kMaxRoutes * 260];
    if (str && CFStringGetCString(str, buf, sizeof(buf), kCFStringEncodingUTF8)) {
        char* save = NULL;
        for (char* line = strtok_r(buf, "\n", &save); line && gRouteCount < kMaxRoutes; line = strtok_r(NULL, "\n", &save)) {
            char* eq = strrchr(line, '=');
            if (!eq) continue;
            *eq = 0;
            int pair = atoi(eq + 1);
            if (pair < 3 || pair > 7 || strlen(line) >= 256) continue;
            strcpy(gRoutes[gRouteCount].bundle, line);
            gRoutes[gRouteCount].pair = pair;
            gRouteCount++;
        }
    }
    for (UInt32 i = 0; i < gClientCount; i++) atomic_store(&gClients[i].target, RouteFor(gClients[i].bundle));
}

static int ClientTarget(UInt32 device, UInt32 client) {
    for (UInt32 i = 0; i < gClientCount; i++)
        if (gClients[i].device == device && gClients[i].client == client) return atomic_load(&gClients[i].target);
    return -1;
}

#pragma mark - Helpers

static CFStringRef CFStr(const char* s) { return CFStringCreateWithCString(NULL, s, kCFStringEncodingUTF8); }

static AudioStreamBasicDescription Format(void) {
    AudioStreamBasicDescription f = {0};
    f.mSampleRate = gSampleRate;
    f.mFormatID = kAudioFormatLinearPCM;
    f.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked;
    f.mBytesPerPacket = 4 * kChannels;
    f.mFramesPerPacket = 1;
    f.mBytesPerFrame = 4 * kChannels;
    f.mChannelsPerFrame = kChannels;
    f.mBitsPerChannel = 32;
    return f;
}

#define WRITE(type, value) do { if (inDataSize < sizeof(type)) return kAudioHardwareBadPropertySizeError; *(type*)outData = (value); *outDataSize = sizeof(type); } while (0)

#pragma mark - Plug-in interface prototypes

static HRESULT QueryInterface(void*, REFIID, LPVOID*);
static ULONG AddRef(void*);
static ULONG Release(void*);
static OSStatus Initialize(AudioServerPlugInDriverRef, AudioServerPlugInHostRef);
static OSStatus CreateDevice(AudioServerPlugInDriverRef, CFDictionaryRef, const AudioServerPlugInClientInfo*, AudioObjectID*);
static OSStatus DestroyDevice(AudioServerPlugInDriverRef, AudioObjectID);
static OSStatus AddDeviceClient(AudioServerPlugInDriverRef, AudioObjectID, const AudioServerPlugInClientInfo*);
static OSStatus RemoveDeviceClient(AudioServerPlugInDriverRef, AudioObjectID, const AudioServerPlugInClientInfo*);
static OSStatus PerformDeviceConfigurationChange(AudioServerPlugInDriverRef, AudioObjectID, UInt64, void*);
static OSStatus AbortDeviceConfigurationChange(AudioServerPlugInDriverRef, AudioObjectID, UInt64, void*);
static Boolean HasProperty(AudioServerPlugInDriverRef, AudioObjectID, pid_t, const AudioObjectPropertyAddress*);
static OSStatus IsPropertySettable(AudioServerPlugInDriverRef, AudioObjectID, pid_t, const AudioObjectPropertyAddress*, Boolean*);
static OSStatus GetPropertyDataSize(AudioServerPlugInDriverRef, AudioObjectID, pid_t, const AudioObjectPropertyAddress*, UInt32, const void*, UInt32*);
static OSStatus GetPropertyData(AudioServerPlugInDriverRef, AudioObjectID, pid_t, const AudioObjectPropertyAddress*, UInt32, const void*, UInt32, UInt32*, void*);
static OSStatus SetPropertyData(AudioServerPlugInDriverRef, AudioObjectID, pid_t, const AudioObjectPropertyAddress*, UInt32, const void*, UInt32, const void*);
static OSStatus StartIO(AudioServerPlugInDriverRef, AudioObjectID, UInt32);
static OSStatus StopIO(AudioServerPlugInDriverRef, AudioObjectID, UInt32);
static OSStatus GetZeroTimeStamp(AudioServerPlugInDriverRef, AudioObjectID, UInt32, Float64*, UInt64*, UInt64*);
static OSStatus WillDoIOOperation(AudioServerPlugInDriverRef, AudioObjectID, UInt32, UInt32, Boolean*, Boolean*);
static OSStatus BeginIOOperation(AudioServerPlugInDriverRef, AudioObjectID, UInt32, UInt32, UInt32, const AudioServerPlugInIOCycleInfo*);
static OSStatus DoIOOperation(AudioServerPlugInDriverRef, AudioObjectID, AudioObjectID, UInt32, UInt32, UInt32, const AudioServerPlugInIOCycleInfo*, void*, void*);
static OSStatus EndIOOperation(AudioServerPlugInDriverRef, AudioObjectID, UInt32, UInt32, UInt32, const AudioServerPlugInIOCycleInfo*);

static AudioServerPlugInDriverInterface gInterface = {
    NULL, QueryInterface, AddRef, Release, Initialize, CreateDevice, DestroyDevice, AddDeviceClient, RemoveDeviceClient,
    PerformDeviceConfigurationChange, AbortDeviceConfigurationChange, HasProperty, IsPropertySettable, GetPropertyDataSize,
    GetPropertyData, SetPropertyData, StartIO, StopIO, GetZeroTimeStamp, WillDoIOOperation, BeginIOOperation, DoIOOperation,
    EndIOOperation
};
static AudioServerPlugInDriverInterface* gInterfacePtr = &gInterface;
static AudioServerPlugInDriverRef gDriverRef = &gInterfacePtr;

#pragma mark - Factory

void* NexusDeckAudio_Create(CFAllocatorRef allocator, CFUUIDRef requestedTypeUUID);
void* NexusDeckAudio_Create(CFAllocatorRef allocator, CFUUIDRef requestedTypeUUID) {
    (void)allocator;
    if (CFEqual(requestedTypeUUID, kAudioServerPlugInTypeUUID)) return gDriverRef;
    return NULL;
}

static HRESULT QueryInterface(void* inDriver, REFIID inUUID, LPVOID* outInterface) {
    if (inDriver != gDriverRef || !outInterface) return kAudioHardwareIllegalOperationError;
    CFUUIDRef req = CFUUIDCreateFromUUIDBytes(NULL, inUUID);
    HRESULT r = E_NOINTERFACE;
    if (CFEqual(req, IUnknownUUID) || CFEqual(req, kAudioServerPlugInDriverInterfaceUUID)) {
        pthread_mutex_lock(&gMutex); gRefCount++; pthread_mutex_unlock(&gMutex);
        *outInterface = gDriverRef;
        r = S_OK;
    }
    CFRelease(req);
    return r;
}

static ULONG AddRef(void* inDriver) {
    if (inDriver != gDriverRef) return 0;
    pthread_mutex_lock(&gMutex); ULONG r = ++gRefCount; pthread_mutex_unlock(&gMutex);
    return r;
}

static ULONG Release(void* inDriver) {
    if (inDriver != gDriverRef) return 0;
    pthread_mutex_lock(&gMutex); ULONG r = gRefCount > 0 ? --gRefCount : 0; pthread_mutex_unlock(&gMutex);
    return r;
}

static OSStatus Initialize(AudioServerPlugInDriverRef inDriver, AudioServerPlugInHostRef inHost) {
    if (inDriver != gDriverRef) return kAudioHardwareBadObjectError;
    gHost = inHost;
    mach_timebase_info_data_t tb;
    mach_timebase_info(&tb);
    Float64 hostClockFrequency = (Float64)tb.denom / (Float64)tb.numer * 1000000000.0;
    gHostClockFrequency = hostClockFrequency;
    gHostTicksPerFrame = hostClockFrequency / gSampleRate;
    for (int i = 0; i < kPairCount; i++) {
        gRings[i] = calloc(kRingFrames * kChannels, sizeof(float));
        gSide[i] = calloc(kRingFrames * kChannels, sizeof(float));
    }
    return 0;
}

static OSStatus CreateDevice(AudioServerPlugInDriverRef d, CFDictionaryRef c, const AudioServerPlugInClientInfo* i, AudioObjectID* o) { (void)d; (void)c; (void)i; (void)o; return kAudioHardwareUnsupportedOperationError; }
static OSStatus DestroyDevice(AudioServerPlugInDriverRef d, AudioObjectID o) { (void)d; (void)o; return kAudioHardwareUnsupportedOperationError; }
static OSStatus AddDeviceClient(AudioServerPlugInDriverRef d, AudioObjectID o, const AudioServerPlugInClientInfo* c) {
    (void)d;
    if (!c) return 0;
    pthread_mutex_lock(&gMutex);
    if (gClientCount < kMaxClients) {
        ClientEntry* e = &gClients[gClientCount];
        e->device = o;
        e->client = c->mClientID;
        e->bundle[0] = 0;
        if (c->mBundleID) CFStringGetCString(c->mBundleID, e->bundle, sizeof(e->bundle), kCFStringEncodingUTF8);
        atomic_store(&e->target, RouteFor(e->bundle));
        gClientCount++;
    }
    pthread_mutex_unlock(&gMutex);
    return 0;
}
static OSStatus RemoveDeviceClient(AudioServerPlugInDriverRef d, AudioObjectID o, const AudioServerPlugInClientInfo* c) {
    (void)d;
    if (!c) return 0;
    pthread_mutex_lock(&gMutex);
    for (UInt32 i = 0; i < gClientCount; i++) {
        if (gClients[i].device == o && gClients[i].client == c->mClientID) {
            // Keep the IO thread safe: move the last entry here (targets of other entries stay valid).
            gClients[i].device = gClients[gClientCount - 1].device;
            gClients[i].client = gClients[gClientCount - 1].client;
            memcpy(gClients[i].bundle, gClients[gClientCount - 1].bundle, sizeof(gClients[i].bundle));
            atomic_store(&gClients[i].target, atomic_load(&gClients[gClientCount - 1].target));
            gClientCount--;
            break;
        }
    }
    pthread_mutex_unlock(&gMutex);
    return 0;
}
/// Sample-rate change requested through SetPropertyData: the action carries the new rate in Hz.
static OSStatus PerformDeviceConfigurationChange(AudioServerPlugInDriverRef d, AudioObjectID o, UInt64 a, void* i) {
    (void)d; (void)o; (void)i;
    Float64 rate = (Float64)a;
    if (rate != kRate48 && rate != kRate96) return 0;
    pthread_mutex_lock(&gMutex);
    if (gSampleRate != rate) {
        gSampleRate = rate;
        gHostTicksPerFrame = gHostClockFrequency / gSampleRate;
        for (int k = 0; k < kPairCount; k++) {
            memset(gRings[k], 0, kRingFrames * kChannels * sizeof(float));
            memset(gSide[k], 0, kRingFrames * kChannels * sizeof(float));
        }
    }
    pthread_mutex_unlock(&gMutex);
    return 0;
}
static OSStatus AbortDeviceConfigurationChange(AudioServerPlugInDriverRef d, AudioObjectID o, UInt64 a, void* i) { (void)d; (void)o; (void)a; (void)i; return 0; }

#pragma mark - Properties

static Boolean HasProperty(AudioServerPlugInDriverRef inDriver, AudioObjectID obj, pid_t pid, const AudioObjectPropertyAddress* addr) {
    UInt32 size = 0;
    return GetPropertyDataSize(inDriver, obj, pid, addr, 0, NULL, &size) == 0;
}

static OSStatus IsPropertySettable(AudioServerPlugInDriverRef inDriver, AudioObjectID obj, pid_t pid, const AudioObjectPropertyAddress* addr, Boolean* outSettable) {
    if (!HasProperty(inDriver, obj, pid, addr)) return kAudioHardwareUnknownPropertyError;
    *outSettable = (obj == kPlugInID && (addr->mSelector == kRouteSelector || addr->mSelector == kVisibleSelector || addr->mSelector == kNamesSelector))
                || (DeviceIndex(obj) >= 0 && addr->mSelector == kAudioDevicePropertyNominalSampleRate)
                || (StreamIndex(obj) >= 0 && (addr->mSelector == kAudioStreamPropertyVirtualFormat || addr->mSelector == kAudioStreamPropertyPhysicalFormat));
    return 0;
}

static OSStatus PlugInSize(const AudioObjectPropertyAddress* a, UInt32* s) {
    switch (a->mSelector) {
        case kAudioObjectPropertyBaseClass: case kAudioObjectPropertyClass: *s = sizeof(AudioClassID); return 0;
        case kAudioObjectPropertyOwner: *s = sizeof(AudioObjectID); return 0;
        case kAudioObjectPropertyManufacturer: case kAudioPlugInPropertyResourceBundle: *s = sizeof(CFStringRef); return 0;
        case kAudioObjectPropertyOwnedObjects: case kAudioPlugInPropertyDeviceList: *s = PublishedCount() * sizeof(AudioObjectID); return 0;
        case kAudioPlugInPropertyTranslateUIDToDevice: *s = sizeof(AudioObjectID); return 0;
        case kAudioPlugInPropertyBoxList: *s = 0; return 0;
        case kAudioObjectPropertyCustomPropertyInfoList: *s = 3 * sizeof(AudioServerPlugInCustomPropertyInfo); return 0;
        case kRouteSelector: *s = sizeof(CFStringRef); return 0;
        case kVisibleSelector: *s = sizeof(CFNumberRef); return 0;
        case kNamesSelector: *s = sizeof(CFStringRef); return 0;
    }
    return kAudioHardwareUnknownPropertyError;
}

static OSStatus DeviceSize(int i, const AudioObjectPropertyAddress* a, UInt32* s) {
    bool isIn = kDevices[i].input;
    bool scopeOK = a->mScope == kAudioObjectPropertyScopeGlobal || (isIn ? a->mScope == kAudioObjectPropertyScopeInput : a->mScope == kAudioObjectPropertyScopeOutput);
    switch (a->mSelector) {
        case kAudioObjectPropertyBaseClass: case kAudioObjectPropertyClass: *s = sizeof(AudioClassID); return 0;
        case kAudioObjectPropertyOwner: *s = sizeof(AudioObjectID); return 0;
        case kAudioObjectPropertyName: case kAudioObjectPropertyManufacturer: case kAudioDevicePropertyDeviceUID:
        case kAudioDevicePropertyModelUID: case kAudioDevicePropertyConfigurationApplication: *s = sizeof(CFStringRef); return 0;
        case kAudioObjectPropertyOwnedObjects: case kAudioDevicePropertyStreams: *s = scopeOK ? sizeof(AudioObjectID) : 0; return 0;
        case kAudioObjectPropertyControlList: *s = 0; return 0;
        case kAudioDevicePropertyTransportType: case kAudioDevicePropertyClockDomain: case kAudioDevicePropertyDeviceIsAlive:
        case kAudioDevicePropertyDeviceIsRunning: case kAudioDevicePropertyDeviceCanBeDefaultDevice:
        case kAudioDevicePropertyDeviceCanBeDefaultSystemDevice: case kAudioDevicePropertyLatency:
        case kAudioDevicePropertySafetyOffset: case kAudioDevicePropertyZeroTimeStampPeriod:
        case kAudioDevicePropertyIsHidden: case kAudioDevicePropertyClockIsStable: *s = sizeof(UInt32); return 0;
        case kAudioDevicePropertyRelatedDevices: *s = sizeof(AudioObjectID); return 0;
        case kAudioDevicePropertyNominalSampleRate: *s = sizeof(Float64); return 0;
        case kAudioDevicePropertyAvailableNominalSampleRates: *s = 2 * sizeof(AudioValueRange); return 0;
        case kAudioDevicePropertyPreferredChannelsForStereo: *s = 2 * sizeof(UInt32); return 0;
        case kAudioDevicePropertyPreferredChannelLayout: *s = offsetof(AudioChannelLayout, mChannelDescriptions) + kChannels * sizeof(AudioChannelDescription); return 0;
    }
    return kAudioHardwareUnknownPropertyError;
}

static OSStatus StreamSize(const AudioObjectPropertyAddress* a, UInt32* s) {
    switch (a->mSelector) {
        case kAudioObjectPropertyBaseClass: case kAudioObjectPropertyClass: *s = sizeof(AudioClassID); return 0;
        case kAudioObjectPropertyOwner: *s = sizeof(AudioObjectID); return 0;
        case kAudioObjectPropertyOwnedObjects: *s = 0; return 0;
        case kAudioStreamPropertyIsActive: case kAudioStreamPropertyDirection: case kAudioStreamPropertyTerminalType:
        case kAudioStreamPropertyStartingChannel: case kAudioStreamPropertyLatency: *s = sizeof(UInt32); return 0;
        case kAudioStreamPropertyVirtualFormat: case kAudioStreamPropertyPhysicalFormat: *s = sizeof(AudioStreamBasicDescription); return 0;
        case kAudioStreamPropertyAvailableVirtualFormats: case kAudioStreamPropertyAvailablePhysicalFormats: *s = 2 * sizeof(AudioStreamRangedDescription); return 0;
    }
    return kAudioHardwareUnknownPropertyError;
}

static OSStatus GetPropertyDataSize(AudioServerPlugInDriverRef inDriver, AudioObjectID obj, pid_t pid, const AudioObjectPropertyAddress* a,
                                    UInt32 qs, const void* q, UInt32* outSize) {
    (void)inDriver; (void)pid; (void)qs; (void)q;
    if (obj == kPlugInID) return PlugInSize(a, outSize);
    int d = DeviceIndex(obj);
    if (d >= 0) return DeviceSize(d, a, outSize);
    if (StreamIndex(obj) >= 0) return StreamSize(a, outSize);
    return kAudioHardwareBadObjectError;
}

static OSStatus GetPropertyData(AudioServerPlugInDriverRef inDriver, AudioObjectID obj, pid_t pid, const AudioObjectPropertyAddress* a,
                                UInt32 qs, const void* q, UInt32 inDataSize, UInt32* outDataSize, void* outData) {
    (void)inDriver; (void)pid;
    if (obj == kPlugInID) {
        switch (a->mSelector) {
            case kAudioObjectPropertyBaseClass: WRITE(AudioClassID, kAudioObjectClassID); return 0;
            case kAudioObjectPropertyClass: WRITE(AudioClassID, kAudioPlugInClassID); return 0;
            case kAudioObjectPropertyOwner: WRITE(AudioObjectID, kAudioObjectUnknown); return 0;
            case kAudioObjectPropertyManufacturer: WRITE(CFStringRef, CFStr("NexusDeck")); return 0;
            case kAudioPlugInPropertyResourceBundle: WRITE(CFStringRef, CFStr("")); return 0;
            case kAudioObjectPropertyOwnedObjects:
            case kAudioPlugInPropertyDeviceList: {
                UInt32 max = inDataSize / sizeof(AudioObjectID), n = 0;
                for (UInt32 i = 0; i < kDeviceCount && n < max; i++) if (IsPublished(i)) ((AudioObjectID*)outData)[n++] = DeviceID(i);
                *outDataSize = n * sizeof(AudioObjectID);
                return 0;
            }
            case kAudioPlugInPropertyTranslateUIDToDevice: {
                if (qs != sizeof(CFStringRef) || !q) return kAudioHardwareBadPropertySizeError;
                CFStringRef uid = *(CFStringRef*)q;
                AudioObjectID found = kAudioObjectUnknown;
                for (UInt32 i = 0; i < kDeviceCount; i++) {
                    CFStringRef s = CFStr(kDevices[i].uid);
                    if (IsPublished(i) && CFStringCompare(uid, s, 0) == kCFCompareEqualTo) found = DeviceID(i);
                    CFRelease(s);
                }
                WRITE(AudioObjectID, found);
                return 0;
            }
            case kAudioPlugInPropertyBoxList: *outDataSize = 0; return 0;
            case kAudioObjectPropertyCustomPropertyInfoList: {
                if (inDataSize < 3 * sizeof(AudioServerPlugInCustomPropertyInfo)) return kAudioHardwareBadPropertySizeError;
                AudioServerPlugInCustomPropertyInfo* info = outData;
                info[0] = (AudioServerPlugInCustomPropertyInfo){ kRouteSelector, kAudioServerPlugInCustomPropertyDataTypeCFString, kAudioServerPlugInCustomPropertyDataTypeNone };
                info[1] = (AudioServerPlugInCustomPropertyInfo){ kVisibleSelector, kAudioServerPlugInCustomPropertyDataTypeCFPropertyList, kAudioServerPlugInCustomPropertyDataTypeNone };
                info[2] = (AudioServerPlugInCustomPropertyInfo){ kNamesSelector, kAudioServerPlugInCustomPropertyDataTypeCFString, kAudioServerPlugInCustomPropertyDataTypeNone };
                *outDataSize = 3 * sizeof(AudioServerPlugInCustomPropertyInfo);
                return 0;
            }
            case kNamesSelector: {
                if (inDataSize < sizeof(CFStringRef)) return kAudioHardwareBadPropertySizeError;
                pthread_mutex_lock(&gMutex);
                *(CFStringRef*)outData = gNamesString ? CFStringCreateCopy(NULL, gNamesString) : CFStr("");
                pthread_mutex_unlock(&gMutex);
                *outDataSize = sizeof(CFStringRef);
                return 0;
            }
            case kVisibleSelector: {
                if (inDataSize < sizeof(CFNumberRef)) return kAudioHardwareBadPropertySizeError;
                SInt64 v = atomic_load(&gVisibleMask);
                *(CFNumberRef*)outData = CFNumberCreate(NULL, kCFNumberSInt64Type, &v); *outDataSize = sizeof(CFNumberRef);
                return 0;
            }
            case kRouteSelector: {
                pthread_mutex_lock(&gMutex);
                CFStringRef v = gRouteString ? CFStringCreateCopy(NULL, gRouteString) : CFStr("");
                pthread_mutex_unlock(&gMutex);
                if (inDataSize < sizeof(CFStringRef)) { CFRelease(v); return kAudioHardwareBadPropertySizeError; }
                *(CFStringRef*)outData = v; *outDataSize = sizeof(CFStringRef);
                return 0;
            }
        }
        return kAudioHardwareUnknownPropertyError;
    }

    int d = DeviceIndex(obj);
    if (d >= 0) {
        const DeviceDef* dev = &kDevices[d];
        switch (a->mSelector) {
            case kAudioObjectPropertyBaseClass: WRITE(AudioClassID, kAudioObjectClassID); return 0;
            case kAudioObjectPropertyClass: WRITE(AudioClassID, kAudioDeviceClassID); return 0;
            case kAudioObjectPropertyOwner: WRITE(AudioObjectID, kPlugInID); return 0;
            case kAudioObjectPropertyName: {
                pthread_mutex_lock(&gMutex);
                // Visible devices are prefixed with their direction: "[AM-IN] Chat Mic", "[AM-OUT] System".
                char full[160];
                snprintf(full, sizeof(full), "%s%s", dev->hidden ? "" : (dev->input ? "[AM-IN] " : "[AM-OUT] "), gNames[d][0] ? gNames[d] : dev->name);
                CFStringRef n = CFStr(full);
                pthread_mutex_unlock(&gMutex);
                if (inDataSize < sizeof(CFStringRef)) { CFRelease(n); return kAudioHardwareBadPropertySizeError; }
                *(CFStringRef*)outData = n; *outDataSize = sizeof(CFStringRef);
                return 0;
            }
            case kAudioObjectPropertyManufacturer: WRITE(CFStringRef, CFStr("NexusDeck")); return 0;
            case kAudioDevicePropertyDeviceUID: WRITE(CFStringRef, CFStr(dev->uid)); return 0;
            case kAudioDevicePropertyModelUID: WRITE(CFStringRef, CFStr("NexusDeck.Model")); return 0;
            case kAudioDevicePropertyConfigurationApplication: WRITE(CFStringRef, CFStr("com.nexusdeck.lemarlab")); return 0;
            case kAudioDevicePropertyTransportType: WRITE(UInt32, kAudioDeviceTransportTypeUSB); return 0;
            case kAudioDevicePropertyRelatedDevices: WRITE(AudioObjectID, obj); return 0;
            case kAudioDevicePropertyClockDomain: WRITE(UInt32, 0); return 0;
            case kAudioDevicePropertyDeviceIsAlive: WRITE(UInt32, 1); return 0;
            case kAudioDevicePropertyDeviceIsRunning: WRITE(UInt32, gIOCount[d] > 0 ? 1 : 0); return 0;
            case kAudioDevicePropertyDeviceCanBeDefaultDevice: WRITE(UInt32, dev->hidden ? 0 : 1); return 0;
            case kAudioDevicePropertyDeviceCanBeDefaultSystemDevice: WRITE(UInt32, dev->hidden ? 0 : 1); return 0;
            case kAudioDevicePropertyLatency: WRITE(UInt32, kLatencyFrames); return 0;
            case kAudioDevicePropertySafetyOffset: WRITE(UInt32, kSafetyOffset); return 0;
            case kAudioDevicePropertyZeroTimeStampPeriod: WRITE(UInt32, kZeroPeriod); return 0;
            case kAudioDevicePropertyIsHidden: WRITE(UInt32, dev->hidden ? 1 : 0); return 0;
            case kAudioDevicePropertyClockIsStable: WRITE(UInt32, 1); return 0;
            case kAudioDevicePropertyNominalSampleRate: WRITE(Float64, gSampleRate); return 0;
            case kAudioDevicePropertyAvailableNominalSampleRates: {
                UInt32 n = inDataSize / sizeof(AudioValueRange);
                if (n > 2) n = 2;
                AudioValueRange* out = outData;
                if (n > 0) out[0] = (AudioValueRange){ kRate48, kRate48 };
                if (n > 1) out[1] = (AudioValueRange){ kRate96, kRate96 };
                *outDataSize = n * sizeof(AudioValueRange);
                return 0;
            }
            case kAudioObjectPropertyControlList: *outDataSize = 0; return 0;
            case kAudioObjectPropertyOwnedObjects:
            case kAudioDevicePropertyStreams: {
                bool scopeOK = a->mScope == kAudioObjectPropertyScopeGlobal || (dev->input ? a->mScope == kAudioObjectPropertyScopeInput : a->mScope == kAudioObjectPropertyScopeOutput);
                if (scopeOK && inDataSize >= sizeof(AudioObjectID)) { *(AudioObjectID*)outData = StreamID((UInt32)d); *outDataSize = sizeof(AudioObjectID); }
                else *outDataSize = 0;
                return 0;
            }
            case kAudioDevicePropertyPreferredChannelsForStereo: {
                if (inDataSize < 2 * sizeof(UInt32)) return kAudioHardwareBadPropertySizeError;
                ((UInt32*)outData)[0] = 1; ((UInt32*)outData)[1] = 2;
                *outDataSize = 2 * sizeof(UInt32);
                return 0;
            }
            case kAudioDevicePropertyPreferredChannelLayout: {
                UInt32 size = offsetof(AudioChannelLayout, mChannelDescriptions) + kChannels * sizeof(AudioChannelDescription);
                if (inDataSize < size) return kAudioHardwareBadPropertySizeError;
                AudioChannelLayout* l = (AudioChannelLayout*)outData;
                memset(l, 0, size);
                l->mChannelLayoutTag = kAudioChannelLayoutTag_UseChannelDescriptions;
                l->mNumberChannelDescriptions = kChannels;
                l->mChannelDescriptions[0].mChannelLabel = kAudioChannelLabel_Left;
                l->mChannelDescriptions[1].mChannelLabel = kAudioChannelLabel_Right;
                *outDataSize = size;
                return 0;
            }
        }
        return kAudioHardwareUnknownPropertyError;
    }

    int s = StreamIndex(obj);
    if (s >= 0) {
        switch (a->mSelector) {
            case kAudioObjectPropertyBaseClass: WRITE(AudioClassID, kAudioObjectClassID); return 0;
            case kAudioObjectPropertyClass: WRITE(AudioClassID, kAudioStreamClassID); return 0;
            case kAudioObjectPropertyOwner: WRITE(AudioObjectID, DeviceID((UInt32)s)); return 0;
            case kAudioObjectPropertyOwnedObjects: *outDataSize = 0; return 0;
            case kAudioStreamPropertyIsActive: WRITE(UInt32, 1); return 0;
            case kAudioStreamPropertyDirection: WRITE(UInt32, kDevices[s].input ? 1 : 0); return 0;
            case kAudioStreamPropertyTerminalType: WRITE(UInt32, kDevices[s].input ? kAudioStreamTerminalTypeMicrophone : kAudioStreamTerminalTypeSpeaker); return 0;
            case kAudioStreamPropertyStartingChannel: WRITE(UInt32, 1); return 0;
            case kAudioStreamPropertyLatency: WRITE(UInt32, 0); return 0;
            case kAudioStreamPropertyVirtualFormat:
            case kAudioStreamPropertyPhysicalFormat: WRITE(AudioStreamBasicDescription, Format()); return 0;
            case kAudioStreamPropertyAvailableVirtualFormats:
            case kAudioStreamPropertyAvailablePhysicalFormats: {
                UInt32 n = inDataSize / sizeof(AudioStreamRangedDescription);
                if (n > 2) n = 2;
                AudioStreamRangedDescription* out = outData;
                Float64 rates[2] = { kRate48, kRate96 };
                for (UInt32 k = 0; k < n; k++) {
                    out[k].mFormat = Format();
                    out[k].mFormat.mSampleRate = rates[k];
                    out[k].mSampleRateRange.mMinimum = rates[k];
                    out[k].mSampleRateRange.mMaximum = rates[k];
                }
                *outDataSize = n * sizeof(AudioStreamRangedDescription);
                return 0;
            }
        }
        return kAudioHardwareUnknownPropertyError;
    }
    return kAudioHardwareBadObjectError;
}

static OSStatus SetPropertyData(AudioServerPlugInDriverRef inDriver, AudioObjectID obj, pid_t pid, const AudioObjectPropertyAddress* a,
                                UInt32 qs, const void* q, UInt32 size, const void* data) {
    (void)inDriver; (void)pid; (void)qs; (void)q; (void)size;
    if (obj == kPlugInID && a->mSelector == kNamesSelector) {
        if (size < sizeof(CFStringRef)) return kAudioHardwareBadPropertySizeError;
        CFStringRef str = *(const CFStringRef*)data;
        if (!str || CFGetTypeID(str) != CFStringGetTypeID()) return kAudioHardwareIllegalOperationError;
        char old[64][128], buf[8192];
        pthread_mutex_lock(&gMutex);
        memcpy(old, gNames, sizeof(old));
        memset(gNames, 0, sizeof(gNames));
        if (gNamesString) CFRelease(gNamesString);
        gNamesString = CFStringCreateCopy(NULL, str);
        if (CFStringGetCString(str, buf, sizeof(buf), kCFStringEncodingUTF8)) {
            char* save = NULL;
            for (char* line = strtok_r(buf, "\n", &save); line; line = strtok_r(NULL, "\n", &save)) {
                char* eq = strchr(line, '=');
                if (!eq) continue;
                *eq = 0;
                int i = atoi(line);
                if (i < 0 || i >= (int)kDeviceCount || kDevices[i].hidden) continue;
                strncpy(gNames[i], eq + 1, sizeof(gNames[i]) - 1);
            }
        }
        pthread_mutex_unlock(&gMutex);
        if (gHost) {
            AudioObjectPropertyAddress name = { kAudioObjectPropertyName, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
            for (UInt32 i = 0; i < kDeviceCount; i++)
                if (strcmp(old[i], gNames[i]) != 0) gHost->PropertiesChanged(gHost, DeviceID(i), 1, &name);
        }
        return 0;
    }
    if (obj == kPlugInID && a->mSelector == kVisibleSelector) {
        if (size < sizeof(CFNumberRef)) return kAudioHardwareBadPropertySizeError;
        CFNumberRef num = *(const CFNumberRef*)data;
        SInt64 v = 0;
        if (!num || CFGetTypeID(num) != CFNumberGetTypeID() || !CFNumberGetValue(num, kCFNumberSInt64Type, &v)) return kAudioHardwareIllegalOperationError;
        UInt32 old = atomic_exchange(&gVisibleMask, (UInt32)v);
        if (old != (UInt32)v && gHost) {
            AudioObjectPropertyAddress changed[2] = {
                { kAudioPlugInPropertyDeviceList, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain },
                { kAudioObjectPropertyOwnedObjects, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain },
            };
            gHost->PropertiesChanged(gHost, kPlugInID, 2, changed);
        }
        return 0;
    }
    if (obj == kPlugInID && a->mSelector == kRouteSelector) {
        if (size < sizeof(CFStringRef)) return kAudioHardwareBadPropertySizeError;
        CFStringRef str = *(const CFStringRef*)data;
        pthread_mutex_lock(&gMutex);
        ApplyRoutes(str && CFGetTypeID(str) == CFStringGetTypeID() ? str : NULL);
        pthread_mutex_unlock(&gMutex);
        if (gHost) {
            AudioObjectPropertyAddress changed = { kRouteSelector, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
            gHost->PropertiesChanged(gHost, kPlugInID, 1, &changed);
        }
        return 0;
    }
    // 48 or 96 kHz, stereo float. A change applies to every device (they share one clock).
    Float64 rate = 0;
    if (StreamIndex(obj) >= 0 && (a->mSelector == kAudioStreamPropertyVirtualFormat || a->mSelector == kAudioStreamPropertyPhysicalFormat)) {
        const AudioStreamBasicDescription* f = data;
        if (f->mChannelsPerFrame != kChannels || (f->mSampleRate != kRate48 && f->mSampleRate != kRate96)) return kAudioDeviceUnsupportedFormatError;
        rate = f->mSampleRate;
    } else if (DeviceIndex(obj) >= 0 && a->mSelector == kAudioDevicePropertyNominalSampleRate) {
        rate = *(const Float64*)data;
        if (rate != kRate48 && rate != kRate96) return kAudioHardwareIllegalOperationError;
    } else {
        return kAudioHardwareUnknownPropertyError;
    }
    if (rate != gSampleRate && gHost) {
        for (UInt32 k = 0; k < kDeviceCount; k++) gHost->RequestDeviceConfigurationChange(gHost, DeviceID(k), (UInt64)rate, NULL);
    }
    return 0;
    return kAudioHardwareUnknownPropertyError;
}

#pragma mark - IO

static OSStatus StartIO(AudioServerPlugInDriverRef inDriver, AudioObjectID obj, UInt32 client) {
    (void)inDriver; (void)client;
    int d = DeviceIndex(obj);
    if (d < 0) return kAudioHardwareBadObjectError;
    pthread_mutex_lock(&gMutex);
    if (gIOCount[d]++ == 0) {
        if (gRunningDevices++ == 0) gAnchorHostTime = mach_absolute_time();
        gTimestampCounter[d] = 0;
    }
    pthread_mutex_unlock(&gMutex);
    return 0;
}

static OSStatus StopIO(AudioServerPlugInDriverRef inDriver, AudioObjectID obj, UInt32 client) {
    (void)inDriver; (void)client;
    int d = DeviceIndex(obj);
    if (d < 0) return kAudioHardwareBadObjectError;
    pthread_mutex_lock(&gMutex);
    if (gIOCount[d] > 0 && --gIOCount[d] == 0) {
        if (gRunningDevices > 0) gRunningDevices--;
        if (!kDevices[d].input) memset(gRings[kDevices[d].pair], 0, kRingFrames * kChannels * sizeof(float));
        else memset(gSide[kDevices[d].pair], 0, kRingFrames * kChannels * sizeof(float));
    }
    pthread_mutex_unlock(&gMutex);
    return 0;
}

/// All devices share one clock anchored at the first StartIO, so paired devices stay sample-aligned.
static OSStatus GetZeroTimeStamp(AudioServerPlugInDriverRef inDriver, AudioObjectID obj, UInt32 client, Float64* outSampleTime, UInt64* outHostTime, UInt64* outSeed) {
    (void)inDriver; (void)client;
    if (DeviceIndex(obj) < 0) return kAudioHardwareBadObjectError;
    UInt64 now = mach_absolute_time();
    Float64 ticksPerPeriod = gHostTicksPerFrame * kZeroPeriod;
    UInt64 periods = (UInt64)((Float64)(now - gAnchorHostTime) / ticksPerPeriod);
    *outSampleTime = (Float64)(periods * kZeroPeriod);
    *outHostTime = gAnchorHostTime + (UInt64)((Float64)periods * ticksPerPeriod);
    *outSeed = 1;
    return 0;
}

static OSStatus WillDoIOOperation(AudioServerPlugInDriverRef inDriver, AudioObjectID obj, UInt32 client, UInt32 op, Boolean* outWill, Boolean* outInPlace) {
    (void)inDriver; (void)client;
    int d = DeviceIndex(obj);
    if (d < 0) return kAudioHardwareBadObjectError;
    *outWill = (kDevices[d].input && op == kAudioServerPlugInIOOperationReadInput)
            || (!kDevices[d].input && op == kAudioServerPlugInIOOperationWriteMix)
            || (!kDevices[d].input && !kDevices[d].hidden && op == kAudioServerPlugInIOOperationProcessOutput);
    *outInPlace = true;
    return 0;
}

static OSStatus BeginIOOperation(AudioServerPlugInDriverRef d, AudioObjectID o, UInt32 c, UInt32 op, UInt32 n, const AudioServerPlugInIOCycleInfo* i) { (void)d; (void)o; (void)c; (void)op; (void)n; (void)i; return 0; }
static OSStatus EndIOOperation(AudioServerPlugInDriverRef d, AudioObjectID o, UInt32 c, UInt32 op, UInt32 n, const AudioServerPlugInIOCycleInfo* i) { (void)d; (void)o; (void)c; (void)op; (void)n; (void)i; return 0; }

static OSStatus DoIOOperation(AudioServerPlugInDriverRef inDriver, AudioObjectID obj, AudioObjectID stream, UInt32 client, UInt32 op,
                              UInt32 frames, const AudioServerPlugInIOCycleInfo* cycle, void* mainBuffer, void* secondary) {
    (void)inDriver; (void)stream; (void)client; (void)secondary;
    int d = DeviceIndex(obj);
    if (d < 0) return kAudioHardwareBadObjectError;
    float* ring = gRings[kDevices[d].pair];
    float* buf = mainBuffer;
    if (op == kAudioServerPlugInIOOperationProcessOutput) {
        // One client's audio before the device mix: move it to the pair it is routed to.
        int target = ClientTarget(obj, client);
        if (target < 0 || target == kDevices[d].pair) return 0;
        float* side = gSide[target];
        UInt64 start = (UInt64)cycle->mOutputTime.mSampleTime;
        for (UInt32 f = 0; f < frames; f++) {
            UInt32 idx = (UInt32)((start + f) & (kRingFrames - 1)) * kChannels;
            for (UInt32 c = 0; c < kChannels; c++) side[idx + c] += buf[f * kChannels + c];
        }
        memset(buf, 0, frames * kChannels * sizeof(float));
        return 0;
    }
    if (op == kAudioServerPlugInIOOperationWriteMix) {
        UInt64 start = (UInt64)cycle->mOutputTime.mSampleTime;
        for (UInt32 f = 0; f < frames; f++) {
            UInt32 idx = (UInt32)((start + f) & (kRingFrames - 1)) * kChannels;
            for (UInt32 c = 0; c < kChannels; c++) ring[idx + c] = buf[f * kChannels + c];
        }
    } else if (op == kAudioServerPlugInIOOperationReadInput) {
        UInt64 start = (UInt64)cycle->mInputTime.mSampleTime;
        for (UInt32 f = 0; f < frames; f++) {
            UInt32 idx = (UInt32)((start + f) & (kRingFrames - 1)) * kChannels;
            float* side = gSide[kDevices[d].pair];
            for (UInt32 c = 0; c < kChannels; c++) {
                buf[f * kChannels + c] = ring[idx + c] + side[idx + c];
                ring[idx + c] = 0; side[idx + c] = 0;
            }
        }
    }
    return 0;
}
