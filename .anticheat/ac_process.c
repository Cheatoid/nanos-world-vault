/* ==========================================================================
 * ac_process.c - Detect suspicious processes & injected modules
 *
 * Scans running processes for known cheat signatures and enumerates
 * loaded modules in the game process to detect DLL injection.
 * ========================================================================== */

#include "ac_common.h"

/* ---- Blacklisted process names (lowercase) ---- */
static const CHAR* s_blacklistedProcesses[] = {
    /* Generic cheat engines */
    "cheatengine.exe",  "cheat engine.exe",
    "ce.exe",           "cheatengine-x86_64.exe",
    "x64dbg.exe",       "x32dbg.exe",
    "x64dbg32.exe",     "x64dbg64.exe",
    "ollydbg.exe",      "ollyice.exe",
    "ida.exe",          "ida64.exe",
    "idag.exe",         "idag64.exe",
    "idaq.exe",         "idaq64.exe",
    "windbg.exe",       "cdb.exe",
    "immunitydebugger.exe",
    "processhacker.exe","process hacker.exe",
    "procmon.exe",      "procmon64.exe",
    "procexp.exe",      "procexp64.exe",
    "api-monitor.exe",  "apimonitor-x64.exe",
    "apimonitor-x86.exe",
    "pe-sieve32.exe",   "pe-sieve64.exe",
    "hollows_hunter32.exe", "hollows_hunter64.exe",
    "scylla.exe",       "scylla_x64.exe",
    "scylla_x86.exe",
    "reclass.exe",      "reclass64.exe",
    "dnspy.exe",
    "de4dot.exe",
    "megadumper.exe",
    "extreme injector.exe",
    "injector.exe",
    "processhacker.exe",

    /* FPS-specific cheats */
    "aimbot.exe",       "esp.exe",
    "wallhack.exe",     "triggerbot.exe",
    "hwid_spoofer.exe", "spoofer.exe",

    /* Memory tools */
    "artmoney.exe",     "gameguard.exe",
    "memscan.exe",      "memview.exe",
    "hxd.exe",          "winhex.exe",

    /* DLL injectors */
    "extreme injector.exe",
    " injector.exe",
    "sharpinjector.exe",
    "syringe.exe",
    "faceinjector.exe",

    NULL  /* Sentinel */
};

/* ---- Blacklisted module names (DLLs) ---- */
static const CHAR* s_blacklistedModules[] = {
    "cheatengine",
    "speedhack",
    "autoaim",
    "aimbot",
    "wallhack",
    "esp",
    "triggerbot",
    "overlay",
    "imgui",        /* Many cheats use Dear ImGui overlay  */
    "menu",
    "hack",
    "inject",
    "hook",
    "detour",
    "minhook",
    "polyhook",
    "vmthook",
    "easyhook",
    "deviare",
    "madcodehook",
    "mhook",
    "reclass",
    NULL
};

/* ---- Whitelisted modules (known good) ---- */
static const CHAR* s_whitelistedModules[] = {
    "kernel32.dll",   "user32.dll",     "gdi32.dll",
    "ntdll.dll",      "msvcrt.dll",     "msvcp140.dll",
    "vcruntime140.dll","vcruntime140_1.dll",
    "opengl32.dll",   "glu32.dll",
    "d3d9.dll",       "d3d10.dll",      "d3d11.dll",
    "d3d12.dll",      "dxgi.dll",       "dinput8.dll",
    "dsound.dll",     "winmm.dll",      "ws2_32.dll",
    "xinput1_3.dll",  "xinput1_4.dll",  "xinput9_1_0.dll",
    "physx",          "nvapi",          "nvcuda",
    "steam",          "gameoverlay",    "overlay",
    "dbghelp.dll",    "crypt32.dll",    "secur32.dll",
    "sspicli.dll",    "rpcrt4.dll",     "combase.dll",
    "shlwapi.dll",    "advapi32.dll",   "ole32.dll",
    "shell32.dll",    "msvcp_win.dll",
    NULL
};

static BOOL AC_StringContainsI(const CHAR* haystack, const CHAR* needle)
{
    if (!haystack || !needle) return FALSE;
    CHAR h[260], n[260];
    /* Copy and lowercase */
    size_t i;
    for (i = 0; i < 259 && haystack[i]; i++)
        h[i] = (CHAR)tolower((unsigned char)haystack[i]);
    h[i] = '\0';
    for (i = 0; i < 259 && needle[i]; i++)
        n[i] = (CHAR)tolower((unsigned char)needle[i]);
    n[i] = '\0';
    return strstr(h, n) != NULL;
}

/*
 * Scan all running processes for blacklisted names.
 * Returns number of suspicious processes found.
 */
BOOL AC_ScanSuspiciousProcesses(void)
{
    INT found = 0;

    HANDLE hSnap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (hSnap == INVALID_HANDLE_VALUE) return FALSE;

    PROCESSENTRY32W pe = { .dwSize = sizeof(pe) };

    if (Process32FirstW(hSnap, &pe)) {
        do {
            /* Convert wide name to narrow for comparison */
            CHAR procName[MAX_PATH];
            WideCharToMultiByte(CP_ACP, 0, pe.szExeFile, -1,
                                procName, MAX_PATH, NULL, NULL);

            /* Check against blacklist */
            for (int i = 0; s_blacklistedProcesses[i]; i++) {
                if (AC_StringContainsI(procName, s_blacklistedProcesses[i])) {
                    AC_LOG(AC_SEV_CRITICAL,
                           "Suspicious process: %s (PID %u)",
                           procName, pe.th32ProcessID);

                    AC_RecordEvent(AC_CAT_PROCESS, AC_SEV_CRITICAL,
                                   "Suspicious process detected",
                                   (ULONG_PTR)pe.th32ProcessID, i);
                    found++;
                    break;
                }
            }

        } while (Process32NextW(hSnap, &pe));
    }

    CloseHandle(hSnap);

    if (found > 0) {
        g_ac.suspiciousProcCount += found;
        AC_LOG(AC_SEV_WARNING, "Suspicious process scan: %d found (total %d)",
               found, g_ac.suspiciousProcCount);
    }

    return found > 0;
}

/*
 * Enumerate modules loaded in our own process.
 * Detects DLL injection by checking for unknown/suspicious modules.
 */
BOOL AC_ScanLoadedModules(void)
{
    INT suspicious = 0;
    DWORD ourPid = GetCurrentProcessId();

    HANDLE hSnap = CreateToolhelp32Snapshot(TH32CS_SNAPMODULE, ourPid);
    if (hSnap == INVALID_HANDLE_VALUE) {
        /* May fail with ERROR_BAD_LENGTH on 64-bit - retry */
        hSnap = CreateToolhelp32Snapshot(TH32CS_SNAPMODULE, ourPid);
        if (hSnap == INVALID_HANDLE_VALUE) return FALSE;
    }

    MODULEENTRY32W me = { .dwSize = sizeof(me) };

    if (Module32FirstW(hSnap, &me)) {
        do {
            CHAR modName[MAX_PATH];
            WideCharToMultiByte(CP_ACP, 0, me.szModule, -1,
                                modName, MAX_PATH, NULL, NULL);

            /* Check whitelist first */
            BOOL whitelisted = FALSE;
            for (int i = 0; s_whitelistedModules[i]; i++) {
                if (AC_StringContainsI(modName, s_whitelistedModules[i])) {
                    whitelisted = TRUE;
                    break;
                }
            }

            if (whitelisted) continue;

            /* Check blacklist */
            for (int i = 0; s_blacklistedModules[i]; i++) {
                if (AC_StringContainsI(modName, s_blacklistedModules[i])) {
                    AC_LOG(AC_SEV_BAN,
                           "Blacklisted module: %s at %p (size %u)",
                           modName, me.modBaseAddr, me.modBaseSize);

                    AC_RecordEvent(AC_CAT_PROCESS, AC_SEV_BAN,
                                   "Blacklisted module loaded",
                                   (ULONG_PTR)me.modBaseAddr,
                                   (ULONG_PTR)me.modBaseSize);
                    suspicious++;
                    break;
                }
            }

            /* Check for modules loaded from temp/suspicious paths */
            CHAR modPath[MAX_PATH];
            WideCharToMultiByte(CP_ACP, 0, me.szExePath, -1,
                                modPath, MAX_PATH, NULL, NULL);

            if (AC_StringContainsI(modPath, "	emp") ||
                AC_StringContainsI(modPath, "	mp")   ||
                AC_StringContainsI(modPath, "\desktop") ||
                AC_StringContainsI(modPath, "\downloads") ||
                AC_StringContainsI(modPath, "\appdata\local	emp"))
            {
                AC_LOG(AC_SEV_CRITICAL,
                       "Module loaded from suspicious path: %s", modPath);

                AC_RecordEvent(AC_CAT_PROCESS, AC_SEV_CRITICAL,
                               "Module from suspicious path",
                               (ULONG_PTR)me.modBaseAddr, 0);
                suspicious++;
            }

        } while (Module32NextW(hSnap, &me));
    }

    CloseHandle(hSnap);

    /* Also check for manual-mapped DLLs by scanning for unbacked executable
       regions (VirtualAlloc'd RX/RWX pages not belonging to any module)  */
    suspicious += AC_ScanUnbackedMemory();

    return suspicious > 0;
}

/*
 * Scan virtual address space for executable regions that don't
 * belong to any loaded module - likely manual-mapped DLLs.
 */
int AC_ScanUnbackedMemory(void)
{
    int found = 0;
    MEMORY_BASIC_INFORMATION mbi;
    BYTE* addr = NULL;

    while (VirtualQuery(addr, &mbi, sizeof(mbi))) {
        /* Looking for committed, executable, private pages
           that aren't part of a mapped image */
        if (mbi.State       == MEM_COMMIT  &&
            mbi.Type        == MEM_PRIVATE &&
            (mbi.Protect & (PAGE_EXECUTE | PAGE_EXECUTE_READ |
                            PAGE_EXECUTE_READWRITE | PAGE_EXECUTE_WRITECOPY)))
        {
            /* Check if this region belongs to a known module */
            HMODULE hMod = NULL;
            BOOL result = GetModuleHandleExA(
                GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS,
                (LPCSTR)mbi.AllocationBase, &hMod);

            if (!result) {
                /* Unbacked executable region - very suspicious */
                AC_LOG(AC_SEV_CRITICAL,
                       "Unbacked executable memory at %p, size %llu, prot 0x%X",
                       mbi.BaseAddress,
                       (unsigned long long)mbi.RegionSize,
                       mbi.Protect);

                AC_RecordEvent(AC_CAT_PROCESS, AC_SEV_CRITICAL,
                               "Unbacked executable memory (possible manual map)",
                               (ULONG_PTR)mbi.BaseAddress,
                               (ULONG_PTR)mbi.RegionSize);
                found++;
            }

            if (hMod) FreeLibrary(hMod);
        }

        addr = (BYTE*)mbi.BaseAddress + mbi.RegionSize;
        if (addr < (BYTE*)mbi.BaseAddress) break; /* Overflow guard */
    }

    return found;
}

BOOL AC_IsBlacklistedProcess(DWORD pid)
{
    HANDLE hSnap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (hSnap == INVALID_HANDLE_VALUE) return FALSE;

    PROCESSENTRY32W pe = { .dwSize = sizeof(pe) };
    BOOL found = FALSE;

    if (Process32FirstW(hSnap, &pe)) {
        do {
            if (pe.th32ProcessID == pid) {
                CHAR procName[MAX_PATH];
                WideCharToMultiByte(CP_ACP, 0, pe.szExeFile, -1,
                                    procName, MAX_PATH, NULL, NULL);

                for (int i = 0; s_blacklistedProcesses[i]; i++) {
                    if (AC_StringContainsI(procName,
                                           s_blacklistedProcesses[i])) {
                        found = TRUE;
                        break;
                    }
                }
                break;
            }
        } while (Process32NextW(hSnap, &pe));
    }

    CloseHandle(hSnap);
    return found;
}
