#include "../../src/cnc_micro_action_spec.h"

#include <cuda_runtime.h>

#include <cassert>
#include <cmath>
#include <cstdio>
#include <vector>

using namespace cnc_micro_action;

namespace {

constexpr int kSelected = 5;
constexpr float kDLogprob = 0.37f;
constexpr float kDEntropy = -0.013f;

struct FloatReader {
    const float* values;

    __host__ __device__ float operator()(int offset) const {
        return values[offset];
    }
};

struct Result {
    float logsumexp;
    float entropy;
    float selected_logprob;
    float base_grad[kEntitySlotCount];
    float query_grad[kActorTargetRank];
    float key_grad[kEntitySlotCount * kActorTargetRank];
};

__host__ __device__ bool allowed(int token) {
    return token == 2 || token == 5 || token == 11;
}

__host__ __device__ void evaluate(const float* logits, Result* result) {
    const LogitSpec spec = argument_logit_spec(kAttack, 1, 7, kPad);
    const FloatReader read = {logits};
    float maximum = -INFINITY;
    for (int token = 0; token < kEntitySlotCount; ++token) {
        if (!allowed(token)) continue;
        maximum = fmaxf(maximum, score_logit(spec, token, read));
    }

    float sum = 0.0f;
    for (int token = 0; token < kEntitySlotCount; ++token) {
        if (!allowed(token)) continue;
        sum += expf(score_logit(spec, token, read) - maximum);
    }
    result->logsumexp = maximum + logf(sum);
    result->entropy = 0.0f;
    result->selected_logprob = 0.0f;

    for (int token = 0; token < kEntitySlotCount; ++token) {
        if (!allowed(token)) continue;
        const float logprob = score_logit(spec, token, read) - result->logsumexp;
        const float probability = expf(logprob);
        result->entropy -= probability * logprob;
        if (token == kSelected) result->selected_logprob = logprob;
    }

    for (int token = 0; token < kEntitySlotCount; ++token) {
        if (!allowed(token)) continue;
        const float logprob = score_logit(spec, token, read) - result->logsumexp;
        const float probability = expf(logprob);
        const float gradient = categorical_logit_gradient(
            token, kSelected, probability, logprob,
            result->entropy, kDLogprob, kDEntropy);
        const float interaction_gradient_scale =
            actor_target_gradient_scale(spec.interaction, token, read);
        result->base_grad[token] = gradient;
        for (int rank = 0; rank < kActorTargetRank; ++rank) {
            result->query_grad[rank] += gradient *
                actor_query_gradient_factor(
                    spec.interaction, token, rank,
                    interaction_gradient_scale, read);
            result->key_grad[token * kActorTargetRank + rank] = gradient *
                target_key_gradient_factor(
                    spec.interaction, rank,
                    interaction_gradient_scale, read);
        }
    }
}

__global__ void evaluate_kernel(const float* logits, Result* result) {
    if (blockIdx.x == 0 && threadIdx.x == 0) evaluate(logits, result);
}

float objective(const std::vector<float>& logits) {
    Result result = {};
    evaluate(logits.data(), &result);
    return kDLogprob * result.selected_logprob + kDEntropy * result.entropy;
}

float finite_difference(std::vector<float>* logits, int offset) {
    constexpr float epsilon = 1.0e-3f;
    (*logits)[offset] += epsilon;
    const float positive = objective(*logits);
    (*logits)[offset] -= 2.0f * epsilon;
    const float negative = objective(*logits);
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

} // namespace

int main() {
    std::vector<float> logits(kLogitCount, 0.0f);
    const LogitSpec spec = argument_logit_spec(kAttack, 1, 7, kPad);
    for (int token = 0; token < kEntitySlotCount; ++token) {
        logits[spec.additive.base[0] + token] = 0.07f * float((token % 7) - 3);
        for (int rank = 0; rank < kActorTargetRank; ++rank) {
            logits[spec.interaction.key_base + token * kActorTargetRank + rank] =
                0.03f * float((token + 2 * rank) % 9 - 4);
        }
    }
    const float query_values[kActorTargetRank] = {0.2f, -0.3f, 0.4f, 0.1f};
    const int query = spec.interaction.query_base + spec.interaction.actor * kActorTargetRank;
    for (int rank = 0; rank < kActorTargetRank; ++rank) {
        logits[query + rank] = query_values[rank];
    }

    Result host = {};
    evaluate(logits.data(), &host);

    float* device_logits = nullptr;
    Result* device_result = nullptr;
    check_cuda(cudaMalloc(&device_logits, logits.size() * sizeof(float)));
    check_cuda(cudaMalloc(&device_result, sizeof(Result)));
    check_cuda(cudaMemcpy(
        device_logits, logits.data(), logits.size() * sizeof(float), cudaMemcpyHostToDevice));
    check_cuda(cudaMemset(device_result, 0, sizeof(Result)));
    evaluate_kernel<<<1, 1>>>(device_logits, device_result);
    check_cuda(cudaGetLastError());

    Result gpu = {};
    check_cuda(cudaMemcpy(&gpu, device_result, sizeof(Result), cudaMemcpyDeviceToHost));
    check_cuda(cudaFree(device_result));
    check_cuda(cudaFree(device_logits));

    expect_near(gpu.logsumexp, host.logsumexp, 1.0e-6f);
    expect_near(gpu.entropy, host.entropy, 1.0e-6f);
    expect_near(gpu.selected_logprob, host.selected_logprob, 1.0e-6f);
    for (int token = 0; token < kEntitySlotCount; ++token) {
        expect_near(gpu.base_grad[token], host.base_grad[token], 1.0e-6f);
    }
    for (int rank = 0; rank < kActorTargetRank; ++rank) {
        expect_near(gpu.query_grad[rank], host.query_grad[rank], 1.0e-6f);
    }
    for (int index = 0; index < kEntitySlotCount * kActorTargetRank; ++index) {
        expect_near(gpu.key_grad[index], host.key_grad[index], 1.0e-6f);
    }

    expect_near(
        finite_difference(&logits, spec.additive.base[0] + kSelected),
        host.base_grad[kSelected], 5.0e-5f);
    for (int rank = 0; rank < kActorTargetRank; ++rank) {
        expect_near(
            finite_difference(&logits, query + rank),
            host.query_grad[rank], 5.0e-5f);
    }
    const int selected_key = spec.interaction.key_base + kSelected * kActorTargetRank;
    for (int rank = 0; rank < kActorTargetRank; ++rank) {
        expect_near(
            finite_difference(&logits, selected_key + rank),
            host.key_grad[kSelected * kActorTargetRank + rank], 5.0e-5f);
    }

    std::vector<float> saturated(kLogitCount, 0.0f);
    for (int rank = 0; rank < kActorTargetRank; ++rank) {
        saturated[query + rank] = 100.0f;
        saturated[selected_key + rank] = 100.0f;
    }
    const float saturated_score = score_logit(spec, kSelected, FloatReader{saturated.data()});
    assert(saturated_score >= kActorTargetBound - 1.0e-6f);
    assert(saturated_score <= kActorTargetBound + 1.0e-6f);

    std::puts("cnc_micro ABI13 bounded actor-target CPU/CUDA score and gradient parity ok");
    return 0;
}
