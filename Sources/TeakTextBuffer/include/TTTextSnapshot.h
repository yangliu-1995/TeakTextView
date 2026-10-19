#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Immutable, structurally shared UTF-16 rope. Safe to read concurrently.
NS_SWIFT_SENDABLE
@interface TTTextSnapshot : NSObject
@property(nonatomic, readonly) NSUInteger length;
@property(nonatomic, readonly) NSUInteger lineCount;
@property(nonatomic, readonly) NSUInteger chunkCount;
@property(nonatomic, readonly) NSStringEncoding fileEncoding;
@property(nonatomic, readonly) BOOL hasByteOrderMark;
/// A lazy NSString facade; copying it shares the immutable tree.
@property(nonatomic, readonly) NSString *nativeString;
+ (instancetype)snapshotWithString:(NSString *)string NS_SWIFT_NAME(make(text:));
+ (nullable instancetype)readURL:(NSURL *)url
                    isCancelled:(BOOL (NS_NOESCAPE ^)(void))isCancelled
                          error:(NSError **)error NS_SWIFT_NAME(load(url:isCancelled:));
- (TTTextSnapshot *)replacingRange:(NSRange)range withString:(NSString *)string NS_SWIFT_NAME(replacing(_:with:));
- (NSString *)substringInRange:(NSRange)range NS_SWIFT_NAME(substring(in:));
- (void)getCharacters:(unichar *)buffer range:(NSRange)range;
/// One-based logical line rank, without materializing the document prefix.
- (NSUInteger)lineNumberAtOffset:(NSUInteger)offset NS_SWIFT_NAME(lineNumber(atUTF16Offset:));
- (BOOL)isLineStartAtOffset:(NSUInteger)offset NS_SWIFT_NAME(isLineStart(atUTF16Offset:));
/// Stream into a sibling temporary file, fsync, then atomically rename.
- (BOOL)writeToURL:(NSURL *)url
      isCancelled:(BOOL (NS_NOESCAPE ^)(void))isCancelled
            error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
