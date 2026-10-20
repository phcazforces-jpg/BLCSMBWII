#pragma once

#include <cstdint>

#if defined(MKW_ENABLE_SFML)

namespace SfmlPresenter {

bool IsEnabled();
bool Initialize(uint32_t width, uint32_t height, const char* title);
void Shutdown();
void PollEvents();
bool IsOpen();
void PresentXfb(const void* xfbPixels, uint32_t width, uint32_t height);
void PresentRgba(const void* rgbaPixels, uint32_t width, uint32_t height);

} // namespace SfmlPresenter

#endif // MKW_ENABLE_SFML
