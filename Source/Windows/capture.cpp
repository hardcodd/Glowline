#include "capture.h"
#include <d3dcompiler.h>
#include <windows.graphics.capture.interop.h>
#include <windows.graphics.directx.direct3d11.interop.h>
#include <winrt/Windows.Foundation.h>
#include <algorithm>
#include <cmath>
#include <stdexcept>

namespace glowline {
using namespace winrt;
using namespace winrt::Windows::Graphics;
using namespace winrt::Windows::Graphics::Capture;
using namespace winrt::Windows::Graphics::DirectX;
using namespace winrt::Windows::Graphics::DirectX::Direct3D11;
std::vector<Display> displays() {
    std::vector<Display> result;
    EnumDisplayMonitors(
        nullptr, nullptr,
        [](HMONITOR monitor, HDC, LPRECT, LPARAM data) -> BOOL {
            auto &out = *reinterpret_cast<std::vector<Display> *>(data);
            MONITORINFOEXW info{};
            info.cbSize = sizeof(info);
            if (GetMonitorInfoW(monitor, &info)) {
                DISPLAY_DEVICEW device{};
                device.cb = sizeof(device);
                EnumDisplayDevicesW(info.szDevice, 0, &device, 0);
                out.push_back({monitor, info.szDevice,
                               std::wstring(info.szDevice) + L" — " + device.DeviceString});
            }
            return TRUE;
        },
        reinterpret_cast<LPARAM>(&result));
    return result;
}
static com_ptr<ID3DBlob> shader(char const *source, char const *entry, char const *target) {
    com_ptr<ID3DBlob> code, errors;
    check_hresult(D3DCompile(source, strlen(source), nullptr, nullptr, nullptr, entry, target,
                             D3DCOMPILE_OPTIMIZATION_LEVEL3, 0, code.put(), errors.put()));
    return code;
}
Capture::Capture(std::wstring const &selected) {
    if (!GraphicsCaptureSession::IsSupported())
        throw std::runtime_error("Windows Graphics Capture unavailable");
    auto monitors = displays();
    if (monitors.empty())
        throw std::runtime_error("No active display");
    auto it = std::find_if(monitors.begin(), monitors.end(),
                           [&](auto const &d) { return d.device == selected; });
    if (it == monitors.end()) {
        if (!selected.empty())
            throw std::runtime_error("Selected display disconnected");
        HMONITOR primary = MonitorFromPoint(POINT{0, 0}, MONITOR_DEFAULTTOPRIMARY);
        it = std::find_if(monitors.begin(), monitors.end(),
                          [&](auto const &d) { return d.monitor == primary; });
        if (it == monitors.end())
            it = monitors.begin();
    }
    D3D_FEATURE_LEVEL level;
    HRESULT created = D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr,
                                        D3D11_CREATE_DEVICE_BGRA_SUPPORT, nullptr, 0,
                                        D3D11_SDK_VERSION, device_.put(), &level, context_.put());
    // Display-only virtual adapters have no hardware D3D device. WARP keeps the
    // same floating-point capture pipeline available on these Windows desktops.
    if (created == DXGI_ERROR_UNSUPPORTED) {
        created = D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_WARP, nullptr,
                                    D3D11_CREATE_DEVICE_BGRA_SUPPORT, nullptr, 0, D3D11_SDK_VERSION,
                                    device_.put(), &level, context_.put());
    }
    check_hresult(created);
    auto dxgi = device_.as<IDXGIDevice>();
    com_ptr<IInspectable> inspectable;
    check_hresult(CreateDirect3D11DeviceFromDXGIDevice(dxgi.get(), inspectable.put()));
    runtime_ = inspectable.as<IDirect3DDevice>();
    auto interop = get_activation_factory<GraphicsCaptureItem, IGraphicsCaptureItemInterop>();
    check_hresult(
        interop->CreateForMonitor(it->monitor, guid_of<GraphicsCaptureItem>(), put_abi(item_)));
    closed_ =
        item_.Closed(auto_revoke, [ended = ended_](auto const &, auto const &) { *ended = true; });
    auto size = item_.Size();
    source_width_ = size.Width;
    source_height_ = size.Height;
    pool_ = Direct3D11CaptureFramePool::CreateFreeThreaded(
        runtime_, DirectXPixelFormat::R16G16B16A16Float, 3, size);
    session_ = pool_.CreateCaptureSession(item_);
    session_.IsCursorCaptureEnabled(false);
    constexpr char source[] = R"(
        struct V { float4 position:SV_POSITION;float2 uv:TEXCOORD0; };
        V vs(uint id:SV_VertexID) { V o; o.uv=float2((id<<1)&2,id&2);o.position=float4(o.uv*float2(2,-2)+float2(-1,1),0,1);return o; }
        Texture2D<float4> image:register(t0);SamplerState sampleLinear:register(s0);
        float4 ps(V input):SV_TARGET { return image.SampleLevel(sampleLinear,input.uv,0); }
    )";
    auto v = shader(source, "vs", "vs_4_0"), p = shader(source, "ps", "ps_4_0");
    check_hresult(device_->CreateVertexShader(v->GetBufferPointer(), v->GetBufferSize(), nullptr,
                                              vertex_.put()));
    check_hresult(device_->CreatePixelShader(p->GetBufferPointer(), p->GetBufferSize(), nullptr,
                                             pixel_.put()));
    D3D11_SAMPLER_DESC desc{};
    desc.Filter = D3D11_FILTER_MIN_MAG_MIP_LINEAR;
    desc.AddressU = desc.AddressV = desc.AddressW = D3D11_TEXTURE_ADDRESS_CLAMP;
    desc.MaxLOD = D3D11_FLOAT32_MAX;
    check_hresult(device_->CreateSamplerState(&desc, sampler_.put()));
    resize(size.Width, size.Height);
    session_.StartCapture();
}
void Capture::resize(int sw, int sh) {
    if (sw <= 0 || sh <= 0 || sw > 32768 || sh > 32768)
        throw std::runtime_error("Invalid capture size");
    width = 344;
    height = std::max<size_t>(1, static_cast<size_t>(std::lround(344. * sh / sw)));
    stride = width * 8;
    pixels.assign(stride * height, 0);
    ready = false;
    target_ = nullptr;
    reduced_ = nullptr;
    staging_ = nullptr;
    D3D11_TEXTURE2D_DESC d{};
    d.Width = static_cast<UINT>(width);
    d.Height = static_cast<UINT>(height);
    d.MipLevels = d.ArraySize = 1;
    d.Format = DXGI_FORMAT_R16G16B16A16_FLOAT;
    d.SampleDesc.Count = 1;
    d.Usage = D3D11_USAGE_DEFAULT;
    d.BindFlags = D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE;
    check_hresult(device_->CreateTexture2D(&d, nullptr, reduced_.put()));
    check_hresult(device_->CreateRenderTargetView(reduced_.get(), nullptr, target_.put()));
    d.BindFlags = 0;
    d.Usage = D3D11_USAGE_STAGING;
    d.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
    check_hresult(device_->CreateTexture2D(&d, nullptr, staging_.put()));
}
bool Capture::poll() {
    if (*ended_)
        throw std::runtime_error("Capture display closed");
    auto frame = pool_.TryGetNextFrame();
    if (!frame)
        return false;
    // Drain queued snapshots so output uses the latest desktop, not a FIFO backlog.
    while (auto newer = pool_.TryGetNextFrame()) {
        frame.Close();
        frame = std::move(newer);
    }
    auto size = frame.ContentSize();
    if (size.Width != source_width_ || size.Height != source_height_) {
        frame.Close();
        source_width_ = size.Width;
        source_height_ = size.Height;
        resize(size.Width, size.Height);
        pool_.Recreate(runtime_, DirectXPixelFormat::R16G16B16A16Float, 3, size);
        return false;
    }
    auto access = frame.Surface()
                      .as<::Windows::Graphics::DirectX::Direct3D11::IDirect3DDxgiInterfaceAccess>();
    com_ptr<ID3D11Texture2D> texture;
    check_hresult(access->GetInterface(__uuidof(ID3D11Texture2D), texture.put_void()));
    com_ptr<ID3D11ShaderResourceView> view;
    check_hresult(device_->CreateShaderResourceView(texture.get(), nullptr, view.put()));
    auto target = target_.get();
    auto sampler = sampler_.get();
    auto resource = view.get();
    context_->OMSetRenderTargets(1, &target, nullptr);
    D3D11_VIEWPORT viewport{0, 0, static_cast<float>(width), static_cast<float>(height), 0, 1};
    context_->RSSetViewports(1, &viewport);
    context_->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
    context_->VSSetShader(vertex_.get(), nullptr, 0);
    context_->PSSetShader(pixel_.get(), nullptr, 0);
    context_->PSSetSamplers(0, 1, &sampler);
    context_->PSSetShaderResources(0, 1, &resource);
    context_->Draw(3, 0);
    ID3D11ShaderResourceView *empty = nullptr;
    context_->PSSetShaderResources(0, 1, &empty);
    context_->CopyResource(staging_.get(), reduced_.get());
    D3D11_MAPPED_SUBRESOURCE mapped{};
    check_hresult(context_->Map(staging_.get(), 0, D3D11_MAP_READ, 0, &mapped));
    for (size_t y = 0; y < height; y++)
        memcpy(pixels.data() + y * stride,
               static_cast<uint8_t *>(mapped.pData) + y * mapped.RowPitch, stride);
    context_->Unmap(staging_.get(), 0);
    frame.Close();
    ready = true;
    frames++;
    return true;
}
Capture::~Capture() {
    closed_.revoke();
    // Device removal can make Close fail; cleanup must not terminate the worker.
    try {
        if (session_)
            session_.Close();
    } catch (winrt::hresult_error const &error) {
        OutputDebugStringW(error.message().c_str());
    }
    try {
        if (pool_)
            pool_.Close();
    } catch (winrt::hresult_error const &error) {
        OutputDebugStringW(error.message().c_str());
    }
}
} // namespace glowline
