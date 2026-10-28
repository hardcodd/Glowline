#pragma once
#include <windows.h>
#include <d3d11.h>
#include <winrt/Windows.Graphics.Capture.h>
#include <winrt/Windows.Graphics.DirectX.Direct3D11.h>
#include <vector>
#include <string>
#include <atomic>
#include <memory>

namespace glowline {
struct Display {
    HMONITOR monitor;
    std::wstring device, name;
};
std::vector<Display> displays();

/* Worker-thread-owned capture. Frames are copied before closing WGC surfaces;
 * the GPU downsamples linear RGBA-half to the same 344px boundary as macOS. */
class Capture {
    winrt::com_ptr<ID3D11Device> device_;
    winrt::com_ptr<ID3D11DeviceContext> context_;
    winrt::com_ptr<ID3D11VertexShader> vertex_;
    winrt::com_ptr<ID3D11PixelShader> pixel_;
    winrt::com_ptr<ID3D11SamplerState> sampler_;
    winrt::com_ptr<ID3D11Texture2D> reduced_, staging_;
    winrt::com_ptr<ID3D11RenderTargetView> target_;
    winrt::Windows::Graphics::DirectX::Direct3D11::IDirect3DDevice runtime_{nullptr};
    winrt::Windows::Graphics::Capture::GraphicsCaptureItem item_{nullptr};
    winrt::Windows::Graphics::Capture::Direct3D11CaptureFramePool pool_{nullptr};
    winrt::Windows::Graphics::Capture::GraphicsCaptureSession session_{nullptr};
    winrt::Windows::Graphics::Capture::GraphicsCaptureItem::Closed_revoker closed_;
    std::shared_ptr<std::atomic<bool>> ended_ = std::make_shared<std::atomic<bool>>(false);
    int source_width_ = 0, source_height_ = 0;
    void resize(int width, int height);

  public:
    std::vector<uint8_t> pixels;
    size_t width = 0, height = 0, stride = 0;
    uint64_t frames = 0;
    bool ready = false;
    explicit Capture(std::wstring const &display);
    ~Capture();
    bool poll();
};
} // namespace glowline
