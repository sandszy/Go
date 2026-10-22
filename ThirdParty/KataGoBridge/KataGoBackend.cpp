// KataGo 的神经网络接口（neuralnet/nninterface.h）的实现：按 KataGoBackend::setUseGPU 的选择，
// 转发给加了前缀的 Metal 后端或 Eigen 后端（见 MetalBackend.cpp、EigenBackend.cpp）。
#include "KataGoBackend.h"

#include "../KataGo/cpp/neuralnet/nninterface.h"

// 再声明两遍接口，名字分别加上 Metal_ 和 Eigen_ 前缀。
#undef NEURALNET_NNINTERFACE_H_
#define KATAGO_BACKEND_PREFIX(name) Metal_##name
#include "BackendRenames.h"
#include "../KataGo/cpp/neuralnet/nninterface.h"
#undef NeuralNet
#undef LoadedModel
#undef ComputeContext
#undef ComputeHandle
#undef InputBuffers
#undef KATAGO_BACKEND_PREFIX

#undef NEURALNET_NNINTERFACE_H_
#define KATAGO_BACKEND_PREFIX(name) Eigen_##name
#include "BackendRenames.h"
#include "../KataGo/cpp/neuralnet/nninterface.h"
#undef NeuralNet
#undef LoadedModel
#undef ComputeContext
#undef ComputeHandle
#undef InputBuffers
#undef KATAGO_BACKEND_PREFIX

using std::string;
using std::vector;

namespace {
  bool useGPU = true;
}

void KataGoBackend::setUseGPU(bool value) { useGPU = value; }
bool KataGoBackend::usesGPU() { return useGPU; }

// 每个对象只装着其中一个后端的对象。
struct LoadedModel {
  Metal_LoadedModel* metal = nullptr;
  Eigen_LoadedModel* eigen = nullptr;
};

struct ComputeContext {
  Metal_ComputeContext* metal = nullptr;
  Eigen_ComputeContext* eigen = nullptr;
};

struct ComputeHandle {
  Metal_ComputeHandle* metal = nullptr;
  Eigen_ComputeHandle* eigen = nullptr;
};

struct InputBuffers {
  Metal_InputBuffers* metal = nullptr;
  Eigen_InputBuffers* eigen = nullptr;
};

void NeuralNet::globalInitialize() {
  if(useGPU) Metal_NeuralNet::globalInitialize();
  else Eigen_NeuralNet::globalInitialize();
}

void NeuralNet::globalCleanup() {
  if(useGPU) Metal_NeuralNet::globalCleanup();
  else Eigen_NeuralNet::globalCleanup();
}

void NeuralNet::printDevices() {
  if(useGPU) Metal_NeuralNet::printDevices();
  else Eigen_NeuralNet::printDevices();
}

LoadedModel* NeuralNet::loadModelFile(const string& file, const string& expectedSha256) {
  LoadedModel* model = new LoadedModel();
  if(useGPU) model->metal = Metal_NeuralNet::loadModelFile(file, expectedSha256);
  else model->eigen = Eigen_NeuralNet::loadModelFile(file, expectedSha256);
  return model;
}

void NeuralNet::freeLoadedModel(LoadedModel* model) {
  if(model->metal) Metal_NeuralNet::freeLoadedModel(model->metal);
  if(model->eigen) Eigen_NeuralNet::freeLoadedModel(model->eigen);
  delete model;
}

const ModelDesc& NeuralNet::getModelDesc(const LoadedModel* model) {
  if(model->metal) return Metal_NeuralNet::getModelDesc(model->metal);
  return Eigen_NeuralNet::getModelDesc(model->eigen);
}

ComputeContext* NeuralNet::createComputeContext(
  const vector<int>& gpuIdxs,
  Logger* logger,
  int nnXLen,
  int nnYLen,
  const string& openCLTunerFile,
  const string& homeDataDirOverride,
  bool openCLReTunePerBoardSize,
  enabled_t useFP16Mode,
  enabled_t useNHWCMode,
  const LoadedModel* model
) {
  ComputeContext* context = new ComputeContext();
  if(model->metal) {
    context->metal = Metal_NeuralNet::createComputeContext(
      gpuIdxs, logger, nnXLen, nnYLen, openCLTunerFile, homeDataDirOverride, openCLReTunePerBoardSize,
      useFP16Mode, useNHWCMode, model->metal);
  } else {
    context->eigen = Eigen_NeuralNet::createComputeContext(
      gpuIdxs, logger, nnXLen, nnYLen, openCLTunerFile, homeDataDirOverride, openCLReTunePerBoardSize,
      useFP16Mode, useNHWCMode, model->eigen);
  }
  return context;
}

void NeuralNet::freeComputeContext(ComputeContext* context) {
  if(context->metal) Metal_NeuralNet::freeComputeContext(context->metal);
  if(context->eigen) Eigen_NeuralNet::freeComputeContext(context->eigen);
  delete context;
}

ComputeHandle* NeuralNet::createComputeHandle(
  ComputeContext* context,
  const LoadedModel* model,
  Logger* logger,
  int maxBatchSize,
  bool requireExactNNLen,
  bool inputsUseNHWC,
  int gpuIdxForThisThread,
  int serverThreadIdx
) {
  ComputeHandle* handle = new ComputeHandle();
  if(context->metal) {
    handle->metal = Metal_NeuralNet::createComputeHandle(
      context->metal, model->metal, logger, maxBatchSize, requireExactNNLen, inputsUseNHWC,
      gpuIdxForThisThread, serverThreadIdx);
  } else {
    handle->eigen = Eigen_NeuralNet::createComputeHandle(
      context->eigen, model->eigen, logger, maxBatchSize, requireExactNNLen, inputsUseNHWC,
      gpuIdxForThisThread, serverThreadIdx);
  }
  return handle;
}

void NeuralNet::freeComputeHandle(ComputeHandle* handle) {
  if(handle->metal) Metal_NeuralNet::freeComputeHandle(handle->metal);
  if(handle->eigen) Eigen_NeuralNet::freeComputeHandle(handle->eigen);
  delete handle;
}

bool NeuralNet::isUsingFP16(const ComputeHandle* handle) {
  if(handle->metal) return Metal_NeuralNet::isUsingFP16(handle->metal);
  return Eigen_NeuralNet::isUsingFP16(handle->eigen);
}

InputBuffers* NeuralNet::createInputBuffers(const LoadedModel* model, int maxBatchSize, int nnXLen, int nnYLen) {
  InputBuffers* buffers = new InputBuffers();
  if(model->metal) buffers->metal = Metal_NeuralNet::createInputBuffers(model->metal, maxBatchSize, nnXLen, nnYLen);
  else buffers->eigen = Eigen_NeuralNet::createInputBuffers(model->eigen, maxBatchSize, nnXLen, nnYLen);
  return buffers;
}

void NeuralNet::freeInputBuffers(InputBuffers* buffers) {
  if(buffers->metal) Metal_NeuralNet::freeInputBuffers(buffers->metal);
  if(buffers->eigen) Eigen_NeuralNet::freeInputBuffers(buffers->eigen);
  delete buffers;
}

void NeuralNet::getOutput(
  ComputeHandle* handle,
  InputBuffers* buffers,
  int numBatchEltsFilled,
  NNResultBuf** inputBufs,
  vector<NNOutput*>& outputs
) {
  if(handle->metal) Metal_NeuralNet::getOutput(handle->metal, buffers->metal, numBatchEltsFilled, inputBufs, outputs);
  else Eigen_NeuralNet::getOutput(handle->eigen, buffers->eigen, numBatchEltsFilled, inputBufs, outputs);
}

bool NeuralNet::testEvaluateConv(
  const ConvLayerDesc* desc, int batchSize, int nnXLen, int nnYLen, bool useFP16, bool useNHWC,
  const vector<float>& inputBuffer, vector<float>& outputBuffer
) {
  if(useGPU) return Metal_NeuralNet::testEvaluateConv(desc, batchSize, nnXLen, nnYLen, useFP16, useNHWC, inputBuffer, outputBuffer);
  return Eigen_NeuralNet::testEvaluateConv(desc, batchSize, nnXLen, nnYLen, useFP16, useNHWC, inputBuffer, outputBuffer);
}

bool NeuralNet::testEvaluateBatchNorm(
  const BatchNormLayerDesc* desc, int batchSize, int nnXLen, int nnYLen, bool useFP16, bool useNHWC,
  const vector<float>& inputBuffer, const vector<float>& maskBuffer, vector<float>& outputBuffer
) {
  if(useGPU) return Metal_NeuralNet::testEvaluateBatchNorm(desc, batchSize, nnXLen, nnYLen, useFP16, useNHWC, inputBuffer, maskBuffer, outputBuffer);
  return Eigen_NeuralNet::testEvaluateBatchNorm(desc, batchSize, nnXLen, nnYLen, useFP16, useNHWC, inputBuffer, maskBuffer, outputBuffer);
}

bool NeuralNet::testEvaluateResidualBlock(
  const ResidualBlockDesc* desc, int batchSize, int nnXLen, int nnYLen, bool useFP16, bool useNHWC,
  const vector<float>& inputBuffer, const vector<float>& maskBuffer, vector<float>& outputBuffer
) {
  if(useGPU) return Metal_NeuralNet::testEvaluateResidualBlock(desc, batchSize, nnXLen, nnYLen, useFP16, useNHWC, inputBuffer, maskBuffer, outputBuffer);
  return Eigen_NeuralNet::testEvaluateResidualBlock(desc, batchSize, nnXLen, nnYLen, useFP16, useNHWC, inputBuffer, maskBuffer, outputBuffer);
}

bool NeuralNet::testEvaluateGlobalPoolingResidualBlock(
  const GlobalPoolingResidualBlockDesc* desc, int batchSize, int nnXLen, int nnYLen, bool useFP16, bool useNHWC,
  const vector<float>& inputBuffer, const vector<float>& maskBuffer, vector<float>& outputBuffer
) {
  if(useGPU) return Metal_NeuralNet::testEvaluateGlobalPoolingResidualBlock(desc, batchSize, nnXLen, nnYLen, useFP16, useNHWC, inputBuffer, maskBuffer, outputBuffer);
  return Eigen_NeuralNet::testEvaluateGlobalPoolingResidualBlock(desc, batchSize, nnXLen, nnYLen, useFP16, useNHWC, inputBuffer, maskBuffer, outputBuffer);
}
