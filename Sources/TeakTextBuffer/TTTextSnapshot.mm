#import "include/TTTextSnapshot.h"
#include "TTRope.hpp"
#include <vector>
#include <cstring>
#include <unistd.h>
#include <fcntl.h>

namespace {
NSError *failure(NSString *message) {
    return [NSError errorWithDomain:@"TeakTextBuffer" code:1
                          userInfo:@{NSLocalizedDescriptionKey: message}];
}
void checkRange(NSRange range, NSUInteger length) {
    if (range.location > length || range.length > length - range.location)
        [NSException raise:NSRangeException format:@"Text range is outside the document"];
}
teak::Tree treeFromString(NSString *string) {
    teak::Tree tree;
    for (NSUInteger offset = 0; offset < string.length;) {
        auto count = std::min(teak::chunkCapacity, string.length - offset);
        if (offset + count < string.length) {
            const auto last = [string characterAtIndex:offset + count - 1];
            if (last >= 0xD800 && last <= 0xDBFF) --count;
        }
        // Raw buffers occur only at the Foundation ABI; ownership stays in vector/shared_ptr.
        std::vector<unichar> units(count);
        [string getCharacters:units.data() range:NSMakeRange(offset, count)];
        auto buffer = std::make_shared<const std::u16string>(units.begin(), units.end());
        tree = teak::join(tree, std::make_shared<teak::Node>(buffer, 0, count));
        offset += count;
    }
    return tree;
}
}

@interface TTRopeString : NSString
- (instancetype)initWithTree:(teak::Tree)tree;
@end

@implementation TTRopeString {
    teak::Tree _tree;
}
- (instancetype)initWithTree:(teak::Tree)tree {
    self = [super init];
    if (self) _tree = std::move(tree);
    return self;
}
- (NSUInteger)length { return teak::length(_tree); }
- (unichar)characterAtIndex:(NSUInteger)index {
    checkRange(NSMakeRange(index, 1), self.length);
    return teak::character(_tree, index);
}
- (void)getCharacters:(unichar *)buffer range:(NSRange)range {
    checkRange(range, self.length);
    auto destination = std::span(buffer, range.length);
    teak::visit(_tree, range.location, range.length, [&](std::span<const char16_t> text) {
        static_assert(sizeof(char16_t) == sizeof(unichar));
        std::memcpy(destination.data(), text.data(), text.size_bytes());
        destination = destination.subspan(text.size());
    });
}
- (NSString *)substringWithRange:(NSRange)range {
    checkRange(range, self.length);
    // This buffer is completely overwritten. Avoid constructing/zeroing one
    // UTF-16 unit at a time in Debug when UIKit requests a large paragraph.
    auto units = std::make_unique_for_overwrite<unichar[]>(range.length);
    [self getCharacters:units.get() range:range];
    return [[NSString alloc] initWithCharacters:units.get() length:range.length];
}
- (id)copyWithZone:(NSZone *)zone { return self; }
@end

@interface TTTextSnapshot ()
- (instancetype)initWithTree:(teak::Tree)tree encoding:(NSStringEncoding)encoding bom:(BOOL)bom;
@end

@implementation TTTextSnapshot {
    teak::Tree _tree;
    NSString *_nativeString;
}
- (instancetype)initWithTree:(teak::Tree)tree encoding:(NSStringEncoding)encoding bom:(BOOL)bom {
    self = [super init];
    if (self) {
        _tree = std::move(tree);
        _fileEncoding = encoding;
        _hasByteOrderMark = bom;
        // Eagerly publish this immutable facade; concurrent readers never mutate lazy state.
        _nativeString = [[TTRopeString alloc] initWithTree:_tree];
    }
    return self;
}
+ (instancetype)snapshotWithString:(NSString *)string {
    return [[self alloc] initWithTree:treeFromString(string) encoding:NSUTF8StringEncoding bom:NO];
}
- (NSUInteger)length { return teak::length(_tree); }
- (NSUInteger)lineCount { return (_tree ? _tree->breaks : 0) + 1; }
- (NSUInteger)chunkCount { return _tree ? _tree->leaves : 0; }
- (NSString *)nativeString { return _nativeString; }
- (void)getCharacters:(unichar *)buffer range:(NSRange)range {
    [_nativeString getCharacters:buffer range:range];
}
- (NSString *)substringInRange:(NSRange)range { return [_nativeString substringWithRange:range]; }
- (NSUInteger)lineNumberAtOffset:(NSUInteger)offset {
    checkRange(NSMakeRange(offset, 0), self.length);
    return teak::lineNumber(_tree, offset);
}
- (BOOL)isLineStartAtOffset:(NSUInteger)offset {
    checkRange(NSMakeRange(offset, 0), self.length);
    return teak::isLineStart(_tree, offset);
}
- (TTTextSnapshot *)replacingRange:(NSRange)range withString:(NSString *)string {
    checkRange(range, self.length);
    auto prefix = teak::split(_tree, range.location);
    auto suffix = teak::split(prefix.second, range.length);
    auto root = teak::join(teak::join(prefix.first, treeFromString(string)), suffix.second);
    return [[TTTextSnapshot alloc] initWithTree:root encoding:_fileEncoding bom:_hasByteOrderMark];
}
+ (instancetype)readURL:(NSURL *)url isCancelled:(BOOL (NS_NOESCAPE ^)(void))isCancelled error:(NSError **)error {
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingFromURL:url error:error];
    if (!handle) return nil;
    teak::Tree root;
    NSStringEncoding encoding = NSUTF8StringEncoding;
    BOOL bom = NO;
    BOOL first = YES;
    BOOL success = YES;
    NSMutableData *pending = [NSMutableData data];
    while (success) {
        @autoreleasepool {
            if (isCancelled()) {
                if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil];
                success = NO;
                break;
            }
            NSData *data = [handle readDataUpToLength:64 * 1024 error:error];
            if (!data) { success = NO; break; }
            [pending appendData:data];
            std::vector<uint8_t> bytes(pending.length);
            [pending getBytes:bytes.data() length:bytes.size()];
            NSUInteger prefix = 0;
            if (first) {
                first = NO;
                if (bytes.size() >= 4 && ((bytes[0] == 0xFF && bytes[1] == 0xFE && !bytes[2] && !bytes[3])
                    || (!bytes[0] && !bytes[1] && bytes[2] == 0xFE && bytes[3] == 0xFF))) {
                    if (error) *error = failure(@"UTF-32 is not supported by this prototype.");
                    success = NO; break;
                }
                if (bytes.size() >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) prefix = 3;
                else if (bytes.size() >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
                    prefix = 2; encoding = NSUTF16LittleEndianStringEncoding;
                } else if (bytes.size() >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
                    prefix = 2; encoding = NSUTF16BigEndianStringEncoding;
                }
                bom = prefix > 0;
            }
            NSUInteger end = bytes.size();
            if (data.length && end > prefix) {
                if (encoding == NSUTF8StringEncoding) {
                    auto lead = end - 1;
                    while (lead > prefix && (bytes[lead] & 0xC0) == 0x80) --lead;
                    const auto c = bytes[lead];
                    const size_t expected = c < 0x80 ? 1 : c >= 0xF0 ? 4 : c >= 0xE0 ? 3 : c >= 0xC0 ? 2 : 1;
                    if (end - lead < expected) end = lead;
                } else {
                    end -= (end - prefix) % 2;
                    if (end >= prefix + 2) {
                        const auto last = encoding == NSUTF16LittleEndianStringEncoding
                            ? bytes[end - 2] | (bytes[end - 1] << 8)
                            : (bytes[end - 2] << 8) | bytes[end - 1];
                        if (last >= 0xD800 && last <= 0xDBFF) end -= 2;
                    }
                }
            }
            NSData *part = [pending subdataWithRange:NSMakeRange(prefix, end - prefix)];
            NSString *decoded = [[NSString alloc] initWithData:part encoding:encoding];
            if (!decoded) {
                if (error) *error = failure(@"The file is not valid UTF-8 or BOM-marked UTF-16 text.");
                success = NO; break;
            }
            root = teak::join(root, treeFromString(decoded));
            [pending replaceBytesInRange:NSMakeRange(0, end) withBytes:nullptr length:0];
            if (!data.length) break;
        }
    }
    NSError *closeError = nil;
    if (![handle closeAndReturnError:&closeError] && success) {
        success = NO;
        if (error) *error = closeError;
    }
    if (!success) return nil;
    return [[self alloc] initWithTree:root encoding:encoding bom:bom];
}
- (BOOL)writeToURL:(NSURL *)url isCancelled:(BOOL (NS_NOESCAPE ^)(void))isCancelled error:(NSError **)error {
    NSURL *temporary = [[url URLByDeletingLastPathComponent]
        URLByAppendingPathComponent:[@".teak-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    const int descriptor = open(temporary.fileSystemRepresentation, O_CREAT | O_EXCL | O_WRONLY, 0600);
    if (descriptor < 0) {
        if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
        return NO;
    }
    NSFileHandle *handle = [[NSFileHandle alloc] initWithFileDescriptor:descriptor closeOnDealloc:YES];
    BOOL success = handle != nil;
    NSError *writeError = nil;
    if (_hasByteOrderMark && success) {
        const std::vector<uint8_t> marker = _fileEncoding == NSUTF8StringEncoding
            ? std::vector<uint8_t>{0xEF, 0xBB, 0xBF}
            : _fileEncoding == NSUTF16LittleEndianStringEncoding
                ? std::vector<uint8_t>{0xFF, 0xFE} : std::vector<uint8_t>{0xFE, 0xFF};
        success = [handle writeData:[NSData dataWithBytes:marker.data() length:marker.size()] error:&writeError];
    }
    unichar pendingHigh = 0;
    teak::visit(_tree, 0, self.length, [&](std::span<const char16_t> part) {
        @autoreleasepool {
            if (!success) return;
            if (isCancelled()) {
                success = NO;
                writeError = [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil];
                return;
            }
            std::vector<unichar> units;
            units.reserve(part.size() + 1);
            if (pendingHigh) units.push_back(pendingHigh);
            units.insert(units.end(), part.begin(), part.end());
            pendingHigh = 0;
            if (!units.empty() && units.back() >= 0xD800 && units.back() <= 0xDBFF) {
                pendingHigh = units.back(); units.pop_back();
            }
            NSString *text = [[NSString alloc] initWithCharacters:units.data() length:units.size()];
            NSData *encoded = [text dataUsingEncoding:_fileEncoding allowLossyConversion:NO];
            if (!encoded) { success = NO; writeError = failure(@"The document contains an unpaired Unicode surrogate."); return; }
            success = [handle writeData:encoded error:&writeError];
        }
    });
    if (pendingHigh) { success = NO; writeError = failure(@"The document contains an unpaired Unicode surrogate."); }
    if (success) success = [handle synchronizeAndReturnError:&writeError];
    NSError *closeError = nil;
    if (![handle closeAndReturnError:&closeError] && success) { success = NO; writeError = closeError; }
    // Commit is the final irreversible step; cancelled saves never replace the destination.
    if (success && isCancelled()) { success = NO; writeError = [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil]; }
    if (success) {
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:url.path error:nil];
        if (attributes[NSFilePosixPermissions])
            [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: attributes[NSFilePosixPermissions]}
                                           ofItemAtPath:temporary.path error:nil];
        if (rename(temporary.fileSystemRepresentation, url.fileSystemRepresentation) != 0) {
            success = NO;
            writeError = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
        }
    }
    if (!success) {
        [[NSFileManager defaultManager] removeItemAtURL:temporary error:nil];
        if (error) *error = writeError ?: failure(@"Could not write the document.");
    }
    return success;
}
@end
