#define PRECISION_FLOAT

#include "../src/kernels.cu"

#include <cmath>
#include <cstdio>

int main() {
    const unsigned char input[] = {0, 1, 127, 255};
    const float expected[] = {0.0f, 1.0f / 255.0f, 127.0f / 255.0f, 1.0f};
    unsigned char* device_input = nullptr;
    precision_t* device_output = nullptr;
    float output[4] = {};

    if (cudaMalloc(&device_input, sizeof(input)) != cudaSuccess
        || cudaMalloc(&device_output, sizeof(output)) != cudaSuccess) {
        return 1;
    }
    cudaMemcpy(device_input, input, sizeof(input), cudaMemcpyHostToDevice);
    cast_scaled_dispatch(device_output, device_input, 4, 1.0f / 255.0f, 0);
    cudaMemcpy(output, device_output, sizeof(output), cudaMemcpyDeviceToHost);
    cudaFree(device_output);
    cudaFree(device_input);

    for (int index = 0; index < 4; ++index) {
        if (std::fabs(output[index] - expected[index]) > 0.000001f) {
            std::fprintf(stderr, "index=%d expected=%f actual=%f\n", index, expected[index], output[index]);
            return 2;
        }
    }
    std::printf("scaled_byte_cast=pass\n");
    return 0;
}
