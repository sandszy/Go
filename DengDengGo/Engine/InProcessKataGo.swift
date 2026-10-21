import Foundation
import GoCore

/// App 进程里跑的 KataGo：模型和配置都打包在 App 里，不用联网。
struct InProcessKataGo: KataGoTransport {
    /// 打包进 App 的模型文件名（不含 .bin.gz）。
    static let modelName = "kata1-b18c384nbt"

    /// 整个 App 共用一个引擎：KataGo 在进程里只能启动一次。模型没打包进来时是 nil，App 就只用入门判题器。
    static let shared: KataGoEngine? = makeEngine()

    private static func makeEngine() -> KataGoEngine? {
        #if targetEnvironment(simulator)
        // 模拟器的虚拟 GPU 不支持 KataGo Metal 后端用的 MPSGraph，一算就崩，模拟器里只用入门判题器。
        return nil
        #else
        guard let model = Bundle.main.path(forResource: modelName, ofType: "bin.gz"),
              let config = Bundle.main.path(forResource: "analysis", ofType: "cfg")
        else { return nil }
        return KataGoEngine(transport: InProcessKataGo(config: config, model: model))
        #endif
    }

    let config: String
    let model: String

    func start(onLine: @escaping @Sendable (String) -> Void) {
        KataGoBridge.start(withConfig: config, model: model, onLine: onLine)
    }

    func send(_ line: String) {
        KataGoBridge.sendLine(line)
    }
}
