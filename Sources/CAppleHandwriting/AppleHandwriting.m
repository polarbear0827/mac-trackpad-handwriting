#import "AppleHandwriting.h"
#import <CoreGraphics/CoreGraphics.h>
#import <dlfcn.h>
#import <objc/message.h>

// CoreHandwriting 是私有框架：用 dlopen + Objective-C runtime 呼叫，不直接連結。
// 若未來 macOS 移除或改了介面，AHIsAvailable() 會回傳 NO，App 改用 Vision。

static NSString *const kFrameworkPath = @"/System/Library/PrivateFrameworks/CoreHandwriting.framework/CoreHandwriting";

// 辨識模式 1：完整候選清單（實測繁中 7/7、每字約 5ms）
static const int kRecognitionMode = 1;

static BOOL loadFramework(void) {
    static BOOL loaded = NO;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        loaded = dlopen(kFrameworkPath.fileSystemRepresentation, RTLD_NOW) != NULL;
    });
    return loaded;
}

BOOL AHIsAvailable(void) {
    if (!loadFramework()) return NO;
    Class recognizer = NSClassFromString(@"CHRecognizer");
    Class drawing = NSClassFromString(@"CHDrawing");
    return recognizer && drawing
        && [recognizer instancesRespondToSelector:NSSelectorFromString(@"initWithMode:locale:")]
        && [recognizer instancesRespondToSelector:NSSelectorFromString(@"recognitionResultsForDrawing:options:")]
        && [drawing instancesRespondToSelector:NSSelectorFromString(@"addPoint:")]
        && [drawing instancesRespondToSelector:NSSelectorFromString(@"endStroke")];
}

/// 每個語系建立一次辨識器（建立要載入模型，之後重複使用）
static id recognizerForLocale(NSString *identifier) {
    static NSMutableDictionary<NSString *, id> *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSMutableDictionary dictionary]; });

    @synchronized (cache) {
        id r = cache[identifier];
        if (r) return r;
        id alloc = [NSClassFromString(@"CHRecognizer") alloc];
        r = ((id (*)(id, SEL, int, id))objc_msgSend)(alloc, NSSelectorFromString(@"initWithMode:locale:"),
                                                     kRecognitionMode, [NSLocale localeWithLocaleIdentifier:identifier]);
        if (r) cache[identifier] = r;
        return r;
    }
}

NSArray<NSString *> *AHRecognize(const double *xs, const double *ys, const NSInteger *strokeEnds,
                                 NSInteger strokeCount, NSString *localeIdentifier, NSInteger maxResults) {
    if (!AHIsAvailable()) return nil;
    id recognizer = recognizerForLocale(localeIdentifier);
    if (!recognizer) return nil;

    id drawing = [NSClassFromString(@"CHDrawing") new];
    SEL addPoint = NSSelectorFromString(@"addPoint:");
    SEL endStroke = NSSelectorFromString(@"endStroke");
    NSInteger start = 0;
    for (NSInteger s = 0; s < strokeCount; s++) {
        for (NSInteger i = start; i < strokeEnds[s]; i++) {
            ((void (*)(id, SEL, CGPoint))objc_msgSend)(drawing, addPoint, CGPointMake(xs[i], ys[i]));
        }
        ((void (*)(id, SEL))objc_msgSend)(drawing, endStroke);
        start = strokeEnds[s];
    }

    id results;
    @synchronized (recognizer) {
        results = ((id (*)(id, SEL, id, id))objc_msgSend)(recognizer,
                    NSSelectorFromString(@"recognitionResultsForDrawing:options:"), drawing, nil);
    }
    if (![results isKindOfClass:[NSArray class]]) return @[];

    NSMutableArray<NSString *> *out = [NSMutableArray array];
    SEL stringSel = NSSelectorFromString(@"string");
    for (id r in (NSArray *)results) {
        if (![r respondsToSelector:stringSel]) continue;
        NSString *s = ((id (*)(id, SEL))objc_msgSend)(r, stringSel);
        if (s.length > 0 && ![out containsObject:s]) [out addObject:s];
        if ((NSInteger)out.count >= maxResults) break;
    }
    return out;
}
