// 两个后端都定义了 NeuralNet 里的同一组函数和 LoadedModel、ComputeContext 等同名类型，
// 放进同一个 App 会冲突。编译各个后端时先用宏给这些名字加上前缀，再由 KataGoBackend.cpp 按运行时的选择转发。
// 用法：先 #define KATAGO_BACKEND_PREFIX(name) 再 #include 本文件。
#define NeuralNet KATAGO_BACKEND_PREFIX(NeuralNet)
#define LoadedModel KATAGO_BACKEND_PREFIX(LoadedModel)
#define ComputeContext KATAGO_BACKEND_PREFIX(ComputeContext)
#define ComputeHandle KATAGO_BACKEND_PREFIX(ComputeHandle)
#define InputBuffers KATAGO_BACKEND_PREFIX(InputBuffers)
