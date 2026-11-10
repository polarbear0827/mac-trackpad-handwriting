#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 系統內建的 CoreHandwriting（iPad Scribble、備忘錄手寫用的同一套引擎）是否可用。
BOOL AHIsAvailable(void);

/// 用 Apple 的手寫引擎辨識筆畫。
/// xs / ys：所有點依序排列（單位約為 pt，y 向下）；strokeEnds[i] 為第 i 筆的結束索引（不含）。
/// 回傳候選字串（最可能的排第一）；引擎不可用時回傳 nil。
NSArray<NSString *> * _Nullable AHRecognize(const double *xs,
                                            const double *ys,
                                            const NSInteger *strokeEnds,
                                            NSInteger strokeCount,
                                            NSString *localeIdentifier,
                                            NSInteger maxResults);

NS_ASSUME_NONNULL_END
