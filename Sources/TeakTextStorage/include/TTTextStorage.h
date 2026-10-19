#import <TargetConditionals.h>
#if TARGET_OS_IOS
#import <UIKit/UIKit.h>
#import "TTTextSnapshot.h"

NS_ASSUME_NONNULL_BEGIN
/// UIKit owns this mutable adapter on the main thread. Snapshots remain immutable.
@interface TTTextStorage : NSTextStorage
@property(nonatomic, readonly) TTTextSnapshot *snapshot;
/// Each primitive edit, after commit but before notifying TextKit. Range uses old coordinates.
/// Invoked synchronously on the main thread, including edits coalesced by begin/endEditing.
@property(nonatomic, copy, nullable) void (^didReplaceCharacters)(NSRange range, NSUInteger replacementLength);
- (instancetype)initWithAttributes:(NSDictionary<NSAttributedStringKey, id> *)attributes;
- (void)installSnapshot:(TTTextSnapshot *)snapshot;
@end
NS_ASSUME_NONNULL_END
#endif
