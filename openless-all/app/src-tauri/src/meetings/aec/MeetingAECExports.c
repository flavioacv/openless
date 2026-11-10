// Export the private upstream archive ABI through an isolated macOS 15 library.
#include "FluidAEC3Bridge.h"

__attribute__((visibility("default"))) FVAEC3Engine* openless_aec3_create_48k_mono(void) {
    return fv_aec3_create_48k_mono();
}
__attribute__((visibility("default"))) void openless_aec3_destroy(FVAEC3Engine* engine) {
    fv_aec3_destroy(engine);
}
__attribute__((visibility("default"))) FVAEC3Status openless_aec3_reset(FVAEC3Engine* engine) {
    return fv_aec3_reset(engine);
}
__attribute__((visibility("default"))) FVAEC3Status openless_aec3_process_10ms(
    FVAEC3Engine* engine, const float* render, const float* capture, float* output, FVAEC3Stats* stats) {
    return fv_aec3_process_10ms(engine, render, capture, output, stats);
}
__attribute__((visibility("default"))) const char* openless_aec3_upstream_revision(void) {
    return fv_aec3_upstream_revision();
}
__attribute__((visibility("default"))) const char* openless_aec3_configuration_id(void) {
    return fv_aec3_configuration_id();
}
