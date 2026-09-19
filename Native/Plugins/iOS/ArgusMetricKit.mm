// ArgusMetricKit.mm — iOS ground-truth hang reader for Argus.
//
// Reads MetricKit's persisted MXHangDiagnostic payloads (MXMetricManager
// pastDiagnosticPayloads, iOS 14+) and returns them as JSON for the C#
// NativeAnrBridge to fold into the next session. MetricKit only delivers on a
// later launch, so these are "recovered from prior run" by nature.
//
// We read crash-class diagnostics too? No — explicitly ONLY hangDiagnostics.
// Crashes are Crashlytics' job; Argus owns user-visible freezes. MetricKit
// installs no in-process signal handler, so there is no SIGQUIT contention.
//
// Best-effort: any failure returns {"items":[]}. The returned C string is
// strdup'd (caller marshals a copy); the tiny per-launch leak is acceptable for
// a once-at-startup drain.
//
// Ships as source under Assets/Argus/Plugins/iOS/; Xcode compiles it into the
// player. The C# bridge stays in Argus.Runtime.dll and calls
// ArgusNative_DrainHangsJson via [DllImport("__Internal")].

#import <Foundation/Foundation.h>

// RE-ENABLED. This file failed several iOS archives with a clang diagnostic that
// xcpretty discarded (only "CompileC ArgusMetricKit.o failed" survived) and that
// did NOT reproduce in isolation. Three separate real bugs came out of it:
//   1. MXCallStackTree's selector is JSONRepresentation, not jsonRepresentation.
//   2. -Wmissing-prototypes and the GNU ?: extension are errors in this target
//      (warnings-as-errors).
//   3. Unity builds UnityFramework with Objective-C EXCEPTIONS DISABLED, so the
//      @try/@catch this file used were a hard error. That is the one that hid
//      the longest: clang defaults to -fobjc-exceptions, so every standalone
//      compile passed while the Unity target kept failing.
// The body is now exception-free (see the note in the function) and enabled
// again. To reproduce this target's conditions locally, pass -fno-objc-exceptions.
#if __has_include(<MetricKit/MetricKit.h>)
#import <MetricKit/MetricKit.h>
#define ARGUS_HAS_METRICKIT 1
#endif

// Forward prototype: the iOS archive compiles UnityFramework with warnings-as-errors,
// which promotes -Wmissing-prototypes. This symbol is called from C# via
// [DllImport("__Internal")], so it must stay extern "C" — declaring it here first
// satisfies the prototype check without making it static.
extern "C" const char *ArgusNative_DrainHangsJson(void);

// Cap the call-stack excerpt so a deep tree can't bloat the capture payload.
#ifdef ARGUS_HAS_METRICKIT
static const NSUInteger kArgusMaxTraceChars = 16 * 1024;
#endif

#ifdef ARGUS_HAS_METRICKIT
static NSString *ArgusTruncate(NSString *s) {
    if (s == nil) return nil;
    if (s.length <= kArgusMaxTraceChars) return s;
    return [s substringToIndex:kArgusMaxTraceChars];
}
#endif

extern "C" const char *ArgusNative_DrainHangsJson(void) {
    // NO @try/@catch ANYWHERE IN THIS FILE.
    //
    // Unity compiles UnityFramework with Objective-C exceptions DISABLED, so
    // `@try` is a hard compile error: "cannot use '@try' with Objective-C
    // exceptions disabled". This cost several iOS releases to find, because the
    // file compiles fine in isolation with clang's default -fobjc-exceptions —
    // it only fails inside Unity's target. Defensive nil-checks below do the same
    // job without needing exceptions; keep it that way.
    NSMutableArray *items = [NSMutableArray array];

#ifdef ARGUS_HAS_METRICKIT
    if (@available(iOS 14.0, *)) {
        MXMetricManager *manager = MXMetricManager.sharedManager;
        NSArray<MXDiagnosticPayload *> *payloads = manager ? [manager pastDiagnosticPayloads] : nil;
        for (MXDiagnosticPayload *payload in payloads) {
            NSArray<MXHangDiagnostic *> *hangs = payload.hangDiagnostics;
            if (hangs == nil) continue;

            NSTimeInterval whenUnix = payload.timeStampEnd
                ? [payload.timeStampEnd timeIntervalSince1970]
                : 0;

            for (MXHangDiagnostic *hang in hangs) {
                if (hang == nil) continue;

                // hangDuration is a time measurement and milliseconds is a time
                // unit, so the conversion is well-defined; the nil check covers a
                // payload that simply carries no duration.
                double stallMs = 0;
                NSMeasurement *duration = hang.hangDuration;
                if (duration != nil) {
                    NSMeasurement *ms = [duration measurementByConvertingToUnit:NSUnitDuration.milliseconds];
                    if (ms != nil) stallMs = ms.doubleValue;
                }

                // JSONRepresentation returns nil rather than throwing.
                NSString *trace = nil;
                MXCallStackTree *tree = hang.callStackTree;
                NSData *json = tree ? [tree JSONRepresentation] : nil;
                if (json != nil) {
                    trace = ArgusTruncate([[NSString alloc] initWithData:json
                                                               encoding:NSUTF8StringEncoding]);
                }

                [items addObject:@{
                    @"atUnixTime"   : @(whenUnix),
                    @"stallMs"      : @(stallMs),
                    @"source"       : @"ios_metrickit",
                    @"traceExcerpt" : (trace != nil ? (id)trace : (id)[NSNull null]),
                }];
            }
        }
    }
#endif

    NSString *result = @"{\"items\":[]}";
    NSDictionary *root = @{ @"items" : items };
    // +isValidJSONObject is the exception-free way to ask this: dataWithJSONObject
    // raises NSInvalidArgumentException on an unserialisable object, and with
    // exceptions disabled that would terminate the app we are profiling.
    if ([NSJSONSerialization isValidJSONObject:root]) {
        NSData *data = [NSJSONSerialization dataWithJSONObject:root options:0 error:nil];
        if (data != nil) {
            NSString *encoded = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            if (encoded != nil) result = encoded;
        }
    }

    return strdup(result.UTF8String);
}

