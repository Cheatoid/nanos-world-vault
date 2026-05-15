/* ==========================================================================
 * win32_api_hook_detector.c — Enhanced Win32 API Hook Detection
 *
 * Comprehensive Win32 API hook detection that compares in-memory functions
 * against original DLLs on disk to detect modifications.
 * ========================================================================== */

#include <windows.h>
#include <winternl.h>
#include <tlhelp32.h>
#include <psapi.h>
#include <shlwapi.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#pragma comment(lib, "psapi.lib")
#pragma comment(lib, "shlwapi.lib")

/* ------------------------------------------------------------------
 * Architecture Compatibility
 * ------------------------------------------------------------------ */
#ifdef _WIN64
    #define POINTER_SIZE 8
    #define ARCH_SUFFIX "64"
#else
    #define POINTER_SIZE 4
    #define ARCH_SUFFIX "32"
#endif

/* Use pointer-sized types for addresses */
typedef UINT_PTR UINT_PTR_TYPE;
typedef ULONG_PTR ULONG_PTR_TYPE;

/* ------------------------------------------------------------------
 * Dynamic Function Loading - Function Pointers
 * ------------------------------------------------------------------ */

/* Kernel32 Function Pointers */
typedef HMODULE (WINAPI *PFN_GETMODULEHANDLEA)(LPCSTR);
typedef FARPROC (WINAPI *PFN_GETPROCADDRESS)(HMODULE, LPCSTR);
typedef DWORD (WINAPI *PFN_GETMODULEFILENAMEA)(HMODULE, LPSTR, DWORD);
typedef BOOL (WINAPI *PFN_GETMODULEINFORMATION)(HANDLE, HMODULE, LPMODULEINFO, DWORD);
typedef HANDLE (WINAPI *PFN_CREATETOOLHELP32SNAPSHOT)(DWORD, DWORD);
typedef BOOL (WINAPI *PFN_MODULE32FIRST)(HANDLE, LPMODULEENTRY32);
typedef BOOL (WINAPI *PFN_MODULE32NEXT)(HANDLE, LPMODULEENTRY32);
#ifdef _WIN64
typedef BOOL (WINAPI *PFN_MODULE32FIRSTWOW64)(HANDLE, LPMODULEENTRY32W);
typedef BOOL (WINAPI *PFN_MODULE32NEXTWOW64)(HANDLE, LPMODULEENTRY32W);
#endif
typedef VOID (WINAPI *PFN_GETSYSTEMDIRECTORYA)(LPSTR, UINT);
typedef HANDLE (WINAPI *PFN_CREATEFILEA)(LPCSTR, DWORD, DWORD, LPSECURITY_ATTRIBUTES, DWORD, DWORD, HANDLE);
typedef DWORD (WINAPI *PFN_GETFILESIZE)(HANDLE, LPDWORD);
typedef HANDLE (WINAPI *PFN_CREATEFILEMAPPING)(HANDLE, LPSECURITY_ATTRIBUTES, DWORD, DWORD, DWORD, LPCSTR);
typedef LPVOID (WINAPI *PFN_MAPVIEWOFFILE)(HANDLE, DWORD, DWORD, DWORD, SIZE_T);
typedef BOOL (WINAPI *PFN_UNMAPVIEWOFFILE)(LPCVOID);

/* User32 Function Pointers */
typedef int (WINAPI *PFN_MESSAGEBOXA)(HWND, LPCSTR, LPCSTR, UINT);

/* ntdll Function Pointers */
typedef NTSTATUS (NTAPI *PFN_NTQUERYINFORMATIONPROCESS)(HANDLE, PROCESSINFOCLASS, PVOID, ULONG, PULONG);
typedef NTSTATUS (NTAPI *PFN_NTQUERYPERFORMANCECOUNTER)(PLARGE_INTEGER, PLARGE_INTEGER);
typedef NTSTATUS (NTAPI *PFN_NTQUERYSYSTEMTIME)(PLARGE_INTEGER);
typedef NTSTATUS (NTAPI *PFN_NTDELAYEXECUTION)(BOOLEAN, PLARGE_INTEGER);
typedef NTSTATUS (NTAPI *PFN_RTLQUERYPERFORMANCECOUNTER)(PLARGE_INTEGER);
typedef NTSTATUS (NTAPI *PFN_RTLGETSYSTEMTIMEPRECISE)(PLARGE_INTEGER);

/* Dynamic Function Structure */
typedef struct _DYNAMIC_FUNCTIONS {
    /* Kernel32 */
    PFN_GETMODULEHANDLEA GetModuleHandleA;
    PFN_GETPROCADDRESS GetProcAddress;
    PFN_GETMODULEFILENAMEA GetModuleFileNameA;
    PFN_GETMODULEINFORMATION GetModuleInformation;
    PFN_CREATETOOLHELP32SNAPSHOT CreateToolhelp32Snapshot;
    PFN_MODULE32FIRST Module32First;
    PFN_MODULE32NEXT Module32Next;
#ifdef _WIN64
    PFN_MODULE32FIRSTWOW64 Module32FirstWOW64;
    PFN_MODULE32NEXTWOW64 Module32NextWOW64;
#endif
    PFN_GETSYSTEMDIRECTORYA GetSystemDirectoryA;
    PFN_CREATEFILEA CreateFileA;
    PFN_GETFILESIZE GetFileSize;
    PFN_CREATEFILEMAPPING CreateFileMapping;
    PFN_MAPVIEWOFFILE MapViewOfFile;
    PFN_UNMAPVIEWOFFILE UnmapViewOfFile;

    /* User32 */
    PFN_MESSAGEBOXA MessageBoxA;

    /* ntdll */
    PFN_NTQUERYINFORMATIONPROCESS NtQueryInformationProcess;
    PFN_NTQUERYPERFORMANCECOUNTER NtQueryPerformanceCounter;
    PFN_NTQUERYSYSTEMTIME NtQuerySystemTime;
    PFN_NTDELAYEXECUTION NtDelayExecution;
    PFN_RTLQUERYPERFORMANCECOUNTER RtlQueryPerformanceCounter;
    PFN_RTLGETSYSTEMTIMEPRECISE RtlGetSystemTimePrecise;
} DYNAMIC_FUNCTIONS;

static DYNAMIC_FUNCTIONS g_DynFuncs = {0};

/* ------------------------------------------------------------------
 * Configuration and Types
 * ------------------------------------------------------------------ */
#define MAX_API_FUNCTIONS 256
#define MAX_DLL_PATH 260
#define MAX_FUNCTION_NAME 128
#define SIGNATURE_SIZE 16

typedef enum _HOOK_TYPE {
    HOOK_NONE = 0,
    HOOK_IAT = 1,
    HOOK_EAT = 2,
    HOOK_INLINE = 3,
    HOOK_DETOUR = 4,
    HOOT_MEMORY_PATCH = 5
} HOOK_TYPE;

typedef struct _API_FUNCTION {
    char dllName[64];
    char functionName[MAX_FUNCTION_NAME];
    FARPROC originalAddress;
    FARPROC currentAddress;
    HOOK_TYPE hookType;
    BOOL isHooked;
    BYTE signature[SIGNATURE_SIZE];
    BYTE diskSignature[SIGNATURE_SIZE];
} API_FUNCTION;

typedef struct _HOOK_REPORT {
    int totalFunctions;
    int hookedFunctions;
    int iatHooks;
    int eatHooks;
    int inlineHooks;
    int memoryPatches;
    API_FUNCTION functions[MAX_API_FUNCTIONS];
} HOOK_REPORT;

/* ------------------------------------------------------------------
 * Comprehensive Win32 API List to Check
 * Prioritizing ntdll functions over kernel32/user32 equivalents
 * ------------------------------------------------------------------ */
static const char* CRITICAL_APIS[][2] = {
    /* System APIs - Prioritize ntdll versions */
    {"ntdll.dll", "NtQueryPerformanceCounter"},
    {"ntdll.dll", "NtQuerySystemTime"},
    {"ntdll.dll", "NtDelayExecution"},
    {"ntdll.dll", "RtlQueryPerformanceCounter"},
    {"ntdll.dll", "RtlGetSystemTimePrecise"},

    {"kernel32.dll", "GetTickCount"},
    {"kernel32.dll", "GetTickCount64"},
    {"kernel32.dll", "QueryPerformanceCounter"},
    {"kernel32.dll", "QueryPerformanceFrequency"},
    {"kernel32.dll", "GetSystemTime"},
    {"kernel32.dll", "GetLocalTime"},
    {"kernel32.dll", "FileTimeToSystemTime"},
    {"kernel32.dll", "SystemTimeToFileTime"},
    {"kernel32.dll", "Sleep"},
    {"kernel32.dll", "SleepEx"},
    {"kernel32.dll", "WaitForSingleObject"},
    {"kernel32.dll", "WaitForMultipleObjects"},

    /* Memory APIs */
    {"kernel32.dll", "VirtualAlloc"},
    {"kernel32.dll", "VirtualAllocEx"},
    {"kernel32.dll", "VirtualFree"},
    {"kernel32.dll", "VirtualProtect"},
    {"kernel32.dll", "VirtualProtectEx"},
    {"kernel32.dll", "ReadProcessMemory"},
    {"kernel32.dll", "WriteProcessMemory"},
    {"kernel32.dll", "CreateRemoteThread"},
    {"kernel32.dll", "OpenProcess"},
    {"kernel32.dll", "GetCurrentProcess"},
    {"kernel32.dll", "GetCurrentProcessId"},
    {"kernel32.dll", "GetCurrentThread"},

    /* File APIs */
    {"kernel32.dll", "CreateFileA"},
    {"kernel32.dll", "CreateFileW"},
    {"kernel32.dll", "ReadFile"},
    {"kernel32.dll", "WriteFile"},
    {"kernel32.dll", "DeleteFileA"},
    {"kernel32.dll", "DeleteFileW"},
    {"kernel32.dll", "MoveFileA"},
    {"kernel32.dll", "MoveFileW"},
    {"kernel32.dll", "CopyFileA"},
    {"kernel32.dll", "CopyFileW"},
    {"kernel32.dll", "GetFileAttributesA"},
    {"kernel32.dll", "GetFileAttributesW"},
    {"kernel32.dll", "SetFileAttributesA"},
    {"kernel32.dll", "SetFileAttributesW"},

    /* Input APIs */
    {"user32.dll", "GetAsyncKeyState"},
    {"user32.dll", "GetKeyboardState"},
    {"user32.dll", "SetKeyboardState"},
    {"user32.dll", "GetCursorPos"},
    {"user32.dll", "SetCursorPos"},
    {"user32.dll", "GetForegroundWindow"},
    {"user32.dll", "SetForegroundWindow"},
    {"user32.dll", "GetActiveWindow"},
    {"user32.dll", "keybd_event"},
    {"user32.dll", "mouse_event"},
    {"user32.dll", "SendInput"},
    {"user32.dll", "GetWindowRect"},
    {"user32.dll", "GetWindowPlacement"},
    {"user32.dll", "SetWindowPos"},
    {"user32.dll", "MoveWindow"},

    /* Window/Message APIs */
    {"user32.dll", "FindWindowA"},
    {"user32.dll", "FindWindowW"},
    {"user32.dll", "FindWindowExA"},
    {"user32.dll", "FindWindowExW"},
    {"user32.dll", "EnumWindows"},
    {"user32.dll", "EnumProcesses"},
    {"user32.dll", "GetWindowTextA"},
    {"user32.dll", "GetWindowTextW"},
    {"user32.dll", "SetWindowTextA"},
    {"user32.dll", "SetWindowTextW"},
    {"user32.dll", "SendMessageA"},
    {"user32.dll", "SendMessageW"},
    {"user32.dll", "PostMessageA"},
    {"user32.dll", "PostMessageW"},
    {"user32.dll", "PeekMessageA"},
    {"user32.dll", "PeekMessageW"},
    {"user32.dll", "GetMessageA"},
    {"user32.dll", "GetMessageW"},

    /* Graphics/DirectX APIs */
    {"d3d9.dll", "Direct3DCreate9"},
    {"d3d9.dll", "Direct3DCreate9Ex"},
    {"d3d11.dll", "D3D11CreateDevice"},
    {"d3d11.dll", "D3D11CreateDeviceAndSwapChain"},
    {"dxgi.dll", "CreateDXGIFactory"},
    {"dxgi.dll", "CreateDXGIFactory1"},
    {"dxgi.dll", "CreateDXGIFactory2"},
    {"opengl32.dll", "wglSwapBuffers"},
    {"opengl32.dll", "wglGetProcAddress"},
    {"gdi32.dll", "SwapBuffers"},
    {"gdi32.dll", "BitBlt"},
    {"gdi32.dll", "StretchBlt"},
    {"gdi32.dll", "GetPixel"},
    {"gdi32.dll", "SetPixel"},

    /* Network APIs */
    {"ws2_32.dll", "send"},
    {"ws2_32.dll", "recv"},
    {"ws2_32.dll", "sendto"},
    {"ws2_32.dll", "recvfrom"},
    {"ws2_32.dll", "connect"},
    {"ws2_32.dll", "accept"},
    {"ws2_32.dll", "listen"},
    {"ws2_32.dll", "bind"},
    {"ws2_32.dll", "socket"},
    {"ws2_32.dll", "closesocket"},
    {"ws2_32.dll", "WSAStartup"},
    {"ws2_32.dll", "WSACleanup"},
    {"ws2_32.dll", "gethostbyname"},
    {"ws2_32.dll", "getaddrinfo"},
    {"ws2_32.dll", "inet_addr"},
    {"ws2_32.dll", "inet_ntoa"},

    /* Timing APIs (commonly hooked for speed hacks) */
    {"ntdll.dll", "NtQueryPerformanceCounter"},
    {"ntdll.dll", "NtQuerySystemTime"},
    {"ntdll.dll", "NtDelayExecution"},
    {"ntdll.dll", "RtlQueryPerformanceCounter"},
    {"ntdll.dll", "RtlGetSystemTimePrecise"},
    {"winmm.dll", "timeGetTime"},
    {"winmm.dll", "timeBeginPeriod"},
    {"winmm.dll", "timeEndPeriod"},

    /* Debug/Anti-debug APIs - Prioritize ntdll versions */
    {"ntdll.dll", "NtQueryInformationProcess"},
    {"ntdll.dll", "NtSetInformationProcess"},
    {"ntdll.dll", "NtClose"},
    {"ntdll.dll", "NtCreateFile"},
    {"ntdll.dll", "NtOpenFile"},
    {"ntdll.dll", "NtReadFile"},
    {"ntdll.dll", "NtWriteFile"},
    {"ntdll.dll", "DbgPrint"},
    {"ntdll.dll", "DbgPrintEx"},
    {"kernel32.dll", "OutputDebugStringA"},
    {"kernel32.dll", "OutputDebugStringW"},
    {"kernel32.dll", "IsDebuggerPresent"},
    {"kernel32.dll", "CheckRemoteDebuggerPresent"},

    /* Registry APIs */
    {"advapi32.dll", "RegOpenKeyA"},
    {"advapi32.dll", "RegOpenKeyW"},
    {"advapi32.dll", "RegOpenKeyExA"},
    {"advapi32.dll", "RegOpenKeyExW"},
    {"advapi32.dll", "RegCreateKeyA"},
    {"advapi32.dll", "RegCreateKeyW"},
    {"advapi32.dll", "RegCreateKeyExA"},
    {"advapi32.dll", "RegCreateKeyExW"},
    {"advapi32.dll", "RegQueryValueA"},
    {"advapi32.dll", "RegQueryValueW"},
    {"advapi32.dll", "RegQueryValueExA"},
    {"advapi32.dll", "RegQueryValueExW"},
    {"advapi32.dll", "RegSetValueA"},
    {"advapi32.dll", "RegSetValueW"},
    {"advapi32.dll", "RegSetValueExA"},
    {"advapi32.dll", "RegSetValueExW"},
    {"advapi32.dll", "RegDeleteKeyA"},
    {"advapi32.dll", "RegDeleteKeyW"},
    {"advapi32.dll", "RegDeleteValueA"},
    {"advapi32.dll", "RegDeleteValueW"},

    /* Cryptography APIs */
    {"advapi32.dll", "CryptAcquireContextA"},
    {"advapi32.dll", "CryptAcquireContextW"},
    {"advapi32.dll", "CryptCreateHash"},
    {"advapi32.dll", "CryptHashData"},
    {"advapi32.dll", "CryptDestroyHash"},
    {"advapi32.dll", "CryptEncrypt"},
    {"advapi32.dll", "CryptDecrypt"},
    {"crypt32.dll", "CryptStringToBinaryA"},
    {"crypt32.dll", "CryptStringToBinaryW"},
    {"crypt32.dll", "CryptBinaryToStringA"},
    {"crypt32.dll", "CryptBinaryToStringW"},

    {NULL, NULL}
};

/* ------------------------------------------------------------------
 * Dynamic Function Loading
 * ------------------------------------------------------------------ */

static BOOL InitializeDynamicFunctions()
{
    HMODULE hKernel32 = GetModuleHandleA("kernel32.dll");
    HMODULE hUser32 = GetModuleHandleA("user32.dll");
    HMODULE hNtdll = GetModuleHandleA("ntdll.dll");

    if (!hKernel32 || !hUser32 || !hNtdll) {
        return FALSE;
    }

    /* Load Kernel32 functions */
    g_DynFuncs.GetModuleHandleA = (PFN_GETMODULEHANDLEA)GetProcAddress(hKernel32, "GetModuleHandleA");
    g_DynFuncs.GetProcAddress = (PFN_GETPROCADDRESS)GetProcAddress(hKernel32, "GetProcAddress");
    g_DynFuncs.GetModuleFileNameA = (PFN_GETMODULEFILENAMEA)GetProcAddress(hKernel32, "GetModuleFileNameA");
    g_DynFuncs.GetModuleInformation = (PFN_GETMODULEINFORMATION)GetProcAddress(hKernel32, "GetModuleInformation");
    g_DynFuncs.CreateToolhelp32Snapshot = (PFN_CREATETOOLHELP32SNAPSHOT)GetProcAddress(hKernel32, "CreateToolhelp32Snapshot");
    g_DynFuncs.Module32First = (PFN_MODULE32FIRST)GetProcAddress(hKernel32, "Module32First");
    g_DynFuncs.Module32Next = (PFN_MODULE32NEXT)GetProcAddress(hKernel32, "Module32Next");
    g_DynFuncs.GetSystemDirectoryA = (PFN_GETSYSTEMDIRECTORYA)GetProcAddress(hKernel32, "GetSystemDirectoryA");
    g_DynFuncs.CreateFileA = (PFN_CREATEFILEA)GetProcAddress(hKernel32, "CreateFileA");
    g_DynFuncs.GetFileSize = (PFN_GETFILESIZE)GetProcAddress(hKernel32, "GetFileSize");
    g_DynFuncs.CreateFileMapping = (PFN_CREATEFILEMAPPING)GetProcAddress(hKernel32, "CreateFileMappingA");
    g_DynFuncs.MapViewOfFile = (PFN_MAPVIEWOFFILE)GetProcAddress(hKernel32, "MapViewOfFile");
    g_DynFuncs.UnmapViewOfFile = (PFN_UNMAPVIEWOFFILE)GetProcAddress(hKernel32, "UnmapViewOfFile");

    /* Load User32 functions */
    g_DynFuncs.MessageBoxA = (PFN_MESSAGEBOXA)GetProcAddress(hUser32, "MessageBoxA");

#ifdef _WIN64
    /* Load WOW64 functions for 64-bit to enumerate 32-bit modules */
    g_DynFuncs.Module32FirstWOW64 = (PFN_MODULE32FIRSTWOW64)GetProcAddress(hKernel32, "Module32FirstWOW64");
    g_DynFuncs.Module32NextWOW64 = (PFN_MODULE32NEXTWOW64)GetProcAddress(hKernel32, "Module32NextWOW64");
#endif

    /* Load ntdll functions */
    g_DynFuncs.NtQueryInformationProcess = (PFN_NTQUERYINFORMATIONPROCESS)GetProcAddress(hNtdll, "NtQueryInformationProcess");
    g_DynFuncs.NtQueryPerformanceCounter = (PFN_NTQUERYPERFORMANCECOUNTER)GetProcAddress(hNtdll, "NtQueryPerformanceCounter");
    g_DynFuncs.NtQuerySystemTime = (PFN_NTQUERYSYSTEMTIME)GetProcAddress(hNtdll, "NtQuerySystemTime");
    g_DynFuncs.NtDelayExecution = (PFN_NTDELAYEXECUTION)GetProcAddress(hNtdll, "NtDelayExecution");
    g_DynFuncs.RtlQueryPerformanceCounter = (PFN_RTLQUERYPERFORMANCECOUNTER)GetProcAddress(hNtdll, "RtlQueryPerformanceCounter");
    g_DynFuncs.RtlGetSystemTimePrecise = (PFN_RTLGETSYSTEMTIMEPRECISE)GetProcAddress(hNtdll, "RtlGetSystemTimePrecise");

    /* Verify critical functions are loaded */
    if (!g_DynFuncs.GetModuleHandleA || !g_DynFuncs.GetProcAddress ||
        !g_DynFuncs.GetModuleFileNameA || !g_DynFuncs.GetModuleInformation) {
        return FALSE;
    }

    return TRUE;
}

/* ------------------------------------------------------------------
 * Utility Functions
 * ------------------------------------------------------------------ */

/* Helper to extract function address from IMAGE_THUNK_DATA (x86/x64 compatible) */
static ULONG_PTR_TYPE GetThunkFunctionAddress(IMAGE_THUNK_DATA* thunk)
{
#ifdef _WIN64
    return thunk->u1.Function;
#else
    return (ULONG_PTR_TYPE)thunk->u1.Function;
#endif
}

/* Helper to check if thunk is ordinal (x86/x64 compatible) */
static BOOL IsThunkOrdinal(IMAGE_THUNK_DATA* thunk)
{
#ifdef _WIN64
    return (thunk->u1.Ordinal & IMAGE_ORDINAL_FLAG64) != 0;
#else
    return (thunk->u1.Ordinal & IMAGE_ORDINAL_FLAG32) != 0;
#endif
}

static BOOL IsJmpInstruction(BYTE* addr)
{
    if (!addr) return FALSE;

    BYTE b0 = addr[0];

    /* Short JMP (EB xx) */
    if (b0 == 0xEB) return TRUE;

    /* Near JMP (E9 xx xx xx xx) */
    if (b0 == 0xE9) return TRUE;

    /* Indirect JMP (FF 25 xx xx xx xx) */
    if (b0 == 0xFF && addr[1] == 0x25) return TRUE;

    /* PUSH addr; RET */
    if (b0 == 0x68 && addr[5] == 0xC3) return TRUE;

    /* MOV RAX, addr; JMP RAX */
    if (b0 == 0x48 && addr[1] == 0xB8 && addr[10] == 0xFF && addr[11] == 0xE0) return TRUE;

    return FALSE;
}

static BOOL IsDetourPattern(BYTE* addr)
{
    if (!addr) return FALSE;

    /* Common detour patterns */

    /* JMP [DWORD PTR] + NOP padding */
    if (addr[0] == 0xFF && addr[1] == 0x25) return TRUE;

    /* MOV EDI, EDI; PUSH EBP; MOV EBP, ESP (hot patch prologue) */
    if (addr[0] == 0x8B && addr[1] == 0xFF && addr[2] == 0x55 && addr[3] == 0x8B && addr[4] == 0xEC) return TRUE;

    /* PUSH EBP; MOV EBP, ESP; MOV ECX, [DWORD PTR] */
    if (addr[0] == 0x55 && addr[1] == 0x8B && addr[2] == 0xEC && addr[3] == 0x8B && addr[4] == 0x0D) return TRUE;

    return FALSE;
}

static void GetSystemDllPath(const char* dllName, char* outputPath, size_t outputSize)
{
    char systemDir[MAX_PATH];
    g_DynFuncs.GetSystemDirectoryA(systemDir, sizeof(systemDir));
    snprintf(outputPath, outputSize, "%s\\%s", systemDir, dllName);
}

static BOOL LoadDllFromDisk(const char* dllPath, HMODULE* outModule, BYTE** outBase, SIZE_T* outSize)
{
    HANDLE hFile = g_DynFuncs.CreateFileA(dllPath, GENERIC_READ, FILE_SHARE_READ, NULL,
                               OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    if (hFile == INVALID_HANDLE_VALUE) return FALSE;

    DWORD fileSize = g_DynFuncs.GetFileSize(hFile, NULL);
    if (fileSize == INVALID_FILE_SIZE) {
        CloseHandle(hFile);
        return FALSE;
    }

    HANDLE hMapping = g_DynFuncs.CreateFileMapping(hFile, NULL, PAGE_READONLY, 0, fileSize, NULL);
    CloseHandle(hFile);

    if (!hMapping) return FALSE;

    BYTE* fileBase = (BYTE*)g_DynFuncs.MapViewOfFile(hMapping, FILE_MAP_READ, 0, 0, fileSize);
    CloseHandle(hMapping);

    if (!fileBase) return FALSE;

    *outBase = fileBase;
    *outSize = fileSize;
    return TRUE;
}

static FARPROC GetFunctionFromDiskImage(BYTE* diskBase, const char* functionName)
{
    IMAGE_DOS_HEADER* dos = (IMAGE_DOS_HEADER*)diskBase;
    if (dos->e_magic != IMAGE_DOS_SIGNATURE) return NULL;

    IMAGE_NT_HEADERS* nt = (IMAGE_NT_HEADERS*)(diskBase + dos->e_lfanew);
    if (nt->Signature != IMAGE_NT_SIGNATURE) return NULL;

    IMAGE_EXPORT_DIRECTORY* exports = (IMAGE_EXPORT_DIRECTORY*)
        (diskBase + nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_EXPORT].VirtualAddress);

    if (!exports) return NULL;

    DWORD* nameTable = (DWORD*)(diskBase + exports->AddressOfNames);
    WORD* ordTable = (WORD*)(diskBase + exports->AddressOfNameOrdinals);
    DWORD* funcTable = (DWORD*)(diskBase + exports->AddressOfFunctions);

    for (DWORD i = 0; i < exports->NumberOfNames; i++) {
        char* name = (char*)(diskBase + nameTable[i]);
        if (strcmp(name, functionName) == 0) {
            DWORD funcRVA = funcTable[ordTable[i]];
            return (FARPROC)(diskBase + funcRVA);
        }
    }

    return NULL;
}

/* ------------------------------------------------------------------
 * Hook Detection Functions
 * ------------------------------------------------------------------ */

static BOOL DetectIATHook(HMODULE hModule, const char* dllName, const char* funcName, HOOK_TYPE* hookType)
{
    if (!hModule) return FALSE;

    BYTE* base = (BYTE*)hModule;
    IMAGE_DOS_HEADER* dos = (IMAGE_DOS_HEADER*)base;
    IMAGE_NT_HEADERS* nt = (IMAGE_NT_HEADERS*)(base + dos->e_lfanew);

    IMAGE_IMPORT_DESCRIPTOR* imports = (IMAGE_IMPORT_DESCRIPTOR*)
        (base + nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT].VirtualAddress);

    while (imports->Name != 0) {
        char* importDllName = (char*)(base + imports->Name);
        if (_stricmp(importDllName, dllName) == 0) {

            IMAGE_THUNK_DATA* thunk = (IMAGE_THUNK_DATA*)(base + imports->FirstThunk);
            IMAGE_THUNK_DATA* origThunk = (IMAGE_THUNK_DATA*)(base + imports->OriginalFirstThunk);

            while (GetThunkFunctionAddress(thunk) != 0) {
                if (GetThunkFunctionAddress(origThunk) != 0 && !IsThunkOrdinal(origThunk)) {
                    IMAGE_IMPORT_BY_NAME* ibn = (IMAGE_IMPORT_BY_NAME*)
                        (base + origThunk->u1.AddressOfData);

                    if (ibn && strcmp(ibn->Name, funcName) == 0) {
                        ULONG_PTR_TYPE funcAddr = GetThunkFunctionAddress(thunk);

                        HMODULE hDll = g_DynFuncs.GetModuleHandleA(dllName);
                        if (hDll) {
                            MODULEINFO dllInfo;
                            if (g_DynFuncs.GetModuleInformation(GetCurrentProcess(), hDll, &dllInfo, sizeof(dllInfo))) {
                                BYTE* dllStart = (BYTE*)dllInfo.lpBaseOfDll;
                                BYTE* dllEnd = dllStart + dllInfo.SizeOfImage;

                                if ((BYTE*)funcAddr < dllStart || (BYTE*)funcAddr >= dllEnd) {
                                    *hookType = HOOK_IAT;
                                    return TRUE;
                                }
                            }
                        }
                    }
                }
                thunk++;
                origThunk++;
            }
        }
        imports++;
    }

    return FALSE;
}

static BOOL DetectEATHook(HMODULE hModule, const char* funcName, HOOK_TYPE* hookType)
{
    if (!hModule) return FALSE;

    BYTE* base = (BYTE*)hModule;
    IMAGE_DOS_HEADER* dos = (IMAGE_DOS_HEADER*)base;
    IMAGE_NT_HEADERS* nt = (IMAGE_NT_HEADERS*)(base + dos->e_lfanew);

    IMAGE_EXPORT_DIRECTORY* exports = (IMAGE_EXPORT_DIRECTORY*)
        (base + nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_EXPORT].VirtualAddress);

    if (!exports) return FALSE;

    DWORD* nameTable = (DWORD*)(base + exports->AddressOfNames);
    WORD* ordTable = (WORD*)(base + exports->AddressOfNameOrdinals);
    DWORD* funcTable = (DWORD*)(base + exports->AddressOfFunctions);

    for (DWORD i = 0; i < exports->NumberOfNames; i++) {
        char* name = (char*)(base + nameTable[i]);
        if (strcmp(name, funcName) == 0) {
            DWORD funcRVA = funcTable[ordTable[i]];
            FARPROC exportAddr = (FARPROC)(base + funcRVA);

            /* Load the same module from disk to compare */
            char modulePath[MAX_DLL_PATH];
            if (g_DynFuncs.GetModuleFileNameA(hModule, modulePath, sizeof(modulePath)) == 0) {
                return FALSE;
            }

            BYTE* diskBase = NULL;
            SIZE_T diskSize = 0;
            if (!LoadDllFromDisk(modulePath, (HMODULE*)&diskBase, &diskBase, &diskSize)) {
                return FALSE;
            }

            FARPROC diskExportAddr = GetFunctionFromDiskImage(diskBase, funcName);
            if (!diskExportAddr) {
                g_DynFuncs.UnmapViewOfFile(diskBase);
                return FALSE;
            }

            /* Compare the export function bytes */
            BOOL isModified = memcmp((BYTE*)exportAddr, (BYTE*)diskExportAddr, SIGNATURE_SIZE) != 0;
            g_DynFuncs.UnmapViewOfFile(diskBase);

            if (isModified) {
                *hookType = HOOK_EAT;
                return TRUE;
            }
        }
    }

    return FALSE;
}

static BOOL DetectInlineHook(FARPROC funcAddr, HOOK_TYPE* hookType)
{
    if (!funcAddr) return FALSE;

    BYTE* funcBytes = (BYTE*)funcAddr;

    /* Check for JMP instruction at start */
    if (IsJmpInstruction(funcBytes)) {
        *hookType = HOOK_INLINE;
        return TRUE;
    }

    /* Check for detour patterns */
    if (IsDetourPattern(funcBytes)) {
        *hookType = HOOK_DETOUR;
        return TRUE;
    }

    /* Check for INT3 breakpoint */
    if (funcBytes[0] == 0xCC) {
        *hookType = HOOK_INLINE;
        return TRUE;
    }

    return FALSE;
}

static BOOL CompareWithDiskSignature(const char* dllName, const char* funcName,
                                    FARPROC currentAddr, BYTE* diskSignature)
{
    char dllPath[MAX_DLL_PATH];
    GetSystemDllPath(dllName, dllPath, sizeof(dllPath));

    BYTE* diskBase = NULL;
    SIZE_T diskSize = 0;

    if (!LoadDllFromDisk(dllPath, (HMODULE*)&diskBase, &diskBase, &diskSize)) {
        return FALSE;
    }

    FARPROC diskFuncAddr = GetFunctionFromDiskImage(diskBase, funcName);
    if (!diskFuncAddr) {
        g_DynFuncs.UnmapViewOfFile(diskBase);
        return FALSE;
    }

    /* Copy signature from disk */
    memcpy(diskSignature, (BYTE*)diskFuncAddr, SIGNATURE_SIZE);

    /* Compare current memory with disk */
    BOOL isModified = memcmp((BYTE*)currentAddr, diskSignature, SIGNATURE_SIZE) != 0;

    g_DynFuncs.UnmapViewOfFile(diskBase);
    return isModified;
}

/* ------------------------------------------------------------------
 * Module-Specific Detection Functions
 * ------------------------------------------------------------------ */

BOOL ScanModuleForHooks(HMODULE hModule, HOOK_REPORT* report, const char* moduleName)
{
    if (!hModule || !report) return FALSE;

    printf("Scanning module: %s\n", moduleName ? moduleName : "Unknown");
    printf("=====================================\n");

    for (int i = 0; CRITICAL_APIS[i][0] != NULL && report->totalFunctions < MAX_API_FUNCTIONS; i++) {
        API_FUNCTION* func = &report->functions[report->totalFunctions];

        strncpy_s(func->dllName, sizeof(func->dllName), CRITICAL_APIS[i][0], _TRUNCATE);
        strncpy_s(func->functionName, sizeof(func->functionName), CRITICAL_APIS[i][1], _TRUNCATE);

        /* Get current function address */
        HMODULE hDll = g_DynFuncs.GetModuleHandleA(func->dllName);
        if (!hDll) continue;

        func->currentAddress = g_DynFuncs.GetProcAddress(hDll, func->functionName);
        if (!func->currentAddress) continue;

        /* Get signature from current memory */
        memcpy(func->signature, (BYTE*)func->currentAddress, SIGNATURE_SIZE);

        /* Compare with disk version */
        func->isHooked = CompareWithDiskSignature(func->dllName, func->functionName,
                                                 func->currentAddress, func->diskSignature);

        /* Determine hook type */
        if (func->isHooked) {
            report->hookedFunctions++;

            /* Check for IAT hook in the specified module */
            if (DetectIATHook(hModule, func->dllName, func->functionName, &func->hookType)) {
                report->iatHooks++;
            }
            /* Check for EAT hook in the DLL itself */
            else if (DetectEATHook(hDll, func->functionName, &func->hookType)) {
                report->eatHooks++;
            }
            /* Check for inline hook */
            else if (DetectInlineHook(func->currentAddress, &func->hookType)) {
                report->inlineHooks++;
            }
            else {
                func->hookType = HOOT_MEMORY_PATCH;
                report->memoryPatches++;
            }

            /* Print hook information */
            printf("HOOKED: %s!%s\n", func->dllName, func->functionName);
            printf("  Type: %s\n",
                func->hookType == HOOK_IAT ? "IAT Hook" :
                func->hookType == HOOK_EAT ? "EAT Hook" :
                func->hookType == HOOK_INLINE ? "Inline Hook" :
                func->hookType == HOOK_DETOUR ? "Detour" : "Memory Patch");

            printf("  Address: %p\n", func->currentAddress);
            printf("  Current: ");
            for (int j = 0; j < 8; j++) {
                printf("%02X ", func->signature[j]);
            }
            printf("\n  Disk:    ");
            for (int j = 0; j < 8; j++) {
                printf("%02X ", func->diskSignature[j]);
            }
            printf("\n\n");
        }

        report->totalFunctions++;
    }

    return TRUE;
}

BOOL ScanAllModulesForHooks(HOOK_REPORT* report)
{
    if (!report) return FALSE;

    memset(report, 0, sizeof(HOOK_REPORT));

    printf("Scanning all loaded modules for hooks...\n");
    printf("==========================================\n");

    DWORD processId = GetCurrentProcessId();

#ifdef _WIN64
    /* On x64, try both 64-bit and 32-bit modules */
    HANDLE hSnapshot = g_DynFuncs.CreateToolhelp32Snapshot(TH32CS_SNAPMODULE, processId);
    if (hSnapshot == INVALID_HANDLE_VALUE) {
        printf("Failed to create module snapshot\n");
        return FALSE;
    }

    MODULEENTRY32 me32;
    me32.dwSize = sizeof(MODULEENTRY32);

    if (!g_DynFuncs.Module32First(hSnapshot, &me32)) {
        CloseHandle(hSnapshot);
        printf("Failed to enumerate modules\n");
        return FALSE;
    }

    do {
        HMODULE hModule = g_DynFuncs.GetModuleHandleA(me32.szModule);
        if (hModule) {
            ScanModuleForHooks(hModule, report, me32.szModule);
        }
    } while (g_DynFuncs.Module32Next(hSnapshot, &me32) && report->totalFunctions < MAX_API_FUNCTIONS);

    CloseHandle(hSnapshot);

    /* Also try to enumerate 32-bit modules if WOW64 functions are available */
    if (g_DynFuncs.Module32FirstWOW64 && g_DynFuncs.Module32NextWOW64) {
        HANDLE hSnapshotWOW64 = g_DynFuncs.CreateToolhelp32Snapshot(TH32CS_SNAPMODULE32, processId);
        if (hSnapshotWOW64 != INVALID_HANDLE_VALUE) {
            MODULEENTRY32W me32w;
            me32w.dwSize = sizeof(MODULEENTRY32W);

            if (g_DynFuncs.Module32FirstWOW64(hSnapshotWOW64, &me32w)) {
                do {
                    char moduleName[MAX_PATH];
                    WideCharToMultiByte(CP_ACP, 0, me32w.szModule, -1, moduleName, sizeof(moduleName), NULL, NULL);
                    HMODULE hModule = g_DynFuncs.GetModuleHandleA(moduleName);
                    if (hModule) {
                        ScanModuleForHooks(hModule, report, moduleName);
                    }
                } while (g_DynFuncs.Module32NextWOW64(hSnapshotWOW64, &me32w) && report->totalFunctions < MAX_API_FUNCTIONS);
            }
            CloseHandle(hSnapshotWOW64);
        }
    }
#else
    /* On x86, only enumerate 32-bit modules */
    HANDLE hSnapshot = g_DynFuncs.CreateToolhelp32Snapshot(TH32CS_SNAPMODULE, processId);
    if (hSnapshot == INVALID_HANDLE_VALUE) {
        printf("Failed to create module snapshot\n");
        return FALSE;
    }

    MODULEENTRY32 me32;
    me32.dwSize = sizeof(MODULEENTRY32);

    if (!g_DynFuncs.Module32First(hSnapshot, &me32)) {
        CloseHandle(hSnapshot);
        printf("Failed to enumerate modules\n");
        return FALSE;
    }

    do {
        HMODULE hModule = g_DynFuncs.GetModuleHandleA(me32.szModule);
        if (hModule) {
            ScanModuleForHooks(hModule, report, me32.szModule);
        }
    } while (g_DynFuncs.Module32Next(hSnapshot, &me32) && report->totalFunctions < MAX_API_FUNCTIONS);

    CloseHandle(hSnapshot);
#endif

    return TRUE;
}

/* ------------------------------------------------------------------
 * Main Detection Function
 * ------------------------------------------------------------------ */

BOOL DetectWin32ApiHooks(HOOK_REPORT* report)
{
    if (!report) return FALSE;

    memset(report, 0, sizeof(HOOK_REPORT));

    /* Get main executable module */
    HMODULE hMainModule = g_DynFuncs.GetModuleHandleA(NULL);
    if (!hMainModule) return FALSE;

    printf("Scanning Win32 APIs for hooks...\n");
    printf("=====================================\n");

    for (int i = 0; CRITICAL_APIS[i][0] != NULL && i < MAX_API_FUNCTIONS; i++) {
        API_FUNCTION* func = &report->functions[report->totalFunctions];

        strncpy_s(func->dllName, sizeof(func->dllName), CRITICAL_APIS[i][0], _TRUNCATE);
        strncpy_s(func->functionName, sizeof(func->functionName), CRITICAL_APIS[i][1], _TRUNCATE);

        /* Get current function address */
        HMODULE hDll = g_DynFuncs.GetModuleHandleA(func->dllName);
        if (!hDll) continue;

        func->currentAddress = g_DynFuncs.GetProcAddress(hDll, func->functionName);
        if (!func->currentAddress) continue;

        /* Get signature from current memory */
        memcpy(func->signature, (BYTE*)func->currentAddress, SIGNATURE_SIZE);

        /* Compare with disk version */
        func->isHooked = CompareWithDiskSignature(func->dllName, func->functionName,
                                                 func->currentAddress, func->diskSignature);

        /* Determine hook type */
        if (func->isHooked) {
            report->hookedFunctions++;

            /* Check for IAT hook */
            if (DetectIATHook(hMainModule, func->dllName, func->functionName, &func->hookType)) {
                report->iatHooks++;
            }
            /* Check for EAT hook */
            else if (DetectEATHook(hDll, func->functionName, &func->hookType)) {
                report->eatHooks++;
            }
            /* Check for inline hook */
            else if (DetectInlineHook(func->currentAddress, &func->hookType)) {
                report->inlineHooks++;
            }
            else {
                func->hookType = HOOT_MEMORY_PATCH;
                report->memoryPatches++;
            }

            /* Print hook information */
            printf("HOOKED: %s!%s\n", func->dllName, func->functionName);
            printf("  Type: %s\n",
                func->hookType == HOOK_IAT ? "IAT Hook" :
                func->hookType == HOOK_EAT ? "EAT Hook" :
                func->hookType == HOOK_INLINE ? "Inline Hook" :
                func->hookType == HOOK_DETOUR ? "Detour" : "Memory Patch");

            printf("  Address: %p\n", func->currentAddress);
            printf("  Current: ");
            for (int j = 0; j < 8; j++) {
                printf("%02X ", func->signature[j]);
            }
            printf("\n  Disk:    ");
            for (int j = 0; j < 8; j++) {
                printf("%02X ", func->diskSignature[j]);
            }
            printf("\n\n");
        }

        report->totalFunctions++;
    }

    return TRUE;
}

/* ------------------------------------------------------------------
 * Reporting Functions
 * ------------------------------------------------------------------ */

void PrintHookReport(const HOOK_REPORT* report)
{
    printf("\n=== WIN32 API HOOK DETECTION REPORT ===\n");
    printf("Total APIs Scanned: %d\n", report->totalFunctions);
    printf("APIs Hooked: %d\n", report->hookedFunctions);
    printf("IAT Hooks: %d\n", report->iatHooks);
    printf("EAT Hooks: %d\n", report->eatHooks);
    printf("Inline Hooks: %d\n", report->inlineHooks);
    printf("Memory Patches: %d\n", report->memoryPatches);

    if (report->hookedFunctions > 0) {
        printf("\n=== DETAILED HOOK INFORMATION ===\n");
        for (int i = 0; i < report->totalFunctions; i++) {
            const API_FUNCTION* func = &report->functions[i];
            if (func->isHooked) {
                printf("\n%s!%s\n", func->dllName, func->functionName);
                printf("  Hook Type: %s\n",
                    func->hookType == HOOK_IAT ? "IAT Hook" :
                    func->hookType == HOOK_EAT ? "EAT Hook" :
                    func->hookType == HOOK_INLINE ? "Inline Hook" :
                    func->hookType == HOOK_DETOUR ? "Detour" : "Memory Patch");
                printf("  Address: %p\n", func->currentAddress);
            }
        }
    }

    printf("\n=== SUMMARY ===\n");
    if (report->hookedFunctions == 0) {
        printf("✓ No Win32 API hooks detected\n");
    } else {
        printf("⚠ %d Win32 API hooks detected - Potential cheat activity\n", report->hookedFunctions);
    }
}

/* ------------------------------------------------------------------
 * Main Entry Point
 * ------------------------------------------------------------------ */

int main(int argc, char* argv[])
{
    printf("Enhanced Win32 API Hook Detector\n");
    printf("=================================\n");
    printf("Architecture: Windows %s-bit\n", ARCH_SUFFIX);
    printf("Pointer Size: %d bytes\n\n", POINTER_SIZE);

    /* Initialize dynamic function loading */
    if (!InitializeDynamicFunctions()) {
        printf("Error: Failed to initialize dynamic functions\n");
        return 1;
    }

    HOOK_REPORT report = {0};
    BOOL success = FALSE;

    if (argc > 1) {
        if (strcmp(argv[1], "--all-modules") == 0) {
            printf("Scanning all loaded modules for hooks...\n\n");
            success = ScanAllModulesForHooks(&report);
        }
        else if (strcmp(argv[1], "--module") == 0 && argc > 2) {
            HMODULE hModule = g_DynFuncs.GetModuleHandleA(argv[2]);
            if (hModule) {
                printf("Scanning specific module: %s\n\n", argv[2]);
                success = ScanModuleForHooks(hModule, &report, argv[2]);
            } else {
                printf("Error: Module '%s' not found\n", argv[2]);
                return 1;
            }
        }
        else {
            printf("Usage:\n");
            printf("  %s                    - Scan main executable for hooks\n", argv[0]);
            printf("  %s --all-modules      - Scan all loaded modules\n", argv[0]);
            printf("  %s --module <name>    - Scan specific module (e.g., kernel32.dll)\n", argv[0]);
            return 1;
        }
    } else {
        printf("Scanning main executable for hooks...\n\n");
        success = DetectWin32ApiHooks(&report);
    }

    if (success) {
        PrintHookReport(&report);
    } else {
        printf("Error: Failed to detect Win32 API hooks\n");
        return 1;
    }

    return 0;
}
