/* ==========================================================================
 * ac_anti_debug.c - Debugger detection techniques
 *
 * Multiple methods to detect user-mode and kernel-mode debuggers.
 * ========================================================================== */

#include "ac_common.h"

/* NtQueryInformationProcess function pointer */
typedef NTSTATUS(NTAPI* pfnNtQueryInformationProcess)(
    HANDLE ProcessHandle,
    PROCESSINFOCLASS ProcessInformationClass,
    PVOID ProcessInformation,
    ULONG ProcessInformationLength,
    PULONG ReturnLength
);

/*
 * Method 1: IsDebuggerPresent
 */
static BOOL AC_CheckIsDebuggerPresent(void)
{
    if (IsDebuggerPresent()) {
        AC_LOG(AC_SEV_BAN, "IsDebuggerPresent() returned TRUE");
        return TRUE;
    }
    return FALSE;
}

/*
 * Method 2: CheckRemoteDebuggerPresent
 */
static BOOL AC_CheckRemoteDebugger(void)
{
    BOOL bDebuggerPresent = FALSE;
    CheckRemoteDebuggerPresent(GetCurrentProcess(), &bDebuggerPresent);
    if (bDebuggerPresent) {
        AC_LOG(AC_SEV_BAN, "Remote debugger detected");
        return TRUE;
    }
    return FALSE;
}

/*
 * Method 3: NtQueryInformationProcess - ProcessDebugPort
 */
static BOOL AC_CheckDebugPort(void)
{
    HMODULE hNtDll = GetModuleHandleA("ntdll.dll");
    if (!hNtDll) return FALSE;

    pfnNtQueryInformationProcess NtQIP =
        (pfnNtQueryInformationProcess)GetProcAddress(hNtDll,
            "NtQueryInformationProcess");

    if (!NtQIP) return FALSE;

    DWORD_PTR debugPort = 0;
    NTSTATUS status = NtQIP(GetCurrentProcess(),
                            (PROCESSINFOCLASS)7, /* ProcessDebugPort */
                            &debugPort, sizeof(debugPort), NULL);

    if (NT_SUCCESS(status) && debugPort != 0) {
        AC_LOG(AC_SEV_BAN, "Debug port detected (0x%llX)",
               (unsigned long long)debugPort);
        return TRUE;
    }
    return FALSE;
}

/*
 * Method 4: NtQueryInformationProcess - ProcessDebugObjectHandle
 */
static BOOL AC_CheckDebugObject(void)
{
    HMODULE hNtDll = GetModuleHandleA("ntdll.dll");
    if (!hNtDll) return FALSE;

    pfnNtQueryInformationProcess NtQIP =
        (pfnNtQueryInformationProcess)GetProcAddress(hNtDll,
            "NtQueryInformationProcess");

    if (!NtQIP) return FALSE;

    HANDLE debugObject = NULL;
    NTSTATUS status = NtQIP(GetCurrentProcess(),
                            (PROCESSINFOCLASS)30, /* ProcessDebugObjectHandle */
                            &debugObject, sizeof(debugObject), NULL);

    if (NT_SUCCESS(status) && debugObject != NULL) {
        AC_LOG(AC_SEV_BAN, "Debug object handle detected");
        CloseHandle(debugObject);
        return TRUE;
    }
    return FALSE;
}

/*
 * Method 5: PEB-based detection (BeingDebugged, NtGlobalFlag)
 */
static BOOL AC_CheckPEB(void)
{
#ifdef _WIN64
    PPEB peb = (PPEB)__readgsqword(0x60);
#else
    PPEB peb = (PPEB)__readfsdword(0x30);
#endif

    if (peb->BeingDebugged) {
        AC_LOG(AC_SEV_BAN, "PEB.BeingDebugged = 1");
        return TRUE;
    }

    /* NtGlobalFlag - at offset 0xBC (x86) or 0xBC (x64) from PEB start */
#ifdef _WIN64
    DWORD ntGlobalFlag = *(DWORD*)((BYTE*)peb + 0xBC);
#else
    DWORD ntGlobalFlag = *(DWORD*)((BYTE*)peb + 0x68);
#endif

    /* FLG_HEAP_ENABLE_TAIL_CHECK (0x10)
       FLG_HEAP_ENABLE_FREE_CHECK (0x20)
       FLG_HEAP_VALIDATE_PARAMETERS (0x40) */
    if (ntGlobalFlag & 0x70) {
        AC_LOG(AC_SEV_BAN, "NtGlobalFlag = 0x%X (debug flags set)",
               ntGlobalFlag);
        return TRUE;
    }

    return FALSE;
}

/*
 * Method 6: Timing checks - rdtsc
 */
static BOOL AC_CheckTimingDebug(void)
{
    LARGE_INTEGER start, end, freq;
    QueryPerformanceFrequency(&freq);
    QueryPerformanceCounter(&start);

    /* Do some work that should take a deterministic time */
    volatile int sink = 0;
    for (int i = 0; i < 1000; i++) {
        sink += i * i;
    }

    QueryPerformanceCounter(&end);

    double elapsed_ms = (double)(end.QuadPart - start.QuadPart)
                      * 1000.0 / (double)freq.QuadPart;

    /* If elapsed > 50ms, likely a debugger single-stepping */
    if (elapsed_ms > 50.0) {
        AC_LOG(AC_SEV_CRITICAL,
               "Timing anomaly: %.2f ms for trivial loop (possible single-step)",
               elapsed_ms);
        return TRUE;
    }

    return FALSE;
}

/*
 * Method 7: Check for hardware breakpoints (DR0-DR3)
 */
BOOL AC_DetectHardwareBreakpoints(void)
{
    CONTEXT ctx = {0};
    ctx.ContextFlags = CONTEXT_DEBUG_REGISTERS;

    if (GetThreadContext(GetCurrentThread(), &ctx)) {
        if (ctx.Dr0 || ctx.Dr1 || ctx.Dr2 || ctx.Dr3) {
            AC_LOG(AC_SEV_BAN,
                   "Hardware breakpoints detected: DR0=0x%llX DR1=0x%llX "
                   "DR2=0x%llX DR3=0x%llX",
                   (unsigned long long)ctx.Dr0,
                   (unsigned long long)ctx.Dr1,
                   (unsigned long long)ctx.Dr2,
                   (unsigned long long)ctx.Dr3);

            AC_RecordEvent(AC_CAT_HOOK, AC_SEV_BAN,
                           "Hardware breakpoints detected",
                           (ULONG_PTR)ctx.Dr0, (ULONG_PTR)ctx.Dr1);
            return TRUE;
        }
    }
    return FALSE;
}

/*
 * Method 8: Check for software breakpoints in game code
 */
static BOOL AC_CheckSoftwareBreakpoints(void)
{
    if (!g_ac.hGameModule) return FALSE;

    BYTE* base = (BYTE*)g_ac.hGameModule;
    IMAGE_DOS_HEADER* dos = (IMAGE_DOS_HEADER*)base;
    IMAGE_NT_HEADERS* nt  = (IMAGE_NT_HEADERS*)(base + dos->e_lfanew);
    IMAGE_SECTION_HEADER* sec = IMAGE_FIRST_SECTION(nt);

    for (int i = 0; i < nt->FileHeader.NumberOfSections; i++) {
        if (sec[i].Characteristics & IMAGE_SCN_MEM_EXECUTE) {
            BYTE* secStart = base + sec[i].VirtualAddress;
            DWORD secSize  = sec[i].Misc.VirtualSize;

            DWORD oldProt;
            VirtualProtect(secStart, secSize, PAGE_READWRITE, &oldProt);

            for (DWORD j = 0; j < secSize; j++) {
                if (secStart[j] == 0xCC) {
                    /* Could be legitimate INT3 - check if it's original */
                    AC_LOG(AC_SEV_CRITICAL,
                           "INT3 (0xCC) at %p (section offset %u)",
                           secStart + j, j);
                }
            }

            VirtualProtect(secStart, secSize, oldProt, &oldProt);
        }
    }

    return FALSE;
}

/*
 * Combined anti-debug check
 */
BOOL AC_DetectDebugger(void)
{
    BOOL detected = FALSE;

    detected |= AC_CheckIsDebuggerPresent();
    detected |= AC_CheckRemoteDebugger();
    detected |= AC_CheckDebugPort();
    detected |= AC_CheckDebugObject();
    detected |= AC_CheckPEB();
    detected |= AC_CheckTimingDebug();
    detected |= AC_DetectHardwareBreakpoints();

    if (detected) {
        AC_RecordEvent(AC_CAT_INTEGRITY, AC_SEV_BAN,
                       "Debugger detected", 0, 0);
    }

    return detected;
}
