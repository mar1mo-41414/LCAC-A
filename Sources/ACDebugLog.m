#import "ACDebugLog.h"

static NSString *ACLogFilePath(void) {
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docs = paths.firstObject ?: NSTemporaryDirectory();
    return [docs stringByAppendingPathComponent:@"lcac-debug.log"];
}

void ACLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSLog(@"[LCAC] %@", message);

    @try {
        NSString *path = ACLogFilePath();
        NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [NSDate date], message];
        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:path]) {
            [fm createFileAtPath:path contents:nil attributes:nil];
        }
        NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
        [handle seekToEndOfFile];
        [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [handle closeFile];
    } @catch (NSException *exception) {
        // ログ書き込みの失敗で本体機能に影響を出さない。
    }
}
