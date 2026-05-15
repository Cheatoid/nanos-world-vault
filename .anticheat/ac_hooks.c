/* ==========================================================================
 * ac_hooks.c - Detect IAT hooks, inline hooks, and debug hooks
 *
 * IAT Hook:   A pointer in the Import Address Table has been overwritten
 *             to point outside the legitimate DLL's address range.
 *
 * Inline Hook:The first bytes of an imported function have been patched
 *             with a JMP (E9 / FF 25) or a detour trampoline.
 * ========================================================================== */

#include "ac_common.h"

/* Common x86-64 jump opcodes */
#define OP_JMP_SHORT   0xEB    /* EB xx            */
#define OP_JMP_NEAR    0xE9    /* E9 xx xx xx xx   */
#define OP_JMP_FAR     0xFF    /* FF 25 xx xx xx xx (indirect) */
#define OP_NOP         0x90
#define OP_INT3        0xCC
#define OP_RETN        0xC3

/* ---- Helper: check if address is a JMP instruction ---- */
static BOOL AC_IsJmpInstruction(BYTE* addr)
{
    if (!addr) return FALSE;

    BYTE b0 = addr[0];

    /* Short JMP (EB xx) */
    if (b0 == OP_JMP_SHORT) return TRUE;

    /* Near JMP (E9 xx xx xx xx) */
    if (b0 == OP_JMP_NEAR) return TRUE;

    /* Indirect JMP (FF 25 xx xx xx xx) - 64-bit common */
    if (b0 == 0xFF && addr[1] == 0x25) return TRUE;

    /* PUSH addr; RET - common detour pattern */
    if (b0 == 0x68 && addr[5] == OP_RETN) return TRUE;

    /* MOV RAX, addr; JMP RAX */
    if (b0 == 0x48 && addr[1] == 0xB8 && addr[10] == 0xFF &&
        addr[11] == 0xE0) return TRUE;

    return FALSE;
}

/*
 * Scan IAT of the game module for entries that point outside
 * the legitimate DLL's code range.
 */
BOOL AC_DetectIATHooks(HMODULE hMod)
{
    if (!hMod) return FALSE;

    BYTE* base = (BYTE*)hMod;
    IMAGE_DOS_HEADER*     dos = (IMAGE_DOS_HEADER*)base;
    IMAGE_NT_HEADERS*     nt  = (IMAGE_NT_HEADERS*)(base + dos->e_lfanew);
    IMAGE_IMPORT_DESCRIPTOR* imports;

    imports = (IMAGE_IMPORT_DESCRIPTOR*)(
        base + nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT]
              .VirtualAddress);

    if (!imports) return FALSE;

    DWORD importSize = nt->OptionalHeader.DataDirectory
                       [IMAGE_DIRECTORY_ENTRY_IMPORT].Size;
    if (importSize == 0) return FALSE;

    INT hooksFound = 0;

    while (imports->Name != 0) {
        CHAR* dllName = (CHAR*)(base + imports->Name);

        /* Get the actual DLL's address range */
        HMODULE hDll = GetModuleHandleA(dllName);
        if (!hDll) {
            imports++;
            continue;
        }

        MODULEINFO dllInfo = {0};
        GetModuleInformation(GetCurrentProcess(), hDll,
                             &dllInfo, sizeof(dllInfo));

        BYTE* dllStart = (BYTE*)dllInfo.lpBaseOfDll;
        BYTE* dllEnd   = dllStart + dllInfo.SizeOfImage;

        /* Walk the IAT for this DLL */
        IMAGE_THUNK_DATA* thunk = (IMAGE_THUNK_DATA*)(
            base + imports->FirstThunk);

        while (thunk->u1.AddressOfData != 0) {
            FARPROC* iatEntry = (FARPROC*)&thunk->u1.Function;
            BYTE* funcAddr = (BYTE*)*iatEntry;

            /* Check if the IAT entry points outside the DLL */
            if (funcAddr < dllStart || funcAddr >= dllEnd) {
                /* Check if it's a legitimate forwarder */
                IMAGE_IMPORT_BY_NAME* ibn = (IMAGE_IMPORT_BY_NAME*)(
                    base + ((IMAGE_THUNK_DATA*)(
                        base + imports->OriginalFirstThunk))
                    ->u1.AddressOfData);

                CHAR funcName[256] = {0};
                if (ibn) {
                    strncpy_s(funcName, sizeof(funcName),
                              (CHAR*)ibn->Name, 255);
                }

                AC_LOG(AC_SEV_CRITICAL,
                       "IAT hook detected: %s!%s -> %p (outside %p-%p)",
                       dllName, funcName, funcAddr, dllStart, dllEnd);

                AC_RecordEvent(AC_CAT_HOOK, AC_SEV_CRITICAL,
                               "IAT hook detected",
                               (ULONG_PTR)funcAddr,
                               (ULONG_PTR)iatEntry);
                hooksFound++;
            }

            thunk++;
        }

        imports++;
    }

    if (hooksFound > 0) {
        g_ac.hookDetectCount += hooksFound;
    }

    return hooksFound > 0;
}

/*
 * Scan the first bytes of critical imported functions for
 * inline/detour hooks (JMP patches, INT3 breakpoints, etc.)
 */
typedef struct _AC_CRITICAL_FUNC {
    const CHAR* dll;
    const CHAR* name;
    FARPROC     funcPtr;
} AC_CRITICAL_FUNC;

/* Functions commonly hooked by cheats */
static AC_CRITICAL_FUNC s_criticalFunctions[] = {
    { "user32.dll",   "GetCursorPos",       NULL },
    { "user32.dll",   "SetCursorPos",       NULL },
    { "user32.dll",   "GetAsyncKeyState",   NULL },
    { "winmm.dll",    "timeGetTime",        NULL },
    { "kernel32.dll", "GetTickCount",       NULL },
    { "kernel32.dll", "QueryPerformanceCounter", NULL },
    { "kernel32.dll", "Sleep",              NULL },
    { "kernel32.dll", "VirtualProtect",     NULL },
    { "kernel32.dll", "VirtualAlloc",       NULL },
    { "kernel32.dll", "WriteProcessMemory", NULL },
    { "kernel32.dll", "ReadProcessMemory",  NULL },
    { "kernel32.dll", "CreateRemoteThread", NULL },
    { "kernel32.dll", "OpenProcess",        NULL },
    { "d3d9.dll",     "Direct3DCreate9",    NULL },
    { "d3d11.dll",    "D3D11CreateDeviceAndSwapChain", NULL },
    { "dxgi.dll",     "CreateDXGIFactory",  NULL },
    { "ws2_32.dll",   "send",              NULL },
    { "ws2_32.dll",   "recv",              NULL },
    { "ws2_32.dll",   "sendto",            NULL },
    { "ws2_32.dll",   "recvfrom",          NULL },
    { NULL, NULL, NULL }
};

BOOL AC_DetectInlineHooks(HMODULE hMod)
{
    INT hooksFound = 0;

    for (int i = 0; s_criticalFunctions[i].dll; i++) {
        AC_CRITICAL_FUNC* cf = &s_criticalFunctions[i];

        HMODULE hDll = GetModuleHandleA(cf->dll);
        if (!hDll) continue;

        cf->funcPtr = GetProcAddress(hDll, cf->name);
        if (!cf->funcPtr) continue;

        BYTE* funcBytes = (BYTE*)cf->funcPtr;

        /* Check first bytes for hook signatures */
        if (AC_IsJmpInstruction(funcBytes)) {
            AC_LOG(AC_SEV_CRITICAL,
                   "Inline hook on %s!%s at %p (first bytes: %02X %02X %02X %02X %02X)",
                   cf->dll, cf->name, funcBytes,
                   funcBytes[0], funcBytes[1], funcBytes[2],
                   funcBytes[3], funcBytes[4]);

            AC_RecordEvent(AC_CAT_HOOK, AC_SEV_CRITICAL,
                           "Inline hook detected",
                           (ULONG_PTR)funcBytes, i);
            hooksFound++;
            continue;
        }

        /* Check for INT3 breakpoint (0xCC) in first 16 bytes */
        for (int j = 0; j < 16; j++) {
            if (funcBytes[j] == OP_INT3) {
                AC_LOG(AC_SEV_CRITICAL,
                       "INT3 breakpoint on %s!%s at offset %d",
                       cf->dll, cf->name, j);

                AC_RecordEvent(AC_CAT_HOOK, AC_SEV_CRITICAL,
                               "INT3 breakpoint detected",
                               (ULONG_PTR)funcBytes, j);
                hooksFound++;
                break;
            }
        }

        /* Check for NOP sled (multiple 0x90) at start */
        int nopCount = 0;
        for (int j = 0; j < 16; j++) {
            if (funcBytes[j] == OP_NOP) nopCount++;
        }
        if (nopCount >= 4) {
            AC_LOG(AC_SEV_WARNING,
                   "NOP sled on %s!%s (%d NOPs)", cf->dll, cf->name, nopCount);

            AC_RecordEvent(AC_CAT_HOOK, AC_SEV_WARNING,
                           "NOP sled detected on function",
                           (ULONG_PTR)funcBytes, nopCount);
            hooksFound++;
        }
    }

    if (hooksFound > 0) {
        g_ac.hookDetectCount += hooksFound;
    }

    return hooksFound > 0;
}

/*
 * Detect debug-related hooks / instrumentation.
 */
BOOL AC_DetectDebugHooks(void)
{
    INT found = 0;

    /* Check NtQueryInformationProcess for debugger detection bypass */
    HMODULE hNtDll = GetModuleHandleA("ntdll.dll");
    if (hNtDll) {
        FARPROC pNtQIP = GetProcAddress(hNtDll, "NtQueryInformationProcess");
        if (pNtQIP && AC_IsJmpInstruction((BYTE*)pNtQIP)) {
            AC_LOG(AC_SEV_CRITICAL,
                   "NtQueryInformationProcess appears hooked!");
            AC_RecordEvent(AC_CAT_HOOK, AC_SEV_CRITICAL,
                           "NtQueryInformationProcess hooked", 0, 0);
            found++;
        }

        /* Check NtClose (anti-debug bypass often hooks this) */
        FARPROC pNtClose = GetProcAddress(hNtDll, "NtClose");
        if (pNtClose && AC_IsJmpInstruction((BYTE*)pNtClose)) {
            AC_LOG(AC_SEV_CRITICAL, "NtClose appears hooked!");
            AC_RecordEvent(AC_CAT_HOOK, AC_SEV_CRITICAL,
                           "NtClose hooked", 0, 0);
            found++;
        }
    }

    /* Check if OutputDebugString is hooked (anti-outputdebugstring bypass) */
    HMODULE hKernel32 = GetModuleHandleA("kernel32.dll");
    if (hKernel32) {
        FARPROC pODS = GetProcAddress(hKernel32, "OutputDebugStringA");
        if (pODS && AC_IsJmpInstruction((BYTE*)pODS)) {
            AC_LOG(AC_SEV_WARNING, "OutputDebugStringA appears hooked");
            AC_RecordEvent(AC_CAT_HOOK, AC_SEV_WARNING,
                           "OutputDebugStringA hooked", 0, 0);
            found++;
        }
    }

    return found > 0;
}
