// Author: Cheatoid ~ https://github.com/Cheatoid
// License: MIT

#include "imgui.h"
#include "imgui_impl_glfw.h"
#include "imgui_impl_wgpu.h"
#include <stdio.h>
#include <stdlib.h>
#include <string>
#include <GLFW/glfw3.h>

#ifdef __EMSCRIPTEN__
#include <emscripten.h>
#include <emscripten/html5.h>
#include <emscripten/val.h>
#include "emscripten_mainloop_stub.h"
#endif

#include <webgpu/webgpu.h>
#if defined(IMGUI_IMPL_WEBGPU_BACKEND_DAWN)
#include <webgpu/webgpu_cpp.h>
#endif

// Data
static WGPUInstance             wgpu_instance = nullptr;
static WGPUDevice               wgpu_device = nullptr;
static WGPUSurface              wgpu_surface = nullptr;
static WGPUQueue                wgpu_queue = nullptr;
static WGPUSurfaceConfiguration wgpu_surface_configuration = {};
static int                      wgpu_surface_width = 1280;
static int                      wgpu_surface_height = 800;

#ifdef __EMSCRIPTEN__
extern "C" void EMSCRIPTEN_KEEPALIVE imgui_ShowWebGPUError(const char* message);
#endif

// Forward declarations
static bool InitWGPU(GLFWwindow* window);
WGPUSurface CreateWGPUSurface(const WGPUInstance& instance, GLFWwindow* window);
#ifdef __EMSCRIPTEN__
extern "C" void imgui_CallJSRender();
#endif

static void glfw_error_callback(int error, const char* description)
{
	printf("GLFW Error %d: %s\n", error, description);
}

static void ResizeSurface(int width, int height)
{
	wgpu_surface_configuration.width = wgpu_surface_width = width;
	wgpu_surface_configuration.height = wgpu_surface_height = height;
	wgpuSurfaceConfigure(wgpu_surface, &wgpu_surface_configuration);
}

// Main code
int main(int, char**)
{
	glfwSetErrorCallback(glfw_error_callback);
	if (!glfwInit())
		return 1;

	// Make sure GLFW does not initialize any graphics context.
	// This needs to be done explicitly later.
	glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);

	// Create window
	float main_scale = ImGui_ImplGlfw_GetContentScaleForMonitor(glfwGetPrimaryMonitor()); // Valid on GLFW 3.3+ only
	wgpu_surface_width = (int)(wgpu_surface_width * main_scale);
	wgpu_surface_height = (int)(wgpu_surface_height * main_scale);
	GLFWwindow* window = glfwCreateWindow(wgpu_surface_width, wgpu_surface_height, "ImGui", nullptr, nullptr);
	if (window == nullptr)
		return 1;

	// Initialize the WebGPU environment
	if (!InitWGPU(window))
	{
		glfwDestroyWindow(window);
		glfwTerminate();
		return 1;
	}

	glfwShowWindow(window);

	// Setup Dear ImGui context
	IMGUI_CHECKVERSION();
	ImGui::CreateContext();
	ImGuiIO& io = ImGui::GetIO(); (void)io;
	io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;     // Enable Keyboard Controls
	io.ConfigFlags |= ImGuiConfigFlags_NavEnableGamepad;      // Enable Gamepad Controls
	io.ConfigFlags |= ImGuiConfigFlags_DockingEnable;         // Enable Docking

	// Setup Dear ImGui style
	ImGui::StyleColorsDark();
	//ImGui::StyleColorsLight();

	// Setup scaling
	ImGuiStyle& style = ImGui::GetStyle();
	style.ScaleAllSizes(main_scale);        // Bake a fixed style scale. (until we have a solution for dynamic style scaling, changing this requires resetting Style + calling this again)
	style.FontScaleDpi = main_scale;        // Set initial font scale. (in docking branch: using io.ConfigDpiScaleFonts=true automatically overrides this for every window depending on the current monitor)

	// Setup Platform/Renderer backends
	ImGui_ImplGlfw_InitForOther(window, true);
#ifdef __EMSCRIPTEN__
	ImGui_ImplGlfw_InstallEmscriptenCallbacks(window, "#canvas");
#endif
	ImGui_ImplWGPU_InitInfo init_info;
	init_info.Device = wgpu_device;
	init_info.NumFramesInFlight = 3;
	init_info.RenderTargetFormat = wgpu_surface_configuration.format;
	init_info.DepthStencilFormat = WGPUTextureFormat_Undefined;
	ImGui_ImplWGPU_Init(&init_info);

	// Load Fonts
	// - If fonts are not explicitly loaded, Dear ImGui will select an embedded font: either AddFontDefaultVector() or AddFontDefaultBitmap().
	//   This selection is based on (style.FontSizeBase * style.FontScaleMain * style.FontScaleDpi) reaching a small threshold.
	// - You can load multiple fonts and use ImGui::PushFont()/PopFont() to select them.
	// - If a file cannot be loaded, AddFont functions will return a nullptr. Please handle those errors in your code (e.g. use an assertion, display an error and quit).
	// - Read 'docs/FONTS.md' for more instructions and details.
	// - Use '#define IMGUI_ENABLE_FREETYPE' in your imconfig file to use FreeType for higher quality font rendering.
	// - Remember that in C/C++ if you want to include a backslash \ in a string literal you need to write a double backslash \\ !
	// - Our Emscripten build process allows embedding fonts to be accessible at runtime from the "fonts/" folder. See Makefile.emscripten for details.
	//style.FontSizeBase = 20.0f;
	//io.Fonts->AddFontDefaultVector();
	//io.Fonts->AddFontDefaultBitmap();
#ifndef IMGUI_DISABLE_FILE_FUNCTIONS
	//io.Fonts->AddFontFromFileTTF("fonts/segoeui.ttf");
	//io.Fonts->AddFontFromFileTTF("fonts/DroidSans.ttf");
	//io.Fonts->AddFontFromFileTTF("fonts/Roboto-Medium.ttf");
	//io.Fonts->AddFontFromFileTTF("fonts/Cousine-Regular.ttf");
	//ImFont* font = io.Fonts->AddFontFromFileTTF("fonts/ArialUni.ttf");
	//IM_ASSERT(font != nullptr);
#endif

	// Our state
	bool show_demo_window = true;
	bool show_another_window = false;
#ifdef __EMSCRIPTEN__
	ImVec4 clear_color = ImVec4(0.0f, 0.0f, 0.0f, 0.0f); // Transparent
#else
	ImVec4 clear_color = ImVec4(0.45f, 0.55f, 0.60f, 1.00f);
#endif

	// Main loop
#ifdef __EMSCRIPTEN__
	// For an Emscripten build we are disabling file-system access, so let's not attempt to do a fopen() of the imgui.ini file.
	// You may manually call LoadIniSettingsFromMemory() to load settings from your own storage.
	io.IniFilename = nullptr;
	EMSCRIPTEN_MAINLOOP_BEGIN
#else
	while (!glfwWindowShouldClose(window))
#endif
	{
		// Poll and handle events (inputs, window resize, etc.)
		// You can read the io.WantCaptureMouse, io.WantCaptureKeyboard flags to tell if dear imgui wants to use your inputs.
		// - When io.WantCaptureMouse is true, do not dispatch mouse input data to your main application, or clear/overwrite your copy of the mouse data.
		// - When io.WantCaptureKeyboard is true, do not dispatch keyboard input data to your main application, or clear/overwrite your copy of the keyboard data.
		// Generally you may always pass all inputs to dear imgui, and hide them from your application based on those two flags.
		glfwPollEvents();
		if (glfwGetWindowAttrib(window, GLFW_ICONIFIED) != 0)
		{
			ImGui_ImplGlfw_Sleep(10);
			continue;
		}

		// React to changes in screen size
		int width, height;
		glfwGetFramebufferSize((GLFWwindow*)window, &width, &height);
		if (width != wgpu_surface_width || height != wgpu_surface_height)
			ResizeSurface(width, height);

		// Check surface status for error. If texture is not optimal, try to reconfigure the surface.
		WGPUSurfaceTexture surface_texture;
		wgpuSurfaceGetCurrentTexture(wgpu_surface, &surface_texture);
		if (ImGui_ImplWGPU_IsSurfaceStatusError(surface_texture.status))
		{
			fprintf(stderr, "Unrecoverable Surface Texture status=%#.8x\n", surface_texture.status);
			abort();
		}
		if (ImGui_ImplWGPU_IsSurfaceStatusSubOptimal(surface_texture.status))
		{
			if (surface_texture.texture)
				wgpuTextureRelease(surface_texture.texture);
			if (width > 0 && height > 0)
				ResizeSurface(width, height);
			continue;
		}

		// Start the Dear ImGui frame
		ImGui_ImplWGPU_NewFrame();
		ImGui_ImplGlfw_NewFrame();
		ImGui::NewFrame();

#ifdef __EMSCRIPTEN__
		// Call JavaScript render function for UI
		imgui_CallJSRender();
#else
		// 1. Show the big demo window (Most of the sample code is in ImGui::ShowDemoWindow()! You can browse its code to learn more about Dear ImGui!).
		if (show_demo_window)
			ImGui::ShowDemoWindow(&show_demo_window);

		// 2. Show a simple window that we create ourselves. We use a Begin/End pair to create a named window.
		{
			static float f = 0.0f;
			static int counter = 0;

			ImGui::Begin("Hello, world!");                                // Create a window called "Hello, world!" and append into it.

			ImGui::Text("This is some useful text.");                     // Display some text (you can use a format strings too)
			ImGui::Checkbox("Demo Window", &show_demo_window);            // Edit bools storing our window open/close state
			ImGui::Checkbox("Another Window", &show_another_window);

			ImGui::SliderFloat("float", &f, 0.0f, 1.0f);                  // Edit 1 float using a slider from 0.0f to 1.0f
			ImGui::ColorEdit3("clear color", (float*)&clear_color);       // Edit 3 floats representing a color

			if (ImGui::Button("Button"))                                  // Buttons return true when clicked (most widgets return true when edited/activated)
				counter++;
			ImGui::SameLine();
			ImGui::Text("counter = %d", counter);

			ImGui::Text("Application average %.3f ms/frame (%.1f FPS)", 1000.0f / io.Framerate, io.Framerate);
			ImGui::End();
		}

		// 3. Show another simple window.
		if (show_another_window)
		{
			ImGui::Begin("Another Window", &show_another_window);         // Pass a pointer to our bool variable (the window will have a closing button that will clear the bool when clicked)
			ImGui::Text("Hello from another window!");
			if (ImGui::Button("Close Me"))
				show_another_window = false;
			ImGui::End();
		}
#endif

		// Rendering
		ImGui::Render();

		WGPUTextureViewDescriptor view_desc = {};
		view_desc.format = wgpu_surface_configuration.format;
		view_desc.dimension = WGPUTextureViewDimension_2D ;
		view_desc.mipLevelCount = WGPU_MIP_LEVEL_COUNT_UNDEFINED;
		view_desc.arrayLayerCount = WGPU_ARRAY_LAYER_COUNT_UNDEFINED;
		view_desc.aspect = WGPUTextureAspect_All;

		WGPUTextureView texture_view = wgpuTextureCreateView(surface_texture.texture, &view_desc);

		WGPURenderPassColorAttachment color_attachments = {};
		color_attachments.depthSlice = WGPU_DEPTH_SLICE_UNDEFINED;
		color_attachments.loadOp = WGPULoadOp_Clear;
		color_attachments.storeOp = WGPUStoreOp_Store;
		color_attachments.clearValue = { clear_color.x * clear_color.w, clear_color.y * clear_color.w, clear_color.z * clear_color.w, clear_color.w };
		color_attachments.view = texture_view;

		WGPURenderPassDescriptor render_pass_desc = {};
		render_pass_desc.colorAttachmentCount = 1;
		render_pass_desc.colorAttachments = &color_attachments;
		render_pass_desc.depthStencilAttachment = nullptr;

		WGPUCommandEncoderDescriptor enc_desc = {};
		WGPUCommandEncoder encoder = wgpuDeviceCreateCommandEncoder(wgpu_device, &enc_desc);

		WGPURenderPassEncoder pass = wgpuCommandEncoderBeginRenderPass(encoder, &render_pass_desc);
		ImGui_ImplWGPU_RenderDrawData(ImGui::GetDrawData(), pass);
		wgpuRenderPassEncoderEnd(pass);

		WGPUCommandBufferDescriptor cmd_buffer_desc = {};
		WGPUCommandBuffer cmd_buffer = wgpuCommandEncoderFinish(encoder, &cmd_buffer_desc);
		wgpuQueueSubmit(wgpu_queue, 1, &cmd_buffer);

#ifndef __EMSCRIPTEN__
		wgpuSurfacePresent(wgpu_surface);
		// Tick needs to be called in Dawn to display validation errors
#if defined(IMGUI_IMPL_WEBGPU_BACKEND_DAWN)
		wgpuDeviceTick(wgpu_device);
#endif
#endif
		wgpuTextureViewRelease(texture_view);
		wgpuRenderPassEncoderRelease(pass);
		wgpuCommandEncoderRelease(encoder);
		wgpuCommandBufferRelease(cmd_buffer);
	}
#ifdef __EMSCRIPTEN__
	EMSCRIPTEN_MAINLOOP_END;
#endif

	// Cleanup
	ImGui_ImplWGPU_Shutdown();
	ImGui_ImplGlfw_Shutdown();
	ImGui::DestroyContext();

	wgpuSurfaceUnconfigure(wgpu_surface);
	wgpuSurfaceRelease(wgpu_surface);
	wgpuQueueRelease(wgpu_queue);
	wgpuDeviceRelease(wgpu_device);
	wgpuInstanceRelease(wgpu_instance);

	glfwDestroyWindow(window);
	glfwTerminate();

	return 0;
}

#if defined(IMGUI_IMPL_WEBGPU_BACKEND_DAWN)
static WGPUAdapter RequestAdapter(wgpu::Instance& instance)
{
	wgpu::Adapter acquired_adapter;
	wgpu::RequestAdapterOptions adapter_options;
	auto onRequestAdapter = [&](wgpu::RequestAdapterStatus status, wgpu::Adapter adapter, wgpu::StringView message)
	{
		if (status != wgpu::RequestAdapterStatus::Success)
		{
			printf("Failed to get an adapter: %s\n", message.data);
			acquired_adapter = nullptr;
			return;
		}
		acquired_adapter = std::move(adapter);
	};

	// Synchronously (wait until) acquire Adapter
	wgpu::Future waitAdapterFunc { instance.RequestAdapter(&adapter_options, wgpu::CallbackMode::WaitAnyOnly, onRequestAdapter) };
	wgpu::WaitStatus waitStatusAdapter = instance.WaitAny(waitAdapterFunc, UINT64_MAX);
	if (!acquired_adapter || waitStatusAdapter != wgpu::WaitStatus::Success)
		return nullptr;
	return acquired_adapter.MoveToCHandle();
}

static WGPUDevice RequestDevice(wgpu::Instance& instance, wgpu::Adapter& adapter)
{
	// Set device callback functions
	wgpu::DeviceDescriptor device_desc;
	device_desc.SetDeviceLostCallback(wgpu::CallbackMode::AllowSpontaneous,
		[](const wgpu::Device&, wgpu::DeviceLostReason type, wgpu::StringView msg) { fprintf(stderr, "%s error: %s\n", ImGui_ImplWGPU_GetDeviceLostReasonName((WGPUDeviceLostReason)type), msg.data); }
	);
	device_desc.SetUncapturedErrorCallback(
		[](const wgpu::Device&, wgpu::ErrorType type, wgpu::StringView msg) { fprintf(stderr, "%s error: %s\n", ImGui_ImplWGPU_GetErrorTypeName((WGPUErrorType)type), msg.data); }
	);

	wgpu::Device acquired_device;
	auto onRequestDevice = [&](wgpu::RequestDeviceStatus status, wgpu::Device local_device, wgpu::StringView message)
	{
		if (status != wgpu::RequestDeviceStatus::Success)
		{
			printf("Failed to get an device: %s\n", message.data);
			acquired_device = nullptr;
			return;
		}
		acquired_device = std::move(local_device);
	};

	// Synchronously (wait until) get Device
	wgpu::Future waitDeviceFunc { adapter.RequestDevice(&device_desc, wgpu::CallbackMode::WaitAnyOnly, onRequestDevice) };
	wgpu::WaitStatus waitStatusDevice = instance.WaitAny(waitDeviceFunc, UINT64_MAX);
	if (!acquired_device || waitStatusDevice != wgpu::WaitStatus::Success)
		return nullptr;
	return acquired_device.MoveToCHandle();
}
#elif defined(IMGUI_IMPL_WEBGPU_BACKEND_WGPU) || defined(IMGUI_IMPL_WEBGPU_BACKEND_WGVK)
static void handle_request_adapter(WGPURequestAdapterStatus status, WGPUAdapter adapter, WGPUStringView message, void* userdata1, void* userdata2)
{
	IM_UNUSED(userdata2);
	WGPUAdapter* extAdapter = (WGPUAdapter*)userdata1;
	if (status == WGPURequestAdapterStatus_Success)
	{
		*extAdapter = adapter;
	}
	else
	{
		*extAdapter = nullptr;
		printf("Request_adapter status=%#.8x message=%.*s\n", status, (int) message.length, message.data);
	}
}

static void handle_request_device(WGPURequestDeviceStatus status, WGPUDevice device, WGPUStringView message, void* userdata1, void* userdata2)
{
	IM_UNUSED(userdata2);
	WGPUDevice* extDevice = (WGPUDevice*)userdata1;
	if (status == WGPURequestDeviceStatus_Success)
	{
		*extDevice = device;
	}
	else
	{
		*extDevice = nullptr;
		printf("Request_device status=%#.8x message=%.*s\n", status, (int) message.length, message.data);
	}
}

static WGPUAdapter RequestAdapter(WGPUInstance& instance)
{
	WGPURequestAdapterOptions adapter_options = {};

	WGPUAdapter local_adapter = nullptr;
	WGPURequestAdapterCallbackInfo adapterCallbackInfo = {};
	adapterCallbackInfo.mode = WGPUCallbackMode_WaitAnyOnly;
	adapterCallbackInfo.callback = handle_request_adapter;
	adapterCallbackInfo.userdata1 = &local_adapter;

	WGPUFuture future = wgpuInstanceRequestAdapter(instance, &adapter_options, adapterCallbackInfo);
	WGPUFutureWaitInfo waitInfo = { future, false };
	wgpuInstanceWaitAny(instance, 1, &waitInfo, ~0ull);
	if (!local_adapter)
		return nullptr;
	return local_adapter;
}

static WGPUDevice RequestDevice(WGPUInstance& instance, WGPUAdapter& adapter)
{
	WGPUDevice local_device = nullptr;
	WGPURequestDeviceCallbackInfo deviceCallbackInfo = {};
	deviceCallbackInfo.mode = WGPUCallbackMode_WaitAnyOnly;
	deviceCallbackInfo.callback = handle_request_device;
	deviceCallbackInfo.userdata1 = &local_device;
	WGPUFuture future = wgpuAdapterRequestDevice(adapter, nullptr, deviceCallbackInfo);
	WGPUFutureWaitInfo waitInfo = { future, false };
	wgpuInstanceWaitAny(instance, 1, &waitInfo, ~0ull);
	if (!local_device)
		return nullptr;
	return local_device;
}
#endif // IMGUI_IMPL_WEBGPU_BACKEND_WGPU

bool InitWGPU(GLFWwindow* window)
{
	WGPUTextureFormat preferred_fmt = WGPUTextureFormat_Undefined;  // acquired from SurfaceCapabilities

	// Google DAWN backend: Adapter and Device acquisition, Surface creation
#if defined(IMGUI_IMPL_WEBGPU_BACKEND_DAWN)
	wgpu::InstanceDescriptor instance_desc = {};
	static constexpr wgpu::InstanceFeatureName timedWaitAny = wgpu::InstanceFeatureName::TimedWaitAny;
	instance_desc.requiredFeatureCount = 1;
	instance_desc.requiredFeatures = &timedWaitAny;
	wgpu::Instance instance = wgpu::CreateInstance(&instance_desc);

	wgpu::Adapter adapter = RequestAdapter(instance);
	if (!adapter)
	{
		const char* errorMsg = "Failed to get WebGPU adapter. WebGPU may not be available on this browser. Please use a WebGPU-enabled browser (Chrome 113+, Edge 113+, or Firefox Nightly with WebGPU enabled).";
		printf("ERROR: %s\n", errorMsg);
#ifdef __EMSCRIPTEN__
		imgui_ShowWebGPUError(errorMsg);
#endif
		return false;
	}
	ImGui_ImplWGPU_DebugPrintAdapterInfo(adapter.Get());

	wgpu_device = RequestDevice(instance, adapter);
	if (!wgpu_device)
	{
		const char* errorMsg = "Failed to get WebGPU device. Your browser may not support WebGPU properly.";
		printf("ERROR: %s\n", errorMsg);
#ifdef __EMSCRIPTEN__
		imgui_ShowWebGPUError(errorMsg);
#endif
		return false;
	}

	// Create the surface.
#ifdef __EMSCRIPTEN__
	wgpu::EmscriptenSurfaceSourceCanvasHTMLSelector canvas_desc = {};
	canvas_desc.selector = "#canvas";

	wgpu::SurfaceDescriptor surface_desc = {};
	surface_desc.nextInChain = &canvas_desc;
	wgpu_surface = instance.CreateSurface(&surface_desc).MoveToCHandle();
#else
	wgpu_surface = CreateWGPUSurface(instance.Get(), window);
#endif
	if (!wgpu_surface)
		return false;

	// Moving Dawn objects into WGPU handles
	wgpu_instance = instance.MoveToCHandle();

	WGPUSurfaceCapabilities surface_capabilities = {};
	wgpuSurfaceGetCapabilities(wgpu_surface, adapter.Get(), &surface_capabilities);

	preferred_fmt = surface_capabilities.formats[0];

	// WGPU backend: Adapter and Device acquisition, Surface creation
#elif defined(IMGUI_IMPL_WEBGPU_BACKEND_WGPU) || defined(IMGUI_IMPL_WEBGPU_BACKEND_WGVK)
	WGPUInstanceDescriptor instanceDesc = {};
	WGPUInstanceFeatureName timedWaitAny = WGPUInstanceFeatureName_TimedWaitAny;
	instanceDesc.requiredFeatureCount = 1;
	instanceDesc.requiredFeatures = &timedWaitAny;
	wgpu_instance = wgpuCreateInstance(&instanceDesc);

#if defined(IMGUI_IMPL_WEBGPU_BACKEND_WGPU)
	wgpuSetLogCallback(
		[](WGPULogLevel level, WGPUStringView msg, void* userdata) { fprintf(stderr, "%s: %.*s\n", ImGui_ImplWGPU_GetLogLevelName(level), (int)msg.length, msg.data); }, nullptr
	);
	wgpuSetLogLevel(WGPULogLevel_Warn);
#endif

	WGPUAdapter adapter = RequestAdapter(wgpu_instance);
	if (!adapter)
	{
		const char* errorMsg = "Failed to get WebGPU adapter. WebGPU may not be available on this browser. Please use a WebGPU-enabled browser (Chrome 113+, Edge 113+, or Firefox Nightly with WebGPU enabled).";
		printf("ERROR: %s\n", errorMsg);
#ifdef __EMSCRIPTEN__
		imgui_ShowWebGPUError(errorMsg);
#endif
		return false;
	}
	ImGui_ImplWGPU_DebugPrintAdapterInfo(adapter);

	wgpu_device = RequestDevice(wgpu_instance, adapter);
	if (!wgpu_device)
	{
		const char* errorMsg = "Failed to get WebGPU device. Your browser may not support WebGPU properly.";
		printf("ERROR: %s\n", errorMsg);
#ifdef __EMSCRIPTEN__
		imgui_ShowWebGPUError(errorMsg);
#endif
		return false;
	}

	// Create the surface.
	wgpu_surface = CreateWGPUSurface(wgpu_instance, window);
	if (!wgpu_surface)
		return false;

	WGPUSurfaceCapabilities surface_capabilities = {};
	wgpuSurfaceGetCapabilities(wgpu_surface, adapter, &surface_capabilities);

	preferred_fmt = surface_capabilities.formats[0];
#endif // IMGUI_IMPL_WEBGPU_BACKEND_WGPU

	wgpu_surface_configuration.presentMode = WGPUPresentMode_Fifo;
	wgpu_surface_configuration.alphaMode = WGPUCompositeAlphaMode_Premultiplied;
	wgpu_surface_configuration.usage = WGPUTextureUsage_RenderAttachment;
	wgpu_surface_configuration.width = wgpu_surface_width;
	wgpu_surface_configuration.height = wgpu_surface_height;
	wgpu_surface_configuration.device = wgpu_device;
	wgpu_surface_configuration.format = preferred_fmt;

	wgpuSurfaceConfigure(wgpu_surface, &wgpu_surface_configuration);
	wgpu_queue = wgpuDeviceGetQueue(wgpu_device);

	return true;
}

// GLFW helper to create a WebGPU surface, used only in WGPU-Native. DAWN-Native already has a built-in function
// As of today (2025/10) there is no "official" support in GLFW to create a surface for WebGPU backend
// This stub uses "low level" GLFW calls to acquire information from a specific Window Manager.
// Currently supported platforms: Windows / Linux (X11 and Wayland) / MacOS. Not necessary nor available with EMSCRIPTEN.
#ifndef __EMSCRIPTEN__

#if defined(__linux__) || defined(__FreeBSD__) || defined(__OpenBSD__) || defined(__NetBSD__) || defined(__DragonFly__)
#define GLFW_HAS_X11_OR_WAYLAND     1
#else
#define GLFW_HAS_X11_OR_WAYLAND     0
#endif
#ifdef _WIN32
#undef APIENTRY
#ifndef GLFW_EXPOSE_NATIVE_WIN32    // for glfwGetWin32Window()
#define GLFW_EXPOSE_NATIVE_WIN32
#endif
#elif defined(__APPLE__)
#ifndef GLFW_EXPOSE_NATIVE_COCOA    // for glfwGetCocoaWindow()
#define GLFW_EXPOSE_NATIVE_COCOA
#endif
#elif GLFW_HAS_X11_OR_WAYLAND
#ifndef GLFW_EXPOSE_NATIVE_X11      // for glfwGetX11Display(), glfwGetX11Window() on Freedesktop (Linux, BSD, etc.)
#define GLFW_EXPOSE_NATIVE_X11
#endif
#ifndef GLFW_EXPOSE_NATIVE_WAYLAND
#if defined(__has_include) && __has_include(<wayland-client.h>)
#define GLFW_EXPOSE_NATIVE_WAYLAND
#endif
#endif
#endif
#include <GLFW/glfw3native.h>
#undef Status                       // X11 headers are leaking this and also 'Success', 'Always', 'None', all used in DAWN api. Add #undef if necessary.

WGPUSurface CreateWGPUSurface(const WGPUInstance& instance, GLFWwindow* window)
{
	ImGui_ImplWGPU_CreateSurfaceInfo create_info = {};
	create_info.Instance = instance;
#if defined(GLFW_EXPOSE_NATIVE_COCOA)
	{
		create_info.System = "cocoa";
		create_info.RawWindow = (void*)glfwGetCocoaWindow(window);
		return ImGui_ImplWGPU_CreateWGPUSurfaceHelper(&create_info);
	}
#elif defined(GLFW_EXPOSE_NATIVE_WAYLAND)
	if (glfwGetPlatform() == GLFW_PLATFORM_WAYLAND)
	{
		create_info.System = "wayland";
		create_info.RawDisplay = (void*)glfwGetWaylandDisplay();
		create_info.RawSurface = (void*)glfwGetWaylandWindow(window);
		return ImGui_ImplWGPU_CreateWGPUSurfaceHelper(&create_info);
	}
#elif defined(GLFW_EXPOSE_NATIVE_X11)
	if (glfwGetPlatform() == GLFW_PLATFORM_X11)
	{
		create_info.System = "x11";
		create_info.RawWindow = (void*)glfwGetX11Window(window);
		create_info.RawDisplay = (void*)glfwGetX11Display();
		return ImGui_ImplWGPU_CreateWGPUSurfaceHelper(&create_info);
	}
#elif defined(GLFW_EXPOSE_NATIVE_WIN32)
	{
		create_info.System = "win32";
		create_info.RawWindow = (void*)glfwGetWin32Window(window);
		create_info.RawInstance = (void*)::GetModuleHandle(NULL);
		return ImGui_ImplWGPU_CreateWGPUSurfaceHelper(&create_info);
	}
#else
#error "Unsupported WebGPU native platform!"
	return nullptr;
#endif
}
#endif // #ifndef __EMSCRIPTEN__

#ifdef __EMSCRIPTEN__
// ImGui API exports for JavaScript
using namespace emscripten;

// Window management
extern "C" void EMSCRIPTEN_KEEPALIVE imgui_Begin(const char* name, bool* p_open, ImGuiWindowFlags flags)
{
	ImGui::Begin(name, p_open, flags);
}

extern "C" void EMSCRIPTEN_KEEPALIVE imgui_End()
{
	ImGui::End();
}

extern "C" void EMSCRIPTEN_KEEPALIVE imgui_ShowDemoWindow(bool* p_open)
{
	ImGui::ShowDemoWindow(p_open);
}

extern "C" void EMSCRIPTEN_KEEPALIVE imgui_ShowWebGPUError(const char* message)
{
	val::global().call<void>("showWebGPUError", std::string(message));
}

// ImGuiCond enum values
extern "C" int EMSCRIPTEN_KEEPALIVE imgui_Cond_None() { return ImGuiCond_None; }
extern "C" int EMSCRIPTEN_KEEPALIVE imgui_Cond_Always() { return ImGuiCond_Always; }
extern "C" int EMSCRIPTEN_KEEPALIVE imgui_Cond_Once() { return ImGuiCond_Once; }
extern "C" int EMSCRIPTEN_KEEPALIVE imgui_Cond_FirstUseEver() { return ImGuiCond_FirstUseEver; }
extern "C" int EMSCRIPTEN_KEEPALIVE imgui_Cond_Appearing() { return ImGuiCond_Appearing; }

// ImGuiWindowFlags enum values
extern "C" int EMSCRIPTEN_KEEPALIVE imgui_WindowFlags_None() { return ImGuiWindowFlags_None; }
extern "C" int EMSCRIPTEN_KEEPALIVE imgui_WindowFlags_NoTitleBar() { return ImGuiWindowFlags_NoTitleBar; }
extern "C" int EMSCRIPTEN_KEEPALIVE imgui_WindowFlags_NoResize() { return ImGuiWindowFlags_NoResize; }
extern "C" int EMSCRIPTEN_KEEPALIVE imgui_WindowFlags_NoMove() { return ImGuiWindowFlags_NoMove; }
extern "C" int EMSCRIPTEN_KEEPALIVE imgui_WindowFlags_NoScrollbar() { return ImGuiWindowFlags_NoScrollbar; }
extern "C" int EMSCRIPTEN_KEEPALIVE imgui_WindowFlags_NoCollapse() { return ImGuiWindowFlags_NoCollapse; }
extern "C" int EMSCRIPTEN_KEEPALIVE imgui_WindowFlags_AlwaysAutoResize() { return ImGuiWindowFlags_AlwaysAutoResize; }
extern "C" int EMSCRIPTEN_KEEPALIVE imgui_WindowFlags_MenuBar() { return ImGuiWindowFlags_MenuBar; }

// ImGuiTreeNodeFlags enum values
extern "C" int EMSCRIPTEN_KEEPALIVE imgui_TreeNodeFlags_None() { return ImGuiTreeNodeFlags_None; }
extern "C" int EMSCRIPTEN_KEEPALIVE imgui_TreeNodeFlags_DefaultOpen() { return ImGuiTreeNodeFlags_DefaultOpen; }
extern "C" int EMSCRIPTEN_KEEPALIVE imgui_TreeNodeFlags_Framed() { return ImGuiTreeNodeFlags_Framed; }

// ImGuiSelectableFlags enum values
extern "C" int EMSCRIPTEN_KEEPALIVE imgui_SelectableFlags_None() { return ImGuiSelectableFlags_None; }
extern "C" int EMSCRIPTEN_KEEPALIVE imgui_SelectableFlags_SpanAvailWidth() { return ImGuiSelectableFlags_SpanAllColumns; }
extern "C" int EMSCRIPTEN_KEEPALIVE imgui_SelectableFlags_AllowDoubleClick() { return ImGuiSelectableFlags_AllowDoubleClick; }

// ImGuiTabBarFlags enum values
extern "C" int EMSCRIPTEN_KEEPALIVE imgui_TabBarFlags_None() { return ImGuiTabBarFlags_None; }
extern "C" int EMSCRIPTEN_KEEPALIVE imgui_TabBarFlags_Reorderable() { return ImGuiTabBarFlags_Reorderable; }
extern "C" int EMSCRIPTEN_KEEPALIVE imgui_TabBarFlags_AutoSelectNewTabs() { return ImGuiTabBarFlags_AutoSelectNewTabs; }

// ImGuiTabItemFlags enum values
extern "C" int EMSCRIPTEN_KEEPALIVE imgui_TabItemFlags_None() { return ImGuiTabItemFlags_None; }
extern "C" int EMSCRIPTEN_KEEPALIVE imgui_TabItemFlags_NoCloseWithMiddleMouseButton() { return ImGuiTabItemFlags_NoCloseWithMiddleMouseButton; }

extern "C" void EMSCRIPTEN_KEEPALIVE imgui_SetNextWindowPos(float x, float y, ImGuiCond cond, float pivot_x, float pivot_y)
{
	ImGui::SetNextWindowPos(ImVec2(x, y), cond, ImVec2(pivot_x, pivot_y));
}

extern "C" void EMSCRIPTEN_KEEPALIVE imgui_SetNextWindowSize(float w, float h, ImGuiCond cond)
{
	ImGui::SetNextWindowSize(ImVec2(w, h), cond);
}

extern "C" void EMSCRIPTEN_KEEPALIVE imgui_SetNextWindowCollapsed(bool collapsed, ImGuiCond cond)
{
	ImGui::SetNextWindowCollapsed(collapsed, cond);
}

// Basic widgets
extern "C" void EMSCRIPTEN_KEEPALIVE imgui_Text(const char* text)
{
	ImGui::Text("%s", text);
}

extern "C" void EMSCRIPTEN_KEEPALIVE imgui_TextWrapped(const char* text)
{
	ImGui::TextWrapped("%s", text);
}

extern "C" bool EMSCRIPTEN_KEEPALIVE imgui_Button(const char* label, float w, float h)
{
	return ImGui::Button(label, ImVec2(w, h));
}

extern "C" bool EMSCRIPTEN_KEEPALIVE imgui_SmallButton(const char* label)
{
	return ImGui::SmallButton(label);
}

extern "C" bool EMSCRIPTEN_KEEPALIVE imgui_Checkbox(const char* label, bool* v)
{
	return ImGui::Checkbox(label, v);
}

extern "C" bool EMSCRIPTEN_KEEPALIVE imgui_SliderFloat(const char* label, float* v, float v_min, float v_max, const char* format, ImGuiSliderFlags flags)
{
	return ImGui::SliderFloat(label, v, v_min, v_max, format, flags);
}

extern "C" bool EMSCRIPTEN_KEEPALIVE imgui_SliderInt(const char* label, int* v, int v_min, int v_max, const char* format, ImGuiSliderFlags flags)
{
	return ImGui::SliderInt(label, v, v_min, v_max, format, flags);
}

extern "C" bool EMSCRIPTEN_KEEPALIVE imgui_ColorEdit3(const char* label, float* col, ImGuiColorEditFlags flags)
{
	return ImGui::ColorEdit3(label, col, flags);
}

extern "C" bool EMSCRIPTEN_KEEPALIVE imgui_ColorEdit4(const char* label, float* col, ImGuiColorEditFlags flags)
{
	return ImGui::ColorEdit4(label, col, flags);
}

extern "C" bool EMSCRIPTEN_KEEPALIVE imgui_InputText(const char* label, char* buf, size_t buf_size, ImGuiInputTextFlags flags, ImGuiInputTextCallback callback, void* user_data)
{
	return ImGui::InputText(label, buf, buf_size, flags, callback, user_data);
}

extern "C" bool EMSCRIPTEN_KEEPALIVE imgui_InputFloat(const char* label, float* v, float step, float step_fast, const char* format, ImGuiInputTextFlags flags)
{
	return ImGui::InputFloat(label, v, step, step_fast, format, flags);
}

extern "C" bool EMSCRIPTEN_KEEPALIVE imgui_InputInt(const char* label, int* v, int step, int step_fast, ImGuiInputTextFlags flags)
{
	return ImGui::InputInt(label, v, step, step_fast, flags);
}

// Layout
extern "C" void EMSCRIPTEN_KEEPALIVE imgui_SameLine(float offset_from_start_x, float spacing)
{
	ImGui::SameLine(offset_from_start_x, spacing);
}

extern "C" void EMSCRIPTEN_KEEPALIVE imgui_NewLine()
{
	ImGui::NewLine();
}

extern "C" void EMSCRIPTEN_KEEPALIVE imgui_Spacing()
{
	ImGui::Spacing();
}

extern "C" void EMSCRIPTEN_KEEPALIVE imgui_Separator()
{
	ImGui::Separator();
}

extern "C" void EMSCRIPTEN_KEEPALIVE imgui_SeparatorText(const char* text)
{
	ImGui::SeparatorText(text);
}

extern "C" void EMSCRIPTEN_KEEPALIVE imgui_Indent(float indent_w)
{
	ImGui::Indent(indent_w);
}

extern "C" void EMSCRIPTEN_KEEPALIVE imgui_Unindent(float indent_w)
{
	ImGui::Unindent(indent_w);
}

// Columns
extern "C" void EMSCRIPTEN_KEEPALIVE imgui_Columns(int count, const char* id, bool border)
{
	ImGui::Columns(count, id, border);
}

extern "C" void EMSCRIPTEN_KEEPALIVE imgui_NextColumn()
{
	ImGui::NextColumn();
}

extern "C" float EMSCRIPTEN_KEEPALIVE imgui_GetColumnOffset(int column_index)
{
	return ImGui::GetColumnOffset(column_index);
}

extern "C" void EMSCRIPTEN_KEEPALIVE imgui_SetColumnOffset(int column_index, float offset_x)
{
	ImGui::SetColumnOffset(column_index, offset_x);
}

// Tree nodes
extern "C" bool EMSCRIPTEN_KEEPALIVE imgui_TreeNode(const char* label)
{
	return ImGui::TreeNode(label);
}

extern "C" bool EMSCRIPTEN_KEEPALIVE imgui_TreeNodeEx(const char* label, ImGuiTreeNodeFlags flags)
{
	return ImGui::TreeNodeEx(label, flags);
}

extern "C" void EMSCRIPTEN_KEEPALIVE imgui_TreePop()
{
	ImGui::TreePop();
}

// Selectables
extern "C" bool EMSCRIPTEN_KEEPALIVE imgui_Selectable(const char* label, bool selected, ImGuiSelectableFlags flags, const ImVec2 size)
{
	return ImGui::Selectable(label, selected, flags, size);
}

// Combo box
extern "C" bool EMSCRIPTEN_KEEPALIVE imgui_BeginCombo(const char* label, const char* preview_value, ImGuiComboFlags flags)
{
	return ImGui::BeginCombo(label, preview_value, flags);
}

extern "C" void EMSCRIPTEN_KEEPALIVE imgui_EndCombo()
{
	ImGui::EndCombo();
}

// List box
extern "C" bool EMSCRIPTEN_KEEPALIVE imgui_ListBox(const char* label, int* current_item, const char* const* items, int items_count, int height_in_items)
{
	return ImGui::ListBox(label, current_item, items, items_count, height_in_items);
}

// Progress bar
extern "C" void EMSCRIPTEN_KEEPALIVE imgui_ProgressBar(float fraction, const ImVec2 size_arg, const char* overlay)
{
	ImGui::ProgressBar(fraction, size_arg, overlay);
}

// Bullet
extern "C" void EMSCRIPTEN_KEEPALIVE imgui_Bullet()
{
	ImGui::Bullet();
}

extern "C" void EMSCRIPTEN_KEEPALIVE imgui_BulletText(const char* text)
{
	ImGui::BulletText("%s", text);
}

// IO access
extern "C" float EMSCRIPTEN_KEEPALIVE imgui_GetFramerate()
{
	return ImGui::GetIO().Framerate;
}

extern "C" float EMSCRIPTEN_KEEPALIVE imgui_GetDeltaTime()
{
	return ImGui::GetIO().DeltaTime;
}

extern "C" void EMSCRIPTEN_KEEPALIVE imgui_SetNextItemWidth(float width)
{
	ImGui::SetNextItemWidth(width);
}

extern "C" float EMSCRIPTEN_KEEPALIVE imgui_GetContentRegionAvailWidth()
{
	return ImGui::GetContentRegionAvail().x;
}

// Style
extern "C" void EMSCRIPTEN_KEEPALIVE imgui_PushStyleColor(ImGuiCol idx, const ImVec4* col)
{
	ImGui::PushStyleColor(idx, *col);
}

extern "C" void EMSCRIPTEN_KEEPALIVE imgui_PopStyleColor(int count)
{
	ImGui::PopStyleColor(count);
}

extern "C" void EMSCRIPTEN_KEEPALIVE imgui_PushStyleVar(ImGuiStyleVar idx, float val)
{
	ImGui::PushStyleVar(idx, val);
}

extern "C" void EMSCRIPTEN_KEEPALIVE imgui_PushStyleVarVec2(ImGuiStyleVar idx, const ImVec2* val)
{
	ImGui::PushStyleVar(idx, *val);
}

extern "C" void EMSCRIPTEN_KEEPALIVE imgui_PopStyleVar(int count)
{
	ImGui::PopStyleVar(count);
}

// ID manipulation
extern "C" void EMSCRIPTEN_KEEPALIVE imgui_PushID(const char* str_id)
{
	ImGui::PushID(str_id);
}

extern "C" void EMSCRIPTEN_KEEPALIVE imgui_PushIDInt(int int_id)
{
	ImGui::PushID(int_id);
}

extern "C" void EMSCRIPTEN_KEEPALIVE imgui_PopID()
{
	ImGui::PopID();
}

// Cursor
extern "C" void EMSCRIPTEN_KEEPALIVE imgui_SetCursorPos(float x, float y)
{
	ImGui::SetCursorPos(ImVec2(x, y));
}

extern "C" void EMSCRIPTEN_KEEPALIVE imgui_SetCursorScreenPos(float x, float y)
{
	ImGui::SetCursorScreenPos(ImVec2(x, y));
}

extern "C" ImVec2 EMSCRIPTEN_KEEPALIVE imgui_GetCursorPos()
{
	return ImGui::GetCursorPos();
}

extern "C" ImVec2 EMSCRIPTEN_KEEPALIVE imgui_GetCursorScreenPos()
{
	return ImGui::GetCursorScreenPos();
}

extern "C" ImVec2 EMSCRIPTEN_KEEPALIVE imgui_GetWindowSize()
{
	return ImGui::GetWindowSize();
}

extern "C" ImVec2 EMSCRIPTEN_KEEPALIVE imgui_GetWindowPos()
{
	return ImGui::GetWindowPos();
}

// Menu
extern "C" bool EMSCRIPTEN_KEEPALIVE imgui_BeginMenuBar()
{
	return ImGui::BeginMenuBar();
}

extern "C" void EMSCRIPTEN_KEEPALIVE imgui_EndMenuBar()
{
	ImGui::EndMenuBar();
}

extern "C" bool EMSCRIPTEN_KEEPALIVE imgui_BeginMenu(const char* label, bool enabled)
{
	return ImGui::BeginMenu(label, enabled);
}

extern "C" void EMSCRIPTEN_KEEPALIVE imgui_EndMenu()
{
	ImGui::EndMenu();
}

extern "C" bool EMSCRIPTEN_KEEPALIVE imgui_MenuItem(const char* label, const char* shortcut, bool selected, bool enabled)
{
	return ImGui::MenuItem(label, shortcut, selected, enabled);
}

// Popup
extern "C" bool EMSCRIPTEN_KEEPALIVE imgui_BeginPopup(const char* str_id, ImGuiWindowFlags flags)
{
	return ImGui::BeginPopup(str_id, flags);
}

extern "C" void EMSCRIPTEN_KEEPALIVE imgui_EndPopup()
{
	ImGui::EndPopup();
}

extern "C" void EMSCRIPTEN_KEEPALIVE imgui_OpenPopup(const char* str_id, ImGuiPopupFlags popup_flags)
{
	ImGui::OpenPopup(str_id, popup_flags);
}

extern "C" bool EMSCRIPTEN_KEEPALIVE imgui_BeginPopupModal(const char* name, bool* p_open, ImGuiWindowFlags flags)
{
	return ImGui::BeginPopupModal(name, p_open, flags);
}

// Tab bar
extern "C" bool EMSCRIPTEN_KEEPALIVE imgui_BeginTabBar(const char* str_id, ImGuiTabBarFlags flags)
{
	return ImGui::BeginTabBar(str_id, flags);
}

extern "C" void EMSCRIPTEN_KEEPALIVE imgui_EndTabBar()
{
	ImGui::EndTabBar();
}

extern "C" bool EMSCRIPTEN_KEEPALIVE imgui_BeginTabItem(const char* label, bool* p_open, ImGuiTabItemFlags flags)
{
	return ImGui::BeginTabItem(label, p_open, flags);
}

extern "C" void EMSCRIPTEN_KEEPALIVE imgui_EndTabItem()
{
	ImGui::EndTabItem();
}

// Group
extern "C" void EMSCRIPTEN_KEEPALIVE imgui_BeginGroup()
{
	ImGui::BeginGroup();
}

extern "C" void EMSCRIPTEN_KEEPALIVE imgui_EndGroup()
{
	ImGui::EndGroup();
}

// Child window
extern "C" bool EMSCRIPTEN_KEEPALIVE imgui_BeginChild(const char* str_id, const ImVec2 size, bool border, ImGuiWindowFlags flags)
{
	return ImGui::BeginChild(str_id, size, border, flags);
}

extern "C" void EMSCRIPTEN_KEEPALIVE imgui_EndChild()
{
	ImGui::EndChild();
}

// Collapsing header
extern "C" bool EMSCRIPTEN_KEEPALIVE imgui_CollapsingHeader(const char* label, ImGuiTreeNodeFlags flags)
{
	return ImGui::CollapsingHeader(label, flags);
}

extern "C" bool EMSCRIPTEN_KEEPALIVE imgui_CollapsingHeaderEx(const char* label, bool* p_visible, ImGuiTreeNodeFlags flags)
{
	return ImGui::CollapsingHeader(label, p_visible, flags);
}

// Image (placeholder - would need texture handling)
// extern "C" void EMSCRIPTEN_KEEPALIVE imgui_Image(ImTextureID user_texture_id, const ImVec2 size, const ImVec2 uv0, const ImVec2 uv1, const ImVec4 tint_col, const ImVec4 border_col)
// {
// 	ImGui::Image(user_texture_id, size, uv0, uv1, tint_col, border_col);
// }

// Checkbox flags
extern "C" bool EMSCRIPTEN_KEEPALIVE imgui_CheckboxFlags(const char* label, unsigned int* flags, unsigned int flags_value)
{
	return ImGui::CheckboxFlags(label, flags, flags_value);
}

// Radio button
extern "C" bool EMSCRIPTEN_KEEPALIVE imgui_RadioButton(const char* label, bool active)
{
	return ImGui::RadioButton(label, active);
}

extern "C" bool EMSCRIPTEN_KEEPALIVE imgui_RadioButtonEx(const char* label, int* v, int v_button)
{
	return ImGui::RadioButton(label, v, v_button);
}

// Drag
extern "C" bool EMSCRIPTEN_KEEPALIVE imgui_DragFloat(const char* label, float* v, float v_speed, float v_min, float v_max, const char* format, ImGuiSliderFlags flags)
{
	return ImGui::DragFloat(label, v, v_speed, v_min, v_max, format, flags);
}

extern "C" bool EMSCRIPTEN_KEEPALIVE imgui_DragInt(const char* label, int* v, float v_speed, int v_min, int v_max, const char* format, ImGuiSliderFlags flags)
{
	return ImGui::DragInt(label, v, v_speed, v_min, v_max, format, flags);
}

// Helper to call JavaScript render function
extern "C" void EMSCRIPTEN_KEEPALIVE imgui_CallJSRender()
{
	val::global().call<void>("imguiRender");
}

#endif
