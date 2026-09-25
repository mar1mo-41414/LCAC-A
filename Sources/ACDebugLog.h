#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 診断用の簡易ログ。NSLog出力に加え、対象アプリのDocumentsフォルダ内
/// lcac-a-debug.log にも追記する(LiveContainerのファイルブラウザ等から確認できる)。
/// アプリ互換性の問題(オーバーレイが表示されない等)を調査する時のためのもので、
/// 通常利用では気にする必要はない。
FOUNDATION_EXPORT void ACLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);

NS_ASSUME_NONNULL_END
