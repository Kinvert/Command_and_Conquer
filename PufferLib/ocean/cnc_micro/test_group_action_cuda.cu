#include "../../src/cnc_micro_action_spec.h"
#include "../../src/cnc_micro_group_action_spec.h"

#include <cuda_runtime.h>

#include <cassert>
#include <cmath>
#include <cstdio>
#include <vector>

using namespace cnc_micro_group_action;

namespace {

constexpr float kDLogprob = 0.37f;
constexpr float kDEntropy = -0.013f;

struct Result {
    float logprob;
    float entropy;
    float gradients[kLogitCount];
};

__host__ __device__ bool allowed(int offset, int token) {
    if (offset == kCommandOffset) return token == 0 || token == kAttack;
    if (offset == kTargetSlotOffset) return token == 0 || token == 2 || token == 5;
    return token == 0 || token == 1;
}

__host__ __device__ void add_head(
        const float* logits,
        int offset,
        int size,
        int selected,
        Result* result) {
    float maximum = -INFINITY;
    for (int token = 0; token < size; ++token) {
        if (allowed(offset, token)) maximum = fmaxf(maximum, logits[offset + token]);
    }
    float sum = 0.0f;
    for (int token = 0; token < size; ++token) {
        if (allowed(offset, token)) sum += expf(logits[offset + token] - maximum);
    }
    const float logsumexp = maximum + logf(sum);
    float entropy = 0.0f;
    for (int token = 0; token < size; ++token) {
        if (!allowed(offset, token)) continue;
        const float logprob = logits[offset + token] - logsumexp;
        const float probability = expf(logprob);
        entropy -= probability * logprob;
    }
    result->logprob += logits[offset + selected] - logsumexp;
    result->entropy += entropy;
    for (int token = 0; token < size; ++token) {
        if (!allowed(offset, token)) continue;
        const float logprob = logits[offset + token] - logsumexp;
        const float probability = expf(logprob);
        result->gradients[offset + token] =
            cnc_micro_action::categorical_logit_gradient(
                token,
                selected,
                probability,
                logprob,
                entropy,
                kDLogprob,
                kDEntropy);
    }
}

__host__ __device__ void evaluate(
        const float* logits,
        bool attack,
        bool select_unit,
        Result* result) {
    const int command = attack ? kAttack : 0;
    add_head(logits, kCommandOffset, kCommandCount, command, result);
    if (!attack) {
        for (int head = kActor; head < kBaseHeadCount; ++head) {
            add_head(logits, head_offset(head), head_size(head), 0, result);
        }
        return;
    }

    const int selector_head = kBaseHeadCount + 3;
    add_head(
        logits,
        head_offset(selector_head),
        kSelectorValueCount,
        select_unit ? 1 : 0,
        result);
    if (select_unit) {
        add_head(logits, kTargetSlotOffset, kTargetSlotCount, 2, result);
    }
}

__global__ void evaluate_kernel(
        const float* logits,
        bool attack,
        bool select_unit,
        Result* result) {
    if (blockIdx.x == 0 && threadIdx.x == 0) {
        evaluate(logits, attack, select_unit, result);
    }
}

float objective(std::vector<float>* logits, bool attack, bool select_unit) {
    Result result = {};
    evaluate(logits->data(), attack, select_unit, &result);
    return kDLogprob * result.logprob + kDEntropy * result.entropy;
}

float finite_difference(
        std::vector<float>* logits,
        int offset,
        bool attack,
        bool select_unit) {
    constexpr float epsilon = 1.0e-3f;
    (*logits)[offset] += epsilon;
    const float positive = objective(logits, attack, select_unit);
    (*logits)[offset] -= 2.0f * epsilon;
    const float negative = objective(logits, attack, select_unit);
    (*logits)[offset] += epsilon;
    return (positive - negative) / (2.0f * epsilon);
}

void expect_near(float actual, float expected, float tolerance) {
    if (fabsf(actual - expected) > tolerance) {
        std::fprintf(stderr, "actual=%g expected=%g tolerance=%g\n", actual, expected, tolerance);
        std::abort();
    }
}

void check_cuda(cudaError_t error) {
    if (error != cudaSuccess) {
        std::fprintf(stderr, "CUDA error: %s\n", cudaGetErrorString(error));
        std::abort();
    }
}

Result gpu_evaluate(const std::vector<float>& logits, bool attack, bool select_unit) {
    float* device_logits = nullptr;
    Result* device_result = nullptr;
    check_cuda(cudaMalloc(&device_logits, logits.size() * sizeof(float)));
    check_cuda(cudaMalloc(&device_result, sizeof(Result)));
    check_cuda(cudaMemcpy(
        device_logits, logits.data(), logits.size() * sizeof(float), cudaMemcpyHostToDevice));
    check_cuda(cudaMemset(device_result, 0, sizeof(Result)));
    evaluate_kernel<<<1, 1>>>(device_logits, attack, select_unit, device_result);
    check_cuda(cudaGetLastError());
    Result result = {};
    check_cuda(cudaMemcpy(&result, device_result, sizeof(Result), cudaMemcpyDeviceToHost));
    check_cuda(cudaFree(device_result));
    check_cuda(cudaFree(device_logits));
    return result;
}

} // namespace

int main() {
    const PpoHeadTerms neutral = ppo_head_terms(-0.7f, -0.7f, 0.25f, 0.2f);
    expect_near(neutral.ratio, 1.0f, 1.0e-7f);
    expect_near(neutral.policy_loss, 0.25f, 1.0e-7f);
    expect_near(neutral.d_new_logprob, 0.25f, 1.0e-7f);
    expect_near(neutral.approx_kl, 0.0f, 1.0e-7f);

    const PpoHeadTerms favorable_clipped =
        ppo_head_terms(0.3f, -0.7f, -0.25f, 0.2f);
    expect_near(favorable_clipped.policy_loss, -0.3f, 1.0e-6f);
    expect_near(favorable_clipped.d_new_logprob, 0.0f, 1.0e-7f);

    const PpoHeadTerms adverse_extreme =
        ppo_head_terms(1.0e6f, -1.0e6f, 0.25f, 0.2f);
    assert(std::isfinite(adverse_extreme.ratio));
    assert(std::isfinite(adverse_extreme.policy_loss));
    assert(std::isfinite(adverse_extreme.d_new_logprob));
    expect_near(adverse_extreme.bounded_logratio, kMaxAbsPpoLogRatio, 1.0e-7f);
    expect_near(
        centered_subaction_policy_loss(4.0f * 0.25f, 4, 0.25f),
        0.25f,
        1.0e-7f);

    std::vector<float> logits(kLogitCount, 0.0f);
    for (int index = 0; index < kLogitCount; ++index) {
        logits[index] = 0.03f * float((index % 11) - 5);
    }

    Result host = {};
    evaluate(logits.data(), true, true, &host);
    const Result gpu = gpu_evaluate(logits, true, true);
    expect_near(gpu.logprob, host.logprob, 1.0e-6f);
    expect_near(gpu.entropy, host.entropy, 1.0e-6f);
    for (int index = 0; index < kLogitCount; ++index) {
        expect_near(gpu.gradients[index], host.gradients[index], 1.0e-6f);
    }

    const int selector_offset = head_offset(kBaseHeadCount + 3);
    expect_near(
        finite_difference(&logits, selector_offset + 1, true, true),
        host.gradients[selector_offset + 1],
        5.0e-5f);
    expect_near(
        finite_difference(&logits, kTargetSlotOffset + 2, true, true),
        host.gradients[kTargetSlotOffset + 2],
        5.0e-5f);

    Result empty = {};
    evaluate(logits.data(), true, false, &empty);
    for (int token = 0; token < kTargetSlotCount; ++token) {
        assert(empty.gradients[kTargetSlotOffset + token] == 0.0f);
    }
    Result nonattack = {};
    evaluate(logits.data(), false, false, &nonattack);
    for (int slot = 0; slot < kSelectorCount; ++slot) {
        const int offset = head_offset(kBaseHeadCount + slot);
        assert(nonattack.gradients[offset] == 0.0f);
        assert(nonattack.gradients[offset + 1] == 0.0f);
    }

    std::puts("cnc_micro ABI14 group CPU/CUDA gradient parity ok");
    return 0;
}
