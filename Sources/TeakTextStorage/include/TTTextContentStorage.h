#import <TargetConditionals.h>
#if TARGET_OS_IOS
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
/// UTF-16 source coordinates with bounded layout elements. No synthetic characters.
/// All mutations and TextKit access belong to the main thread.
@interface TTTextContentStorage : NSTextContentStorage
/// Called for every primitive source replacement, after the source commit and
/// before NSTextStorage's edited notification, including snapshot installation.
- (void)finishReplacementInRange:(NSRange)range replacementLength:(NSUInteger)length;
@end
NS_ASSUME_NONNULL_END
#endif
