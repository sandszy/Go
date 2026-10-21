#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 在 App 进程里跑 KataGo 的 analysis 命令。
/// KataGo 本来是命令行程序，从标准输入读 JSON、往标准输出写 JSON；这里把这两个流换成内存里的队列。
/// 整个进程只能启动一次。
@interface KataGoBridge : NSObject

/// 在后台线程启动 KataGo。引擎每输出一行就调一次 handler（在 KataGo 的线程上）。
+ (void)startWithConfig:(NSString *)configPath
                  model:(NSString *)modelPath
                 onLine:(void (^)(NSString *line))handler;

/// 给引擎发一行 JSON 请求。启动前发的会先排着，启动后再读。
+ (void)sendLine:(NSString *)line;

@end

NS_ASSUME_NONNULL_END
