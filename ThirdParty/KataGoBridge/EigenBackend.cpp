// 编译 KataGo 的 Eigen（CPU）后端，同名的类型和函数都加上 Eigen 前缀，见 BackendRenames.h。
// 这个文件里的代码本来只在定义了 USE_EIGEN_BACKEND 时编译。
#define USE_EIGEN_BACKEND
// 矩阵乘法交给系统的 BLAS（Accelerate），在苹果芯片上会用专门的矩阵单元，比 Eigen 自己算快得多。
#define EIGEN_USE_BLAS
#define KATAGO_BACKEND_PREFIX(name) Eigen_##name
#include "BackendRenames.h"
#include "../KataGo/cpp/neuralnet/eigenbackend.cpp"
