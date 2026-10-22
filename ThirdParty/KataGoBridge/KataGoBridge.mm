#import "KataGoBridge.h"

#include <condition_variable>
#include <deque>
#include <iostream>
#include <mutex>
#include <streambuf>
#include <string>
#include <vector>

#include "../KataGo/cpp/main.h"
#include "KataGoBackend.h"

namespace {

/// 给 std::cin 用的输入缓冲：sendLine 往里放，KataGo 读不到时就等着。
class LineQueueBuf : public std::streambuf {
public:
  void push(const std::string& line) {
    {
      std::lock_guard<std::mutex> lock(mutex);
      pending.push_back(line + "\n");
    }
    ready.notify_one();
  }

protected:
  int_type underflow() override {
    std::unique_lock<std::mutex> lock(mutex);
    ready.wait(lock, [this] { return !pending.empty(); });
    current = std::move(pending.front());
    pending.pop_front();
    char* begin = current.data();
    setg(begin, begin, begin + current.size());
    return traits_type::to_int_type(*gptr());
  }

private:
  std::mutex mutex;
  std::condition_variable ready;
  std::deque<std::string> pending;
  std::string current;
};

/// 给 std::cout 用的输出缓冲：攒够一行就交给回调。
class LineCallbackBuf : public std::streambuf {
public:
  void (^handler)(NSString*) = nil;

protected:
  int_type overflow(int_type c) override {
    if(c == traits_type::eof())
      return traits_type::not_eof(c);
    std::lock_guard<std::mutex> lock(mutex);
    if(c == '\n') {
      flushLine();
    } else {
      line.push_back(traits_type::to_char_type(c));
    }
    return c;
  }

  std::streamsize xsputn(const char* s, std::streamsize n) override {
    for(std::streamsize i = 0; i < n; i++)
      overflow(traits_type::to_int_type(s[i]));
    return n;
  }

private:
  void flushLine() {
    if(line.empty())
      return;
    NSString* text = [[NSString alloc] initWithBytes:line.data() length:line.size() encoding:NSUTF8StringEncoding];
    line.clear();
    if(text != nil && handler != nil)
      handler(text);
  }

  std::mutex mutex;
  std::string line;
};

LineQueueBuf inputBuf;
LineCallbackBuf outputBuf;
std::once_flag started;

}

@implementation KataGoBridge

+ (void)startWithConfig:(NSString*)configPath
                  model:(NSString*)modelPath
                 useGPU:(BOOL)useGPU
              overrides:(NSString*)overrides
                 onLine:(void (^)(NSString*))handler {
  std::call_once(started, [&] {
    outputBuf.handler = [handler copy];
    std::cin.rdbuf(&inputBuf);
    std::cout.rdbuf(&outputBuf);
    KataGoBackend::setUseGPU(useGPU);

    std::vector<std::string> args = {
      "katago", "-config", configPath.UTF8String, "-model", modelPath.UTF8String,
    };
    if(overrides.length > 0) {
      args.push_back("-override-config");
      args.push_back(overrides.UTF8String);
    }
    // KataGo 的搜索递归比较深，默认 512KB 的线程栈不够用。
    NSThread* thread = [[NSThread alloc] initWithBlock:^{
      MainCmds::analysis(args);
    }];
    thread.name = @"KataGo";
    thread.stackSize = 16 * 1024 * 1024;
    thread.qualityOfService = NSQualityOfServiceUserInitiated;
    [thread start];
  });
}

+ (void)sendLine:(NSString*)line {
  inputBuf.push(line.UTF8String);
}

@end
