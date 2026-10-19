#import "include/TTTextStorage.h"
#if TARGET_OS_IOS
#include <vector>
#include <algorithm>

namespace {
struct AttributeRun {
    NSRange range;
    NSDictionary<NSAttributedStringKey, id> *attributes;
};
void append(std::vector<AttributeRun> &runs, NSRange range, NSDictionary *attributes) {
    if (!range.length) return;
    if (!runs.empty() && NSMaxRange(runs.back().range) == range.location
        && [runs.back().attributes isEqualToDictionary:attributes])
        runs.back().range.length += range.length;
    else runs.push_back({range, attributes});
}
}

@implementation TTTextStorage {
    TTTextSnapshot *_snapshot;
    // UIKit/Core NLP require a Foundation-native string for their fast paths.
    // This mirror and the canonical immutable snapshot commit synchronously
    // before the replacement callback or any NSTextStorage notification.
    NSMutableString *_nativeText;
    NSDictionary<NSAttributedStringKey, id> *_defaults;
    std::vector<AttributeRun> _runs;
}
- (instancetype)initWithAttributes:(NSDictionary<NSAttributedStringKey,id> *)attributes {
    self = [super init];
    if (self) {
        _defaults = [attributes copy];
        _snapshot = [TTTextSnapshot snapshotWithString:@""];
        _nativeText = [NSMutableString new];
    }
    return self;
}
- (NSString *)string { return _nativeText; }
- (NSUInteger)length { return _snapshot.length; }
- (TTTextSnapshot *)snapshot { return _snapshot; }
- (NSAttributedString *)attributedSubstringFromRange:(NSRange)range {
    if (range.location > self.length || range.length > self.length - range.location)
        [NSException raise:NSRangeException format:@"Text range outside document"];
    // TextKit retains this immutable paragraph for Core Text shaping. Keep its
    // string Foundation-native, including UIKit's word/paragraph tokenizer.
    NSMutableAttributedString *result = [[NSMutableAttributedString alloc]
        initWithString:[_nativeText substringWithRange:range] attributes:_defaults];
    if (!range.length) return result;
    auto it = std::upper_bound(_runs.begin(), _runs.end(), range.location,
        [](NSUInteger index, const AttributeRun &run) { return index < run.range.location; });
    if (it != _runs.begin()) --it;
    for (; it != _runs.end() && it->range.location < NSMaxRange(range); ++it) {
        const NSRange intersection = NSIntersectionRange(it->range, range);
        if (intersection.length)
            [result setAttributes:it->attributes
                            range:NSMakeRange(intersection.location - range.location, intersection.length)];
    }
    return [result copy];
}
- (NSDictionary<NSAttributedStringKey,id> *)attributesAtIndex:(NSUInteger)location effectiveRange:(NSRangePointer)range {
    if (!self.length) { if (range) *range = NSMakeRange(0, 0); return _defaults; }
    if (location >= self.length) [NSException raise:NSRangeException format:@"Attribute index outside document"];
    const auto it = std::upper_bound(_runs.begin(), _runs.end(), location,
                                    [](NSUInteger index, const AttributeRun &run) { return index < run.range.location; });
    const auto &run = *std::prev(it);
    if (range) *range = run.range;
    return run.attributes;
}
- (void)replaceCharactersInRange:(NSRange)range withString:(NSString *)string {
    NSAssert(NSThread.isMainThread, @"Mutable text storage must remain on the main thread");
    const NSUInteger replacementLength = string.length;
    NSDictionary *inherited = self.length
        ? [self attributesAtIndex:std::min(range.location, self.length - 1) effectiveRange:nullptr] : _defaults;
    TTTextSnapshot *next = [_snapshot replacingRange:range withString:string];
    const NSInteger delta = (NSInteger)replacementLength - (NSInteger)range.length;
    std::vector<AttributeRun> runs;
    for (const auto &run : _runs) {
        if (run.range.location < range.location) {
            const auto end = std::min(NSMaxRange(run.range), range.location);
            append(runs, NSMakeRange(run.range.location, end - run.range.location), run.attributes);
        }
    }
    append(runs, NSMakeRange(range.location, replacementLength), inherited);
    for (const auto &run : _runs) {
        if (NSMaxRange(run.range) > NSMaxRange(range)) {
            const auto start = std::max(run.range.location, NSMaxRange(range));
            append(runs, NSMakeRange(start + delta, NSMaxRange(run.range) - start), run.attributes);
        }
    }
    _runs = std::move(runs);
    [_nativeText replaceCharactersInRange:range withString:string];
    _snapshot = next;
    if (_didReplaceCharacters) _didReplaceCharacters(range, replacementLength);
    [self edited:NSTextStorageEditedCharacters | NSTextStorageEditedAttributes range:range changeInLength:delta];
}
- (void)setAttributes:(NSDictionary<NSAttributedStringKey,id> *)attributes range:(NSRange)range {
    NSAssert(NSThread.isMainThread, @"Mutable text storage must remain on the main thread");
    if (range.location > self.length || range.length > self.length - range.location)
        [NSException raise:NSRangeException format:@"Attribute range outside document"];
    if (!range.length) return;
    std::vector<AttributeRun> runs;
    for (const auto &run : _runs) {
        if (run.range.location < range.location) {
            const auto end = std::min(NSMaxRange(run.range), range.location);
            append(runs, NSMakeRange(run.range.location, end - run.range.location), run.attributes);
        }
    }
    append(runs, range, attributes ?: @{});
    for (const auto &run : _runs) {
        if (NSMaxRange(run.range) > NSMaxRange(range)) {
            const auto start = std::max(run.range.location, NSMaxRange(range));
            append(runs, NSMakeRange(start, NSMaxRange(run.range) - start), run.attributes);
        }
    }
    _runs = std::move(runs);
    [self edited:NSTextStorageEditedAttributes range:range changeInLength:0];
}
- (void)installSnapshot:(TTTextSnapshot *)snapshot {
    NSAssert(NSThread.isMainThread, @"Mutable text storage must remain on the main thread");
    const NSUInteger previousLength = self.length;
    [self beginEditing];
    [_nativeText setString:[snapshot substringInRange:NSMakeRange(0, snapshot.length)]];
    _snapshot = snapshot;
    _runs.clear();
    append(_runs, NSMakeRange(0, snapshot.length), _defaults);
    if (_didReplaceCharacters) _didReplaceCharacters(NSMakeRange(0, previousLength), snapshot.length);
    [self edited:NSTextStorageEditedCharacters | NSTextStorageEditedAttributes
           range:NSMakeRange(0, previousLength) changeInLength:(NSInteger)snapshot.length - (NSInteger)previousLength];
    [self endEditing];
}
@end
#endif
