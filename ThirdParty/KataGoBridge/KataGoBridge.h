#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 在 App 进程里跑 KataGo 的 analysis 命令。
/// KataGo 本来是命令行程序，从标准输入读 JSON、往标准输出写 JSON；这里把这两个流换成内存里的队列。
/// 整个进程只能启动一次。
@interface KataGoBridge : NSObject

/// 在后台线程启动 KataGo。引擎每输出一行就调一次 handler（在 KataGo 的线程上）。
/// useGPU 为 YES 用 Metal（GPU）算神经网络，NO 用 Eigen（CPU）。
/// overrides 是覆盖配置文件的设置，格式 "key=value, key=value"，空字符串表示不覆盖。
+ (void)startWithConfig:(NSString *)configPath
                  model:(NSString *)modelPath
                 useGPU:(BOOL)useGPU
              overrides:(NSString *)overrides
                 onLine:(void (^)(NSString *line))handler;

/// 给引擎发一行 JSON 请求。启动前发的会先排着，启动后再读。
+ (void)sendLine:(NSString *)line;

@end

NS_ASSUME_NONNULL_END
