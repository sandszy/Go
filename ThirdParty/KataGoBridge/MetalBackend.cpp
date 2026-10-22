// 编译 KataGo 的 Metal（GPU）后端，同名的类型和函数都加上 Metal 前缀，见 BackendRenames.h。
#define KATAGO_BACKEND_PREFIX(name) Metal_##name
#include "BackendRenames.h"
#include "../KataGo/cpp/neuralnet/metalbackend.cpp"
