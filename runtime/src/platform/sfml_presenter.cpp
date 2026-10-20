#include "sfml_presenter.h"

#if defined(MKW_ENABLE_SFML)

#include <SFML/Graphics.hpp>
#include <algorithm>
#include <iostream>
#include <memory>
#include <mutex>
#include <vector>

namespace SfmlPresenter {
namespace {

std::unique_ptr<sf::RenderWindow> g_window;
sf::Texture g_texture;
std::unique_ptr<sf::Sprite> g_sprite;
std::vector<uint32_t> g_rgbaBuffer;
std::mutex g_mutex;
bool g_enabled = false;

inline uint32_t YuvToRgba(int y, int u, int v) noexcept {
    int r = std::clamp(y + (1402 * v) / 1000, 0, 255);
    int g = std::clamp(y - (344 * u + 714 * v) / 1000, 0, 255);
    int b = std::clamp(y + (1772 * u) / 1000, 0, 255);
    return 0xFF000000u | (static_cast<uint32_t>(b) << 16) | (static_cast<uint32_t>(g) << 8) | static_cast<uint32_t>(r);
}

} // namespace

bool IsEnabled() {
    return g_enabled && g_window && g_window->isOpen();
}

bool Initialize(uint32_t width, uint32_t height, const char* title) {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (width == 0) width = 1280;
    if (height == 0) height = 720;

    sf::ContextSettings settings;
    settings.majorVersion = 3;
    settings.minorVersion = 3;
    settings.attributeFlags = sf::ContextSettings::Core;

    g_window = std::make_unique<sf::RenderWindow>(
        sf::VideoMode({width, height}),
        (title && title[0] != '\0') ? title : "New Super Mario Bros. Wii (SFML/OpenGL Core)",
        sf::Style::Default,
        sf::State::Windowed,
        settings
    );

    if (!g_window || !g_window->isOpen()) {
        std::cerr << "[SfmlPresenter] Failed to create SFML 3.1.0 render window\n";
        g_enabled = false;
        return false;
    }

    g_window->setVerticalSyncEnabled(true);
    if (!g_texture.resize({640, 480})) {
        std::cerr << "[SfmlPresenter] Failed to allocate texture\n";
    }
    g_sprite = std::make_unique<sf::Sprite>(g_texture);
    g_rgbaBuffer.resize(640 * 480, 0xFF000000u);

    g_enabled = true;
    std::cout << "[SfmlPresenter] Initialized SFML 3.1.0 with OpenGL 3.3 Core presentation\n";
    return true;
}

void Shutdown() {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (g_window) {
        if (g_window->isOpen()) {
            g_window->close();
        }
        g_window.reset();
    }
    g_sprite.reset();
    g_enabled = false;
}

void PollEvents() {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_window || !g_window->isOpen()) return;

    while (const auto event = g_window->pollEvent()) {
        if (event->is<sf::Event::Closed>()) {
            g_window->close();
        }
    }
}

bool IsOpen() {
    return g_window && g_window->isOpen();
}

void PresentRgba(const void* rgbaPixels, uint32_t width, uint32_t height) {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_window || !g_window->isOpen() || !rgbaPixels || width == 0 || height == 0) {
        return;
    }

    if (g_texture.getSize().x != width || g_texture.getSize().y != height) {
        g_texture.resize({width, height});
        g_sprite = std::make_unique<sf::Sprite>(g_texture);
    }

    g_texture.update(reinterpret_cast<const uint8_t*>(rgbaPixels));

    sf::Vector2u winSize = g_window->getSize();
    float scaleX = static_cast<float>(winSize.x) / width;
    float scaleY = static_cast<float>(winSize.y) / height;
    float scale = std::min(scaleX, scaleY);

    g_sprite->setScale({scale, scale});
    g_sprite->setPosition({
        (winSize.x - width * scale) * 0.5f,
        (winSize.y - height * scale) * 0.5f
    });

    g_window->clear(sf::Color::Black);
    g_window->draw(*g_sprite);
    g_window->display();
}

void PresentXfb(const void* xfbPixels, uint32_t width, uint32_t height) {
    if (!xfbPixels || width == 0 || height == 0) return;

    const size_t totalPixels = width * height;
    if (g_rgbaBuffer.size() < totalPixels) {
        g_rgbaBuffer.resize(totalPixels);
    }

    const uint8_t* src = reinterpret_cast<const uint8_t*>(xfbPixels);
    uint32_t* dst = g_rgbaBuffer.data();

    // GameCube/Wii XFB format is YUYV 4:2:2 (Y0, U, Y1, V)
    const size_t numPairs = totalPixels / 2;
    for (size_t i = 0; i < numPairs; ++i) {
        int y0 = src[i * 4 + 0];
        int u  = static_cast<int>(src[i * 4 + 1]) - 128;
        int y1 = src[i * 4 + 2];
        int v  = static_cast<int>(src[i * 4 + 3]) - 128;

        dst[i * 2 + 0] = YuvToRgba(y0, u, v);
        dst[i * 2 + 1] = YuvToRgba(y1, u, v);
    }

    PresentRgba(g_rgbaBuffer.data(), width, height);
}

} // namespace SfmlPresenter

#endif // MKW_ENABLE_SFML
