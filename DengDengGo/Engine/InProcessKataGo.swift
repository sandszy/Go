import Foundation
import GoCore
import Metal

/// App 进程里跑的 KataGo：模型和配置都打包在 App 里，不用联网。
struct InProcessKataGo: KataGoTransport {
    /// 打包进 App 的模型文件名（不含 .bin.gz）。
    static let modelName = "kata1-b18c384nbt"

    /// 神经网络在哪里算。
    enum Hardware: String {
        case gpu = "GPU"
        case cpu = "CPU"

        /// 有能用的 GPU 就用 GPU，快得多；模拟器的虚拟 GPU 不支持 KataGo Metal 后端用的 MPSGraph，一算就崩，只能用 CPU。
        /// 启动参数 `-katagoHardware cpu` 或 `gpu` 可以强制指定，`off` 不用引擎，不判题（UI 测试用，结果固定）。
        /// 返回 nil 表示不用引擎。
        static var preferred: Hardware? {
            let arguments = ProcessInfo.processInfo.arguments
            if let index = arguments.firstIndex(of: "-katagoHardware"), index + 1 < arguments.count {
                let forced = arguments[index + 1].uppercased()
                if forced == "OFF" { return nil }
                if let hardware = Hardware(rawValue: forced) { return hardware }
            }
            let isSimulator = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil
            guard !isSimulator, MTLCreateSystemDefaultDevice() != nil else { return .cpu }
            return .gpu
        }

        /// 在配置文件 analysis.cfg 之上，按硬件改的设置。
        var configOverrides: String {
            switch self {
            case .gpu:
                return ""
            case .cpu:
                // CPU 上的矩阵乘法交给 Accelerate，会用到芯片里共用的矩阵单元，线程多了反而互相抢；
                // 在 Mac 上的模拟器里试过，4 个线程、每批 8 个局面最快。
                // Eigen 后端只认 NHWC 排列的输入，共用的设置代码是按 Metal 编的，默认不是 NHWC。
                let threads = min(4, ProcessInfo.processInfo.activeProcessorCount)
                return "numNNServerThreadsPerModel=\(threads), nnMaxBatchSize=8, inputsUseNHWC=true"
            }
        }
    }

    /// 整个 App 共用一个引擎：KataGo 在进程里只能启动一次。模型没打包进来时是 nil，App 不判题，只能自己两边下。
    static let shared: KataGoEngine? = makeEngine()

    private static func makeEngine() -> KataGoEngine? {
        guard let model = Bundle.main.path(forResource: modelName, ofType: "bin.gz"),
              let config = Bundle.main.path(forResource: "analysis", ofType: "cfg")
        else { return nil }
        guard let hardware = Hardware.preferred else { return nil }
        let transport = InProcessKataGo(config: config, model: model, hardware: hardware)
        return KataGoEngine(transport: transport, name: "KataGo（\(hardware.rawValue)）")
    }

    /// 开发时用启动参数 `-katagoConfig "参数=值, 参数=值"` 临时改配置，比较不同设置的速度。
    private static var debugOverrides: String {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-katagoConfig"), index + 1 < arguments.count { return arguments[index + 1] }
        #endif
        return ""
    }

    let config: String
    let model: String
    let hardware: Hardware

    func start(onLine: @escaping @Sendable (String) -> Void) {
        KataGoBridge.start(
            withConfig: config,
            model: model,
            useGPU: hardware == .gpu,
            overrides: [hardware.configOverrides, Self.debugOverrides].filter { !$0.isEmpty }.joined(separator: ", "),
            onLine: onLine
        )
    }

    func send(_ line: String) {
        KataGoBridge.sendLine(line)
    }
}
