#import "TTTextParagraph.h"
#if TARGET_OS_IOS
@implementation TTTextParagraph {
    NSUInteger _separatorLength;
}
- (instancetype)initWithAttributedString:(NSAttributedString *)string separatorLength:(NSUInteger)separatorLength {
    self = [super initWithAttributedString:string];
    if (self) _separatorLength = separatorLength;
    return self;
}
- (NSTextRange *)paragraphContentRange {
    NSTextRange *range = self.elementRange;
    if (!range) return nil;
    id<NSTextLocation> end = [self.textContentManager locationFromLocation:range.endLocation
                                                            withOffset:-(NSInteger)_separatorLength];
    return end ? [[NSTextRange alloc] initWithLocation:range.location endLocation:end] : nil;
}
- (NSTextRange *)paragraphSeparatorRange {
    NSTextRange *content = self.paragraphContentRange;
    return content ? [[NSTextRange alloc] initWithLocation:content.endLocation
                                             endLocation:self.elementRange.endLocation] : nil;
}
@end
#endif
