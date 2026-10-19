#import <TargetConditionals.h>
#if TARGET_OS_IOS
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
@interface TTTextParagraph : NSTextParagraph
- (instancetype)initWithAttributedString:(NSAttributedString *)string
                        separatorLength:(NSUInteger)separatorLength;
@end
NS_ASSUME_NONNULL_END
#endif
