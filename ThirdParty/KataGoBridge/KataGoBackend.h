// KataGo 的神经网络后端本来是编译时选一个（Metal、Eigen……）。
// 这里把 Metal（GPU）和 Eigen（CPU）两个后端都编进 App，启动引擎前选用哪一个。
#pragma once

namespace KataGoBackend {
  /// 在 KataGo 加载模型之前调用。true 用 GPU（Metal），false 用 CPU（Eigen）。
  void setUseGPU(bool useGPU);
  bool usesGPU();
}
