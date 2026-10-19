#import "include/TTTextContentStorage.h"
#import "TTTextParagraph.h"
#if TARGET_OS_IOS
#include <algorithm>
#include <vector>

namespace {
constexpr NSUInteger maximumElementLength = 4096;
struct Segment {
    NSRange range;
    NSUInteger separatorLength;
    TTTextParagraph *paragraph = nil;
    bool dirty = true;
};
}

@implementation TTTextContentStorage {
    std::vector<Segment> _segments;
    NSMutableArray<NSTextParagraph *> *_retiredParagraphs;
}
- (NSTextRange *)textRangeForRange:(NSRange)range {
    id<NSTextLocation> start = [self locationFromLocation:self.documentRange.location withOffset:range.location];
    id<NSTextLocation> end = [self locationFromLocation:start withOffset:range.length];
    NSAssert(start && end, @"Source range must map to TextKit locations");
    return [[NSTextRange alloc] initWithLocation:start endLocation:end];
}
- (NSUInteger)segmentIndexAtOffset:(NSUInteger)offset {
    const auto it = std::upper_bound(_segments.begin(), _segments.end(), offset,
        [](NSUInteger value, const Segment &segment) { return value < segment.range.location; });
    return it == _segments.begin() ? 0 : std::distance(_segments.begin(), it) - 1;
}
- (void)retireParagraph:(NSTextParagraph *)paragraph {
    if (!paragraph) return;
    if (!_retiredParagraphs) _retiredParagraphs = [NSMutableArray new];
    // TextKit tracks elements weakly. Keep removed elements alive until their
    // fragments have been explicitly invalidated in processEditing below.
    [_retiredParagraphs addObject:paragraph];
}
- (std::vector<Segment>)segmentsForRange:(NSRange)range {
    NSString *text = [self.textStorage.string substringWithRange:range];
    std::vector<Segment> result;
    for (NSUInteger cursor = 0; cursor < text.length;) {
        NSUInteger paragraphEnd = 0, contentEnd = 0;
        [text getParagraphStart:nullptr end:&paragraphEnd contentsEnd:&contentEnd forRange:NSMakeRange(cursor, 0)];
        while (cursor < paragraphEnd) {
            NSUInteger end = std::min(cursor + maximumElementLength, paragraphEnd);
            if (end < paragraphEnd)
                end = NSMaxRange([text rangeOfComposedCharacterSequenceAtIndex:end - 1]);
            const NSUInteger separatorLength = end == paragraphEnd ? paragraphEnd - contentEnd : 0;
            result.push_back({NSMakeRange(range.location + cursor, end - cursor), separatorLength});
            cursor = end;
        }
    }
    if (!self.textStorage.length) result.push_back({NSMakeRange(0, 0), 0});
    return result;
}
- (void)finishReplacementInRange:(NSRange)range replacementLength:(NSUInteger)length {
    NSAssert(NSThread.isMainThread, @"Primitive replacements must remain on the main thread");
    const NSInteger delta = (NSInteger)length - (NSInteger)range.length;
    NSUInteger first = 0, last = 0, start = 0, end = self.textStorage.length;
    if (!_segments.empty()) {
        first = [self segmentIndexAtOffset:range.location];
        if (first) --first;
        last = std::min([self segmentIndexAtOffset:NSMaxRange(range)] + 1, _segments.size() - 1);
        start = _segments[first].range.location;
        end = NSMaxRange(_segments[last].range) + delta;
        // An edit can join a grapheme across an old boundary (emoji/combining
        // marks/CRLF). Extend to an unchanged safe boundary before re-slicing.
        while (end && end < self.textStorage.length && last + 1 < _segments.size()
               && NSMaxRange([self.textStorage.string rangeOfComposedCharacterSequenceAtIndex:end - 1]) > end) {
            ++last;
            end = NSMaxRange(_segments[last].range) + delta;
        }
        for (NSUInteger index = first; index <= last; ++index)
            [self retireParagraph:_segments[index].paragraph];
        _segments.erase(_segments.begin() + first, _segments.begin() + last + 1);
        for (NSUInteger index = first; index < _segments.size(); ++index) {
            auto &segment = _segments[index];
            segment.range.location += delta;
            if (segment.paragraph) segment.paragraph.elementRange = [self textRangeForRange:segment.range];
        }
    }
    auto replacements = [self segmentsForRange:NSMakeRange(start, end - start)];
    _segments.insert(_segments.begin() + first, replacements.begin(), replacements.end());
}
- (void)processEditingForTextStorage:(NSTextStorage *)storage edited:(NSTextStorageEditActions)mask
                              range:(NSRange)range changeInLength:(NSInteger)delta invalidatedRange:(NSRange)invalidatedRange {
    NSAssert(NSThread.isMainThread, @"Layout publication must remain on the main thread");
    // Preserve NSTextContentStorage's entire editing transaction, including
    // its input/paragraph caches and selection adjustment. Only the element
    // mapping is custom. Surviving elements keep their identity and fragments.
    if (mask & NSTextStorageEditedAttributes) {
        for (auto &segment : _segments) {
            if (NSIntersectionRange(segment.range, invalidatedRange).length) {
                [self retireParagraph:segment.paragraph];
                segment.paragraph = nil;
                segment.dirty = true;
            }
        }
    }
    [super processEditingForTextStorage:storage edited:mask range:range
                        changeInLength:delta invalidatedRange:invalidatedRange];
    for (auto &segment : _segments) {
        if (!segment.dirty) continue;
        NSTextRange *textRange = [self textRangeForRange:segment.range];
        for (NSTextLayoutManager *layout in self.textLayoutManagers)
            [layout invalidateLayoutForRange:textRange];
        segment.dirty = false;
    }
    [_retiredParagraphs removeAllObjects];
}
- (id<NSTextLocation>)enumerateTextElementsFromLocation:(id<NSTextLocation>)location
                                               options:(NSTextContentManagerEnumerationOptions)options
                                            usingBlock:(BOOL (NS_NOESCAPE ^)(NSTextElement *))block {
    const BOOL reverse = options & NSTextContentManagerEnumerationOptionsReverse;
    const NSInteger size = self.textStorage.length;
    NSInteger offset = location ? [self offsetFromLocation:self.documentRange.location toLocation:location]
                               : reverse ? size : 0;
    if (reverse) --offset;
    if (offset < 0 || offset > size || (offset == size && size)) return nil;
    if (_segments.empty()) _segments = [self segmentsForRange:NSMakeRange(0, size)];
    NSInteger index = [self segmentIndexAtOffset:offset];
    id<NSTextLocation> edge = nil;
    while (index >= 0 && index < (NSInteger)_segments.size()) {
        auto &segment = _segments[index];
        if (!segment.paragraph) {
            segment.paragraph = [[TTTextParagraph alloc]
                initWithAttributedString:[self.textStorage attributedSubstringFromRange:segment.range]
                         separatorLength:segment.separatorLength];
            segment.paragraph.textContentManager = self;
            segment.paragraph.elementRange = [self textRangeForRange:segment.range];
        }
        edge = reverse ? segment.paragraph.elementRange.location : segment.paragraph.elementRange.endLocation;
        if (!block(segment.paragraph)) break;
        index += reverse ? -1 : 1;
    }
    return edge;
}
- (NSAttributedString *)attributedStringForTextElement:(NSTextElement *)element {
    return [element isKindOfClass:NSTextParagraph.class] ? ((NSTextParagraph *)element).attributedString : nil;
}
@end
#endif
