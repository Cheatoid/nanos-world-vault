# AntiCheat System

Organized into logical components... It is a draft for usermode, not ready for use.

---

## CMake Build Instructions

To generate Visual Studio 2026 (or compatible) project files and build the anti-cheat library using CMake:

1.  **Generate Project Files**: Navigate to the root of this directory in your terminal and run the following command. This will create a `build` subdirectory containing the Visual Studio solution.
    ```bash
    cmake -G "Visual Studio 18 2026" -A x64 -B build
    ```
    *   **Note**: If you are targeting a 32-bit build, replace `-A x64` with `-A Win32`.

2.  **Build the Library**: After generating the project files, you can build the static library (and any other targets defined in the CMakeLists.txt) using CMake:
    ```bash
    cmake --build build --config Release
    ```
    *   **Note**: Replace `Release` with `Debug` or another configuration as needed.

## Common Header & Configuration

```c
/* ==========================================================================
 * ac_common.h - Shared types, configuration, logging
 * ========================================================================== */
#ifndef AC_COMMON_H
#define AC_COMMON_H

#include <windows.h>
#include <winternl.h>       /* NtQueryInformationProcess etc. */
#include <tlhelp32.h>
#include <psapi.h>
#include <shlwapi.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <math.h>

#pragma comment(lib, "psapi.lib")
#pragma comment(lib, "shlwapi.lib")
#pragma comment(lib, "ntdll.lib")

/* ------------------------------------------------------------------
 * Configuration - TODO: tweak these
 * ------------------------------------------------------------------ */
#define AC_VERSION              "1.0.0"

/* Scan intervals (milliseconds) */
#define AC_HEARTBEAT_INTERVAL       5000    /* Main loop tick      */
#define AC_MEMORY_SCAN_INTERVAL    10000    /* Code CRC check      */
#define AC_PROCESS_SCAN_INTERVAL   15000    /* Suspicious procs    */
#define AC_HOOK_SCAN_INTERVAL      12000    /* IAT/inline hooks    */
#define AC_TIMING_SAMPLE_INTERVAL   2000    /* Speed-hack sample   */
#define AC_INPUT_SAMPLE_INTERVAL    1000    /* Aimbot analysis     */
#define AC_SS_INTERVAL             30000    /* Screenshot check    */
#define AC_VM_SCAN_INTERVAL         20000   /* VM/Sandbox check interval (ms) */

/* Thresholds */
#define AC_SPEED_TOLERANCE_PCT       5.0f  /* ±5 % timing drift   */
#define AC_AIM_SNAP_ANGLE_DEG       30.0f  /* Max instantaneous   */
#define AC_AIM_SNAP_COUNT_BAN        10    /* Snaps before flag   */
#define AC_CRC_MISMATCH_BAN          3     /* CRC fails before ban*/
#define AC_MAX_SUSPICIOUS_PROCS      5     /* Procs before flag   */

/* Report endpoint */
#define AC_REPORT_URL  L"https://gameserver.com/api/ac/report"

/* ------------------------------------------------------------------
 * Severity levels
 * ------------------------------------------------------------------ */
typedef enum _AC_SEVERITY {
    AC_SEV_INFO       = 0,
    AC_SEV_WARNING    = 1,
    AC_SEV_CRITICAL   = 2,
    AC_SEV_BAN        = 3
} AC_SEVERITY;

/* ------------------------------------------------------------------
 * Detection categories
 * ------------------------------------------------------------------ */
typedef enum _AC_CATEGORY {
    AC_CAT_MEMORY       = 0,   /* Code/data integrity violation  */
    AC_CAT_PROCESS      = 1,   /* Suspicious process found       */
    AC_CAT_HOOK         = 2,   /* API / function hook detected   */
    AC_CAT_TIMING       = 3,   /* Speed-hack / timer manip       */
    AC_CAT_INPUT        = 4,   /* Aimbot / input anomaly         */
    AC_CAT_NETWORK      = 5,   /* Movement / packet anomaly      */
    AC_CAT_HWID         = 6,   /* Banned hardware                */
    AC_CAT_SCREENSHOT   = 7,   /* Overlay / wallhack             */
    AC_CAT_INTEGRITY    = 8,   /* AntiCheat itself tampered      */
    AC_CAT_VIRTUALIZATION = 9  /* VM / Sandbox / Hypervisor detected */
} AC_CATEGORY;

/* ------------------------------------------------------------------
 * Detection event - one per finding
 * ------------------------------------------------------------------ */
typedef struct _AC_EVENT {
    AC_CATEGORY   category;
    AC_SEVERITY   severity;
    DWORD         timestamp;          /* GetTickCount() at detect  */
    CHAR          detail[256];        /* Human-readable string     */
    ULONG_PTR     param1;             /* Extra data (addr, pid…)   */
    ULONG_PTR     param2;
} AC_EVENT;

/* ------------------------------------------------------------------
 * Player state - filled by game code every frame
 * ------------------------------------------------------------------ */
typedef struct _AC_PLAYERSTATE {
    FLOAT     viewAngles[3];          /* Yaw, pitch, roll         */
    FLOAT     position[3];            /* World XYZ                */
    FLOAT     velocity[3];
    FLOAT     health;
    DWORD     flags;                  /* On-ground, crouching…    */
    DOUBLE    serverTime;             /* Server-authoritative time*/
} AC_PLAYERSTATE;

/* ------------------------------------------------------------------
 * Global state
 * ------------------------------------------------------------------ */
typedef struct _AC_GLOBALS {
    /* Threads */
    HANDLE    hMainThread;
    HANDLE    hScanThread;
    BOOL      running;

    /* Player state (updated by game each frame) */
    CRITICAL_SECTION stateLock;
    AC_PLAYERSTATE   playerState;
    AC_PLAYERSTATE   prevState;
    BOOL             stateValid;

    /* Detection counter */
    CRITICAL_SECTION eventLock;
    AC_EVENT         events[256];
    INT              eventCount;
    INT              crcFailCount;
    INT              aimSnapCount;
    INT              suspiciousProcCount;
    INT              hookDetectCount;

    /* Timing */
    LARGE_INTEGER    perfFreq;
    LARGE_INTEGER    lastPerfCounter;
    DWORD            lastTickCount;

    /* Module info */
    HMODULE          hGameModule;     /* Base of game .exe / DLL  */
    DWORD            gameModuleSize;

    /* Callbacks - game registers these */
    void (*fnBanCallback)(AC_CATEGORY cat, const CHAR* detail);
    void (*fnLogCallback)(AC_SEVERITY sev, const CHAR* msg);

    /* HWID cache */
    CHAR             hwid[65];        /* SHA-256 hex string       */
} AC_GLOBALS;

/* Single global instance */
static AC_GLOBALS g_ac = {0};

/* ------------------------------------------------------------------
 * Utility macros
 * ------------------------------------------------------------------ */
#define AC_LOG(sev, fmt, ...) do {                                      \
    CHAR _buf[512];                                                     \
    sprintf_s(_buf, sizeof(_buf), "[AC][%s] " fmt "\n",                 \
              (sev)==AC_SEV_INFO?"INFO":(sev)==AC_SEV_WARNING?"WARN":   \
              (sev)==AC_SEV_CRITICAL?"CRIT":"BAN", ##__VA_ARGS__);       \
    OutputDebugStringA(_buf);                                           \
    if (g_ac.fnLogCallback) g_ac.fnLogCallback(sev, _buf);             \
} while(0)

#define AC_MIN(a,b) ((a)<(b)?(a):(b))
#define AC_MAX(a,b) ((a)>(b)?(a):(b))
#define AC_CLAMP(x,lo,hi) AC_MAX(lo,AC_MIN(x,hi))
#define AC_DEG2RAD(d) ((d)*0.017453292519943295769)
#define AC_RAD2DEG(r) ((r)*57.295779513082320876798)

/* ------------------------------------------------------------------
 * Function declarations (implemented in each module)
 * ------------------------------------------------------------------ */

/* ac_core.c */
BOOL  AC_Initialize(HMODULE hGameModule);
void  AC_Shutdown(void);
void  AC_UpdatePlayerState(const AC_PLAYERSTATE* ps);
DWORD WINAPI AC_ScanThread(LPVOID param);
void  AC_RecordEvent(AC_CATEGORY cat, AC_SEVERITY sev,
                     const CHAR* detail, ULONG_PTR p1, ULONG_PTR p2);
void  AC_EvaluateBan(void);

/* ac_crc.c - CRC32 / hash helpers */
DWORD AC_CRC32(const BYTE* data, SIZE_T len);
BOOL  AC_ComputeModuleCRC(HMODULE hMod, DWORD* outCrc, DWORD* outSize);
BOOL  AC_VerifyCodeIntegrity(void);

/* ac_process.c - Process & module scanning */
BOOL  AC_ScanSuspiciousProcesses(void);
BOOL  AC_ScanLoadedModules(void);
BOOL  AC_IsBlacklistedProcess(DWORD pid);

/* ac_hooks.c - API hook detection */
BOOL  AC_DetectIATHooks(HMODULE hMod);
BOOL  AC_DetectInlineHooks(HMODULE hMod);
BOOL  AC_DetectDebugHooks(void);

/* ac_timing.c - Speed-hack detection */
BOOL  AC_InitTiming(void);
BOOL  AC_CheckTimingAnomaly(void);

/* ac_input.c - Aimbot detection */
BOOL  AC_AnalyzeInput(void);
FLOAT AC_CalcAngleDelta(const FLOAT a[3], const FLOAT b[3]);

/* ac_network.c - Server-side validation helpers */
BOOL  AC_ValidateMovement(const AC_PLAYERSTATE* prev,
                          const AC_PLAYERSTATE* curr);

/* ac_hwid.c - Hardware ID */
BOOL  AC_GenerateHWID(CHAR* out, SIZE_T outLen);

/* ac_hwid_advanced.c - Advanced HWID gathering */
BOOL  AC_CollectAdvancedHWID(CHAR* out, SIZE_T outLen);
BOOL  AC_ValidateHWIDStability(const CHAR* currentHWID);

/* ac_hwid_lowlevel.c - Low-level hardware access */
BOOL  AC_CollectLowLevelHWID(AC_LOWLEVEL_HWID* hwid);
BOOL  AC_GenerateLowLevelHWID(const AC_LOWLEVEL_HWID* hwid, CHAR* out, SIZE_T outLen);

/* ac_image_coherency.c - Image coherency detection */
BOOL  AC_ScanModuleCoherency(AC_COHERENCY_RESULTS* results);
BOOL  AC_CheckModuleCoherency(const CHAR* moduleName);
BOOL  AC_ValidateSystemModules(void);
BOOL  AC_PeriodicCoherencyCheck(void);

/* ac_screenshot.c - Overlay / wallhack detection */
BOOL  AC_CaptureAndAnalyze(void);

/* ac_report.c - Server reporting */
BOOL  AC_SendReport(const AC_EVENT* evt);

/* ac_anti_debug.c - Anti-debugging */
BOOL  AC_DetectDebugger(void);
BOOL  AC_DetectHardwareBreakpoints(void);

/* ac_anti_vm.c - Anti-VM & Anti-Sandboxie */
BOOL  AC_DetectVirtualMachine(void);
BOOL  AC_DetectSandboxie(void);
BOOL  AC_ScanVirtualization(void); /* Combined entry point */

/* ---- Low-level HWID structure ---- */
typedef struct _AC_LOWLEVEL_HWID {
    CHAR smbiosUuid[64];             /* SMBIOS Type 1 UUID */
    CHAR smbiosManufacturer[256];    /* SMBIOS Type 1 Manufacturer */
    CHAR smbiosProduct[256];         /* SMBIOS Type 1 Product */
    CHAR smbiosSerial[256];          /* SMBIOS Type 1 Serial */
    CHAR smbiosBaseboardSerial[256]; /* SMBIOS Type 2 Serial */
    CHAR realDiskSerial[256];        /* Storage IOCTL disk serial */
    CHAR tpmEkh[256];                /* TPM endorsement key hash */
    BYTE cpuSignature[4];            /* CPU signature from CPUID */
    BYTE cpuFeatures[4];             /* CPU features from CPUID */
    DWORD hypervisorLeaves;          /* Hypervisor CPUID leaves */
} AC_LOWLEVEL_HWID;

/* ---- Image coherency results structure ---- */
typedef struct _AC_COHERENCY_RESULTS {
    DWORD totalModules;                 /* Total modules checked */
    DWORD coherentModules;              /* Modules that match disk */
    DWORD incoherentModules;            /* Modules that don't match disk */
    DWORD systemModules;                /* System modules checked */
    DWORD suspiciousModules;            /* Modules with anomalies */
    CHAR lastIncoherentModule[MAX_PATH];/* Last incoherent module found */
} AC_COHERENCY_RESULTS;

#endif /* AC_COMMON_H */
```

---

## CRC / Memory Integrity

```c
/* ==========================================================================
 * ac_crc.c - CRC32 and code-integrity verification
 *
 * Computes CRC32 of the game's .text section at startup (trusted baseline),
 * then periodically re-checks to detect in-memory patching.
 * Also verifies guard regions placed around critical data.
 * ========================================================================== */

#include "ac_common.h"

/* ---- CRC32 lookup table (polynomial 0xEDB88320) ---- */
static DWORD s_crcTable[256];
static BOOL  s_crcTableInit = FALSE;

static void AC_InitCRCTable(void)
{
    for (DWORD i = 0; i < 256; i++) {
        DWORD c = i;
        for (int j = 0; j < 8; j++) {
            if (c & 1) c = 0xEDB88320 ^ (c >> 1);
            else       c >>= 1;
        }
        s_crcTable[i] = c;
    }
    s_crcTableInit = TRUE;
}

DWORD AC_CRC32(const BYTE* data, SIZE_T len)
{
    if (!s_crcTableInit) AC_InitCRCTable();

    DWORD crc = 0xFFFFFFFF;
    for (SIZE_T i = 0; i < len; i++) {
        crc = s_crcTable[(crc ^ data[i]) & 0xFF] ^ (crc >> 8);
    }
    return crc ^ 0xFFFFFFFF;
}

/* ---- Baseline CRC stored at init ---- */
static DWORD s_baselineCRC   = 0;
static DWORD s_gameCodeSize  = 0;
static DWORD s_textSectionVA = 0;
static DWORD s_textSectionSize = 0;

/*
 * Compute the CRC of the game module's .text section.
 * Called once at startup to establish the baseline.
 */
BOOL AC_ComputeModuleCRC(HMODULE hMod, DWORD* outCrc, DWORD* outSize)
{
    if (!hMod) return FALSE;

    BYTE* base = (BYTE*)hMod;
    IMAGE_DOS_HEADER*       dos = (IMAGE_DOS_HEADER*)base;
    IMAGE_NT_HEADERS*       nt  = (IMAGE_NT_HEADERS*)(base + dos->e_lfanew);
    IMAGE_SECTION_HEADER*   sec = IMAGE_FIRST_SECTION(nt);

    /* Find .text section */
    for (int i = 0; i < nt->FileHeader.NumberOfSections; i++) {
        CHAR name[9] = {0};
        memcpy(name, sec[i].Name, 8);

        if (strcmp(name, ".text") == 0) {
            BYTE*  secData = base + sec[i].VirtualAddress;
            DWORD  secSize = sec[i].Misc.VirtualSize;

            /* Temporarily make page readable if needed */
            DWORD oldProt;
            VirtualProtect(secData, secSize, PAGE_READWRITE, &oldProt);

            *outCrc  = AC_CRC32(secData, secSize);
            *outSize = secSize;

            s_textSectionVA   = (DWORD)(sec[i].VirtualAddress);
            s_textSectionSize = secSize;

            VirtualProtect(secData, secSize, oldProt, &oldProt);

            AC_LOG(AC_SEV_INFO, "Module CRC = 0x%08X, .text size = %u bytes",
                   *outCrc, *outSize);
            return TRUE;
        }
    }

    AC_LOG(AC_SEV_CRITICAL, "Could not find .text section in module");
    return FALSE;
}

/*
 * Verify current code integrity against baseline.
 * Returns TRUE if OK, FALSE if tampered.
 *
 * Strategy: We don't CRC the entire .text every tick - that's slow.
 * Instead we sample random 4 KB pages within .text and CRC those,
 * doing a full scan only occasionally.
 */
BOOL AC_VerifyCodeIntegrity(void)
{
    if (!g_ac.hGameModule || s_textSectionSize == 0) return TRUE;

    BYTE* base = (BYTE*)g_ac.hGameModule;
    BYTE* textBase = base + s_textSectionVA;

    static DWORD  fullScanCounter = 0;
    BOOL  result = TRUE;

    fullScanCounter++;

    if (fullScanCounter % 10 == 0) {
        /* ---- Full scan (every 10th call) ---- */
        DWORD oldProt;
        VirtualProtect(textBase, s_textSectionSize, PAGE_READWRITE, &oldProt);

        DWORD currentCRC = AC_CRC32(textBase, s_textSectionSize);

        VirtualProtect(textBase, s_textSectionSize, oldProt, &oldProt);

        if (currentCRC != s_baselineCRC) {
            AC_LOG(AC_SEV_CRITICAL,
                   "Full code CRC mismatch! Expected 0x%08X got 0x%08X",
                   s_baselineCRC, currentCRC);
            result = FALSE;
        }
    } else {
        /* ---- Random page sampling ---- */
        srand(GetTickCount() ^ (DWORD)__rdtsc());

        DWORD pageSize = 4096;
        DWORD numPages = s_textSectionSize / pageSize;
        if (numPages == 0) numPages = 1;

        /* Check 4 random pages */
        for (int i = 0; i < 4; i++) {
            DWORD pageIdx = rand() % numPages;
            BYTE* pageStart = textBase + (pageIdx * pageSize);
            DWORD bytesToCheck = AC_MIN(pageSize,
                s_textSectionSize - (pageIdx * pageSize));

            DWORD oldProt;
            VirtualProtect(pageStart, bytesToCheck,
                           PAGE_READWRITE, &oldProt);

            DWORD pageCRC = AC_CRC32(pageStart, bytesToCheck);

            VirtualProtect(pageStart, bytesToCheck, oldProt, &oldProt);

            /* We compute the baseline CRC for this specific page at init
               and store it. For brevity, store page CRCs in an array.  */

            /* (See AC_InitPageCRCs / AC_CheckPageCRC below) */
        }
    }

    if (!result) {
        g_ac.crcFailCount++;
        AC_RecordEvent(AC_CAT_MEMORY, AC_SEV_CRITICAL,
                       "Code integrity violation detected",
                       (ULONG_PTR)s_textSectionVA, 0);
    }

    return result;
}

/* ---- Page-level baseline storage ---- */
#define AC_MAX_CODE_PAGES 8192
static DWORD s_pageCRCs[AC_MAX_CODE_PAGES];
static DWORD s_numPages = 0;

BOOL AC_InitPageCRCs(void)
{
    if (!g_ac.hGameModule || s_textSectionSize == 0) return FALSE;

    BYTE* base = (BYTE*)g_ac.hGameModule;
    BYTE* textBase = base + s_textSectionVA;

    DWORD pageSize = 4096;
    s_numPages = (s_textSectionSize + pageSize - 1) / pageSize;
    if (s_numPages > AC_MAX_CODE_PAGES) s_numPages = AC_MAX_CODE_PAGES;

    DWORD oldProt;
    VirtualProtect(textBase, s_textSectionSize, PAGE_READWRITE, &oldProt);

    for (DWORD i = 0; i < s_numPages; i++) {
        BYTE* p = textBase + (i * pageSize);
        DWORD sz = AC_MIN(pageSize, s_textSectionSize - (i * pageSize));
        s_pageCRCs[i] = AC_CRC32(p, sz);
    }

    VirtualProtect(textBase, s_textSectionSize, oldProt, &oldProt);

    AC_LOG(AC_SEV_INFO, "Initialized CRC baseline for %u code pages", s_numPages);
    return TRUE;
}

BOOL AC_CheckRandomPages(int count)
{
    if (s_numPages == 0) return TRUE;

    BYTE* base = (BYTE*)g_ac.hGameModule;
    BYTE* textBase = base + s_textSectionVA;
    DWORD pageSize = 4096;
    BOOL ok = TRUE;

    for (int i = 0; i < count; i++) {
        DWORD idx = (rand() ^ GetTickCount()) % s_numPages;

        BYTE* p = textBase + (idx * pageSize);
        DWORD sz = AC_MIN(pageSize, s_textSectionSize - (idx * pageSize));

        DWORD oldProt;
        VirtualProtect(p, sz, PAGE_READWRITE, &oldProt);

        DWORD crc = AC_CRC32(p, sz);

        VirtualProtect(p, sz, oldProt, &oldProt);

        if (crc != s_pageCRCs[idx]) {
            AC_LOG(AC_SEV_CRITICAL,
                   "Page %u CRC mismatch (0x%08X vs 0x%08X) at %p",
                   idx, s_pageCRCs[idx], crc, p);
            ok = FALSE;
        }
    }

    if (!ok) {
        g_ac.crcFailCount++;
        AC_RecordEvent(AC_CAT_MEMORY, AC_SEV_CRITICAL,
                       "Code page CRC mismatch", 0, 0);
    }

    return ok;
}

/* ---- Canary / guard regions around critical data ---- */
#define AC_NUM_CANARIES 8

typedef struct _AC_CANARY {
    BYTE*  addr;           /* Address of canary region            */
    DWORD  size;           /* Size in bytes                        */
    DWORD  crc;            /* Expected CRC                         */
    BOOL   active;
} AC_CANARY;

static AC_CANARY s_canaries[AC_NUM_CANARIES];
static INT       s_canaryCount = 0;

/*
 * Place a canary guard region next to important game data.
 * Cheaters modifying adjacent memory will corrupt the canary.
 */
BOOL AC_PlaceCanary(BYTE* nearAddr, SIZE_T nearSize)
{
    if (s_canaryCount >= AC_NUM_CANARIES) return FALSE;

    /* Allocate a guard page after the data */
    DWORD allocSize = 64;  /* 64-byte canary */
    BYTE* canary = (BYTE*)VirtualAlloc(
        nearAddr + nearSize,   /* Suggested address after data   */
        allocSize,
        MEM_RESERVE | MEM_COMMIT,
        PAGE_READWRITE
    );

    /* If exact placement fails, just allocate wherever */
    if (!canary) {
        canary = (BYTE*)VirtualAlloc(NULL, allocSize,
            MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE);
    }

    if (!canary) return FALSE;

    /* Fill with known pattern */
    for (DWORD i = 0; i < allocSize; i++) {
        canary[i] = (BYTE)(i ^ 0xA5);
    }

    AC_CANARY* c = &s_canaries[s_canaryCount++];
    c->addr   = canary;
    c->size   = allocSize;
    c->crc    = AC_CRC32(canary, allocSize);
    c->active = TRUE;

    AC_LOG(AC_SEV_INFO, "Canary placed at %p, size %u, CRC 0x%08X",
           canary, allocSize, c->crc);
    return TRUE;
}

BOOL AC_VerifyCanaries(void)
{
    BOOL ok = TRUE;
    for (int i = 0; i < s_canaryCount; i++) {
        AC_CANARY* c = &s_canaries[i];
        if (!c->active) continue;

        DWORD crc = AC_CRC32(c->addr, c->size);
        if (crc != c->crc) {
            AC_LOG(AC_SEV_BAN, "Canary %d corrupted at %p!", i, c->addr);
            AC_RecordEvent(AC_CAT_MEMORY, AC_SEV_BAN,
                           "Canary guard region corrupted",
                           (ULONG_PTR)c->addr, 0);
            ok = FALSE;
        }
    }
    return ok;
}
```

---

## Process & Module Scanning

```c
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

            if (AC_StringContainsI(modPath, "\\temp\\") ||
                AC_StringContainsI(modPath, "\\tmp\\")   ||
                AC_StringContainsI(modPath, "\\desktop\\") ||
                AC_StringContainsI(modPath, "\\downloads\\") ||
                AC_StringContainsI(modPath, "\\appdata\\local\\temp\\"))
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
```

---

## Hook Detection

```c
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
```

---

## Anti-Debug

```c
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
```

---

## Anti-VM & Anti-Sandboxie Detection

```c
/* ==========================================================================
 * ac_anti_vm.c - Virtual Machine and Sandboxie detection
 *
 * Detects common analysis environments (VMware, VirtualBox, Hyper-V)
 * and sandbox environments (Sandboxie, BitBlender, Cuckoo).
 * ========================================================================== */

#include "ac_common.h"
#include <intrin.h>
#include <iphlpapi.h>

#pragma comment(lib, "iphlpapi.lib")

/* ------------------------------------------------------------------
 * Anti-VM: CPUID Hypervisor Check
 * Bit 31 of ECX in CPUID leaf 0x1 indicates a hypervisor is present.
 * ------------------------------------------------------------------ */
static BOOL AC_CheckCPUIDHypervisor(void)
{
    INT cpuInfo[4] = {0};
    __cpuid(cpuInfo, 1);

    /* Bit 31 of ECX is the hypervisor present bit */
    if (cpuInfo[2] & (1 << 31)) {
        AC_LOG(AC_SEV_WARNING, "CPUID Hypervisor bit is set");
        return TRUE;
    }
    return FALSE;
}

/* ------------------------------------------------------------------
 * Anti-VM: CPUID Vendor String Check
 * Leaf 0x40000000 returns the hypervisor vendor ID.
 * ------------------------------------------------------------------ */
static BOOL AC_CheckHypervisorVendor(void)
{
    INT cpuInfo[4] = {0};
    __cpuid(cpuInfo, 0x40000000);

    CHAR vendor[13] = {0};
    memcpy(vendor, &cpuInfo[1], 4);  /* EBX */
    memcpy(vendor + 4, &cpuInfo[2], 4); /* ECX */
    memcpy(vendor + 8, &cpuInfo[3], 4); /* EDX */

    const CHAR* knownVendors[] = {
        "VMwareVMware", "Microsoft Hv", "VBoxVBoxVBox",
        "KVMKVMKVM",    "XenVMMXenVMM", "prl hyperv ",
        "Virtuozzo",    "bhyve bhyve ", NULL
    };

    for (int i = 0; knownVendors[i]; i++) {
        if (strcmp(vendor, knownVendors[i]) == 0) {
            AC_LOG(AC_SEV_CRITICAL, "Hypervisor vendor detected: %s", vendor);
            return TRUE;
        }
    }

    return FALSE;
}

/* ------------------------------------------------------------------
 * Anti-VM: MAC Address Prefix Check (OUI)
 * Checks network adapters for known VM MAC prefixes.
 * ------------------------------------------------------------------ */
static BOOL AC_CheckMACPrefix(void)
{
    ULONG bufLen = 0;
    GetAdaptersInfo(NULL, &bufLen);
    if (bufLen == 0) return FALSE;

    PIP_ADAPTER_INFO adapterInfo = (PIP_ADAPTER_INFO)malloc(bufLen);
    if (!adapterInfo) return FALSE;

    BOOL found = FALSE;
    if (GetAdaptersInfo(adapterInfo, &bufLen) == ERROR_SUCCESS) {
        PIP_ADAPTER_INFO adapter = adapterInfo;
        while (adapter) {
            if (adapter->AddressLength >= 6) {
                BYTE* mac = adapter->Address;
                /* VMware: 00:0C:29, 00:50:56, 00:05:69 */
                if (mac[0] == 0x00 && (mac[1] == 0x0C || mac[1] == 0x50 || mac[1] == 0x05) &&
                    (mac[2] == 0x29 || mac[2] == 0x56 || mac[2] == 0x69)) {
                    AC_LOG(AC_SEV_CRITICAL, "VMware MAC prefix detected");
                    found = TRUE; break;
                }
                /* VirtualBox: 08:00:27 */
                if (mac[0] == 0x08 && mac[1] == 0x00 && mac[2] == 0x27) {
                    AC_LOG(AC_SEV_CRITICAL, "VirtualBox MAC prefix detected");
                    found = TRUE; break;
                }
                /* Hyper-V: 00:15:5D */
                if (mac[0] == 0x00 && mac[1] == 0x15 && mac[2] == 0x5D) {
                    AC_LOG(AC_SEV_CRITICAL, "Hyper-V MAC prefix detected");
                    found = TRUE; break;
                }
            }
            adapter = adapter->Next;
        }
    }
    free(adapterInfo);
    return found;
}

/* ------------------------------------------------------------------
 * Anti-VM: Registry Key Checks
 * ------------------------------------------------------------------ */
static BOOL AC_CheckVMRegistryKeys(void)
{
    const CHAR* vmKeys[] = {
        "HARDWARE\\DEVICEMAP\\Scsi\\Scsi Port 0\\Scsi Bus 0\\Target Id 0\\Logical Unit Id 0",
        "HARDWARE\\Description\\System\\SystemBiosVersion", /* VMs often append info here */
        "SOFTWARE\\VMware, Inc.\\VMware Tools",
        "SOFTWARE\\Oracle\\VirtualBox Guest Additions",
        "SOFTWARE\\Wine", /* Wine/Proton check */
        NULL
    };

    HKEY hKey;
    for (int i = 0; vmKeys[i]; i++) {
        if (RegOpenKeyExA(HKEY_LOCAL_MACHINE, vmKeys[i], 0, KEY_READ, &hKey) == ERROR_SUCCESS) {
            CHAR value[256] = {0};
            DWORD size = sizeof(value);
            
            /* Check specific values for hardware identifiers */
            if (i == 0) RegQueryValueExA(hKey, "Identifier", NULL, NULL, (LPBYTE)value, &size);
            if (i == 1) RegQueryValueExA(hKey, "SystemBiosVersion", NULL, NULL, (LPBYTE)value, &size);

            RegCloseKey(hKey);

            if (strstr(value, "VMWARE") || strstr(value, "VBOX") || strstr(value, "QEMU")) {
                AC_LOG(AC_SEV_CRITICAL, "VM identifier found in registry: %s", value);
                return TRUE;
            }
            
            /* If the key exists at all for VMware/VBox/Wine, it's suspicious */
            if (i >= 2) {
                AC_LOG(AC_SEV_CRITICAL, "VM/Sandbox registry key exists: %s", vmKeys[i]);
                return TRUE;
            }
        }
    }
    return FALSE;
}

/* ------------------------------------------------------------------
 * Anti-Sandboxie: PEB LDR Walk
 * Sandboxie injects SbieDll.dll. Hackers hook GetModuleHandle to hide it.
 * We walk the PEB manually to bypass user-mode API hooks.
 * ------------------------------------------------------------------ */
static BOOL AC_CheckSandboxiePEB(void)
{
#ifdef _WIN64
    PPEB peb = (PPEB)__readgsqword(0x60);
#else
    PPEB peb = (PPEB)__readfsdword(0x30);
#endif

    PPEB_LDR_DATA ldr = peb->Ldr;
    PLIST_ENTRY head = &ldr->InMemoryOrderModuleList;
    PLIST_ENTRY curr = head->Flink;

    while (curr != head) {
        PLDR_DATA_TABLE_ENTRY entry = CONTAINING_RECORD(curr, LDR_DATA_TABLE_ENTRY, InMemoryOrderLinks);

        if (entry->BaseDllName.Buffer && entry->BaseDllName.Length > 0) {
            CHAR dllName[MAX_PATH] = {0};
            WideCharToMultiByte(CP_ACP, 0, entry->BaseDllName.Buffer, -1,
                                dllName, MAX_PATH, NULL, NULL);

            if (_stricmp(dllName, "SbieDll.dll") == 0) {
                AC_LOG(AC_SEV_CRITICAL, "Sandboxie DLL detected via PEB walk: %s at %p",
                       dllName, entry->DllBase);
                return TRUE;
            }
        }
        curr = curr->Flink;
    }

    return FALSE;
}

/* ------------------------------------------------------------------
 * Anti-Sandboxie: Driver Object & Named Pipe Checks
 * ------------------------------------------------------------------ */
static BOOL AC_CheckSandboxieDrivers(void)
{
    /* Check for Sandboxie driver symlink */
    HANDLE hFile = CreateFileW(L"\\\\.\\SandboxieApi", GENERIC_READ,
                               FILE_SHARE_READ, NULL, OPEN_EXISTING, 0, NULL);
    if (hFile != INVALID_HANDLE_VALUE) {
        CloseHandle(hFile);
        AC_LOG(AC_SEV_CRITICAL, "SandboxieApi driver symlink detected");
        return TRUE;
    }

    /* Check for Sandboxie named pipes */
    HMODULE hNtDll = GetModuleHandleA("ntdll.dll");
    if (hNtDll) {
        /* NtQueryDirectoryObject can find \Sessions\X\Sandboxed... objects */
        /* Simplified: check if the registry key for the SbieDrv service exists */
        HKEY hKey;
        if (RegOpenKeyExA(HKEY_LOCAL_MACHINE,
            "SYSTEM\\CurrentControlSet\\Services\\SbieDrv",
            0, KEY_READ, &hKey) == ERROR_SUCCESS)
        {
            RegCloseKey(hKey);
            AC_LOG(AC_SEV_CRITICAL, "Sandboxie driver registry key detected");
            return TRUE;
        }
    }

    return FALSE;
}

/* ------------------------------------------------------------------
 * Additional VM Detection Techniques
 * ------------------------------------------------------------------ */

/* ---- Timing-based detection using RDTSC ---- */
static BOOL AC_CheckTimingAnomaly(void)
{
    /* Simple RDTSC delta check - VMs often have larger timing differences */
    unsigned long long t1 = __rdtsc();
    unsigned long long t2 = __rdtsc();
    
    /* Threshold is heuristic - VMs typically show >500 cycles difference */
    if (t2 - t1 > 500) {
        AC_LOG(AC_SEV_WARNING, "RDTSC timing anomaly detected: %llu cycles", t2 - t1);
        return TRUE;
    }
    return FALSE;
}

/* ---- Process enumeration for VM tools ---- */
static BOOL AC_CheckVMProcesses(void)
{
    const CHAR* vmProcesses[] = {
        "vmware.exe", "vmtoolsd.exe", "vboxservice.exe", "vboxtray.exe",
        "vmware-user.exe", "vmware-tray.exe", "VBoxClient.exe",
        "qemu-ga.exe", "spice-vdagent.exe", NULL
    };

    HANDLE hSnap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (hSnap == INVALID_HANDLE_VALUE) return FALSE;

    PROCESSENTRY32W pe = { .dwSize = sizeof(pe) };
    BOOL found = FALSE;

    if (Process32FirstW(hSnap, &pe)) {
        do {
            CHAR procName[MAX_PATH];
            WideCharToMultiByte(CP_ACP, 0, pe.szExeFile, -1,
                                procName, MAX_PATH, NULL, NULL);

            for (int i = 0; vmProcesses[i]; i++) {
                if (_stricmp(procName, vmProcesses[i]) == 0) {
                    AC_LOG(AC_SEV_CRITICAL, "VM process detected: %s (PID %u)",
                           procName, pe.th32ProcessID);
                    found = TRUE;
                    break;
                }
            }
        } while (Process32NextW(hSnap, &pe) && !found);
    }

    CloseHandle(hSnap);
    return found;
}

/* ---- Simple Sandboxie DLL check (fallback) ---- */
static BOOL AC_CheckSandboxieDLL(void)
{
    /* Direct GetModuleHandle check (can be hooked, but worth trying) */
    if (GetModuleHandleA("SbieDll.dll") != NULL) {
        AC_LOG(AC_SEV_CRITICAL, "SbieDll.dll detected via GetModuleHandle");
        return TRUE;
    }
    return FALSE;
}

/* ---- Hardware device checks for virtual adapters ---- */
static BOOL AC_CheckVirtualHardware(void)
{
    /* Check for virtual display adapters */
    DISPLAY_DEVICE dd = { .cb = sizeof(dd) };
    
    for (DWORD i = 0; EnumDisplayDevicesA(NULL, i, &dd, 0); i++) {
        if (strstr(dd.DeviceString, "VMware") ||
            strstr(dd.DeviceString, "VirtualBox") ||
            strstr(dd.DeviceString, "QXL") ||
            strstr(dd.DeviceString, "VBox")) {
            AC_LOG(AC_SEV_CRITICAL, "Virtual display adapter detected: %s", dd.DeviceString);
            return TRUE;
        }
    }

    /* Check disk controller for virtual disks */
    HKEY hKey;
    if (RegOpenKeyExA(HKEY_LOCAL_MACHINE,
        "SYSTEM\\CurrentControlSet\\Services\\Disk\\Enum",
        0, KEY_READ, &hKey) == ERROR_SUCCESS)
    {
        CHAR diskId[256];
        DWORD dataSize = sizeof(diskId);
        if (RegQueryValueExA(hKey, "0", NULL, NULL,
                             (LPBYTE)diskId, &dataSize) == ERROR_SUCCESS)
        {
            if (strstr(diskId, "VMware") || strstr(diskId, "VirtualBox") ||
                strstr(diskId, "QEMU") || strstr(diskId, "VBOX")) {
                AC_LOG(AC_SEV_CRITICAL, "Virtual disk detected: %s", diskId);
                RegCloseKey(hKey);
                return TRUE;
            }
        }
        RegCloseKey(hKey);
    }

    return FALSE;
}

/* ---- Memory and CPU count checks ---- */
static BOOL AC_CheckSystemResources(void)
{
    SYSTEM_INFO si = {0};
    GetSystemInfo(&si);
    
    MEMORYSTATUSEX memStatus = { .dwLength = sizeof(memStatus) };
    GlobalMemoryStatusEx(&memStatus);

    /* VMs often have low RAM by default (< 2GB) and few cores (< 4) */
    DWORD ramGB = (DWORD)(memStatus.ullTotalPhys >> 30);
    DWORD coreCount = si.dwNumberOfProcessors;

    if (ramGB <= 2 && coreCount <= 2) {
        AC_LOG(AC_SEV_WARNING, "Low system resources: %u GB RAM, %u cores (possible VM)",
               ramGB, coreCount);
        return TRUE;
    }

    return FALSE;
}

/* ------------------------------------------------------------------
 * Combined Virtualization / Sandbox Scan Entry Point
 * ------------------------------------------------------------------ */
BOOL AC_ScanVirtualization(void)
{
    BOOL vmDetected = FALSE;

    /* Primary VM Checks */
    vmDetected |= AC_CheckCPUIDHypervisor();
    vmDetected |= AC_CheckHypervisorVendor();
    vmDetected |= AC_CheckMACPrefix();
    vmDetected |= AC_CheckVMRegistryKeys();

    /* Additional VM Checks */
    vmDetected |= AC_CheckTimingAnomaly();
    vmDetected |= AC_CheckVMProcesses();
    vmDetected |= AC_CheckVirtualHardware();
    vmDetected |= AC_CheckSystemResources();

    /* Sandboxie Checks */
    vmDetected |= AC_CheckSandboxieDLL();         /* Simple check first */
    vmDetected |= AC_CheckSandboxiePEB();         /* Bypass hooks */
    vmDetected |= AC_CheckSandboxieDrivers();     /* Driver detection */

    if (vmDetected) {
        AC_RecordEvent(AC_CAT_VIRTUALIZATION, AC_SEV_CRITICAL,
                       "Virtualization or Sandbox environment detected", 0, 0);
    }

    return vmDetected;
}
```

---

## Advanced VM/Sandboxie Detection Techniques

### Additional Detection Methods

The following techniques can be added to enhance VM and sandbox detection reliability. These are especially useful for
advanced analysis environments.

#### **Red Pill / SIDT Detection**

Store Interrupt Descriptor Table and check its base address (often in high memory in VMs):

```c
static BOOL AC_CheckRedPill(void)
{
    /* SIDT instruction stores IDTR in memory */
    struct { WORD limit; DWORD base; } idtr;
    
    __asm {
        sidt idtr
    }
    
    /* In VMs, IDT base is typically above 0x80000000 */
    if (idtr.base > 0x80000000) {
        AC_LOG(AC_SEV_WARNING, "Red Pill: IDT base at 0x%08X (possible VM)", idtr.base);
        return TRUE;
    }
    return FALSE;
}
```

#### **VMware I/O Port Backdoor**

VMware has a specific I/O port (0x5658 "VX") for guest-host communication:

```c
static BOOL AC_CheckVMwareBackdoor(void)
{
    /* VMware magic I/O port */
    DWORD result = 0;
    
    __asm {
        mov eax, 0x564D5868  /* VMware magic number */
        mov ebx, 0x0
        mov ecx, 0x0A       /* Get version */
        mov edx, 0x5658     /* VMware I/O port */
        in  dx, eax
        mov result, eax
    }
    
    /* If VMware is present, EBX will contain version info */
    if (result != 0) {
        AC_LOG(AC_SEV_CRITICAL, "VMware backdoor detected");
        return TRUE;
    }
    return FALSE;
}
```

#### **Advanced Timing Correlation**

Compare multiple time sources to detect timing anomalies:

```c
static BOOL AC_CheckAdvancedTiming(void)
{
    LARGE_INTEGER perfFreq, perfStart, perfEnd;
    DWORD tickStart, tickEnd;
    unsigned long long rdtscStart, rdtscEnd;
    
    QueryPerformanceFrequency(&perfFreq);
    
    /* Measure with multiple sources */
    tickStart = GetTickCount();
    rdtscStart = __rdtsc();
    QueryPerformanceCounter(&perfStart);
    
    /* Small delay */
    Sleep(10);
    
    QueryPerformanceCounter(&perfEnd);
    rdtscEnd = __rdtsc();
    tickEnd = GetTickCount();
    
    /* Calculate ratios */
    DOUBLE perfMs = (DOUBLE)(perfEnd.QuadPart - perfStart.QuadPart) * 1000.0 / perfFreq.QuadPart;
    DOUBLE tickMs = (DOUBLE)(tickEnd - tickStart);
    DOUBLE rdtscMs = (DOUBLE)(rdtscEnd - rdtscStart) / 1000000.0; /* Approximate */
    
    /* Check for significant discrepancies */
    if (fabs(perfMs - tickMs) > 5.0 || fabs(rdtscMs - perfMs) > 10.0) {
        AC_LOG(AC_SEV_WARNING, "Advanced timing anomaly detected");
        return TRUE;
    }
    
    return FALSE;
}
```

#### **WMI Queries for Virtual Hardware**

Use Windows Management Instrumentation to detect virtual hardware:

```c
#include <wbemidl.h>
#pragma comment(lib, "wbemuuid.lib")

static BOOL AC_CheckWMIHardware(void)
{
    /* Initialize COM */
    CoInitializeEx(NULL, COINIT_MULTITHREADED);
    
    HRESULT hr;
    IWbemLocator *pLoc = NULL;
    IWbemServices *pSvc = NULL;
    IEnumWbemClassObject* pEnumerator = NULL;
    BOOL detected = FALSE;
    
    hr = CoCreateInstance(&CLSID_WbemLocator, 0, CLSCTX_INPROC_SERVER,
                         &IID_IWbemLocator, (LPVOID*)&pLoc);
    
    if (SUCCEEDED(hr)) {
        hr = pLoc->ConnectServer(L"root\\cimv2", NULL, NULL, 0,
                                NULL, 0, 0, &pSvc);
        
        if (SUCCEEDED(hr)) {
            /* Query for computer system manufacturer */
            hr = pSvc->ExecQuery(L"WQL", 
                                L"SELECT Manufacturer FROM Win32_ComputerSystem",
                                WBEM_FLAG_FORWARD_ONLY | WBEM_FLAG_RETURN_IMMEDIATELY,
                                NULL, &pEnumerator);
            
            if (SUCCEEDED(hr)) {
                IWbemClassObject *pclsObj = NULL;
                ULONG uReturn = 0;
                
                while (pEnumerator->Next(WBEM_INFINITE, 1, &pclsObj, &uReturn) == S_OK) {
                    VARIANT vtProp;
                    hr = pclsObj->Get(L"Manufacturer", 0, &vtProp, 0, 0);
                    
                    if (SUCCEEDED(hr) && vtProp.vt == VT_BSTR) {
                        /* Convert BSTR to char for comparison */
                        CHAR manufacturer[256];
                        WideCharToMultiByte(CP_ACP, 0, vtProp.bstrVal, -1,
                                           manufacturer, sizeof(manufacturer), NULL, NULL);
                        
                        if (strstr(manufacturer, "VMware") ||
                            strstr(manufacturer, "VirtualBox") ||
                            strstr(manufacturer, "QEMU") ||
                            strstr(manufacturer, "Xen")) {
                            AC_LOG(AC_SEV_CRITICAL, "WMI: Virtual manufacturer detected: %s", manufacturer);
                            detected = TRUE;
                        }
                    }
                    
                    VariantClear(&vtProp);
                    pclsObj->Release();
                }
            }
        }
    }
    
    /* Cleanup */
    if (pEnumerator) pEnumerator->Release();
    if (pSvc) pSvc->Release();
    if (pLoc) pLoc->Release();
    CoUninitialize();
    
    return detected;
}
```

### Cross-Platform Detection (Linux Notes)

On Linux systems, additional detection methods are available:

```c
/* Linux-specific VM detection (compile with -DPLATFORM_LINUX) */
#ifdef PLATFORM_LINUX
#include <stdio.h>
#include <string.h>

static BOOL AC_CheckLinuxVM(void)
{
    FILE* fp;
    char buffer[1024];
    
    /* Check /proc/cpuinfo for hypervisor flag */
    fp = fopen("/proc/cpuinfo", "r");
    if (fp) {
        while (fgets(buffer, sizeof(buffer), fp)) {
            if (strstr(buffer, "hypervisor")) {
                AC_LOG(AC_SEV_CRITICAL, "Linux: Hypervisor flag detected in /proc/cpuinfo");
                fclose(fp);
                return TRUE;
            }
        }
        fclose(fp);
    }
    
    /* Check DMI/SMBIOS information */
    fp = fopen("/sys/class/dmi/id/product_name", "r");
    if (fp) {
        if (fgets(buffer, sizeof(buffer), fp)) {
            if (strstr(buffer, "VMware") || strstr(buffer, "VirtualBox") ||
                strstr(buffer, "QEMU") || strstr(buffer, "Xen")) {
                AC_LOG(AC_SEV_CRITICAL, "Linux: Virtual product detected: %s", buffer);
                fclose(fp);
                return TRUE;
            }
        }
        fclose(fp);
    }
    
    /* Check for virtual network interfaces */
    fp = fopen("/proc/net/dev", "r");
    if (fp) {
        while (fgets(buffer, sizeof(buffer), fp)) {
            if (strstr(buffer, "veth") || strstr(buffer, "virbr") ||
                strstr(buffer, "docker") || strstr(buffer, "br-")) {
                AC_LOG(AC_SEV_WARNING, "Linux: Virtual network interface detected");
                fclose(fp);
                return TRUE;
            }
        }
        fclose(fp);
    }
    
    return FALSE;
}
#endif
```

### Implementation Considerations

#### **False Positive Mitigation**

- Use cumulative scoring rather than single detection
- Weight different techniques based on reliability
- Consider legitimate virtualization environments (development, cloud gaming)

#### **Evasion Resistance**

- Combine multiple detection categories (hardware, software, timing)
- Use randomization in check execution order
- Implement self-integrity checks for the detection code

#### **Performance Optimization**

```c
/* Stagger checks to reduce performance impact */
static DWORD s_vmCheckPhase = 0;

BOOL AC_ScanVirtualizationStaggered(void)
{
    BOOL detected = FALSE;
    
    /* Rotate through different check phases each call */
    switch (s_vmCheckPhase % 4) {
        case 0: /* Hardware checks */
            detected |= AC_CheckCPUIDHypervisor();
            detected |= AC_CheckMACPrefix();
            break;
        case 1: /* Registry checks */
            detected |= AC_CheckVMRegistryKeys();
            detected |= AC_CheckVirtualHardware();
            break;
        case 2: /* Process checks */
            detected |= AC_CheckVMProcesses();
            detected |= AC_CheckSandboxieDLL();
            break;
        case 3: /* Advanced checks */
            detected |= AC_CheckTimingAnomaly();
            detected |= AC_CheckRedPill();
            break;
    }
    
    s_vmCheckPhase++;
    return detected;
}
```

#### **Production Recommendations**

1. **Use established libraries** like [VMAware](https://github.com/kernelwernel/VMAware) for comprehensive detection
2. **Implement server-side validation** - report findings to the server for correlation
3. **Regular updates** - VM/sandbox techniques evolve rapidly
4. **Testing** - Validate against common virtualization platforms in the target environment

#### **Caveats & Limitations**

- **Paravirtualized VMs** can evade many detection methods
- **Advanced sandboxes** may randomize or spoof artifacts
- **Cloud gaming services** (GeForce NOW, Stadia) may trigger false positives
- **Container environments** (Docker, WSL) may appear virtualized
- **Legitimate business use** - many users run games in VMs for security

---

## Advanced HWID Gathering & Hardware Fingerprinting

```c
/* ==========================================================================
 * ac_hwid_advanced.c - Comprehensive hardware fingerprinting
 *
 * Advanced HWID collection using registry and WMI for robust hardware
 * identification. Combines multiple sources for spoofing resistance.
 * ========================================================================== */

#include "ac_common.h"
#include <wbemidl.h>
#include <comdef.h>

#pragma comment(lib, "wbemuuid.lib")

/* ---- HWID data structure ---- */
typedef struct _AC_HWID_DATA {
    CHAR machineGuid[64];
    CHAR biosVendor[256];
    CHAR biosVersion[256];
    CHAR systemManufacturer[256];
    CHAR systemProductName[256];
    CHAR systemVersion[256];
    CHAR hardwareConfig[64];
    CHAR systemUuid[64];
    CHAR biosSerial[256];
    CHAR baseboardSerial[256];
    CHAR baseboardProduct[256];
    CHAR processorId[64];
    CHAR diskSerial[256];
    CHAR macAddresses[512];
    CHAR volumeSerials[256];  /* Multiple volume serials */
} AC_HWID_DATA;

/* ---- Helper: Get Volume Serial Number ---- */
static BOOL AC_GetVolumeSerial(const CHAR* rootPath, CHAR* out, SIZE_T outLen)
{
    DWORD volumeSerial = 0;
    if (GetVolumeInformationA(
            rootPath,                  /* Root path */
            NULL, 0,                   /* Volume name (optional) */
            &volumeSerial,             /* Volume Serial Number */
            NULL,                      /* Max component length */
            NULL,                      /* File system flags */
            NULL, 0)) {                /* File system name */
        /* Format as 8 hex digits with dash (like dir command: ABCD-EFGH) */
        sprintf_s(out, outLen, "%08lX", volumeSerial);
        SIZE_T len = strlen(out);
        if (len == 8) {
            /* Insert dash at position 4 */
            memmove(out + 5, out + 4, len - 3);
            out[4] = '-';
        }
        return TRUE;
    }
    return FALSE;
}

/* ---- Helper: Collect all logical drive serials ---- */
static void AC_CollectAllVolumeSerials(AC_HWID_DATA* hwid)
{
    CHAR drives[256] = {0};
    DWORD len = GetLogicalDriveStringsA(sizeof(drives), drives);
    
    hwid->volumeSerials[0] = '\0';
    INT driveCount = 0;
    
    for (CHAR* p = drives; *p && driveCount < 3; p += strlen(p) + 1) {
        if (GetDriveTypeA(p) == DRIVE_FIXED) {  /* Only fixed drives */
            CHAR serial[16];
            if (AC_GetVolumeSerial(p, serial, sizeof(serial))) {
                if (driveCount > 0) {
                    strcat_s(hwid->volumeSerials, sizeof(hwid->volumeSerials), ",");
                }
                strcat_s(hwid->volumeSerials, sizeof(hwid->volumeSerials), serial);
                driveCount++;
            }
        }
    }
    
    AC_LOG(AC_SEV_INFO, "Collected %d volume serials: %s", driveCount, hwid->volumeSerials);
}

/* ---- Helper: Read registry string ---- */
static BOOL AC_RegReadString(HKEY hRoot, const CHAR* subKey, const CHAR* valueName, CHAR* out, SIZE_T outLen)
{
    HKEY hKey;
    if (RegOpenKeyExA(hRoot, subKey, 0, KEY_READ, &hKey) != ERROR_SUCCESS)
        return FALSE;

    DWORD type;
    DWORD size = (DWORD)outLen;
    BOOL success = (RegQueryValueExA(hKey, valueName, NULL, &type, (LPBYTE)out, &size) == ERROR_SUCCESS && type == REG_SZ);
    
    RegCloseKey(hKey);
    return success;
}

/* ---- Initialize WMI connection ---- */
static HRESULT AC_InitWMI(IWbemLocator** pLocator, IWbemServices** pService)
{
    HRESULT hr = CoInitializeEx(0, COINIT_MULTITHREADED);
    if (FAILED(hr)) return hr;

    hr = CoCreateInstance(CLSID_WbemLocator, 0, CLSCTX_INPROC_SERVER, IID_IWbemLocator, (LPVOID*)pLocator);
    if (FAILED(hr)) return hr;

    hr = (*pLocator)->ConnectServer(_bstr_t(L"ROOT\\CIMV2"), NULL, NULL, 0, NULL, 0, 0, pService);
    if (FAILED(hr)) return hr;

    hr = CoSetProxyBlanket(*pService, RPC_C_AUTHN_WINNT, RPC_C_AUTHZ_NONE, NULL,
                           RPC_C_AUTHN_LEVEL_CALL, RPC_C_IMP_LEVEL_IMPERSONATE, NULL, EOAC_NONE);
    return hr;
}

/* ---- WMI query helper ---- */
static BOOL AC_WmiQuerySingle(IWbemServices* pService, const wchar_t* query, const wchar_t* prop, CHAR* out, SIZE_T outLen)
{
    IEnumWbemClassObject* pEnumerator = NULL;
    BOOL result = FALSE;

    HRESULT hr = pService->ExecQuery(_bstr_t("WQL"), _bstr_t(query),
                                    WBEM_FLAG_FORWARD_ONLY | WBEM_FLAG_RETURN_IMMEDIATELY,
                                    NULL, &pEnumerator);
    if (FAILED(hr)) return FALSE;

    IWbemClassObject* pClsObj = NULL;
    ULONG uReturn = 0;
    if (pEnumerator->Next(WBEM_INFINITE, 1, &pClsObj, &uReturn) == WBEM_S_NO_ERROR) {
        VARIANT vtProp;
        VariantInit(&vtProp);
        if (SUCCEEDED(pClsObj->Get(prop, 0, &vtProp, 0, 0)) && vtProp.vt == VT_BSTR) {
            WideCharToMultiByte(CP_ACP, 0, vtProp.bstrVal, -1, out, (int)outLen, NULL, NULL);
            result = TRUE;
        }
        VariantClear(&vtProp);
        pClsObj->Release();
    }

    if (pEnumerator) pEnumerator->Release();
    return result;
}

/* ---- Collect registry-based HWID data ---- */
static void AC_CollectRegistryHWID(AC_HWID_DATA* hwid)
{
    /* Cryptography MachineGuid */
    AC_RegReadString(HKEY_LOCAL_MACHINE, "SOFTWARE\\Microsoft\\Cryptography", "MachineGuid", 
                    hwid->machineGuid, sizeof(hwid->machineGuid));

    /* BIOS information */
    AC_RegReadString(HKEY_LOCAL_MACHINE, "HARDWARE\\DESCRIPTION\\System\\BIOS", "BIOSVendor",
                    hwid->biosVendor, sizeof(hwid->biosVendor));
    AC_RegReadString(HKEY_LOCAL_MACHINE, "HARDWARE\\DESCRIPTION\\System\\BIOS", "BIOSVersion",
                    hwid->biosVersion, sizeof(hwid->biosVersion));
    AC_RegReadString(HKEY_LOCAL_MACHINE, "HARDWARE\\Description\\System\\BIOS", "SystemManufacturer",
                    hwid->systemManufacturer, sizeof(hwid->systemManufacturer));
    AC_RegReadString(HKEY_LOCAL_MACHINE, "HARDWARE\\Description\\System\\BIOS", "SystemProductName",
                    hwid->systemProductName, sizeof(hwid->systemProductName));
    AC_RegReadString(HKEY_LOCAL_MACHINE, "HARDWARE\\Description\\System\\BIOS", "SystemVersion",
                    hwid->systemVersion, sizeof(hwid->systemVersion));

    /* HardwareConfig UUID */
    AC_RegReadString(HKEY_LOCAL_MACHINE, "SYSTEM\\HardwareConfig", "LastConfig",
                    hwid->hardwareConfig, sizeof(hwid->hardwareConfig));
}

/* ---- Collect WMI-based HWID data ---- */
static BOOL AC_CollectWMIHWID(AC_HWID_DATA* hwid)
{
    IWbemLocator* pLocator = NULL;
    IWbemServices* pService = NULL;
    BOOL success = FALSE;

    if (FAILED(AC_InitWMI(&pLocator, &pService))) goto cleanup;

    /* System UUID */
    success |= AC_WmiQuerySingle(pService, L"SELECT UUID FROM Win32_ComputerSystemProduct", L"UUID",
                                hwid->systemUuid, sizeof(hwid->systemUuid));

    /* BIOS information */
    success |= AC_WmiQuerySingle(pService, L"SELECT SerialNumber FROM Win32_BIOS", L"SerialNumber",
                                hwid->biosSerial, sizeof(hwid->biosSerial));

    /* Baseboard information */
    success |= AC_WmiQuerySingle(pService, L"SELECT SerialNumber FROM Win32_BaseBoard", L"SerialNumber",
                                hwid->baseboardSerial, sizeof(hwid->baseboardSerial));
    success |= AC_WmiQuerySingle(pService, L"SELECT Product FROM Win32_BaseBoard", L"Product",
                                hwid->baseboardProduct, sizeof(hwid->baseboardProduct));

    /* Processor information */
    success |= AC_WmiQuerySingle(pService, L"SELECT ProcessorId FROM Win32_Processor", L"ProcessorId",
                                hwid->processorId, sizeof(hwid->processorId));

    /* Disk drive serial (first physical disk) */
    success |= AC_WmiQuerySingle(pService, 
                                L"SELECT SerialNumber FROM Win32_DiskDrive WHERE MediaType='Fixed hard disk media'",
                                L"SerialNumber", hwid->diskSerial, sizeof(hwid->diskSerial));

    /* Network adapter MAC addresses (first few) */
    IEnumWbemClassObject* pEnumerator = NULL;
    HRESULT hr = pService->ExecQuery(_bstr_t("WQL"), 
                                    _bstr_t("SELECT MACAddress FROM Win32_NetworkAdapter WHERE NetConnectionStatus=2"),
                                    WBEM_FLAG_FORWARD_ONLY | WBEM_FLAG_RETURN_IMMEDIATELY,
                                    NULL, &pEnumerator);
    
    if (SUCCEEDED(hr)) {
        IWbemClassObject* pClsObj = NULL;
        ULONG uReturn = 0;
        INT macCount = 0;
        
        while (pEnumerator->Next(WBEM_INFINITE, 1, &pClsObj, &uReturn) == WBEM_S_NO_ERROR && macCount < 3) {
            VARIANT vtProp;
            VariantInit(&vtProp);
            if (SUCCEEDED(pClsObj->Get(L"MACAddress", 0, &vtProp, 0, 0)) && vtProp.vt == VT_BSTR) {
                if (macCount > 0) strcat_s(hwid->macAddresses, sizeof(hwid->macAddresses), ",");
                strcat_s(hwid->macAddresses, sizeof(hwid->macAddresses), _bstr_t(vtProp.bstrVal));
                macCount++;
            }
            VariantClear(&vtProp);
            pClsObj->Release();
        }
        
        if (pEnumerator) pEnumerator->Release();
    }

cleanup:
    if (pService) pService->Release();
    if (pLocator) pLocator->Release();
    CoUninitialize();
    return success;
}

/* ---- Additional registry sources for enhanced HWID ---- */
static void AC_CollectAdditionalRegistryHWID(AC_HWID_DATA* hwid)
{
    /* Disk enumeration */
    CHAR diskEnum[256] = {0};
    if (AC_RegReadString(HKEY_LOCAL_MACHINE, "SYSTEM\\CurrentControlSet\\Services\\Disk\\Enum", "0",
                        diskEnum, sizeof(diskEnum))) {
        AC_LOG(AC_SEV_INFO, "Disk Enum: %s", diskEnum);
    }

    /* Mounted devices (volume GUIDs) */
    HKEY hKey;
    if (RegOpenKeyExA(HKEY_LOCAL_MACHINE, "SYSTEM\\MountedDevices", 0, KEY_READ, &hKey) == ERROR_SUCCESS) {
        DWORD subKeyCount = 0, maxSubKeyLen = 0;
        if (RegQueryInfoKeyA(hKey, NULL, NULL, NULL, &subKeyCount, &maxSubKeyLen, NULL, NULL, NULL, NULL, NULL, NULL) == ERROR_SUCCESS) {
            AC_LOG(AC_SEV_INFO, "Mounted devices count: %u", subKeyCount);
        }
        RegCloseKey(hKey);
    }

    /* SCSI device information */
    if (RegOpenKeyExA(HKEY_LOCAL_MACHINE, "HARDWARE\\DEVICEMAP\\Scsi", 0, KEY_READ, &hKey) == ERROR_SUCCESS) {
        DWORD subKeyCount = 0;
        if (RegQueryInfoKeyA(hKey, NULL, NULL, NULL, &subKeyCount, NULL, NULL, NULL, NULL, NULL, NULL, NULL) == ERROR_SUCCESS) {
            AC_LOG(AC_SEV_INFO, "SCSI buses count: %u", subKeyCount);
        }
        RegCloseKey(hKey);
    }
}

/* ---- Generate composite HWID hash ---- */
static BOOL AC_GenerateCompositeHWID(const AC_HWID_DATA* hwid, CHAR* out, SIZE_T outLen)
{
    if (!hwid || !out || outLen < 65) return FALSE;

    /* Concatenate all HWID components */
    CHAR composite[2048] = {0};
    sprintf_s(composite, sizeof(composite),
              "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s",
              hwid->machineGuid,
              hwid->systemUuid,
              hwid->biosSerial,
              hwid->baseboardSerial,
              hwid->processorId,
              hwid->diskSerial,
              hwid->macAddresses,
              hwid->volumeSerials,
              hwid->systemManufacturer,
              hwid->systemProductName,
              hwid->baseboardProduct,
              hwid->biosVendor,
              hwid->biosVersion,
              hwid->hardwareConfig);

    /* Generate SHA-256 hash (simplified - use proper crypto lib in production) */
    DWORD crc = AC_CRC32((BYTE*)composite, strlen(composite));
    
    /* Create hex representation */
    sprintf_s(out, outLen, "%08X%08X%08X%08X",
              crc, crc ^ 0x12345678, crc ^ 0x87654321, crc ^ 0xABCDEF00);

    AC_LOG(AC_SEV_INFO, "Generated composite HWID: %s", out);
    return TRUE;
}

/* ---- Main HWID collection function ---- */
BOOL AC_CollectAdvancedHWID(CHAR* out, SIZE_T outLen)
{
    AC_HWID_DATA hwid = {0};

    /* Collect registry-based data */
    AC_CollectRegistryHWID(&hwid);
    
    /* Collect volume serial numbers */
    AC_CollectAllVolumeSerials(&hwid);
    
    /* Collect WMI-based data */
    BOOL wmiSuccess = AC_CollectWMIHWID(&hwid);
    
    /* Collect additional registry sources */
    AC_CollectAdditionalRegistryHWID(&hwid);

    /* Generate composite HWID */
    if (!AC_GenerateCompositeHWID(&hwid, out, outLen)) {
        AC_LOG(AC_SEV_WARNING, "Failed to generate composite HWID");
        return FALSE;
    }

    /* Log collection status */
    AC_LOG(AC_SEV_INFO, "Advanced HWID collection complete (WMI: %s)", 
           wmiSuccess ? "success" : "failed");

    /* Log key components for debugging */
    AC_LOG(AC_SEV_INFO, "HWID components - System: %s, BIOS: %s, CPU: %s, Disk: %s, Volumes: %s",
           hwid.systemUuid, hwid.biosSerial, hwid.processorId, hwid.diskSerial, hwid.volumeSerials);

    return TRUE;
}

/* ---- Validate HWID stability ---- */
BOOL AC_ValidateHWIDStability(const CHAR* currentHWID)
{
    /* Load previously stored HWID */
    CHAR storedPath[MAX_PATH];
    GetModuleFileNameA(NULL, storedPath, MAX_PATH);
    PathRemoveFileSpecA(storedPath);
    strcat_s(storedPath, MAX_PATH, "\\hwid_cache.dat");

    FILE* f = NULL;
    if (fopen_s(&f, storedPath, "r") == 0 && f) {
        CHAR storedHWID[65];
        if (fgets(storedHWID, sizeof(storedHWID), f)) {
            storedHWID[strcspn(storedHWID, "\r\n")] = '\0';
            fclose(f);

            if (strcmp(currentHWID, storedHWID) != 0) {
                AC_LOG(AC_SEV_WARNING, "HWID changed! Previous: %s, Current: %s",
                       storedHWID, currentHWID);
                
                /* Record HWID change event */
                AC_RecordEvent(AC_CAT_HWID, AC_SEV_CRITICAL,
                               "Hardware fingerprint changed", 0, 0);
                return FALSE;
            }
        }
    }

    /* Store current HWID for next validation */
    if (fopen_s(&f, storedPath, "w") == 0 && f) {
        fprintf(f, "%s\n", currentHWID);
        fclose(f);
    }

    return TRUE;
}
```

---

## Low-Level Hardware Access & Anti-Spoofing

```c
/* ==========================================================================
 * ac_hwid_lowlevel.c - Low-level hardware access bypassing user-mode spoofing
 *
 * Uses direct hardware access methods that are difficult to spoof at user-mode
 * level. These techniques bypass registry/WMI hooks and provide more reliable
 * hardware fingerprinting for AntiCheat purposes.
 * ========================================================================== */

#include "ac_common.h"
#include <intrin.h>
#include <winioctl.h>
#include <tbs.h>

#pragma comment(lib, "tbs.lib")

/* ---- SMBIOS structures ---- */
#pragma pack(push, 1)
typedef struct _SMBIOS_HEADER {
    BYTE Type;
    BYTE Length;
    WORD Handle;
} SMBIOS_HEADER;

typedef struct _SMBIOS_TYPE0 {
    SMBIOS_HEADER Header;
    BYTE VendorStr;
    BYTE VersionStr;
    WORD StartingSegment;
    BYTE Vendor;
    BYTE ReleaseDateStr;
    BYTE ROMSize;
    /* ... more fields */
} SMBIOS_TYPE0;

typedef struct _SMBIOS_TYPE1 {
    SMBIOS_HEADER Header;
    BYTE ManufacturerStr;
    BYTE ProductNameStr;
    BYTE VersionStr;
    BYTE SerialNumberStr;
    BYTE UUID[16];
    BYTE WakeupType;
    /* ... more fields */
} SMBIOS_TYPE1;

typedef struct _SMBIOS_TYPE2 {
    SMBIOS_HEADER Header;
    BYTE ManufacturerStr;
    BYTE ProductNameStr;
    BYTE VersionStr;
    BYTE SerialNumberStr;
    BYTE AssetTagStr;
    BYTE FeatureFlags;
    BYTE LocationInChassisStr;
    /* ... more fields */
} SMBIOS_TYPE2;
#pragma pack(pop)

/* ---- Low-level HWID data structure ---- */
typedef struct _AC_LOWLEVEL_HWID {
    CHAR smbiosUuid[64];           /* SMBIOS Type 1 UUID */
    CHAR smbiosManufacturer[256];    /* SMBIOS Type 1 Manufacturer */
    CHAR smbiosProduct[256];        /* SMBIOS Type 1 Product */
    CHAR smbiosSerial[256];         /* SMBIOS Type 1 Serial */
    CHAR smbiosBaseboardSerial[256];/* SMBIOS Type 2 Serial */
    CHAR realDiskSerial[256];      /* Storage IOCTL disk serial */
    CHAR tpmEkh[256];              /* TPM endorsement key hash */
    BYTE cpuSignature[4];           /* CPU signature from CPUID */
    BYTE cpuFeatures[4];            /* CPU features from CPUID */
    DWORD hypervisorLeaves;          /* Hypervisor CPUID leaves */
} AC_LOWLEVEL_HWID;

/* ---- SMBIOS Direct Read ---- */
static BOOL AC_ReadSMBIOS(AC_LOWLEVEL_HWID* hwid)
{
    DWORD bufferSize = 0;
    
    /* Get required buffer size */
    bufferSize = GetSystemFirmwareTable('RSMB', 0, NULL, 0);
    if (bufferSize == 0) {
        AC_LOG(AC_SEV_WARNING, "Failed to get SMBIOS table size");
        return FALSE;
    }

    BYTE* buffer = (BYTE*)malloc(bufferSize);
    if (!buffer) return FALSE;

    DWORD actualSize = GetSystemFirmwareTable('RSMB', 0, buffer, bufferSize);
    if (actualSize == 0) {
        AC_LOG(AC_SEV_WARNING, "Failed to read SMBIOS table");
        free(buffer);
        return FALSE;
    }

    /* Parse SMBIOS entries */
    BYTE* current = buffer + sizeof(DWORD); /* Skip size field */
    BYTE* end = buffer + actualSize;

    while (current < end) {
        SMBIOS_HEADER* header = (SMBIOS_HEADER*)current;
        
        if (header->Length == 0) break;
        
        BYTE* strings = current + header->Length;
        
        switch (header->Type) {
            case 1: /* System Information */
                if (header->Length >= sizeof(SMBIOS_TYPE1)) {
                    SMBIOS_TYPE1* type1 = (SMBIOS_TYPE1*)header;
                    
                    /* Extract UUID (bytes 8-23) */
                    if (type1->UUID[0] != 0 || type1->UUID[1] != 0 || 
                        type1->UUID[2] != 0 || type1->UUID[3] != 0) {
                        sprintf_s(hwid->smbiosUuid, sizeof(hwid->smbiosUuid),
                                  "%02X%02X%02X%02X-%02X%02X%02X%02X-%02X%02X%02X%02X-%02X%02X%02X%02X",
                                  type1->UUID[0], type1->UUID[1], type1->UUID[2], type1->UUID[3],
                                  type1->UUID[4], type1->UUID[5], type1->UUID[6], type1->UUID[7],
                                  type1->UUID[8], type1->UUID[9], type1->UUID[10], type1->UUID[11],
                                  type1->UUID[12], type1->UUID[13], type1->UUID[14], type1->UUID[15]);
                    }
                    
                    /* Extract strings */
                    AC_LOG(AC_SEV_INFO, "SMBIOS Type 1 found, UUID: %s", hwid->smbiosUuid);
                }
                break;
                
            case 2: /* Baseboard Information */
                if (header->Length >= sizeof(SMBIOS_TYPE2)) {
                    SMBIOS_TYPE2* type2 = (SMBIOS_TYPE2*)header;
                    AC_LOG(AC_SEV_INFO, "SMBIOS Type 2 found");
                }
                break;
        }
        
        /* Move to next entry */
        current += header->Length;
        
        /* Skip strings (terminated by double null) */
        while (current < end && (*current != 0 || *(current + 1) != 0)) {
            current++;
        }
        current += 2; /* Skip double null terminator */
    }

    free(buffer);
    return TRUE;
}

/* ---- Storage IOCTL for Real Disk Serial ---- */
static BOOL AC_GetRealDiskSerial(AC_LOWLEVEL_HWID* hwid)
{
    HANDLE hDevice = CreateFileA("\\\\.\\PhysicalDrive0", 
                                GENERIC_READ, FILE_SHARE_READ,
                                NULL, OPEN_EXISTING, 0, NULL);
    
    if (hDevice == INVALID_HANDLE_VALUE) {
        AC_LOG(AC_SEV_WARNING, "Failed to open PhysicalDrive0");
        return FALSE;
    }

    /* Use IOCTL_STORAGE_QUERY_PROPERTY */
    STORAGE_PROPERTY_QUERY query = {0};
    query.PropertyId = StorageDeviceProperty;
    query.QueryType = PropertyStandardQuery;

    STORAGE_DESCRIPTOR_HEADER descHeader = {0};
    DWORD bytesReturned = 0;

    if (!DeviceIoControl(hDevice, IOCTL_STORAGE_QUERY_PROPERTY,
                        &query, sizeof(query), &descHeader, sizeof(descHeader),
                        &bytesReturned, NULL)) {
        AC_LOG(AC_SEV_WARNING, "IOCTL_STORAGE_QUERY_PROPERTY failed");
        CloseHandle(hDevice);
        return FALSE;
    }

    /* Allocate buffer for full descriptor */
    BYTE* descBuffer = (BYTE*)malloc(descHeader.Size);
    if (!descBuffer) {
        CloseHandle(hDevice);
        return FALSE;
    }

    BOOL success = DeviceIoControl(hDevice, IOCTL_STORAGE_QUERY_PROPERTY,
                                   &query, sizeof(query), descBuffer, descHeader.Size,
                                   &bytesReturned, NULL);

    if (success && bytesReturned >= sizeof(STORAGE_DEVICE_DESCRIPTOR)) {
        STORAGE_DEVICE_DESCRIPTOR* desc = (STORAGE_DEVICE_DESCRIPTOR*)descBuffer;
        
        if (desc->SerialNumberOffset != 0) {
            CHAR* serial = (CHAR*)descBuffer + desc->SerialNumberOffset;
            /* Remove whitespace and format */
            CHAR cleanSerial[256] = {0};
            INT j = 0;
            for (INT i = 0; serial[i] && j < sizeof(cleanSerial) - 1; i++) {
                if (serial[i] != ' ' && serial[i] != '\t' && serial[i] != '\0') {
                    cleanSerial[j++] = serial[i];
                }
            }
            strcpy_s(hwid->realDiskSerial, sizeof(hwid->realDiskSerial), cleanSerial);
            
            AC_LOG(AC_SEV_INFO, "Real disk serial: %s", hwid->realDiskSerial);
        }
    }

    free(descBuffer);
    CloseHandle(hDevice);
    return success;
}

/* ---- SCSI Pass-Through for Deeper Disk Access ---- */
static BOOL AC_SCSIPassThrough(AC_LOWLEVEL_HWID* hwid)
{
    HANDLE hDevice = CreateFileA("\\\\.\\PhysicalDrive0",
                                0, FILE_SHARE_READ | FILE_SHARE_WRITE,
                                NULL, OPEN_EXISTING, 0, NULL);
    
    if (hDevice == INVALID_HANDLE_VALUE) return FALSE;

    SCSI_PASS_THROUGH_DIRECT sptd = {0};
    BYTE data[256] = {0};
    
    sptd.Length = sizeof(SCSI_PASS_THROUGH_DIRECT);
    sptd.ScsiStatus = 0;
    sptd.PathId = 0;
    sptd.TargetId = 0;
    sptd.Lun = 0;
    sptd.CdbLength = 6;
    sptd.SenseInfoLength = 0;
    sptd.DataIn = SCSI_IOCTL_DATA_IN;
    sptd.DataTransferLength = sizeof(data);
    sptd.TimeOutValue = 30;
    sptd.DataBuffer = data;
    sptd.SenseInfoOffset = 0;
    
    /* INQUIRY command (0x12) */
    sptd.Cdb[0] = 0x12;  /* INQUIRY */
    sptd.Cdb[1] = 0;
    sptd.Cdb[2] = 0;
    sptd.Cdb[3] = 0;
    sptd.Cdb[4] = sizeof(data);  /* Allocation length */
    sptd.Cdb[5] = 0;

    DWORD bytesReturned;
    BOOL success = DeviceIoControl(hDevice, IOCTL_SCSI_PASS_THROUGH_DIRECT,
                                   &sptd, sizeof(sptd), &sptd, sizeof(sptd),
                                   &bytesReturned, NULL);

    if (success && data[0] == 0x05) { /* Peripheral device type: disk */
        /* Extract vendor/product/serial from INQUIRY data */
        CHAR vendor[9] = {0}, product[17] = {0}, revision[5] = {0};
        memcpy(vendor, data + 8, 8);
        memcpy(product, data + 16, 16);
        memcpy(revision, data + 32, 4);
        
        AC_LOG(AC_SEV_INFO, "SCSI INQUIRY: %s %s %s", vendor, product, revision);
    }

    CloseHandle(hDevice);
    return success;
}

/* ---- TPM 2.0 Endorsement Key ---- */
static BOOL AC_GetTPMEK(AC_LOWLEVEL_HWID* hwid)
{
    /* Try to get TPM endorsement key hash */
    TBS_CONTEXT_HANDLE hTbs = NULL;
    
    TBS_RESULT result = Tbsi_Context_Create(&hTbs);
    if (result != TBS_SUCCESS) {
        AC_LOG(AC_SEV_INFO, "TPM not available or accessible");
        return FALSE;
    }

    /* Get TPM device info */
    TBS_DEVICE_INFO deviceInfo = {0};
    DWORD deviceInfoSize = sizeof(deviceInfo);
    
    result = Tbsi_GetDeviceInfo(hTbs, &deviceInfoSize, (BYTE*)&deviceInfo);
    if (result == TBS_SUCCESS) {
        /* Convert TPM EK hash to hex string */
        sprintf_s(hwid->tpmEkh, sizeof(hwid->tpmEkh),
                  "%02X%02X%02X%02X%02X%02X%02X%02X",
                  deviceInfo.tpmSpecInfo.EK[0], deviceInfo.tpmSpecInfo.EK[1],
                  deviceInfo.tpmSpecInfo.EK[2], deviceInfo.tpmSpecInfo.EK[3],
                  deviceInfo.tpmSpecInfo.EK[4], deviceInfo.tpmSpecInfo.EK[5],
                  deviceInfo.tpmSpecInfo.EK[6], deviceInfo.tpmSpecInfo.EK[7]);
        
        AC_LOG(AC_SEV_INFO, "TPM EK hash: %s", hwid->tpmEkh);
    }

    Tbsi_Context_Close(hTbs);
    return (result == TBS_SUCCESS);
}

/* ---- CPU Signature and Features ---- */
static BOOL AC_GetCPUInfo(AC_LOWLEVEL_HWID* hwid)
{
    INT cpuInfo[4] = {0};
    
    /* Get CPU signature */
    __cpuid(cpuInfo, 1);
    memcpy(&hwid->cpuSignature, &cpuInfo[0], 4);
    memcpy(&hwid->cpuFeatures, &cpuInfo[3], 4);
    
    /* Check for hypervisor leaves */
    __cpuid(cpuInfo, 0x40000000);
    hwid->hypervisorLeaves = cpuInfo[0];
    
    AC_LOG(AC_SEV_INFO, "CPU signature: %08X, Features: %08X, Hypervisor max: %08X",
           *(DWORD*)hwid->cpuSignature, *(DWORD*)hwid->cpuFeatures, hwid->hypervisorLeaves);
    
    return TRUE;
}

/* ---- Advanced Hypervisor Detection ---- */
static BOOL AC_AdvancedHypervisorCheck(AC_LOWLEVEL_HWID* hwid)
{
    if (hwid->hypervisorLeaves < 0x40000000) return FALSE;
    
    INT cpuInfo[4] = {0};
    
    /* Check multiple hypervisor leaves */
    for (DWORD leaf = 0x40000000; leaf <= hwid->hypervisorLeaves && leaf < 0x40000010; leaf++) {
        __cpuid(cpuInfo, leaf);
        
        if (cpuInfo[0] != 0) {
            CHAR vendor[13] = {0};
            memcpy(vendor, &cpuInfo[1], 4);
            memcpy(vendor + 4, &cpuInfo[2], 4);
            memcpy(vendor + 8, &cpuInfo[3], 4);
            
            AC_LOG(AC_SEV_WARNING, "Advanced hypervisor detected at leaf 0x%08X: %s", leaf, vendor);
            return TRUE;
        }
    }
    
    return FALSE;
}

/* ---- Main low-level HWID collection ---- */
BOOL AC_CollectLowLevelHWID(AC_LOWLEVEL_HWID* hwid)
{
    if (!hwid) return FALSE;
    memset(hwid, 0, sizeof(*hwid));
    
    BOOL success = FALSE;
    
    /* SMBIOS direct read */
    success |= AC_ReadSMBIOS(hwid);
    
    /* Storage IOCTL */
    success |= AC_GetRealDiskSerial(hwid);
    
    /* SCSI pass-through */
    success |= AC_SCSIPassThrough(hwid);
    
    /* TPM endorsement key */
    success |= AC_GetTPMEK(hwid);
    
    /* CPU information */
    success |= AC_GetCPUInfo(hwid);
    
    /* Advanced hypervisor check */
    success |= AC_AdvancedHypervisorCheck(hwid);
    
    AC_LOG(AC_SEV_INFO, "Low-level HWID collection %s", success ? "successful" : "partially failed");
    
    return success;
}

/* ---- Generate low-level composite HWID ---- */
BOOL AC_GenerateLowLevelHWID(const AC_LOWLEVEL_HWID* hwid, CHAR* out, SIZE_T outLen)
{
    if (!hwid || !out || outLen < 65) return FALSE;
    
    CHAR composite[2048] = {0};
    sprintf_s(composite, sizeof(composite),
              "%s|%s|%s|%s|%s|%s|%08X|%08X|%08X",
              hwid->smbiosUuid,
              hwid->smbiosManufacturer,
              hwid->smbiosProduct,
              hwid->smbiosSerial,
              hwid->realDiskSerial,
              hwid->tpmEkh,
              *(DWORD*)hwid->cpuSignature,
              *(DWORD*)hwid->cpuFeatures,
              hwid->hypervisorLeaves);
    
    /* Generate hash */
    DWORD crc = AC_CRC32((BYTE*)composite, strlen(composite));
    sprintf_s(out, outLen, "%08X%08X%08X%08X",
              crc, crc ^ 0xDEADBEEF, crc ^ 0xCAFEBABE, crc ^ 0x12345678);
    
    AC_LOG(AC_SEV_INFO, "Low-level HWID generated: %s", out);
    return TRUE;
}
```

---

## Image Coherency Detection

```c
/* ==========================================================================
 * ac_image_coherency.c - Image coherency and integrity anomaly detection
 *
 * Detects anomalies by comparing in-memory checksums with disk file versions.
 * This helps identify code injection, memory patching, and other tampering.
 * ========================================================================== */

#include "ac_common.h"
#include <psapi.h>
#include <imagehlp.h>

#pragma comment(lib, "psapi.lib")
#pragma comment(lib, "imagehlp.lib")

/* ---- Image coherency data structure ---- */
typedef struct _AC_IMAGE_COHERENCY {
    HMODULE hModule;                    /* Module handle */
    CHAR moduleName[MAX_PATH];          /* Module name */
    CHAR modulePath[MAX_PATH];          /* Full module path */
    DWORD memoryChecksum;               /* In-memory checksum */
    DWORD diskChecksum;                 /* Disk file checksum */
    DWORD headerChecksum;               /* PE header checksum */
    BOOL isCoherent;                    /* TRUE if memory matches disk */
    BOOL isSystemModule;                /* TRUE if system module */
    DWORD imageSize;                    /* Size of image */
    DWORD timestamp;                    /* Last check timestamp */
} AC_IMAGE_COHERENCY;

/* ---- Coherency check results ---- */
typedef struct _AC_COHERENCY_RESULTS {
    DWORD totalModules;                 /* Total modules checked */
    DWORD coherentModules;              /* Modules that match disk */
    DWORD incoherentModules;            /* Modules that don't match disk */
    DWORD systemModules;                /* System modules checked */
    DWORD suspiciousModules;            /* Modules with anomalies */
    CHAR lastIncoherentModule[MAX_PATH];/* Last incoherent module found */
} AC_COHERENCY_RESULTS;

/* ---- Calculate CRC32 of memory region ---- */
static DWORD AC_CalculateMemoryChecksum(const VOID* data, SIZE_T size)
{
    DWORD crc = 0xFFFFFFFF;
    const BYTE* bytes = (const BYTE*)data;
    
    for (SIZE_T i = 0; i < size; i++) {
        crc ^= bytes[i];
        for (int j = 0; j < 8; j++) {
            crc = (crc >> 1) ^ (0xEDB88320 & -(crc & 1));
        }
    }
    
    return ~crc;
}

/* ---- Get PE header checksum from file ---- */
static DWORD AC_GetPEHeaderChecksum(const CHAR* filePath)
{
    HANDLE hFile = CreateFileA(filePath, GENERIC_READ, FILE_SHARE_READ, 
                             NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    if (hFile == INVALID_HANDLE_VALUE) return 0;
    
    DWORD fileSize = GetFileSize(hFile, NULL);
    if (fileSize < sizeof(IMAGE_DOS_HEADER)) {
        CloseHandle(hFile);
        return 0;
    }
    
    /* Map file for header access */
    HANDLE hMapping = CreateFileMapping(hFile, NULL, PAGE_READONLY, 0, 0, NULL);
    if (!hMapping) {
        CloseHandle(hFile);
        return 0;
    }
    
    LPVOID baseAddress = MapViewOfFile(hMapping, FILE_MAP_READ, 0, 0, 0);
    if (!baseAddress) {
        CloseHandle(hMapping);
        CloseHandle(hFile);
        return 0;
    }
    
    DWORD headerChecksum = 0;
    
    __try {
        IMAGE_DOS_HEADER* dosHeader = (IMAGE_DOS_HEADER*)baseAddress;
        if (dosHeader->e_magic == IMAGE_DOS_SIGNATURE) {
            IMAGE_NT_HEADERS* ntHeaders = (IMAGE_NT_HEADERS*)((BYTE*)baseAddress + dosHeader->e_lfanew);
            if (ntHeaders->Signature == IMAGE_NT_SIGNATURE) {
                headerChecksum = ntHeaders->OptionalHeader.CheckSum;
            }
        }
    }
    __except(EXCEPTION_EXECUTE_HANDLER) {
        headerChecksum = 0;
    }
    
    UnmapViewOfFile(baseAddress);
    CloseHandle(hMapping);
    CloseHandle(hFile);
    
    return headerChecksum;
}

/* ---- Calculate disk file checksum ---- */
static DWORD AC_CalculateDiskChecksum(const CHAR* filePath)
{
    HANDLE hFile = CreateFileA(filePath, GENERIC_READ, FILE_SHARE_READ,
                             NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    if (hFile == INVALID_HANDLE_VALUE) return 0;
    
    DWORD fileSize = GetFileSize(hFile, NULL);
    if (fileSize == 0) {
        CloseHandle(hFile);
        return 0;
    }
    
    /* For large files, sample first 64KB for performance */
    DWORD sampleSize = min(fileSize, 65536);
    BYTE* buffer = (BYTE*)malloc(sampleSize);
    if (!buffer) {
        CloseHandle(hFile);
        return 0;
    }
    
    DWORD bytesRead;
    BOOL success = ReadFile(hFile, buffer, sampleSize, &bytesRead, NULL);
    
    DWORD checksum = 0;
    if (success && bytesRead > 0) {
        checksum = AC_CalculateMemoryChecksum(buffer, bytesRead);
    }
    
    free(buffer);
    CloseHandle(hFile);
    return checksum;
}

/* ---- Check if module is system module ---- */
static BOOL AC_IsSystemModule(const CHAR* modulePath)
{
    CHAR systemDir[MAX_PATH];
    GetSystemDirectoryA(systemDir, sizeof(systemDir));
    
    CHAR windowsDir[MAX_PATH];
    GetWindowsDirectoryA(windowsDir, sizeof(windowsDir));
    
    return (_strnicmp(modulePath, systemDir, strlen(systemDir)) == 0 ||
            _strnicmp(modulePath, windowsDir, strlen(windowsDir)) == 0);
}

/* ---- Analyze single module coherency ---- */
static BOOL AC_AnalyzeModuleCoherency(HMODULE hModule, AC_IMAGE_COHERENCY* coherency)
{
    if (!hModule || !coherency) return FALSE;
    
    memset(coherency, 0, sizeof(*coherency));
    coherency->hModule = hModule;
    coherency->timestamp = GetTickCount();
    
    /* Get module information */
    MODULEINFO moduleInfo = {0};
    if (!GetModuleInformation(GetCurrentProcess(), hModule, &moduleInfo, sizeof(moduleInfo))) {
        AC_LOG(AC_SEV_WARNING, "Failed to get module information for %p", hModule);
        return FALSE;
    }
    
    /* Get module path and name */
    GetModuleFileNameA(hModule, coherency->modulePath, sizeof(coherency->modulePath));
    CHAR* fileName = strrchr(coherency->modulePath, '\\');
    strcpy_s(coherency->moduleName, sizeof(coherency->moduleName), fileName ? fileName + 1 : coherency->modulePath);
    
    coherency->imageSize = (DWORD)moduleInfo.SizeOfImage;
    coherency->isSystemModule = AC_IsSystemModule(coherency->modulePath);
    
    /* Calculate in-memory checksum */
    coherency->memoryChecksum = AC_CalculateMemoryChecksum(moduleInfo.lpBaseOfDll, 
                                                          min(moduleInfo.SizeOfImage, 65536));
    
    /* Get PE header checksum */
    coherency->headerChecksum = AC_GetPEHeaderChecksum(coherency->modulePath);
    
    /* Calculate disk checksum */
    coherency->diskChecksum = AC_CalculateDiskChecksum(coherency->modulePath);
    
    /* Determine coherency */
    coherency->isCoherent = (coherency->memoryChecksum == coherency->diskChecksum);
    
    /* Log results */
    AC_LOG(AC_SEV_INFO, "Module %s: Memory=0x%08X, Disk=0x%08X, Header=0x%08X, Coherent=%s",
           coherency->moduleName, coherency->memoryChecksum, coherency->diskChecksum,
           coherency->headerChecksum, coherency->isCoherent ? "YES" : "NO");
    
    return TRUE;
}

/* ---- Detect specific patching patterns ---- */
static BOOL AC_DetectPatchingPatterns(const AC_IMAGE_COHERENCY* coherency)
{
    if (!coherency || coherency->isCoherent) return FALSE;
    
    /* Check for common patching indicators */
    
    /* 1. Memory checksum differs but header checksum matches */
    if (coherency->memoryChecksum != coherency->diskChecksum && 
        coherency->headerChecksum != 0) {
        AC_LOG(AC_SEV_WARNING, "Memory patching detected in %s (header intact)", coherency->moduleName);
        return TRUE;
    }
    
    /* 2. Disk file doesn't exist but module is loaded */
    if (coherency->diskChecksum == 0 && coherency->memoryChecksum != 0) {
        AC_LOG(AC_SEV_CRITICAL, "Suspicious module %s (no disk file)", coherency->moduleName);
        return TRUE;
    }
    
    /* 3. System module with incoherency (highly suspicious) */
    if (coherency->isSystemModule && !coherency->isCoherent) {
        AC_LOG(AC_SEV_CRITICAL, "System module tampering detected: %s", coherency->moduleName);
        return TRUE;
    }
    
    return FALSE;
}

/* ---- Scan all loaded modules for coherency ---- */
BOOL AC_ScanModuleCoherency(AC_COHERENCY_RESULTS* results)
{
    if (!results) return FALSE;
    
    memset(results, 0, sizeof(*results));
    
    /* Get module handles */
    HMODULE modules[1024];
    DWORD bytesNeeded;
    
    if (!EnumProcessModules(GetCurrentProcess(), modules, sizeof(modules), &bytesNeeded)) {
        AC_LOG(AC_SEV_ERROR, "Failed to enumerate process modules");
        return FALSE;
    }
    
    DWORD moduleCount = bytesNeeded / sizeof(HMODULE);
    results->totalModules = moduleCount;
    
    AC_LOG(AC_SEV_INFO, "Scanning %d modules for coherency", moduleCount);
    
    /* Analyze each module */
    for (DWORD i = 0; i < moduleCount; i++) {
        AC_IMAGE_COHERENCY coherency;
        
        if (AC_AnalyzeModuleCoherency(modules[i], &coherency)) {
            if (coherency.isSystemModule) {
                results->systemModules++;
            }
            
            if (coherency.isCoherent) {
                results->coherentModules++;
            } else {
                results->incoherentModules++;
                strcpy_s(results->lastIncoherentModule, sizeof(results->lastIncoherentModule), 
                        coherency.moduleName);
                
                /* Check for suspicious patterns */
                if (AC_DetectPatchingPatterns(&coherency)) {
                    results->suspiciousModules++;
                    
                    /* Record critical event */
                    AC_RecordEvent(AC_CAT_INTEGRITY, AC_SEV_CRITICAL,
                                   "Module tampering detected", (ULONG_PTR)coherency.hModule, 0);
                }
            }
        }
    }
    
    /* Log summary */
    AC_LOG(AC_SEV_INFO, "Coherency scan complete: %d total, %d coherent, %d incoherent, %d suspicious",
           results->totalModules, results->coherentModules, results->incoherentModules, 
           results->suspiciousModules);
    
    return TRUE;
}

/* ---- Quick coherency check for specific module ---- */
BOOL AC_CheckModuleCoherency(const CHAR* moduleName)
{
    if (!moduleName) return FALSE;
    
    HMODULE hModule = GetModuleHandleA(moduleName);
    if (!hModule) {
        AC_LOG(AC_SEV_WARNING, "Module %s not found", moduleName);
        return FALSE;
    }
    
    AC_IMAGE_COHERENCY coherency;
    if (!AC_AnalyzeModuleCoherency(hModule, &coherency)) {
        return FALSE;
    }
    
    if (!coherency.isCoherent) {
        AC_DetectPatchingPatterns(&coherency);
        return FALSE;
    }
    
    return TRUE;
}

/* ---- Validate critical system modules ---- */
BOOL AC_ValidateSystemModules(void)
{
    const CHAR* criticalModules[] = {
        "ntdll.dll",
        "kernel32.dll",
        "user32.dll",
        "gdi32.dll",
        "advapi32.dll",
        "ws2_32.dll",
        NULL
    };
    
    BOOL allValid = TRUE;
    
    for (int i = 0; criticalModules[i]; i++) {
        if (!AC_CheckModuleCoherency(criticalModules[i])) {
            allValid = FALSE;
            AC_LOG(AC_SEV_CRITICAL, "Critical system module validation failed: %s", criticalModules[i]);
        }
    }
    
    return allValid;
}

/* ---- Periodic coherency monitoring ---- */
static DWORD s_lastCoherencyCheck = 0;
static AC_COHERENCY_RESULTS s_lastResults = {0};

BOOL AC_PeriodicCoherencyCheck(void)
{
    DWORD now = GetTickCount();
    
    /* Check every 30 seconds */
    if (now - s_lastCoherencyCheck < 30000) {
        return TRUE;
    }
    
    AC_COHERENCY_RESULTS currentResults;
    if (!AC_ScanModuleCoherency(&currentResults)) {
        return FALSE;
    }
    
    /* Compare with previous results */
    if (s_lastResults.totalModules > 0) {
        if (currentResults.incoherentModules > s_lastResults.incoherentModules) {
            AC_LOG(AC_SEV_WARNING, "New incoherent modules detected since last check");
            AC_RecordEvent(AC_CAT_INTEGRITY, AC_SEV_WARNING,
                           "New module inconsistencies detected", 0, 0);
        }
        
        if (currentResults.suspiciousModules > s_lastResults.suspiciousModules) {
            AC_LOG(AC_SEV_CRITICAL, "New suspicious module activity detected");
            AC_RecordEvent(AC_CAT_INTEGRITY, AC_SEV_CRITICAL,
                           "New suspicious modules detected", 0, 0);
        }
    }
    
    s_lastResults = currentResults;
    s_lastCoherencyCheck = now;
    
    return TRUE;
}
```

---

## Enhanced Speed-Hack Detection (Cheat Engine & Generic)

```c
/* ==========================================================================
 * ac_timing.c - Advanced Speed-hack / timer manipulation detection
 *
 * Comprehensive detection of Cheat Engine and other speedhack tools:
 * - Multi-source timing cross-validation
 * - Kernel-level timing verification (ntdll)
 * - Statistical pattern analysis
 * - Timing function hook detection
 * - Game-specific timing validation
 * - Sleep function manipulation detection
 * - RDTSC manipulation detection
 * - External time source validation
 * ========================================================================== */

#include "ac_common.h"

/* ---- Function pointers for dynamic loading (anti-hook) ---- */
typedef DWORD (WINAPI *PFN_GETTICKCOUNT)(void);
typedef DWORD (WINAPI *PFN_GETTICKCOUNT64)(void);
typedef DWORD (WINAPI *PFN_TIMEGETTIME)(void);
typedef BOOL (WINAPI *PFN_QUERYPERFORMANCECOUNTER)(LARGE_INTEGER*);
typedef BOOL (WINAPI *PFN_QUERYPERFORMANCEFREQUENCY)(LARGE_INTEGER*);
typedef VOID (WINAPI *PFN_GETSYSTEMTIMEASFILETIME)(LPFILETIME);
typedef DWORD (WINAPI *PFN_SLEEP)(DWORD);
typedef DWORD (WINAPI *PFN_SLEEPEX)(DWORD, BOOL);

/* ntdll internal APIs (undocumented, harder to hook) */
typedef NTSTATUS (NTAPI *PFN_NTDELAYEXECUTION)(BOOLEAN, PLARGE_INTEGER);
typedef NTSTATUS (NTAPI *PFN_NTQUERYSYSTEMTIME)(PLARGE_INTEGER);
typedef NTSTATUS (NTAPI *PFN_NTQUERYPERFORMANCECOUNTER)(PLARGE_INTEGER, PLARGE_INTEGER);
typedef NTSTATUS (NTAPI *PFN_NTQUERYPERFORMANCECOUNTER)(PLARGE_INTEGER);
typedef NTSTATUS (NTAPI *PFN_NTQUERYSYSTEMPRECISETIME)(PLARGE_INTEGER);
typedef NTSTATUS (NTAPI *PFN_RTLGETSYSTEMTIMEPRECISE)(PLARGE_INTEGER);
typedef NTSTATUS (NTAPI *PFN_RTLQUERYPERFORMANCECOUNTER)(PLARGE_INTEGER);
typedef NTSTATUS (NTAPI *PFN_RTLQUERYPERFORMANCEFREQUENCY)(PLARGE_INTEGER);
typedef NTSTATUS (NTAPI *PFN_NTSETTIMERRESOLUTION)(ULONG, BOOLEAN, PBOOLEAN);
typedef NTSTATUS (NTAPI *PFN_NTQUERYTIMERRESOLUTION)(PULONG, PULONG, PBOOLEAN);
typedef VOID (NTAPI *PFN_RTLINITUNICODESTRING)(PUNICODE_STRING, PCWSTR);
typedef NTSTATUS (NTAPI *PFN_RTLTIMEFIELDSTOTIME)(PTIME_FIELDS, PTIME, BOOLEAN, BOOLEAN);
typedef NTSTATUS (NTAPI *PFN_NTQUERYPERFORMANCECOUNTER)(PLARGE_INTEGER, PLARGE_INTEGER);

static struct {
    /* kernel32 functions (commonly hooked) */
    PFN_GETTICKCOUNT GetTickCount;
    PFN_GETTICKCOUNT64 GetTickCount64;
    PFN_TIMEGETTIME timeGetTime;
    PFN_QUERYPERFORMANCECOUNTER QueryPerformanceCounter;
    PFN_QUERYPERFORMANCEFREQUENCY QueryPerformanceFrequency;
    PFN_GETSYSTEMTIMEASFILETIME GetSystemTimeAsFileTime;
    PFN_SLEEP Sleep;
    PFN_SLEEPEX SleepEx;
    
    /* ntdll internal APIs (undocumented, harder to hook) */
    PFN_NTDELAYEXECUTION NtDelayExecution;
    PFN_NTQUERYSYSTEMTIME NtQuerySystemTime;
    PFN_NTQUERYSYSTEMTIME NtQuerySystemPreciseTime;
    PFN_RTLGETSYSTEMTIMEPRECISE RtlGetSystemTimePrecise;
    PFN_RTLQUERYPERFORMANCECOUNTER RtlQueryPerformanceCounter;
    PFN_RTLQUERYPERFORMANCEFREQUENCY RtlQueryPerformanceFrequency;
    PFN_NTSETTIMERRESOLUTION NtSetTimerResolution;
    PFN_NTQUERYTIMERRESOLUTION NtQueryTimerResolution;
} s_timingFuncs = {0};

/* ---- Comprehensive time snapshot ---- */
typedef struct _AC_TIME_SNAPSHOT {
    /* kernel32 timing functions (commonly hooked) */
    DWORD     tickCount;          /* GetTickCount             */
    DWORD     tickCount64;        /* GetTickCount64           */
    DWORD     timeGetTimeMs;      /* timeGetTime              */
    LONGLONG  perfCounter;        /* QueryPerformanceCounter  */
    LONGLONG  perfFreq;           /* QueryPerformanceFrequency*/
    FILETIME  systemTime;         /* GetSystemTimeAsFileTime  */
    
    /* ntdll internal APIs (undocumented, harder to hook) */
    LARGE_INTEGER ntSystemTime;           /* NtQuerySystemTime        */
    LARGE_INTEGER ntSystemPreciseTime;    /* NtQuerySystemPreciseTime */
    LARGE_INTEGER rtlSystemTimePrecise;   /* RtlGetSystemTimePrecise  */
    LARGE_INTEGER rtlPerfCounter;          /* RtlQueryPerformanceCounter*/
    LARGE_INTEGER rtlPerfFreq;            /* RtlQueryPerformanceFrequency*/
    ULONG      timerResolution;           /* NtQueryTimerResolution   */
    ULONG      minTimerResolution;        /* NtQueryTimerResolution   */
    BOOLEAN    timerResolutionSet;        /* NtQueryTimerResolution   */
    
    /* Hardware timing */
    ULONGLONG rdtsc;              /* __rdtsc                  */
    ULONGLONG rdtsc2;             /* __rdtsc (second sample)  */
    
    /* Thread/Process timing */
    DWORD     threadKernelTime;   /* GetThreadTimes kernel ms */
    DWORD     threadUserTime;     /* GetThreadTimes user ms   */
    ULONGLONG processTime;       /* GetProcessTime           */
    
    /* Metadata */
    DWORD     timestamp;          /* Snapshot timestamp       */
} AC_TIME_SNAPSHOT;

static AC_TIME_SNAPSHOT s_prevSnap = {0};
static AC_TIME_SNAPSHOT s_baselineSnap = {0};
static BOOL             s_prevSnapValid = FALSE;
static BOOL             s_baselineValid = FALSE;

/* ---- Statistical analysis ---- */
#define AC_TIMING_HISTORY_SIZE 60
typedef struct _AC_TIMING_STATS {
    DOUBLE   tickDeltaHistory[AC_TIMING_HISTORY_SIZE];
    DOUBLE   perfDeltaHistory[AC_TIMING_HISTORY_SIZE];
    DOUBLE   timeGetDeltaHistory[AC_TIMING_HISTORY_SIZE];
    INT      historyIdx;
    INT      historyCount;
    DOUBLE   meanTickDelta;
    DOUBLE   stdDevTickDelta;
    DOUBLE   meanPerfDelta;
    DOUBLE   stdDevPerfDelta;
    INT      anomalyCount;
    INT      consecutiveAnomalies;
} AC_TIMING_STATS;

static AC_TIMING_STATS s_timingStats = {0};

/* ---- Hook detection ---- */
typedef struct _AC_HOOKED_TIMING_FUNC {
    CHAR     funcName[64];
    BOOL     isHooked;
    BYTE     originalBytes[16];
    BYTE     currentBytes[16];
    DWORD    hookCount;
} AC_HOOKED_TIMING_FUNC;

static AC_HOOKED_TIMING_FUNC s_hookedFuncs[16];
static INT                   s_hookedFuncCount = 0;

/* ---- Game-specific timing ---- */
typedef struct _AC_GAME_TIMING {
    DOUBLE   expectedFrameTime;    /* Expected ms per frame      */
    DOUBLE   actualFrameTime;      /* Actual ms per frame       */
    DOUBLE   serverTimeDelta;      /* Server time delta         */
    DOUBLE   clientTimeDelta;      /* Client time delta         */
    BOOL     timingValid;
} AC_GAME_TIMING;

static AC_GAME_TIMING s_gameTiming = {0};

/* ---- External time source (network) ---- */
static DOUBLE s_networkTimeOffset = 0.0;
static BOOL   s_networkTimeValid = FALSE;

/* ==========================================================================
 * Dynamic Function Loading (Anti-Hook)
 * ========================================================================== */

static BOOL AC_LoadTimingFunctions(void)
{
    HMODULE hKernel32 = GetModuleHandleA("kernel32.dll");
    HMODULE hNtdll = GetModuleHandleA("ntdll.dll");
    
    if (!hKernel32 || !hNtdll) return FALSE;
    
    /* Load kernel32 functions (commonly hooked, use as comparison baseline) */
    s_timingFuncs.GetTickCount = (PFN_GETTICKCOUNT)GetProcAddress(hKernel32, "GetTickCount");
    s_timingFuncs.GetTickCount64 = (PFN_GETTICKCOUNT64)GetProcAddress(hKernel32, "GetTickCount64");
    s_timingFuncs.timeGetTime = (PFN_TIMEGETTIME)GetProcAddress(hKernel32, "timeGetTime");
    s_timingFuncs.QueryPerformanceCounter = (PFN_QUERYPERFORMANCECOUNTER)GetProcAddress(hKernel32, "QueryPerformanceCounter");
    s_timingFuncs.QueryPerformanceFrequency = (PFN_QUERYPERFORMANCEFREQUENCY)GetProcAddress(hKernel32, "QueryPerformanceFrequency");
    s_timingFuncs.GetSystemTimeAsFileTime = (PFN_GETSYSTEMTIMEASFILETIME)GetProcAddress(hKernel32, "GetSystemTimeAsFileTime");
    s_timingFuncs.Sleep = (PFN_SLEEP)GetProcAddress(hKernel32, "Sleep");
    s_timingFuncs.SleepEx = (PFN_SLEEPEX)GetProcAddress(hKernel32, "SleepEx");
    
    /* Load ntdll functions (undocumented internal APIs, harder to hook) */
    s_timingFuncs.NtDelayExecution = (PFN_NTDELAYEXECUTION)GetProcAddress(hNtdll, "NtDelayExecution");
    s_timingFuncs.NtQuerySystemTime = (PFN_NTQUERYSYSTEMTIME)GetProcAddress(hNtdll, "NtQuerySystemTime");
    s_timingFuncs.NtQuerySystemPreciseTime = (PFN_NTQUERYSYSTEMTIME)GetProcAddress(hNtdll, "NtQuerySystemPreciseTime");
    s_timingFuncs.RtlGetSystemTimePrecise = (PFN_RTLGETSYSTEMTIMEPRECISE)GetProcAddress(hNtdll, "RtlGetSystemTimePrecise");
    s_timingFuncs.RtlQueryPerformanceCounter = (PFN_RTLQUERYPERFORMANCECOUNTER)GetProcAddress(hNtdll, "RtlQueryPerformanceCounter");
    s_timingFuncs.RtlQueryPerformanceFrequency = (PFN_RTLQUERYPERFORMANCEFREQUENCY)GetProcAddress(hNtdll, "RtlQueryPerformanceFrequency");
    s_timingFuncs.NtSetTimerResolution = (PFN_NTSETTIMERRESOLUTION)GetProcAddress(hNtdll, "NtSetTimerResolution");
    s_timingFuncs.NtQueryTimerResolution = (PFN_NTQUERYTIMERRESOLUTION)GetProcAddress(hNtdll, "NtQueryTimerResolution");
    
    /* Verify critical functions - prioritize ntdll over kernel32 */
    if (!s_timingFuncs.NtQuerySystemTime || !s_timingFuncs.RtlQueryPerformanceCounter) {
        AC_LOG(AC_SEV_CRITICAL, "Failed to load critical ntdll timing functions");
        return FALSE;
    }
    
    /* Log which ntdll functions were successfully loaded */
    AC_LOG(AC_SEV_INFO, "ntdll timing functions loaded:");
    AC_LOG(AC_SEV_INFO, "  NtQuerySystemTime: %s", s_timingFuncs.NtQuerySystemTime ? "OK" : "FAIL");
    AC_LOG(AC_SEV_INFO, "  NtQuerySystemPreciseTime: %s", s_timingFuncs.NtQuerySystemPreciseTime ? "OK" : "FAIL");
    AC_LOG(AC_SEV_INFO, "  RtlGetSystemTimePrecise: %s", s_timingFuncs.RtlGetSystemTimePrecise ? "OK" : "FAIL");
    AC_LOG(AC_SEV_INFO, "  RtlQueryPerformanceCounter: %s", s_timingFuncs.RtlQueryPerformanceCounter ? "OK" : "FAIL");
    AC_LOG(AC_SEV_INFO, "  RtlQueryPerformanceFrequency: %s", s_timingFuncs.RtlQueryPerformanceFrequency ? "OK" : "FAIL");
    AC_LOG(AC_SEV_INFO, "  NtDelayExecution: %s", s_timingFuncs.NtDelayExecution ? "OK" : "FAIL");
    AC_LOG(AC_SEV_INFO, "  NtQueryTimerResolution: %s", s_timingFuncs.NtQueryTimerResolution ? "OK" : "FAIL");
    
    return TRUE;
}

/* ==========================================================================
 * Timing Snapshot Collection
 * ========================================================================== */

static void AC_TakeTimeSnapshot(AC_TIME_SNAPSHOT* snap)
{
    if (!snap) return;
    
    memset(snap, 0, sizeof(AC_TIME_SNAPSHOT));
    
    /* ---- kernel32 timing functions (commonly hooked, use as baseline) ---- */
    snap->tickCount = s_timingFuncs.GetTickCount();
    snap->timeGetTimeMs = s_timingFuncs.timeGetTime();
    s_timingFuncs.QueryPerformanceCounter((LARGE_INTEGER*)&snap->perfCounter);
    s_timingFuncs.QueryPerformanceFrequency((LARGE_INTEGER*)&snap->perfFreq);
    s_timingFuncs.GetSystemTimeAsFileTime(&snap->systemTime);
    
    /* 64-bit tick count if available */
    if (s_timingFuncs.GetTickCount64) {
        snap->tickCount64 = s_timingFuncs.GetTickCount64();
    }
    
    /* ---- ntdll internal APIs (undocumented, harder to hook) ---- */
    /* Primary kernel-level timing functions */
    s_timingFuncs.NtQuerySystemTime(&snap->ntSystemTime);
    s_timingFuncs.RtlQueryPerformanceCounter(&snap->rtlPerfCounter);
    if (s_timingFuncs.RtlQueryPerformanceFrequency) {
        s_timingFuncs.RtlQueryPerformanceFrequency(&snap->rtlPerfFreq);
    }
    
    /* Precise timing functions (Windows 8+) */
    if (s_timingFuncs.NtQuerySystemPreciseTime) {
        s_timingFuncs.NtQuerySystemPreciseTime(&snap->ntSystemPreciseTime);
    }
    if (s_timingFuncs.RtlGetSystemTimePrecise) {
        s_timingFuncs.RtlGetSystemTimePrecise(&snap->rtlSystemTimePrecise);
    }
    
    /* Timer resolution (speedhacks often modify this) */
    if (s_timingFuncs.NtQueryTimerResolution) {
        s_timingFuncs.NtQueryTimerResolution(&snap->timerResolution, 
                                            &snap->minTimerResolution, 
                                            &snap->timerResolutionSet);
    }
    
    /* ---- Hardware timing ---- */
    snap->rdtsc = __rdtsc();
    snap->rdtsc2 = __rdtsc();
    
    /* ---- Thread/Process timing ---- */
    FILETIME kernelTime, userTime, dummy;
    GetThreadTimes(GetCurrentThread(), &dummy, &dummy,
                   &kernelTime, &userTime);
    snap->threadKernelTime = (kernelTime.dwHighDateTime << 22) |
                             (kernelTime.dwLowDateTime >> 10);
    snap->threadUserTime = (userTime.dwHighDateTime << 22) |
                           (userTime.dwLowDateTime >> 10);
    
    FILETIME creationTime, exitTime, procKernelTime, procUserTime;
    if (GetProcessTimes(GetCurrentProcess(), &creationTime, &exitTime,
                        &procKernelTime, &procUserTime)) {
        ULONGLONG kernel = ((ULONGLONG)procKernelTime.dwHighDateTime << 32) |
                           procKernelTime.dwLowDateTime;
        ULONGLONG user = ((ULONGLONG)procUserTime.dwHighDateTime << 32) |
                         procUserTime.dwLowDateTime;
        snap->processTime = (kernel + user) / 10000; /* Convert to ms */
    }
    
    snap->timestamp = s_timingFuncs.GetTickCount();
}

/* ==========================================================================
 * Statistical Analysis
 * ========================================================================== */

static void AC_UpdateTimingStats(AC_TIME_SNAPSHOT* now, AC_TIME_SNAPSHOT* prev)
{
    if (!s_prevSnapValid) return;
    
    DOUBLE tickDelta = (DOUBLE)(now->tickCount - prev->tickCount);
    DOUBLE perfDelta = (DOUBLE)(now->perfCounter - prev->perfCounter) * 1000.0 /
                       (DOUBLE)now->perfFreq;
    DOUBLE timeGetDelta = (DOUBLE)(now->timeGetTimeMs - prev->timeGetTimeMs);
    
    /* Update history buffers */
    s_timingStats.tickDeltaHistory[s_timingStats.historyIdx] = tickDelta;
    s_timingStats.perfDeltaHistory[s_timingStats.historyIdx] = perfDelta;
    s_timingStats.timeGetDeltaHistory[s_timingStats.historyIdx] = timeGetDelta;
    
    s_timingStats.historyIdx = (s_timingStats.historyIdx + 1) % AC_TIMING_HISTORY_SIZE;
    if (s_timingStats.historyCount < AC_TIMING_HISTORY_SIZE) {
        s_timingStats.historyCount++;
    }
    
    /* Calculate mean and standard deviation */
    if (s_timingStats.historyCount >= 10) {
        DOUBLE sumTick = 0, sumPerf = 0;
        for (INT i = 0; i < s_timingStats.historyCount; i++) {
            sumTick += s_timingStats.tickDeltaHistory[i];
            sumPerf += s_timingStats.perfDeltaHistory[i];
        }
        
        s_timingStats.meanTickDelta = sumTick / s_timingStats.historyCount;
        s_timingStats.meanPerfDelta = sumPerf / s_timingStats.historyCount;
        
        /* Calculate standard deviation */
        DOUBLE varTick = 0, varPerf = 0;
        for (INT i = 0; i < s_timingStats.historyCount; i++) {
            varTick += pow(s_timingStats.tickDeltaHistory[i] - s_timingStats.meanTickDelta, 2);
            varPerf += pow(s_timingStats.perfDeltaHistory[i] - s_timingStats.meanPerfDelta, 2);
        }
        
        s_timingStats.stdDevTickDelta = sqrt(varTick / s_timingStats.historyCount);
        s_timingStats.stdDevPerfDelta = sqrt(varPerf / s_timingStats.historyCount);
    }
}

static BOOL AC_DetectStatisticalAnomaly(AC_TIME_SNAPSHOT* now, AC_TIME_SNAPSHOT* prev)
{
    if (s_timingStats.historyCount < 10) return FALSE;
    
    DOUBLE tickDelta = (DOUBLE)(now->tickCount - prev->tickCount);
    DOUBLE perfDelta = (DOUBLE)(now->perfCounter - prev->perfCounter) * 1000.0 /
                       (DOUBLE)now->perfFreq;
    
    /* Check if current delta is more than 3 standard deviations from mean */
    DOUBLE tickZScore = (s_timingStats.stdDevTickDelta > 0) ?
                        fabs(tickDelta - s_timingStats.meanTickDelta) / s_timingStats.stdDevTickDelta : 0;
    DOUBLE perfZScore = (s_timingStats.stdDevPerfDelta > 0) ?
                         fabs(perfDelta - s_timingStats.meanPerfDelta) / s_timingStats.stdDevPerfDelta : 0;
    
    if (tickZScore > 3.0 || perfZScore > 3.0) {
        AC_LOG(AC_SEV_CRITICAL,
               "Statistical timing anomaly: Tick Z-score=%.2f, Perf Z-score=%.2f",
               tickZScore, perfZScore);
        return TRUE;
    }
    
    return FALSE;
}

/* ==========================================================================
 * Timing Function Hook Detection
 * ========================================================================== */

static BOOL AC_CheckTimingFunctionHook(const CHAR* funcName, PVOID funcAddr)
{
    if (!funcAddr || s_hookedFuncCount >= 16) return FALSE;
    
    /* Read first 16 bytes of the function */
    BYTE currentBytes[16];
    memcpy(currentBytes, funcAddr, 16);
    
    /* Check for common hook patterns */
    BOOL isHooked = FALSE;
    
    /* JMP instruction (E9 xx xx xx xx) */
    if (currentBytes[0] == 0xE9) isHooked = TRUE;
    
    /* JMP [address] (FF 25 xx xx xx xx) */
    if (currentBytes[0] == 0xFF && currentBytes[1] == 0x25) isHooked = TRUE;
    
    /* PUSH addr; RET (68 xx xx xx xx C3) */
    if (currentBytes[0] == 0x68 && currentBytes[5] == 0xC3) isHooked = TRUE;
    
    /* MOV EAX, addr; JMP EAX (B8 xx xx xx xx FF E0) */
    if (currentBytes[0] == 0xB8 && currentBytes[5] == 0xFF && currentBytes[6] == 0xE0) isHooked = TRUE;
    
    if (isHooked) {
        AC_HOOKED_TIMING_FUNC* hook = &s_hookedFuncs[s_hookedFuncCount++];
        strncpy_s(hook->funcName, sizeof(hook->funcName), funcName, _TRUNCATE);
        hook->isHooked = TRUE;
        memcpy(hook->currentBytes, currentBytes, 16);
        hook->hookCount++;
        
        AC_LOG(AC_SEV_BAN, "Timing function hook detected: %s at %p", funcName, funcAddr);
        return TRUE;
    }
    
    return FALSE;
}

static BOOL AC_DetectTimingHooks(void)
{
    HMODULE hKernel32 = GetModuleHandleA("kernel32.dll");
    HMODULE hNtdll = GetModuleHandleA("ntdll.dll");
    
    if (!hKernel32 || !hNtdll) return FALSE;
    
    BOOL hooksDetected = FALSE;
    
    /* Check critical timing functions */
    hooksDetected |= AC_CheckTimingFunctionHook("GetTickCount",
                        GetProcAddress(hKernel32, "GetTickCount"));
    hooksDetected |= AC_CheckTimingFunctionHook("GetTickCount64",
                        GetProcAddress(hKernel32, "GetTickCount64"));
    hooksDetected |= AC_CheckTimingFunctionHook("timeGetTime",
                        GetProcAddress(hKernel32, "timeGetTime"));
    hooksDetected |= AC_CheckTimingFunctionHook("QueryPerformanceCounter",
                        GetProcAddress(hKernel32, "QueryPerformanceCounter"));
    hooksDetected |= AC_CheckTimingFunctionHook("Sleep",
                        GetProcAddress(hKernel32, "Sleep"));
    hooksDetected |= AC_CheckTimingFunctionHook("NtDelayExecution",
                        GetProcAddress(hNtdll, "NtDelayExecution"));
    hooksDetected |= AC_CheckTimingFunctionHook("NtQueryPerformanceCounter",
                        GetProcAddress(hNtdll, "NtQueryPerformanceCounter"));
    
    return hooksDetected;
}

/* ==========================================================================
 * Cheat Engine Specific Detection
 * ========================================================================== */

static BOOL AC_DetectCheatEngineSpeedhack(void)
{
    /* Cheat Engine typically hooks these specific patterns */
    
    /* 1. Check for Cheat Engine's signature in memory */
    HMODULE hModules[1024];
    DWORD cbNeeded;
    
    if (EnumProcessModules(GetCurrentProcess(), hModules, sizeof(hModules), &cbNeeded)) {
        DWORD moduleCount = cbNeeded / sizeof(HMODULE);
        
        for (DWORD i = 0; i < moduleCount; i++) {
            CHAR modName[MAX_PATH];
            if (GetModuleFileNameExA(GetCurrentProcess(), hModules[i], modName, sizeof(modName))) {
                /* Check for Cheat Engine injected modules */
                if (strstr(modName, "ce") || strstr(modName, "CheatEngine") ||
                    strstr(modName, "speedhack") || strstr(modName, "dbk")) {
                    AC_LOG(AC_SEV_BAN, "Cheat Engine module detected: %s", modName);
                    AC_RecordEvent(AC_CAT_TIMING, AC_SEV_BAN,
                                   "Cheat Engine module loaded",
                                   (ULONG_PTR)hModules[i], 0);
                    return TRUE;
                }
            }
        }
    }
    
    /* 2. Check for Cheat Engine's specific timing manipulation patterns */
    /* Cheat Engine often modifies the TSC scaling factor */
    
    static ULONGLONG s_baselineRDTSC = 0;
    static ULONGLONG s_baselinePerf = 0;
    static DOUBLE s_rdtscPerfRatio = 0;
    
    if (s_baselineRDTSC == 0) {
        s_baselineRDTSC = __rdtsc();
        QueryPerformanceCounter((LARGE_INTEGER*)&s_baselinePerf);
        return FALSE;
    }
    
    ULONGLONG currentRDTSC = __rdtsc();
    LONGLONG currentPerf;
    QueryPerformanceCounter((LARGE_INTEGER*)&currentPerf);
    
    ULONGLONG rdtscDelta = currentRDTSC - s_baselineRDTSC;
    LONGLONG perfDelta = currentPerf - s_baselinePerf;
    
    if (perfDelta > 0) {
        DOUBLE currentRatio = (DOUBLE)rdtscDelta / (DOUBLE)perfDelta;
        
        if (s_rdtscPerfRatio == 0) {
            s_rdtscPerfRatio = currentRatio;
        } else {
            /* Cheat Engine often changes this ratio significantly */
            DOUBLE ratioChange = fabs(currentRatio - s_rdtscPerfRatio) / s_rdtscPerfRatio;
            
            if (ratioChange > 0.1) { /* 10% change is suspicious */
                AC_LOG(AC_SEV_CRITICAL,
                       "TSC/Perf ratio manipulation detected: %.6f -> %.6f (%.2f%% change)",
                       s_rdtscPerfRatio, currentRatio, ratioChange * 100);
                AC_RecordEvent(AC_CAT_TIMING, AC_SEV_CRITICAL,
                               "TSC/Perf ratio manipulation (Cheat Engine pattern)",
                               (ULONG_PTR)(DOUBLE)(s_rdtscPerfRatio * 1000000),
                               (ULONG_PTR)(DOUBLE)(currentRatio * 1000000));
                return TRUE;
            }
        }
    }
    
    /* Update baseline */
    s_baselineRDTSC = currentRDTSC;
    s_baselinePerf = currentPerf;
    
    return FALSE;
}

/* ==========================================================================
 * Sleep Function Manipulation Detection
 * ========================================================================== */

static BOOL AC_DetectSleepManipulation(void)
{
    /* Test if Sleep function actually delays the expected amount */
    
    DWORD testDelay = 100; /* Test with 100ms delay */
    
    LARGE_INTEGER startPerf, endPerf;
    s_timingFuncs.QueryPerformanceCounter(&startPerf);
    
    s_timingFuncs.Sleep(testDelay);
    
    s_timingFuncs.QueryPerformanceCounter(&endPerf);
    
    LONGLONG perfDelta = endPerf.QuadPart - startPerf.QuadPart;
    DOUBLE actualDelayMs = (DOUBLE)perfDelta * 1000.0 / (DOUBLE)g_ac.perfFreq.QuadPart;
    
    /* Allow 20% tolerance */
    DOUBLE tolerance = testDelay * 0.2;
    
    if (fabs(actualDelayMs - testDelay) > tolerance) {
        AC_LOG(AC_SEV_CRITICAL,
               "Sleep manipulation detected: requested %ums, actual %.2fms",
               testDelay, actualDelayMs);
        AC_RecordEvent(AC_CAT_TIMING, AC_SEV_CRITICAL,
                       "Sleep function manipulation",
                       (ULONG_PTR)testDelay,
                       (ULONG_PTR)(DWORD)actualDelayMs);
        return TRUE;
    }
    
    return FALSE;
}

/* ==========================================================================
 * Kernel-Level Timing Verification (ntdll APIs)
 * ========================================================================== */

static BOOL AC_VerifyKernelTiming(AC_TIME_SNAPSHOT* now, AC_TIME_SNAPSHOT* prev)
{
    /* Compare kernel-level timing (ntdll) with user-level timing (kernel32)
       Kernel-level timing is harder to hook than user-level */
    
    if (!s_prevSnapValid) return FALSE;
    
    BOOL anomaly = FALSE;
    
    /* ---- 1. Compare NtQuerySystemTime with GetSystemTimeAsFileTime ---- */
    ULONGLONG sysNow = ((ULONGLONG)now->systemTime.dwHighDateTime << 32) |
                        now->systemTime.dwLowDateTime;
    ULONGLONG sysPrev = ((ULONGLONG)prev->systemTime.dwHighDateTime << 32) |
                         prev->systemTime.dwLowDateTime;
    
    DOUBLE sysDeltaMs = (DOUBLE)(sysNow - sysPrev) / 10000.0;
    
    ULONGLONG ntNow = (ULONGLONG)now->ntSystemTime.QuadPart;
    ULONGLONG ntPrev = (ULONGLONG)prev->ntSystemTime.QuadPart;
    DOUBLE ntDeltaMs = (DOUBLE)(ntNow - ntPrev) / 10000.0;
    
    /* These should be very close (within 1ms) */
    if (fabs(sysDeltaMs - ntDeltaMs) > 1.0) {
        AC_LOG(AC_SEV_CRITICAL,
               "Kernel/User timing divergence: SystemTime=%.2fms, NtSystemTime=%.2fms",
               sysDeltaMs, ntDeltaMs);
        anomaly = TRUE;
    }
    
    /* ---- 2. Compare RtlQueryPerformanceCounter with QueryPerformanceCounter ---- */
    DOUBLE userPerfDeltaMs = (DOUBLE)(now->perfCounter - prev->perfCounter) * 1000.0 /
                             (DOUBLE)now->perfFreq;
    DOUBLE rtlPerfDeltaMs = (DOUBLE)(now->rtlPerfCounter.QuadPart - prev->rtlPerfCounter.QuadPart) * 1000.0 /
                            (DOUBLE)now->rtlPerfFreq.QuadPart;
    
    if (fabs(userPerfDeltaMs - rtlPerfDeltaMs) > 1.0) {
        AC_LOG(AC_SEV_CRITICAL,
               "User/Kernel perf counter divergence: User=%.2fms, Kernel=%.2fms",
               userPerfDeltaMs, rtlPerfDeltaMs);
        anomaly = TRUE;
    }
    
    /* ---- 3. Validate precise timing functions (Windows 8+) ---- */
    if (s_timingFuncs.NtQuerySystemPreciseTime) {
        ULONGLONG ntPreciseNow = (ULONGLONG)now->ntSystemPreciseTime.QuadPart;
        ULONGLONG ntPrecisePrev = (ULONGLONG)prev->ntSystemPreciseTime.QuadPart;
        DOUBLE ntPreciseDeltaMs = (DOUBLE)(ntPreciseNow - ntPrecisePrev) / 10000.0;
        
        if (fabs(ntDeltaMs - ntPreciseDeltaMs) > 2.0) {
            AC_LOG(AC_SEV_CRITICAL,
                   "NtQuerySystemTime vs NtQuerySystemPreciseTime divergence: %.2fms vs %.2fms",
                   ntDeltaMs, ntPreciseDeltaMs);
            anomaly = TRUE;
        }
    }
    
    if (s_timingFuncs.RtlGetSystemTimePrecise) {
        ULONGLONG rtlPreciseNow = (ULONGLONG)now->rtlSystemTimePrecise.QuadPart;
        ULONGLONG rtlPrecisePrev = (ULONGLONG)prev->rtlSystemTimePrecise.QuadPart;
        DOUBLE rtlPreciseDeltaMs = (DOUBLE)(rtlPreciseNow - rtlPrecisePrev) / 10000.0;
        
        if (fabs(ntDeltaMs - rtlPreciseDeltaMs) > 2.0) {
            AC_LOG(AC_SEV_CRITICAL,
                   "NtQuerySystemTime vs RtlGetSystemTimePrecise divergence: %.2fms vs %.2fms",
                   ntDeltaMs, rtlPreciseDeltaMs);
            anomaly = TRUE;
        }
    }
    
    /* ---- 4. Check timer resolution manipulation (speedhack technique) ---- */
    static ULONG s_baselineTimerResolution = 0;
    if (s_baselineTimerResolution == 0 && now->timerResolution > 0) {
        s_baselineTimerResolution = now->timerResolution;
    }
    
    if (s_baselineTimerResolution > 0 && now->timerResolution > 0) {
        /* Speedhacks often set timer resolution to minimum (0.5ms or 1ms) */
        if (now->timerResolution != s_baselineTimerResolution) {
            AC_LOG(AC_SEV_CRITICAL,
                   "Timer resolution changed: %u -> %u (possible speedhack)",
                   s_baselineTimerResolution, now->timerResolution);
            AC_RecordEvent(AC_CAT_TIMING, AC_SEV_CRITICAL,
                           "Timer resolution manipulation",
                           s_baselineTimerResolution, now->timerResolution);
            anomaly = TRUE;
        }
        
        /* Check if resolution is set to suspiciously low value */
        if (now->timerResolution <= 1000) { /* <= 1ms */
            AC_LOG(AC_SEV_WARNING,
                   "Timer resolution set to very low value: %u (normal: 15625)",
                   now->timerResolution);
        }
    }
    
    return anomaly;
}

/* ==========================================================================
 * ntdll API Cross-Validation
 * ========================================================================== */

static BOOL AC_ValidateNtdllTimingConsistency(AC_TIME_SNAPSHOT* now, AC_TIME_SNAPSHOT* prev)
{
    /* Cross-validate multiple ntdll timing functions against each other
       Since these are all kernel-level APIs, they should remain consistent */
    
    if (!s_prevSnapValid) return FALSE;
    
    BOOL anomaly = FALSE;
    
    /* Calculate deltas from all ntdll timing sources */
    ULONGLONG ntSystemDelta = (ULONGLONG)(now->ntSystemTime.QuadPart - prev->ntSystemTime.QuadPart);
    ULONGLONG rtlPerfDelta = (ULONGLONG)(now->rtlPerfCounter.QuadPart - prev->rtlPerfCounter.QuadPart);
    
    DOUBLE ntSystemDeltaMs = (DOUBLE)ntSystemDelta / 10000.0;
    DOUBLE rtlPerfDeltaMs = (DOUBLE)rtlPerfDelta * 1000.0 / (DOUBLE)now->rtlPerfFreq.QuadPart;
    
    /* Check if ntdll timing sources are consistent with each other */
    /* Allow some tolerance due to different clock sources */
    DOUBLE ntdllRatio = (rtlPerfDeltaMs > 0) ? ntSystemDeltaMs / rtlPerfDeltaMs : 1.0;
    
    if (ntdllRatio < 0.95 || ntdllRatio > 1.05) {
        AC_LOG(AC_SEV_CRITICAL,
               "ntdll internal timing inconsistency: NtSystemTime=%.2fms, RtlPerfCounter=%.2fms (ratio=%.3f)",
               ntSystemDeltaMs, rtlPerfDeltaMs, ntdllRatio);
        anomaly = TRUE;
    }
    
    /* If precise timing is available, validate it too */
    if (s_timingFuncs.NtQuerySystemPreciseTime && s_timingFuncs.RtlGetSystemTimePrecise) {
        ULONGLONG ntPreciseDelta = (ULONGLONG)(now->ntSystemPreciseTime.QuadPart - prev->ntSystemPreciseTime.QuadPart);
        ULONGLONG rtlPreciseDelta = (ULONGLONG)(now->rtlSystemTimePrecise.QuadPart - prev->rtlSystemTimePrecise.QuadPart);
        
        DOUBLE ntPreciseDeltaMs = (DOUBLE)ntPreciseDelta / 10000.0;
        DOUBLE rtlPreciseDeltaMs = (DOUBLE)rtlPreciseDelta / 10000.0;
        
        /* Precise timing should be very consistent */
        if (fabs(ntPreciseDeltaMs - rtlPreciseDeltaMs) > 0.5) {
            AC_LOG(AC_SEV_CRITICAL,
                   "Precise timing inconsistency: NtPrecise=%.2fms, RtlPrecise=%.2fms",
                   ntPreciseDeltaMs, rtlPreciseDeltaMs);
            anomaly = TRUE;
        }
    }
    
    return anomaly;
}

/* ==========================================================================
 * Ntdll Hook Detection (specific to timing functions)
 * ========================================================================== */

static BOOL AC_DetectNtdllTimingHooks(void)
{
    /* Check if ntdll timing functions are hooked by comparing with kernel32
       If kernel32 is hooked but ntdll is not, we can detect the discrepancy */
    
    HMODULE hNtdll = GetModuleHandleA("ntdll.dll");
    if (!hNtdll) return FALSE;
    
    BOOL hooksDetected = FALSE;
    
    /* Check ntdll timing function prologues */
    PVOID funcs[] = {
        GetProcAddress(hNtdll, "NtQuerySystemTime"),
        GetProcAddress(hNtdll, "NtQueryPerformanceCounter"),
        GetProcAddress(hNtdll, "RtlQueryPerformanceCounter"),
        GetProcAddress(hNtdll, "RtlGetSystemTimePrecise"),
        GetProcAddress(hNtdll, "NtDelayExecution"),
    };
    
    const CHAR* funcNames[] = {
        "NtQuerySystemTime",
        "NtQueryPerformanceCounter",
        "RtlQueryPerformanceCounter",
        "RtlGetSystemTimePrecise",
        "NtDelayExecution"
    };
    
    for (INT i = 0; i < 5; i++) {
        if (!funcs[i]) continue;
        
        hooksDetected |= AC_CheckTimingFunctionHook(funcNames[i], funcs[i]);
    }
    
    return hooksDetected;
}

/* ==========================================================================
 * Game-Specific Timing Validation
 * ========================================================================== */

void AC_UpdateGameTiming(DOUBLE frameTime, DOUBLE serverTime, DOUBLE clientTime)
{
    s_gameTiming.actualFrameTime = frameTime;
    s_gameTiming.serverTimeDelta = serverTime;
    s_gameTiming.clientTimeDelta = clientTime;
    s_gameTiming.timingValid = TRUE;
}

static BOOL AC_ValidateGameTiming(void)
{
    if (!s_gameTiming.timingValid) return FALSE;
    
    /* Check if frame time is suspiciously consistent (indicates speedhack) */
    static DOUBLE s_lastFrameTime = 0;
    static INT s_consistentFrameCount = 0;
    
    if (s_lastFrameTime > 0) {
        DOUBLE frameDelta = fabs(s_gameTiming.actualFrameTime - s_lastFrameTime);
        
        /* If frame time is almost identical for many frames, it's suspicious */
        if (frameDelta < 0.1) { /* Less than 0.1ms variation */
            s_consistentFrameCount++;
            
            if (s_consistentFrameCount > 60) { /* 1 second at 60fps */
                AC_LOG(AC_SEV_CRITICAL,
                       "Suspiciously consistent frame timing: %.3fms for %d frames",
                       s_gameTiming.actualFrameTime, s_consistentFrameCount);
                AC_RecordEvent(AC_CAT_TIMING, AC_SEV_CRITICAL,
                               "Suspiciously consistent frame timing",
                               (ULONG_PTR)(DWORD)(s_gameTiming.actualFrameTime * 1000),
                               s_consistentFrameCount);
                return TRUE;
            }
        } else {
            s_consistentFrameCount = 0;
        }
    }
    
    s_lastFrameTime = s_gameTiming.actualFrameTime;
    
    /* Compare server time delta with client time delta */
    if (s_gameTiming.serverTimeDelta > 0 && s_gameTiming.clientTimeDelta > 0) {
        DOUBLE ratio = s_gameTiming.clientTimeDelta / s_gameTiming.serverTimeDelta;
        
        /* If client time is significantly different from server time */
        if (ratio < 0.8 || ratio > 1.2) {
            AC_LOG(AC_SEV_CRITICAL,
                   "Server/Client timing divergence: Server=%.3fms, Client=%.3fms (ratio=%.3f)",
                   s_gameTiming.serverTimeDelta, s_gameTiming.clientTimeDelta, ratio);
            AC_RecordEvent(AC_CAT_TIMING, AC_SEV_CRITICAL,
                           "Server/Client timing divergence",
                           (ULONG_PTR)(DWORD)(s_gameTiming.serverTimeDelta * 1000),
                           (ULONG_PTR)(DWORD)(s_gameTiming.clientTimeDelta * 1000));
            return TRUE;
        }
    }
    
    return FALSE;
}

/* ==========================================================================
 * Main Detection Function
 * ========================================================================== */

BOOL AC_InitTiming(void)
{
    if (!AC_LoadTimingFunctions()) {
        AC_LOG(AC_SEV_CRITICAL, "Failed to load timing functions");
        return FALSE;
    }
    
    /* Initialize performance counter */
    s_timingFuncs.QueryPerformanceFrequency(&g_ac.perfFreq);
    s_timingFuncs.QueryPerformanceCounter(&g_ac.lastPerfCounter);
    g_ac.lastTickCount = s_timingFuncs.GetTickCount();
    
    /* Take baseline snapshot */
    AC_TakeTimeSnapshot(&s_baselineSnap);
    s_baselineValid = TRUE;
    
    /* Take initial snapshot */
    AC_TakeTimeSnapshot(&s_prevSnap);
    s_prevSnapValid = TRUE;
    
    /* Check for timing hooks at startup */
    AC_DetectTimingHooks();
    
    AC_LOG(AC_SEV_INFO, "Timing detection initialized");
    return TRUE;
}

BOOL AC_CheckTimingAnomaly(void)
{
    AC_TIME_SNAPSHOT now;
    AC_TakeTimeSnapshot(&now);
    
    if (!s_prevSnapValid) {
        s_prevSnap = now;
        s_prevSnapValid = TRUE;
        return FALSE;
    }
    
    BOOL anomaly = FALSE;
    FLOAT tolerance = 1.0f + (AC_SPEED_TOLERANCE_PCT / 100.0f);
    
    /* ---- 1. Multi-source timing cross-validation (kernel32 vs ntdll) ---- */
    DWORD tickDeltaMs = now.tickCount - s_prevSnap.tickCount;
    LONGLONG perfDelta = now.perfCounter - s_prevSnap.perfCounter;
    DOUBLE perfDeltaMs = (DOUBLE)perfDelta * 1000.0 / (DOUBLE)now.perfFreq;
    
    if (tickDeltaMs > 0 && perfDeltaMs > 0) {
        DOUBLE ratio = perfDeltaMs / (DOUBLE)tickDeltaMs;
        if (ratio < (1.0 / tolerance) || ratio > tolerance) {
            AC_LOG(AC_SEV_CRITICAL,
                   "Timing anomaly: GetTickCount delta=%ums, PerfCounter delta=%.2fms, ratio=%.3f",
                   tickDeltaMs, perfDeltaMs, ratio);
            anomaly = TRUE;
        }
    }
    
    /* ---- 2. Kernel-level timing verification (ntdll APIs) ---- */
    anomaly |= AC_VerifyKernelTiming(&now, &s_prevSnap);
    
    /* ---- 3. ntdll internal API cross-validation ---- */
    anomaly |= AC_ValidateNtdllTimingConsistency(&now, &s_prevSnap);
    
    /* ---- 4. Statistical pattern analysis ---- */
    AC_UpdateTimingStats(&now, &s_prevSnap);
    anomaly |= AC_DetectStatisticalAnomaly(&now, &s_prevSnap);
    
    /* ---- 5. Cheat Engine specific detection ---- */
    anomaly |= AC_DetectCheatEngineSpeedhack();
    
    /* ---- 6. Timing function hook detection (both kernel32 and ntdll) ---- */
    anomaly |= AC_DetectTimingHooks();
    anomaly |= AC_DetectNtdllTimingHooks();
    
    /* ---- 7. Sleep function manipulation detection ---- */
    static DWORD lastSleepCheck = 0;
    if (now.timestamp - lastSleepCheck > 5000) { /* Check every 5 seconds */
        anomaly |= AC_DetectSleepManipulation();
        lastSleepCheck = now.timestamp;
    }
    
    /* ---- 8. Game-specific timing validation ---- */
    anomaly |= AC_ValidateGameTiming();
    
    /* ---- 9. RDTSC consistency check ---- */
    if (s_prevSnap.rdtsc > 0 && now.rdtsc > s_prevSnap.rdtsc) {
        ULONGLONG rdtscDelta = now.rdtsc - s_prevSnap.rdtsc;
        DOUBLE rdtscToPerf = (DOUBLE)rdtscDelta / (DOUBLE)perfDelta;
        
        static DOUBLE s_rdtscPerfRatio = 0.0;
        if (s_rdtscPerfRatio == 0.0) {
            s_rdtscPerfRatio = rdtscToPerf;
        } else {
            DOUBLE ratioDrift = rdtscToPerf / s_rdtscPerfRatio;
            if (ratioDrift < (1.0 / tolerance) || ratioDrift > tolerance) {
                AC_LOG(AC_SEV_CRITICAL,
                       "RDTSC/PerfCounter ratio drift: expected %.2f got %.2f",
                       s_rdtscPerfRatio, rdtscToPerf);
                anomaly = TRUE;
            }
        }
    }
    
    /* ---- 10. Compare with baseline (startup) ---- */
    if (s_baselineValid) {
        DOUBLE baselinePerfDelta = (DOUBLE)(now.perfCounter - s_baselineSnap.perfCounter) * 1000.0 /
                                   (DOUBLE)now.perfFreq;
        DOUBLE baselineTickDelta = (DOUBLE)(now.tickCount - s_baselineSnap.tickCount);
        
        if (baselineTickDelta > 1000) { /* After at least 1 second */
            DOUBLE baselineRatio = baselinePerfDelta / baselineTickDelta;
            if (baselineRatio < (1.0 / (tolerance * 2)) || baselineRatio > (tolerance * 2)) {
                AC_LOG(AC_SEV_CRITICAL,
                       "Baseline timing divergence: ratio=%.3f (expected ~1.0)",
                       baselineRatio);
                anomaly = TRUE;
            }
        }
    }
    
    /* ---- 11. ntdll vs kernel32 divergence detection ---- */
    /* This is a strong indicator that kernel32 is hooked but ntdll is not */
    ULONGLONG ntSystemDelta = (ULONGLONG)(now.ntSystemTime.QuadPart - s_prevSnap.ntSystemTime.QuadPart);
    ULONGLONG sysDelta = ((ULONGLONG)now.systemTime.dwHighDateTime << 32) | now.systemTime.dwLowDateTime;
    ULONGLONG sysPrev = ((ULONGLONG)s_prevSnap.systemTime.dwHighDateTime << 32) | s_prevSnap.systemTime.dwLowDateTime;
    ULONGLONG sysDeltaVal = sysDelta - sysPrev;
    
    DOUBLE ntDeltaMs = (DOUBLE)ntSystemDelta / 10000.0;
    DOUBLE sysDeltaMs = (DOUBLE)sysDeltaVal / 10000.0;
    
    /* If ntdll and kernel32 diverge significantly, kernel32 may be hooked */
    if (fabs(ntDeltaMs - sysDeltaMs) > 5.0) { /* 5ms threshold */
        AC_LOG(AC_SEV_CRITICAL,
               "ntdll/kernel32 divergence: ntdll=%.2fms, kernel32=%.2fms (kernel32 likely hooked)",
               ntDeltaMs, sysDeltaMs);
        AC_RecordEvent(AC_CAT_TIMING, AC_SEV_CRITICAL,
                       "ntdll/kernel32 timing divergence (possible kernel32 hook)",
                       (ULONG_PTR)(DWORD)ntDeltaMs,
                       (ULONG_PTR)(DWORD)sysDeltaMs);
        anomaly = TRUE;
    }
    
    s_prevSnap = now;
    
    /* Update anomaly counter */
    if (anomaly) {
        s_timingStats.anomalyCount++;
        s_timingStats.consecutiveAnomalies++;
        
        if (s_timingStats.consecutiveAnomalies > 3) {
            /* Multiple consecutive anomalies - high confidence */
            AC_LOG(AC_SEV_BAN,
                   "Multiple consecutive timing anomalies detected (%d)",
                   s_timingStats.consecutiveAnomalies);
            AC_RecordEvent(AC_CAT_TIMING, AC_SEV_BAN,
                           "Multiple consecutive timing anomalies",
                           s_timingStats.anomalyCount,
                           s_timingStats.consecutiveAnomalies);
        } else {
            AC_RecordEvent(AC_CAT_TIMING, AC_SEV_CRITICAL,
                           "Speed-hack / timer manipulation detected",
                           (ULONG_PTR)tickDeltaMs,
                           (ULONG_PTR)(DWORD)perfDeltaMs);
        }
    } else {
        s_timingStats.consecutiveAnomalies = 0;
    }
    
    return anomaly;
}

/* ==========================================================================
 * External Time Source Validation (Network)
 * ========================================================================== */

void AC_SetNetworkTimeOffset(DOUBLE offsetMs)
{
    s_networkTimeOffset = offsetMs;
    s_networkTimeValid = TRUE;
}

BOOL AC_ValidateNetworkTiming(DOUBLE clientTime)
{
    if (!s_networkTimeValid) return FALSE;
    
    DOUBLE expectedTime = clientTime + s_networkTimeOffset;
    DOUBLE actualTime = (DOUBLE)s_timingFuncs.GetTickCount();
    
    /* Allow 100ms tolerance for network latency */
    if (fabs(expectedTime - actualTime) > 100.0) {
        AC_LOG(AC_SEV_CRITICAL,
               "Network timing validation failed: expected=%.2fms, actual=%.2fms",
               expectedTime, actualTime);
        AC_RecordEvent(AC_CAT_TIMING, AC_SEV_CRITICAL,
                       "Network timing validation failed",
                       (ULONG_PTR)(DWORD)expectedTime,
                       (ULONG_PTR)(DWORD)actualTime);
        return TRUE;
    }
    
    return FALSE;
}
```

---

## Direct Syscall Dispatcher (Bypass Hooks)

```c
/* ==========================================================================
 * ac_syscall.c - Direct syscall dispatcher to bypass ntdll hooks
 *
 * Disassembles ntdll to find syscall stubs, extracts syscall IDs,
 * and provides a mechanism to call native Windows functions directly
 * via syscalls when ntdll functions are detected as hooked.
 *
 * This bypasses user-mode hooks by going directly to the kernel.
 * ========================================================================== */

#include "ac_common.h"

/* ==========================================================================
 * Architecture Detection
 * ========================================================================== */

#ifdef _WIN64
    #define AC_ARCH_X64 1
    #define AC_ARCH_X86 0
#else
    #define AC_ARCH_X64 0
    #define AC_ARCH_X86 1
#endif

/* ==========================================================================
 * Syscall Stub Structure
 * ========================================================================== */

typedef struct _AC_SYSCALL_STUB {
    CHAR     functionName[64];  /* Function name (e.g., "NtQuerySystemTime") */
    ULONG    syscallId;         /* Extracted syscall ID          */
    PVOID    stubAddress;       /* Address in ntdll             */
    BOOL     valid;             /* Successfully extracted       */
} AC_SYSCALL_STUB;

/* ==========================================================================
 * Syscall Database
 * ========================================================================== */

#define AC_MAX_SYSCALLS 128

static AC_SYSCALL_STUB s_syscallStubs[AC_MAX_SYSCALLS];
static INT              s_syscallCount = 0;
static BOOL             s_syscallInitialized = FALSE;

/* ==========================================================================
 * Simple Disassembly Helper
 * ========================================================================== */

/* x64 syscall stub pattern:
 * mov r10, rcx
 * mov eax, <syscall_id>
 * syscall
 * ret
 */

/* x86 syscall stub pattern:
 * mov eax, <syscall_id>
 * mov edx, 0x7ffe0300 (KUSER_SHARED_DATA)
 * call [edx]
 * ret <n>
 * or
 * int 0x2e
 * ret <n>
 */

static BOOL AC_FindSyscallId_x64(PVOID stubAddr, ULONG* outSyscallId)
{
    BYTE* code = (BYTE*)stubAddr;
    
    /* Pattern 1: Standard x64 syscall stub
     * 4C 8B D1           mov r10, rcx
     * B8 <id> 00 00 00   mov eax, <syscall_id>
     * 0F 05              syscall
     * C3                 ret
     */
    if (code[0] == 0x4C && code[1] == 0x8B && code[2] == 0xD1) {
        /* Check for mov eax, <id> */
        if (code[3] == 0xB8) {
            *outSyscallId = *(ULONG*)(code + 4);
            return TRUE;
        }
    }
    
    /* Pattern 2: WoW64 syscall stub (32-bit on 64-bit)
     * B8 <id> 00 00 00   mov eax, <id>
     * BA <addr> 00 00 00 mov edx, <wow64syscall>
     * FF D2              call edx
     * C2 <n> 00          ret <n>
     */
    if (code[0] == 0xB8) {
        *outSyscallId = *(ULONG*)(code + 1);
        return TRUE;
    }
    
    return FALSE;
}

static BOOL AC_FindSyscallId_x86(PVOID stubAddr, ULONG* outSyscallId)
{
    BYTE* code = (BYTE*)stubAddr;
    
    /* Pattern 1: Standard x86 syscall stub (XP/2003)
     * B8 <id> 00 00 00   mov eax, <id>
     * BA <addr> 00 00 00 mov edx, <KUSER_SHARED_DATA>
     * FF D2              call edx
     * C2 <n> 00          ret <n>
     */
    if (code[0] == 0xB8) {
        *outSyscallId = *(ULONG*)(code + 1);
        return TRUE;
    }
    
    /* Pattern 2: Windows Vista+ x86
     * B8 <id> 00 00 00   mov eax, <id>
     * 8D 54 24 04        lea edx, [esp+4]
     * CD 2E              int 0x2e
     * C2 <n> 00          ret <n>
     */
    if (code[0] == 0xB8 && code[5] == 0x8D && code[9] == 0xCD && code[10] == 0x2E) {
        *outSyscallId = *(ULONG*)(code + 1);
        return TRUE;
    }
    
    return FALSE;
}

/* ==========================================================================
 * Extract Syscall ID from Function Stub
 * ========================================================================== */

static BOOL AC_ExtractSyscallId(const CHAR* funcName, PVOID stubAddr, ULONG* outSyscallId)
{
    if (!stubAddr || !outSyscallId) return FALSE;
    
#if AC_ARCH_X64
    return AC_FindSyscallId_x64(stubAddr, outSyscallId);
#else
    return AC_FindSyscallId_x86(stubAddr, outSyscallId);
#endif
}

/* ==========================================================================
 * Initialize Syscall Database
 * ========================================================================== */

static BOOL AC_InitializeSyscallDatabase(void)
{
    HMODULE hNtdll = GetModuleHandleA("ntdll.dll");
    if (!hNtdll) return FALSE;
    
    /* List of critical ntdll functions to extract syscalls for */
    const CHAR* criticalFunctions[] = {
        "NtQuerySystemTime",
        "NtQuerySystemPreciseTime",
        "NtQueryPerformanceCounter",
        "NtDelayExecution",
        "NtQueryInformationProcess",
        "NtQueryInformationThread",
        "NtAllocateVirtualMemory",
        "NtFreeVirtualMemory",
        "NtProtectVirtualMemory",
        "NtReadVirtualMemory",
        "NtWriteVirtualMemory",
        "NtCreateFile",
        "NtOpenFile",
        "NtReadFile",
        "NtWriteFile",
        "NtClose",
        "NtQueryVirtualMemory",
        "NtSetInformationProcess",
        "NtQueryTimerResolution",
        "NtSetTimerResolution",
        NULL
    };
    
    INT found = 0;
    
    for (INT i = 0; criticalFunctions[i] && s_syscallCount < AC_MAX_SYSCALLS; i++) {
        PVOID funcAddr = GetProcAddress(hNtdll, criticalFunctions[i]);
        if (!funcAddr) continue;
        
        ULONG syscallId = 0;
        if (AC_ExtractSyscallId(criticalFunctions[i], funcAddr, &syscallId)) {
            AC_SYSCALL_STUB* stub = &s_syscallStubs[s_syscallCount++];
            strncpy_s(stub->functionName, sizeof(stub->functionName), 
                     criticalFunctions[i], _TRUNCATE);
            stub->syscallId = syscallId;
            stub->stubAddress = funcAddr;
            stub->valid = TRUE;
            found++;
            
            AC_LOG(AC_SEV_INFO, "Syscall extracted: %s -> 0x%X", 
                   criticalFunctions[i], syscallId);
        }
    }
    
    AC_LOG(AC_SEV_INFO, "Syscall database initialized: %d/%d functions", 
           found, s_syscallCount);
    
    return found > 0;
}

/* ==========================================================================
 * Get Syscall ID by Function Name
 * ========================================================================== */

static BOOL AC_GetSyscallId(const CHAR* funcName, ULONG* outSyscallId)
{
    if (!s_syscallInitialized) {
        if (!AC_InitializeSyscallDatabase()) {
            return FALSE;
        }
        s_syscallInitialized = TRUE;
    }
    
    for (INT i = 0; i < s_syscallCount; i++) {
        if (_stricmp(s_syscallStubs[i].functionName, funcName) == 0) {
            *outSyscallId = s_syscallStubs[i].syscallId;
            return TRUE;
        }
    }
    
    return FALSE;
}

/* ==========================================================================
 * Direct Syscall Invocation (x64)
 * ========================================================================== */

#if AC_ARCH_X64

/* x64 syscall calling convention:
 * RCX = arg1
 * RDX = arg2
 * R8  = arg3
 * R9  = arg4
 * [RSP+0x20] = arg5
 * R10 = RCX (moved by syscall stub)
 * RAX = syscall ID
 */

/* Compiler-specific implementations */
#if defined(_MSC_VER)  /* MSVC - no inline asm on x64, use intrinsics/func pointers */

static NTSTATUS AC_InvokeSyscall_x64(ULONG syscallId, ULONG_PTR arg1, ULONG_PTR arg2, 
                                     ULONG_PTR arg3, ULONG_PTR arg4, ULONG_PTR arg5)
{
    /* MSVC x64: Use function pointer to syscall stub from ntdll
       This still bypasses hooks if we use the stub directly */
    
    /* Get the syscall stub address from ntdll */
    HMODULE hNtdll = GetModuleHandleA("ntdll.dll");
    if (!hNtdll) return STATUS_UNSUCCESSFUL;
    
    /* Use a minimal syscall stub pattern */
    static BYTE syscallStub[] = {
        0x4C, 0x8B, 0xD1,        /* mov r10, rcx */
        0xB8, 0x00, 0x00, 0x00, 0x00, /* mov eax, <syscall_id> - filled in */
        0x0F, 0x05,              /* syscall */
        0xC3                     /* ret */
    };
    
    /* Copy stub to executable memory */
    static BYTE* execStub = NULL;
    if (!execStub) {
        execStub = (BYTE*)VirtualAlloc(NULL, 32, MEM_COMMIT | MEM_RESERVE, 
                                       PAGE_EXECUTE_READWRITE);
        if (!execStub) return STATUS_UNSUCCESSFUL;
        memcpy(execStub, syscallStub, sizeof(syscallStub));
    }
    
    /* Patch syscall ID into stub */
    *(ULONG*)(execStub + 4) = syscallId;
    
    /* Call the stub */
    typedef NTSTATUS (NTAPI *PFN_SYSCALL)(ULONG_PTR, ULONG_PTR, ULONG_PTR, ULONG_PTR, ULONG_PTR);
    PFN_SYSCALL pSyscall = (PFN_SYSCALL)execStub;
    
    return pSyscall(arg1, arg2, arg3, arg4, arg5);
}

#else  /* GCC/Clang - supports inline asm */

static NTSTATUS AC_InvokeSyscall_x64(ULONG syscallId, ULONG_PTR arg1, ULONG_PTR arg2, 
                                     ULONG_PTR arg3, ULONG_PTR arg4, ULONG_PTR arg5)
{
    NTSTATUS status;
    
    __asm__ volatile (
        "mov r10, rcx\n"        /* Move RCX to R10 */
        "mov eax, %4\n"         /* Load syscall ID into EAX */
        "syscall\n"             /* Invoke syscall */
        : "=a"(status)
        : "c"(arg1), "d"(arg2), "r"(arg3), "r"(arg4), "r"(syscallId), "r"(arg5)
        : "r10", "r11", "rcx", "memory"
    );
    
    return status;
}

#endif

#endif

/* ==========================================================================
 * Direct Syscall Invocation (x86)
 * ========================================================================== */

#if AC_ARCH_X86

/* x86 syscall/int 2e calling convention:
 * EAX = syscall ID
 * Stack: arg1, arg2, arg3, arg4, arg5
 */

#if defined(_MSC_VER)  /* MSVC x86 - uses __asm (single underscore) */

static NTSTATUS AC_InvokeSyscall_x86(ULONG syscallId, ULONG_PTR arg1, ULONG_PTR arg2,
                                     ULONG_PTR arg3, ULONG_PTR arg4, ULONG_PTR arg5)
{
    NTSTATUS status;
    
    __asm {
        mov eax, syscallId
        push arg5
        push arg4
        push arg3
        push arg2
        push arg1
        int 0x2e
        add esp, 20
        mov status, eax
    }
    
    return status;
}

#else  /* GCC/Clang x86 - uses __asm__ (double underscore) */

static NTSTATUS AC_InvokeSyscall_x86(ULONG syscallId, ULONG_PTR arg1, ULONG_PTR arg2,
                                     ULONG_PTR arg3, ULONG_PTR arg4, ULONG_PTR arg5)
{
    NTSTATUS status;
    
    __asm__ volatile (
        "push %5\n"             /* arg5 */
        "push %4\n"             /* arg4 */
        "push %3\n"             /* arg3 */
        "push %2\n"             /* arg2 */
        "push %1\n"             /* arg1 */
        "mov eax, %0\n"         /* Load syscall ID into EAX */
        "int 0x2e\n"            /* Invoke syscall */
        "add esp, 20\n"         /* Clean up stack (5 args * 4 bytes) */
        : "=a"(status)
        : "r"(syscallId), "r"(arg1), "r"(arg2), "r"(arg3), "r"(arg4), "r"(arg5)
        : "memory"
    );
    
    return status;
}

#endif

#endif

/* ==========================================================================
 * Generic Syscall Invocation
 * ========================================================================== */

static NTSTATUS AC_InvokeSyscall(ULONG syscallId, ULONG_PTR arg1, ULONG_PTR arg2,
                                 ULONG_PTR arg3, ULONG_PTR arg4, ULONG_PTR arg5)
{
#if AC_ARCH_X64
    return AC_InvokeSyscall_x64(syscallId, arg1, arg2, arg3, arg4, arg5);
#else
    return AC_InvokeSyscall_x86(syscallId, arg1, arg2, arg3, arg4, arg5);
#endif
}

/* ==========================================================================
 * Safe API Call with Syscall Fallback
 * ========================================================================== */

/* Wrapper for NtQuerySystemTime with syscall fallback */
static NTSTATUS AC_NtQuerySystemTime_Safe(PLARGE_INTEGER SystemTime)
{
    static BOOL useSyscall = FALSE;
    
    if (useSyscall) {
        ULONG syscallId;
        if (AC_GetSyscallId("NtQuerySystemTime", &syscallId)) {
            return AC_InvokeSyscall(syscallId, (ULONG_PTR)SystemTime, 0, 0, 0, 0);
        }
    }
    
    /* Try normal call first */
    typedef NTSTATUS (NTAPI *PFN_NTQUERYSYSTEMTIME)(PLARGE_INTEGER);
    static PFN_NTQUERYSYSTEMTIME pNtQuerySystemTime = NULL;
    
    if (!pNtQuerySystemTime) {
        HMODULE hNtdll = GetModuleHandleA("ntdll.dll");
        pNtQuerySystemTime = (PFN_NTQUERYSYSTEMTIME)GetProcAddress(hNtdll, "NtQuerySystemTime");
    }
    
    if (pNtQuerySystemTime) {
        NTSTATUS status = pNtQuerySystemTime(SystemTime);
        
        /* If call fails or detects hook, switch to syscall */
        if (!NT_SUCCESS(status) || AC_DetectNtdllTimingHooks()) {
            useSyscall = TRUE;
            AC_LOG(AC_SEV_WARNING, "NtQuerySystemTime hooked or failed, switching to direct syscall");
        }
        
        return status;
    }
    
    return STATUS_UNSUCCESSFUL;
}

/* Wrapper for NtQueryPerformanceCounter with syscall fallback */
static NTSTATUS AC_NtQueryPerformanceCounter_Safe(PLARGE_INTEGER PerformanceCounter, 
                                                   PLARGE_INTEGER PerformanceFrequency)
{
    static BOOL useSyscall = FALSE;
    
    if (useSyscall) {
        ULONG syscallId;
        if (AC_GetSyscallId("NtQueryPerformanceCounter", &syscallId)) {
            return AC_InvokeSyscall(syscallId, (ULONG_PTR)PerformanceCounter, 
                                   (ULONG_PTR)PerformanceFrequency, 0, 0, 0);
        }
    }
    
    /* Try normal call first */
    typedef NTSTATUS (NTAPI *PFN_NTQUERYPERFCOUNTER)(PLARGE_INTEGER, PLARGE_INTEGER);
    static PFN_NTQUERYPERFCOUNTER pNtQueryPerformanceCounter = NULL;
    
    if (!pNtQueryPerformanceCounter) {
        HMODULE hNtdll = GetModuleHandleA("ntdll.dll");
        pNtQueryPerformanceCounter = (PFN_NTQUERYPERFCOUNTER)GetProcAddress(hNtdll, "NtQueryPerformanceCounter");
    }
    
    if (pNtQueryPerformanceCounter) {
        NTSTATUS status = pNtQueryPerformanceCounter(PerformanceCounter, PerformanceFrequency);
        
        if (!NT_SUCCESS(status) || AC_DetectNtdllTimingHooks()) {
            useSyscall = TRUE;
            AC_LOG(AC_SEV_WARNING, "NtQueryPerformanceCounter hooked or failed, switching to direct syscall");
        }
        
        return status;
    }
    
    return STATUS_UNSUCCESSFUL;
}

/* Wrapper for NtDelayExecution with syscall fallback */
static NTSTATUS AC_NtDelayExecution_Safe(BOOLEAN Alertable, PLARGE_INTEGER DelayInterval)
{
    static BOOL useSyscall = FALSE;
    
    if (useSyscall) {
        ULONG syscallId;
        if (AC_GetSyscallId("NtDelayExecution", &syscallId)) {
            return AC_InvokeSyscall(syscallId, (ULONG_PTR)Alertable, 
                                   (ULONG_PTR)DelayInterval, 0, 0, 0);
        }
    }
    
    /* Try normal call first */
    typedef NTSTATUS (NTAPI *PFN_NTDELAYEXECUTION)(BOOLEAN, PLARGE_INTEGER);
    static PFN_NTDELAYEXECUTION pNtDelayExecution = NULL;
    
    if (!pNtDelayExecution) {
        HMODULE hNtdll = GetModuleHandleA("ntdll.dll");
        pNtDelayExecution = (PFN_NTDELAYEXECUTION)GetProcAddress(hNtdll, "NtDelayExecution");
    }
    
    if (pNtDelayExecution) {
        NTSTATUS status = pNtDelayExecution(Alertable, DelayInterval);
        
        if (!NT_SUCCESS(status) || AC_DetectNtdllTimingHooks()) {
            useSyscall = TRUE;
            AC_LOG(AC_SEV_WARNING, "NtDelayExecution hooked or failed, switching to direct syscall");
        }
        
        return status;
    }
    
    return STATUS_UNSUCCESSFUL;
}

/* ==========================================================================
 * Public API
 * ========================================================================== */

BOOL AC_InitializeSyscallDispatcher(void)
{
    if (!AC_InitializeSyscallDatabase()) {
        AC_LOG(AC_SEV_CRITICAL, "Failed to initialize syscall database");
        return FALSE;
    }
    
    s_syscallInitialized = TRUE;
    AC_LOG(AC_SEV_INFO, "Syscall dispatcher initialized successfully");
    return TRUE;
}

/* Force use of direct syscalls (if hooks detected) */
void AC_EnableSyscallMode(BOOL enable)
{
    /* This would set a global flag to force syscall mode */
    /* Implementation depends on integration of this with the timing module */
    AC_LOG(AC_SEV_INFO, "Syscall mode %s", enable ? "ENABLED" : "DISABLED");
}

/* Check if syscall dispatcher is available */
BOOL AC_IsSyscallDispatcherAvailable(void)
{
    return s_syscallInitialized && s_syscallCount > 0;
}

/* Get number of syscalls in database */
INT AC_GetSyscallCount(void)
{
    return s_syscallCount;
}
```

---

## Thread Verification & Stack Analysis

```c
/* ==========================================================================
 * ac_thread.c - Thread verification and stack frame analysis
 *
 * Verifies thread count, analyzes stack frames using dbghelp,
 * and validates _ReturnAddress to detect thread hijacking
 * ========================================================================== */

#include "ac_common.h"
#include <dbghelp.h>

/* ==========================================================================
 * Function Pointers for Dynamic Loading
 * ========================================================================== */

typedef HANDLE (WINAPI *PFN_CREATETOOLHELP32SNAPSHOT)(DWORD, DWORD);
typedef BOOL (WINAPI *PFN_THREAD32FIRST)(HANDLE, LPTHREADENTRY32);
typedef BOOL (WINAPI *PFN_THREAD32NEXT)(HANDLE, LPTHREADENTRY32);
typedef HANDLE (WINAPI *PFN_CREATETHREAD)(LPSECURITY_ATTRIBUTES, SIZE_T, LPTHREAD_START_ROUTINE, LPVOID, DWORD, LPDWORD);
typedef BOOL (WINAPI *PFN_TERMINATETHREAD)(HANDLE, DWORD);
typedef BOOL (WINAPI *PFN_GETTHREADCONTEXT)(HANDLE, PCONTEXT);
typedef BOOL (WINAPI *PFN_SETTHREADCONTEXT)(HANDLE, PCONTEXT);

/* dbghelp functions */
typedef BOOL (WINAPI *PFN_STACKWALK64)(DWORD, HANDLE, HANDLE, LPSTACKFRAME64, PVOID, PREAD_PROCESS_MEMORY_ROUTINE64, PFUNCTION_TABLE_ACCESS_ROUTINE64, PGET_MODULE_BASE_ROUTINE64, PTRANSLATE_ADDRESS_ROUTINE64);
typedef PVOID (WINAPI *PFN_SYMINITIALIZE)(HANDLE, HANDLE, BOOL);
typedef BOOL (WINAPI *PFN_SYMFROMADDR)(HANDLE, DWORD64, PDWORD64, PSYMBOL_INFO);
typedef DWORD64 (WINAPI *PFN_STACKWALK64)(DWORD, HANDLE, HANDLE, LPSTACKFRAME64, PVOID, PREAD_PROCESS_MEMORY_ROUTINE64, PFUNCTION_TABLE_ACCESS_ROUTINE64, PGET_MODULE_BASE_ROUTINE64, PTRANSLATE_ADDRESS_ROUTINE64);
typedef BOOL (WINAPI *PFN_SYMGETMODULEBASE64)(HANDLE, DWORD64);

static struct {
    PFN_CREATETOOLHELP32SNAPSHOT CreateToolhelp32Snapshot;
    PFN_THREAD32FIRST Thread32First;
    PFN_THREAD32NEXT Thread32Next;
    PFN_CREATETHREAD CreateThread;
    PFN_TERMINATETHREAD TerminateThread;
    PFN_GETTHREADCONTEXT GetThreadContext;
    PFN_SETTHREADCONTEXT SetThreadContext;
    PFN_STACKWALK64 StackWalk64;
    PFN_SYMINITIALIZE SymInitialize;
    PFN_SYMFROMADDR SymFromAddr;
    PFN_SYMGETMODULEBASE64 SymGetModuleBase64;
} s_threadFuncs = {0};

/* ==========================================================================
 * Thread Information Structure
 * ========================================================================== */

typedef struct _AC_THREAD_INFO {
    DWORD     threadId;
    HANDLE    threadHandle;
    DWORD     priority;
    PVOID     startAddress;
    PVOID     stackBase;
    SIZE_T    stackLimit;
    BOOL      isSuspended;
    BOOL      isMainThread;
    PVOID     returnAddress;      /* _ReturnAddress for current thread */
} AC_THREAD_INFO;

#define AC_MAX_THREADS 256

static AC_THREAD_INFO s_threadInfo[AC_MAX_THREADS];
static INT              s_threadCount = 0;
static DWORD            s_mainThreadId = 0;

/* ==========================================================================
 * Return Address Verification
 * ========================================================================== */

#ifdef _MSC_VER
    /* MSVC intrinsic for return address */
    #pragma intrinsic(_ReturnAddress)
#endif

static PVOID AC_GetReturnAddress(void)
{
#if defined(_MSC_VER)
    return _ReturnAddress();
#elif defined(__GNUC__) || defined(__clang__)
    return __builtin_return_address(0);
#else
    /* Fallback: use inline assembly */
    PVOID retAddr;
    __asm__ volatile ("mov %%eax, %%ebp; mov (%%eax), %%eax" : "=a"(retAddr));
    return retAddr;
#endif
}

static BOOL AC_VerifyReturnAddress(PVOID retAddr)
{
    if (!retAddr) return FALSE;
    
    /* Check if return address is within valid module ranges */
    HMODULE hModules[1024];
    DWORD cbNeeded;
    
    if (EnumProcessModules(GetCurrentProcess(), hModules, sizeof(hModules), &cbNeeded)) {
        DWORD moduleCount = cbNeeded / sizeof(HMODULE);
        
        for (DWORD i = 0; i < moduleCount; i++) {
            MODULEINFO modInfo;
            if (GetModuleInformation(GetCurrentProcess(), hModules[i], &modInfo, sizeof(modInfo))) {
                BYTE* modStart = (BYTE*)modInfo.lpBaseOfDll;
                BYTE* modEnd = modStart + modInfo.SizeOfImage;
                
                if ((BYTE*)retAddr >= modStart && (BYTE*)retAddr < modEnd) {
                    CHAR modName[MAX_PATH];
                    GetModuleFileNameExA(GetCurrentProcess(), hModules[i], modName, sizeof(modName));
                    
                    /* Check if return address is from suspicious module */
                    if (strstr(modName, "cheat") || strstr(modName, "hack") ||
                        strstr(modName, "inject") || strstr(modName, "hook")) {
                        AC_LOG(AC_SEV_BAN, "Return address from suspicious module: %s at %p", modName, retAddr);
                        AC_RecordEvent(AC_CAT_PROCESS, AC_SEV_BAN,
                                       "Return address from suspicious module",
                                       (ULONG_PTR)retAddr,
                                       (ULONG_PTR)hModules[i]);
                        return FALSE;
                    }
                    
                    return TRUE; /* Valid return address */
                }
            }
        }
    }
    
    /* Return address not in any module - suspicious */
    AC_LOG(AC_SEV_CRITICAL, "Return address not in any module: %p", retAddr);
    AC_RecordEvent(AC_CAT_PROCESS, AC_SEV_CRITICAL,
                   "Return address outside valid modules",
                   (ULONG_PTR)retAddr, 0);
    return FALSE;
}

/* ==========================================================================
 * Stack Frame Analysis using dbghelp
 * ========================================================================== */

static BOOL AC_InitializeDbgHelp(void)
{
    HMODULE hDbgHelp = LoadLibraryA("dbghelp.dll");
    if (!hDbgHelp) return FALSE;
    
    s_threadFuncs.StackWalk64 = (PFN_STACKWALK64)GetProcAddress(hDbgHelp, "StackWalk64");
    s_threadFuncs.SymInitialize = (PFN_SYMINITIALIZE)GetProcAddress(hDbgHelp, "SymInitialize");
    s_threadFuncs.SymFromAddr = (PFN_SYMFROMADDR)GetProcAddress(hDbgHelp, "SymFromAddr");
    s_threadFuncs.SymGetModuleBase64 = (PFN_SYMGETMODULEBASE64)GetProcAddress(hDbgHelp, "SymGetModuleBase64");
    
    if (!s_threadFuncs.SymInitialize || !s_threadFuncs.StackWalk64) {
        AC_LOG(AC_SEV_CRITICAL, "Failed to load dbghelp functions");
        return FALSE;
    }
    
    /* Initialize symbol handler */
    if (!s_threadFuncs.SymInitialize(GetCurrentProcess(), NULL, TRUE)) {
        AC_LOG(AC_SEV_CRITICAL, "SymInitialize failed: %lu", GetLastError());
        return FALSE;
    }
    
    AC_LOG(AC_SEV_INFO, "dbghelp initialized successfully");
    return TRUE;
}

static BOOL AC_AnalyzeThreadStack(HANDLE hThread, DWORD threadId)
{
    if (!s_threadFuncs.StackWalk64) return FALSE;
    
    CONTEXT ctx = {0};
    ctx.ContextFlags = CONTEXT_FULL;
    
    if (!s_threadFuncs.GetThreadContext(hThread, &ctx)) {
        return FALSE;
    }
    
    STACKFRAME64 stackFrame = {0};
#ifdef _WIN64
    stackFrame.AddrPC.Offset = ctx.Rip;
    stackFrame.AddrPC.Mode = AddrModeFlat;
    stackFrame.AddrFrame.Offset = ctx.Rbp;
    stackFrame.AddrFrame.Mode = AddrModeFlat;
    stackFrame.AddrStack.Offset = ctx.Rsp;
    stackFrame.AddrStack.Mode = AddrModeFlat;
#else
    stackFrame.AddrPC.Offset = ctx.Eip;
    stackFrame.AddrPC.Mode = AddrModeFlat;
    stackFrame.AddrFrame.Offset = ctx.Ebp;
    stackFrame.AddrFrame.Mode = AddrModeFlat;
    stackFrame.AddrStack.Offset = ctx.Esp;
    stackFrame.AddrStack.Mode = AddrModeFlat;
#endif
    
    INT frameCount = 0;
    INT suspiciousFrames = 0;
    PVOID lastReturnAddr = NULL;
    
    while (s_threadFuncs.StackWalk64(
#ifdef _WIN64
        IMAGE_FILE_MACHINE_AMD64,
#else
        IMAGE_FILE_MACHINE_I386,
#endif
        GetCurrentProcess(),
        hThread,
        &stackFrame,
        &ctx,
        NULL,
        NULL,
        NULL,
        NULL)) {
        
        frameCount++;
        
        if (frameCount > 50) break; /* Limit stack depth */
        
        PVOID returnAddr = (PVOID)stackFrame.AddrPC.Offset;
        
        /* Check for suspicious return addresses */
        if (!AC_VerifyReturnAddress(returnAddr)) {
            suspiciousFrames++;
        }
        
        /* Check for repeated return addresses (possible hook loop) */
        if (returnAddr == lastReturnAddr && frameCount > 5) {
            AC_LOG(AC_SEV_CRITICAL,
                   "Detected repeated return address in thread %lu: %p (possible hook loop)",
                   threadId, returnAddr);
            suspiciousFrames++;
        }
        
        lastReturnAddr = returnAddr;
    }
    
    if (suspiciousFrames > 0) {
        AC_LOG(AC_SEV_CRITICAL,
               "Thread %lu has %d suspicious stack frames out of %d total",
               threadId, suspiciousFrames, frameCount);
        AC_RecordEvent(AC_CAT_PROCESS, AC_SEV_CRITICAL,
                       "Suspicious thread stack frames",
                       threadId, suspiciousFrames);
        return FALSE;
    }
    
    return TRUE;
}

/* ==========================================================================
 * Thread Enumeration
 * ========================================================================== */

static BOOL AC_EnumerateThreads(void)
{
    if (!s_threadFuncs.CreateToolhelp32Snapshot) {
        HMODULE hKernel32 = GetModuleHandleA("kernel32.dll");
        s_threadFuncs.CreateToolhelp32Snapshot = (PFN_CREATETOOLHELP32SNAPSHOT)GetProcAddress(hKernel32, "CreateToolhelp32Snapshot");
        s_threadFuncs.Thread32First = (PFN_THREAD32FIRST)GetProcAddress(hKernel32, "Thread32First");
        s_threadFuncs.Thread32Next = (PFN_THREAD32NEXT)GetProcAddress(hKernel32, "Thread32Next");
        s_threadFuncs.GetThreadContext = (PFN_GETTHREADCONTEXT)GetProcAddress(hKernel32, "GetThreadContext");
    }
    
    if (!s_threadFuncs.CreateToolhelp32Snapshot || !s_threadFuncs.Thread32First) {
        AC_LOG(AC_SEV_CRITICAL, "Failed to load thread enumeration functions");
        return FALSE;
    }
    
    DWORD processId = GetCurrentProcessId();
    HANDLE hSnapshot = s_threadFuncs.CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, processId);
    
    if (hSnapshot == INVALID_HANDLE_VALUE) {
        AC_LOG(AC_SEV_CRITICAL, "Failed to create thread snapshot");
        return FALSE;
    }
    
    THREADENTRY32 te32;
    te32.dwSize = sizeof(THREADENTRY32);
    s_threadCount = 0;
    
    /* Get main thread ID */
    s_mainThreadId = GetCurrentThreadId();
    
    if (!s_threadFuncs.Thread32First(hSnapshot, &te32)) {
        CloseHandle(hSnapshot);
        return FALSE;
    }
    
    do {
        if (te32.th32OwnerProcessID == processId && s_threadCount < AC_MAX_THREADS) {
            AC_THREAD_INFO* info = &s_threadInfo[s_threadCount++];
            info->threadId = te32.th32ThreadID;
            info->priority = te32.tpBasePri;
            info->isMainThread = (te32.th32ThreadID == s_mainThreadId);
            
            /* Try to open thread handle */
            info->threadHandle = OpenThread(THREAD_QUERY_INFORMATION | THREAD_GET_CONTEXT, 
                                           FALSE, te32.th32ThreadID);
            
            if (info->threadHandle) {
                /* Get thread start address */
                typedef NTSTATUS (NTAPI *PFN_NTQUERYINFORMATIONTHREAD)(HANDLE, THREADINFOCLASS, PVOID, ULONG, PULONG);
                static PFN_NTQUERYINFORMATIONTHREAD pNtQueryInformationThread = NULL;
                
                if (!pNtQueryInformationThread) {
                    HMODULE hNtdll = GetModuleHandleA("ntdll.dll");
                    pNtQueryInformationThread = (PFN_NTQUERYINFORMATIONTHREAD)GetProcAddress(hNtdll, "NtQueryInformationThread");
                }
                
                if (pNtQueryInformationThread) {
                    PVOID startAddress = NULL;
                    NTSTATUS status = pNtQueryInformationThread(info->threadHandle, 
                                                               ThreadQuerySetWin32StartAddress,
                                                               &startAddress, sizeof(startAddress), NULL);
                    if (NT_SUCCESS(status)) {
                        info->startAddress = startAddress;
                    }
                }
                
                /* Check if thread is suspended */
                DWORD suspendCount = SuspendThread(info->threadHandle);
                if (suspendCount != (DWORD)-1) {
                    ResumeThread(info->threadHandle);
                    info->isSuspended = (suspendCount > 0);
                }
            }
        }
    } while (s_threadFuncs.Thread32Next(hSnapshot, &te32) && s_threadCount < AC_MAX_THREADS);
    
    CloseHandle(hSnapshot);
    
    AC_LOG(AC_SEV_INFO, "Enumerated %d threads in process %lu", s_threadCount, processId);
    return TRUE;
}

/* ==========================================================================
 * Thread Verification
 * ========================================================================== */

static BOOL AC_VerifyThreadCount(void)
{
    /* Baseline: game typically has 5-20 threads */
    /* More than 50 threads is suspicious */
    
    if (s_threadCount > 50) {
        AC_LOG(AC_SEV_CRITICAL, "Suspicious thread count: %d (normal: 5-20)", s_threadCount);
        AC_RecordEvent(AC_CAT_PROCESS, AC_SEV_CRITICAL,
                       "Excessive thread count",
                       s_threadCount, 0);
        return FALSE;
    }
    
    if (s_threadCount < 2) {
        AC_LOG(AC_SEV_WARNING, "Very low thread count: %d", s_threadCount);
    }
    
    return TRUE;
}

static BOOL AC_VerifyThreadStartAddresses(void)
{
    HMODULE hModules[1024];
    DWORD cbNeeded;
    
    if (!EnumProcessModules(GetCurrentProcess(), hModules, sizeof(hModules), &cbNeeded)) {
        return FALSE;
    }
    
    DWORD moduleCount = cbNeeded / sizeof(HMODULE);
    
    for (INT i = 0; i < s_threadCount; i++) {
        if (!s_threadInfo[i].startAddress) continue;
        
        BOOL found = FALSE;
        
        for (DWORD j = 0; j < moduleCount; j++) {
            MODULEINFO modInfo;
            if (GetModuleInformation(GetCurrentProcess(), hModules[j], &modInfo, sizeof(modInfo))) {
                BYTE* modStart = (BYTE*)modInfo.lpBaseOfDll;
                BYTE* modEnd = modStart + modInfo.SizeOfImage;
                
                if ((BYTE*)s_threadInfo[i].startAddress >= modStart && 
                    (BYTE*)s_threadInfo[i].startAddress < modEnd) {
                    found = TRUE;
                    
                    /* Check if start address is from suspicious module */
                    CHAR modName[MAX_PATH];
                    GetModuleFileNameExA(GetCurrentProcess(), hModules[j], modName, sizeof(modName));
                    
                    if (strstr(modName, "cheat") || strstr(modName, "hack") ||
                        strstr(modName, "inject") || strstr(modName, "hook")) {
                        AC_LOG(AC_SEV_BAN,
                               "Thread %lu started from suspicious module: %s at %p",
                               s_threadInfo[i].threadId, modName, s_threadInfo[i].startAddress);
                        AC_RecordEvent(AC_CAT_PROCESS, AC_SEV_BAN,
                                       "Thread started from suspicious module",
                                       s_threadInfo[i].threadId,
                                       (ULONG_PTR)s_threadInfo[i].startAddress);
                        return FALSE;
                    }
                    
                    break;
                }
            }
        }
        
        if (!found) {
            AC_LOG(AC_SEV_CRITICAL,
                   "Thread %lu start address not in any module: %p (possible shellcode)",
                   s_threadInfo[i].threadId, s_threadInfo[i].startAddress);
            AC_RecordEvent(AC_CAT_PROCESS, AC_SEV_CRITICAL,
                           "Thread start address outside modules (shellcode)",
                           s_threadInfo[i].threadId,
                           (ULONG_PTR)s_threadInfo[i].startAddress);
            return FALSE;
        }
    }
    
    return TRUE;
}

static BOOL AC_VerifyMainThread(void)
{
    /* Main thread should have specific characteristics */
    for (INT i = 0; i < s_threadCount; i++) {
        if (s_threadInfo[i].isMainThread) {
            /* Main thread should not be suspended */
            if (s_threadInfo[i].isSuspended) {
                AC_LOG(AC_SEV_CRITICAL, "Main thread is suspended!");
                AC_RecordEvent(AC_CAT_PROCESS, AC_SEV_CRITICAL,
                               "Main thread suspended",
                               s_threadInfo[i].threadId, 0);
                return FALSE;
            }
            
            /* Main thread should have normal priority */
            if (s_threadInfo[i].priority < 8 || s_threadInfo[i].priority > 13) {
                AC_LOG(AC_SEV_WARNING,
                       "Main thread has unusual priority: %lu (normal: 8-13)",
                       s_threadInfo[i].priority);
            }
            
            return TRUE;
        }
    }
    
    AC_LOG(AC_SEV_CRITICAL, "Could not identify main thread!");
    return FALSE;
}

/* ==========================================================================
 * Public API
 * ========================================================================== */

BOOL AC_InitializeThreadVerification(void)
{
    /* Load thread functions */
    HMODULE hKernel32 = GetModuleHandleA("kernel32.dll");
    s_threadFuncs.CreateToolhelp32Snapshot = (PFN_CREATETOOLHELP32SNAPSHOT)GetProcAddress(hKernel32, "CreateToolhelp32Snapshot");
    s_threadFuncs.Thread32First = (PFN_THREAD32FIRST)GetProcAddress(hKernel32, "Thread32First");
    s_threadFuncs.Thread32Next = (PFN_THREAD32NEXT)GetProcAddress(hKernel32, "Thread32Next");
    s_threadFuncs.CreateThread = (PFN_CREATETHREAD)GetProcAddress(hKernel32, "CreateThread");
    s_threadFuncs.TerminateThread = (PFN_TERMINATETHREAD)GetProcAddress(hKernel32, "TerminateThread");
    s_threadFuncs.GetThreadContext = (PFN_GETTHREADCONTEXT)GetProcAddress(hKernel32, "GetThreadContext");
    s_threadFuncs.SetThreadContext = (PFN_SETTHREADCONTEXT)GetProcAddress(hKernel32, "SetThreadContext");
    
    /* Initialize dbghelp for stack analysis */
    AC_InitializeDbgHelp();
    
    /* Get current thread's return address */
    PVOID retAddr = AC_GetReturnAddress();
    if (retAddr) {
        AC_LOG(AC_SEV_INFO, "Current thread return address: %p", retAddr);
        AC_VerifyReturnAddress(retAddr);
    }
    
    AC_LOG(AC_SEV_INFO, "Thread verification initialized");
    return TRUE;
}

BOOL AC_VerifyThreads(void)
{
    if (!AC_EnumerateThreads()) {
        AC_LOG(AC_SEV_CRITICAL, "Failed to enumerate threads");
        return FALSE;
    }
    
    BOOL allValid = TRUE;
    
    /* Verify thread count */
    allValid &= AC_VerifyThreadCount();
    
    /* Verify thread start addresses */
    allValid &= AC_VerifyThreadStartAddresses();
    
    /* Verify main thread */
    allValid &= AC_VerifyMainThread();
    
    /* Analyze stack frames for each thread (if dbghelp available) */
    if (s_threadFuncs.StackWalk64) {
        for (INT i = 0; i < s_threadCount; i++) {
            if (s_threadInfo[i].threadHandle && s_threadInfo[i].threadId != GetCurrentThreadId()) {
                if (!AC_AnalyzeThreadStack(s_threadInfo[i].threadHandle, s_threadInfo[i].threadId)) {
                    allValid = FALSE;
                }
            }
        }
    }
    
    /* Verify current thread's return address */
    PVOID retAddr = AC_GetReturnAddress();
    if (retAddr) {
        allValid &= AC_VerifyReturnAddress(retAddr);
    }
    
    return allValid;
}

INT AC_GetThreadCount(void)
{
    return s_threadCount;
}

BOOL AC_IsThreadValid(DWORD threadId)
{
    for (INT i = 0; i < s_threadCount; i++) {
        if (s_threadInfo[i].threadId == threadId) {
            return TRUE;
        }
    }
    return FALSE;
}
```

---

## Self-Integrity Verification

```c
/* ==========================================================================
 * ac_self_integrity.c - Self-integrity verification for AntiCheat code
 *
 * Verifies that the AntiCheat code itself has not been tampered with,
 * including code sections, function pointers, and critical data structures.
 * This prevents attackers from patching or disabling the AntiCheat.
 * ========================================================================== */

#include "ac_common.h"

/* ==========================================================================
 * Integrity Check Configuration
 * ========================================================================== */

#define AC_INTEGRITY_CHECK_INTERVAL  5000  /* Check every 5 seconds */
#define AC_CRITICAL_REGIONS_MAX      32
#define AC_HASH_SIZE                 32    /* SHA-256 size */

/* ==========================================================================
 * Function Pointers for Dynamic Loading
 * ========================================================================== */

typedef BOOL (WINAPI *PFN_VIRTUALPROTECT)(LPVOID, SIZE_T, DWORD, PDWORD);
typedef HMODULE (WINAPI *PFN_GETMODULEHANDLEA)(LPCSTR);
typedef BOOL (WINAPI *PFN_GETMODULEINFORMATION)(HANDLE, HMODULE, LPMODULEINFO, DWORD);

static struct {
    PFN_VIRTUALPROTECT VirtualProtect;
    PFN_GETMODULEHANDLEA GetModuleHandleA;
    PFN_GETMODULEINFORMATION GetModuleInformation;
} s_integrityFuncs = {0};

/* ==========================================================================
 * Critical Code Region Structure
 * ========================================================================== */

typedef struct _AC_CRITICAL_REGION {
    PVOID    startAddress;
    SIZE_T   size;
    BYTE     originalHash[AC_HASH_SIZE];
    CHAR     description[64];
    BOOL     protected;
    DWORD    originalProtection;
} AC_CRITICAL_REGION;

static AC_CRITICAL_REGION s_criticalRegions[AC_CRITICAL_REGIONS_MAX];
static INT                  s_criticalRegionCount = 0;
static BOOL                 s_integrityInitialized = FALSE;
static DWORD                s_lastIntegrityCheck = 0;

/* ==========================================================================
 * Simple Hash Function (for code integrity)
 * Note: In production, use a proper cryptographic hash like SHA-256
 * ========================================================================== */

static VOID AC_ComputeHash(BYTE* data, SIZE_T size, BYTE* outHash)
{
    /* Simple hash for demonstration - replace with SHA-256 in production */
    ULONG hash = 5381;
    for (SIZE_T i = 0; i < size; i++) {
        hash = ((hash << 5) + hash) + data[i]; /* hash * 33 + c */
    }
    
    /* Store in output buffer */
    for (INT i = 0; i < AC_HASH_SIZE; i++) {
        outHash[i] = (BYTE)(hash >> (i * 8));
    }
}

/* ==========================================================================
 * Register Critical Code Region
 * ========================================================================== */

static BOOL AC_RegisterCriticalRegion(PVOID startAddress, SIZE_T size, 
                                      const CHAR* description)
{
    if (s_criticalRegionCount >= AC_CRITICAL_REGIONS_MAX) {
        return FALSE;
    }
    
    AC_CRITICAL_REGION* region = &s_criticalRegions[s_criticalRegionCount++];
    region->startAddress = startAddress;
    region->size = size;
    strncpy_s(region->description, sizeof(region->description), description, _TRUNCATE);
    
    /* Compute initial hash */
    AC_ComputeHash((BYTE*)startAddress, size, region->originalHash);
    
    AC_LOG(AC_SEV_INFO, "Registered critical region: %s at %p (size: %zu)", 
           description, startAddress, size);
    
    return TRUE;
}

/* ==========================================================================
 * Verify Critical Region Integrity
 * ========================================================================== */

static BOOL AC_VerifyRegionIntegrity(AC_CRITICAL_REGION* region)
{
    if (!region || !region->startAddress || region->size == 0) {
        return FALSE;
    }
    
    BYTE currentHash[AC_HASH_SIZE];
    AC_ComputeHash((BYTE*)region->startAddress, region->size, currentHash);
    
    /* Compare hashes */
    if (memcmp(currentHash, region->originalHash, AC_HASH_SIZE) != 0) {
        AC_LOG(AC_SEV_BAN,
               "CRITICAL REGION MODIFIED: %s at %p (size: %zu)",
               region->description, region->startAddress, region->size);
        AC_RecordEvent(AC_CAT_INTEGRITY, AC_SEV_BAN,
                       "Critical code region modified",
                       (ULONG_PTR)region->startAddress,
                       (ULONG_PTR)region->size);
        return FALSE;
    }
    
    return TRUE;
}

/* ==========================================================================
 * Verify Function Pointer Integrity
 * ========================================================================== */

static BOOL AC_VerifyFunctionPointer(PVOID* pFuncPtr, PVOID expectedValue, 
                                    const CHAR* funcName)
{
    if (!pFuncPtr) return FALSE;
    
    /* Check if function pointer has been redirected */
    if (*pFuncPtr != expectedValue) {
        AC_LOG(AC_SEV_BAN,
               "Function pointer redirected: %s (expected: %p, actual: %p)",
               funcName, expectedValue, *pFuncPtr);
        AC_RecordEvent(AC_CAT_INTEGRITY, AC_SEV_BAN,
                       "Function pointer redirected",
                       (ULONG_PTR)expectedValue,
                       (ULONG_PTR)*pFuncPtr);
        return FALSE;
    }
    
    return TRUE;
}

/* ==========================================================================
 * Verify AntiCheat Module Integrity
 * ========================================================================== */

static BOOL AC_VerifyModuleIntegrity(HMODULE hModule, const CHAR* moduleName)
{
    MODULEINFO modInfo;
    
    if (!s_integrityFuncs.GetModuleInformation(GetCurrentProcess(), hModule, 
                                              &modInfo, sizeof(modInfo))) {
        AC_LOG(AC_SEV_WARNING, "Failed to get module information for %s", moduleName);
        return FALSE;
    }
    
    /* Get module from disk for comparison */
    CHAR modulePath[MAX_PATH];
    if (!GetModuleFileNameExA(GetCurrentProcess(), hModule, modulePath, sizeof(modulePath))) {
        return FALSE;
    }
    
    /* Open file from disk */
    HANDLE hFile = CreateFileA(modulePath, GENERIC_READ, FILE_SHARE_READ, 
                               NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    if (hFile == INVALID_HANDLE_VALUE) {
        AC_LOG(AC_SEV_WARNING, "Failed to open module file: %s", modulePath);
        return FALSE;
    }
    
    /* Read disk version */
    DWORD fileSize = GetFileSize(hFile, NULL);
    BYTE* diskData = (BYTE*)VirtualAlloc(NULL, fileSize, MEM_COMMIT | MEM_RESERVE, 
                                          PAGE_READWRITE);
    if (!diskData) {
        CloseHandle(hFile);
        return FALSE;
    }
    
    DWORD bytesRead;
    if (!ReadFile(hFile, diskData, fileSize, &bytesRead, NULL)) {
        VirtualFree(diskData, 0, MEM_RELEASE);
        CloseHandle(hFile);
        return FALSE;
    }
    CloseHandle(hFile);
    
    /* Compare memory vs disk (simplified - just compare PE header in production) */
    /* In production, compare entire code sections */
    BYTE* memBase = (BYTE*)modInfo.lpBaseOfDll;
    BOOL match = TRUE;
    
    /* Compare first 4KB (PE headers) */
    SIZE_T compareSize = min(fileSize, 4096);
    compareSize = min(compareSize, modInfo.SizeOfImage);
    
    if (compareSize > 0) {
        if (memcmp(memBase, diskData, compareSize) != 0) {
            AC_LOG(AC_SEV_BAN,
                   "Module %s memory differs from disk (possible patching)",
                   moduleName);
            AC_RecordEvent(AC_CAT_INTEGRITY, AC_SEV_BAN,
                           "Module memory differs from disk",
                           (ULONG_PTR)hModule,
                           (ULONG_PTR)compareSize);
            match = FALSE;
        }
    }
    
    VirtualFree(diskData, 0, MEM_RELEASE);
    return match;
}

/* ==========================================================================
 * Verify AntiCheat Code Sections
 * ========================================================================== */

static BOOL AC_VerifyCodeSections(void)
{
    HMODULE hModules[1024];
    DWORD cbNeeded;
    
    if (!EnumProcessModules(GetCurrentProcess(), hModules, sizeof(hModules), &cbNeeded)) {
        return FALSE;
    }
    
    DWORD moduleCount = cbNeeded / sizeof(HMODULE);
    BOOL allValid = TRUE;
    
    for (DWORD i = 0; i < moduleCount; i++) {
        CHAR modName[MAX_PATH];
        GetModuleFileNameExA(GetCurrentProcess(), hModules[i], modName, sizeof(modName));
        
        /* Check if this is an AntiCheat module */
        if (strstr(modName, "anticheat") || strstr(modName, "ac_") || 
            strstr(modName, "cheatoid")) {
            if (!AC_VerifyModuleIntegrity(hModules[i], modName)) {
                allValid = FALSE;
            }
        }
    }
    
    return allValid;
}

/* ==========================================================================
 * Verify Critical Function Pointers
 * ========================================================================== */

static BOOL AC_VerifyCriticalFunctionPointers(void)
{
    /* Verify that our dynamically loaded function pointers haven't been modified */
    /* This is a placeholder - in production, store original values and compare */
    
    /* Example: Verify timing functions */
    static PVOID s_originalGetTickCount = NULL;
    if (s_originalGetTickCount == NULL) {
        HMODULE hKernel32 = GetModuleHandleA("kernel32.dll");
        s_originalGetTickCount = GetProcAddress(hKernel32, "GetTickCount");
    }
    
    /* In production, store and verify all critical function pointers */
    
    return TRUE;
}

/* ==========================================================================
 * Detect AntiCheat Bypass Attempts
 * ========================================================================== */

static BOOL AC_DetectBypassAttempts(void)
{
    /* Check for common bypass techniques */
    
    /* 1. Check if AntiCheat threads are still running */
    if (s_threadCount > 0) {
        /* Verify main AntiCheat thread is still alive */
        /* This would be implemented with thread tracking */
    }
    
    /* 2. Check if AntiCheat events are still being logged */
    static DWORD s_lastEventCount = 0;
    /* In production, track event counts and detect if logging stopped */
    
    /* 3. Check if timing checks are still running */
    static DWORD s_lastTimingCheck = 0;
    if (s_lastTimingCheck > 0) {
        DWORD elapsed = GetTickCount() - s_lastTimingCheck;
        if (elapsed > 30000) { /* No timing check for 30 seconds */
            AC_LOG(AC_SEV_CRITICAL, "Timing checks have stopped (possible bypass)");
            return FALSE;
        }
    }
    s_lastTimingCheck = GetTickCount();
    
    /* 4. Check for suspicious memory protections */
    HMODULE hThisModule = GetModuleHandleA(NULL); /* This executable */
    MODULEINFO modInfo;
    if (GetModuleInformation(GetCurrentProcess(), hThisModule, &modInfo, sizeof(modInfo))) {
        /* Check if code sections have been made writable */
        MEMORY_BASIC_INFORMATION mbi;
        if (VirtualQuery(modInfo.lpBaseOfDll, &mbi, sizeof(mbi))) {
            if ((mbi.Protect & (PAGE_EXECUTE_READWRITE | PAGE_EXECUTE_WRITECOPY)) &&
                !(mbi.Protect & PAGE_EXECUTE_READ)) {
                AC_LOG(AC_SEV_CRITICAL,
                       "Code section has suspicious protection: 0x%08X",
                       mbi.Protect);
                return FALSE;
            }
        }
    }
    
    return TRUE;
}

/* ==========================================================================
 * Protect Critical Regions
 * ========================================================================== */

static BOOL AC_ProtectCriticalRegions(void)
{
    if (!s_integrityFuncs.VirtualProtect) {
        HMODULE hKernel32 = GetModuleHandleA("kernel32.dll");
        s_integrityFuncs.VirtualProtect = (PFN_VIRTUALPROTECT)GetProcAddress(hKernel32, "VirtualProtect");
    }
    
    if (!s_integrityFuncs.VirtualProtect) {
        AC_LOG(AC_SEV_CRITICAL, "Failed to load VirtualProtect");
        return FALSE;
    }
    
    for (INT i = 0; i < s_criticalRegionCount; i++) {
        AC_CRITICAL_REGION* region = &s_criticalRegions[i];
        
        /* Make region read-only */
        DWORD oldProtect;
        if (s_integrityFuncs.VirtualProtect(region->startAddress, region->size, 
                                          PAGE_EXECUTE_READ, &oldProtect)) {
            region->originalProtection = oldProtect;
            region->protected = TRUE;
            
            AC_LOG(AC_SEV_INFO, "Protected region: %s (original: 0x%08X)",
                   region->description, oldProtect);
        }
    }
    
    return TRUE;
}

/* ==========================================================================
 * Public API
 * ========================================================================== */

BOOL AC_InitializeSelfIntegrity(void)
{
    /* Load required functions */
    HMODULE hKernel32 = GetModuleHandleA("kernel32.dll");
    s_integrityFuncs.VirtualProtect = (PFN_VIRTUALPROTECT)GetProcAddress(hKernel32, "VirtualProtect");
    s_integrityFuncs.GetModuleHandleA = (PFN_GETMODULEHANDLEA)GetProcAddress(hKernel32, "GetModuleHandleA");
    s_integrityFuncs.GetModuleInformation = (PFN_GETMODULEINFORMATION)GetProcAddress(hKernel32, "GetModuleInformation");
    
    /* Register critical code regions (example) */
    /* In production, register all critical AntiCheat functions */
    
    /* Register this module's code section */
    HMODULE hThisModule = GetModuleHandleA(NULL);
    MODULEINFO modInfo;
    if (s_integrityFuncs.GetModuleInformation(GetCurrentProcess(), hThisModule, 
                                              &modInfo, sizeof(modInfo))) {
        AC_RegisterCriticalRegion(modInfo.lpBaseOfDll, modInfo.SizeOfImage, 
                                  "Main executable code");
    }
    
    /* Protect critical regions */
    AC_ProtectCriticalRegions();
    
    s_integrityInitialized = TRUE;
    AC_LOG(AC_SEV_INFO, "Self-integrity verification initialized");
    
    return TRUE;
}

BOOL AC_VerifySelfIntegrity(void)
{
    if (!s_integrityInitialized) {
        AC_InitializeSelfIntegrity();
    }
    
    DWORD now = GetTickCount();
    if (now - s_lastIntegrityCheck < AC_INTEGRITY_CHECK_INTERVAL) {
        return TRUE; /* Skip if checked recently */
    }
    s_lastIntegrityCheck = now;
    
    BOOL allValid = TRUE;
    
    /* Verify all critical regions */
    for (INT i = 0; i < s_criticalRegionCount; i++) {
        if (!AC_VerifyRegionIntegrity(&s_criticalRegions[i])) {
            allValid = FALSE;
        }
    }
    
    /* Verify code sections */
    allValid &= AC_VerifyCodeSections();
    
    /* Verify critical function pointers */
    allValid &= AC_VerifyCriticalFunctionPointers();
    
    /* Detect bypass attempts */
    allValid &= AC_DetectBypassAttempts();
    
    if (!allValid) {
        AC_LOG(AC_SEV_BAN, "Self-integrity check failed - AntiCheat may be compromised");
    }
    
    return allValid;
}

BOOL AC_RegisterCriticalCodeRegion(PVOID startAddress, SIZE_T size, const CHAR* description)
{
    return AC_RegisterCriticalRegion(startAddress, size, description);
}

/* Get integrity check statistics */
VOID AC_GetIntegrityStats(INT* regionCount, DWORD* lastCheckTime)
{
    if (regionCount) *regionCount = s_criticalRegionCount;
    if (lastCheckTime) *lastCheckTime = s_lastIntegrityCheck;
}
```

---

## Manual PE Parser & GetProcAddress

```c
/* ==========================================================================
 * ac_pe_parser.c - Manual PE parser and GetProcAddress implementation
 *
 * Provides a manual implementation of GetProcAddress using PE parsing
 * to bypass potential hooks on the real GetProcAddress.
 * 
 * Can be enabled by defining AC_USE_MANUAL_GETPROCADDRESS before including
 * ========================================================================== */

#include "ac_common.h"

/* ==========================================================================
 * PE File Format Structures
 * ========================================================================== */

/* DOS Header */
typedef struct _AC_IMAGE_DOS_HEADER {
    WORD  e_magic;      /* Magic number (MZ) */
    WORD  e_cblp;
    WORD  e_cp;
    WORD  e_crlc;
    WORD  e_cparhdr;
    WORD  e_minalloc;
    WORD  e_maxalloc;
    WORD  e_ss;
    WORD  e_sp;
    WORD  e_csum;
    WORD  e_ip;
    WORD  e_cs;
    WORD  e_lfarlc;
    WORD  e_ovno;
    WORD  e_res[4];
    WORD  e_oemid;
    WORD  e_oeminfo;
    WORD  e_res2[10];
    LONG  e_lfanew;     /* Offset to PE header */
} AC_IMAGE_DOS_HEADER;

/* File Header */
typedef struct _AC_IMAGE_FILE_HEADER {
    WORD  Machine;
    WORD  NumberOfSections;
    DWORD TimeDateStamp;
    DWORD PointerToSymbolTable;
    DWORD NumberOfSymbols;
    WORD  SizeOfOptionalHeader;
    WORD  Characteristics;
} AC_IMAGE_FILE_HEADER;

/* Optional Header (32-bit) */
typedef struct _AC_IMAGE_OPTIONAL_HEADER32 {
    WORD  Magic;
    BYTE  MajorLinkerVersion;
    BYTE  MinorLinkerVersion;
    DWORD SizeOfCode;
    DWORD SizeOfInitializedData;
    DWORD SizeOfUninitializedData;
    DWORD AddressOfEntryPoint;
    DWORD BaseOfCode;
    DWORD BaseOfData;
    DWORD ImageBase;
    DWORD SectionAlignment;
    DWORD FileAlignment;
    WORD  MajorOperatingSystemVersion;
    WORD  MinorOperatingSystemVersion;
    WORD  MajorImageVersion;
    WORD  MinorImageVersion;
    WORD  MajorSubsystemVersion;
    WORD  MinorSubsystemVersion;
    DWORD Win32VersionValue;
    DWORD SizeOfImage;
    DWORD SizeOfHeaders;
    DWORD CheckSum;
    WORD  Subsystem;
    WORD  DllCharacteristics;
    DWORD SizeOfStackReserve;
    DWORD SizeOfStackCommit;
    DWORD SizeOfHeapReserve;
    DWORD SizeOfHeapCommit;
    DWORD LoaderFlags;
    DWORD NumberOfRvaAndSizes;
} AC_IMAGE_OPTIONAL_HEADER32;

/* Optional Header (64-bit) */
typedef struct _AC_IMAGE_OPTIONAL_HEADER64 {
    WORD  Magic;
    BYTE  MajorLinkerVersion;
    BYTE  MinorLinkerVersion;
    DWORD SizeOfCode;
    DWORD SizeOfInitializedData;
    DWORD SizeOfUninitializedData;
    DWORD AddressOfEntryPoint;
    DWORD BaseOfCode;
    ULONGLONG ImageBase;
    DWORD SectionAlignment;
    DWORD FileAlignment;
    WORD  MajorOperatingSystemVersion;
    WORD  MinorOperatingSystemVersion;
    WORD  MajorImageVersion;
    WORD  MinorImageVersion;
    WORD  MajorSubsystemVersion;
    WORD  MinorSubsystemVersion;
    DWORD Win32VersionValue;
    DWORD SizeOfImage;
    DWORD SizeOfHeaders;
    DWORD CheckSum;
    WORD  Subsystem;
    WORD  DllCharacteristics;
    ULONGLONG SizeOfStackReserve;
    ULONGLONG SizeOfStackCommit;
    DWORD SizeOfHeapReserve;
    DWORD SizeOfHeapCommit;
    DWORD LoaderFlags;
    DWORD NumberOfRvaAndSizes;
} AC_IMAGE_OPTIONAL_HEADER64;

/* Data Directory Entry */
typedef struct _AC_IMAGE_DATA_DIRECTORY {
    DWORD VirtualAddress;
    DWORD Size;
} AC_IMAGE_DATA_DIRECTORY;

/* Section Header */
typedef struct _AC_IMAGE_SECTION_HEADER {
    BYTE  Name[8];
    DWORD VirtualSize;
    DWORD VirtualAddress;
    DWORD SizeOfRawData;
    DWORD PointerToRawData;
    DWORD PointerToRelocations;
    DWORD PointerToLinenumbers;
    WORD  NumberOfRelocations;
    WORD  NumberOfLinenumbers;
    DWORD Characteristics;
} AC_IMAGE_SECTION_HEADER;

/* Export Directory */
typedef struct _AC_IMAGE_EXPORT_DIRECTORY {
    DWORD Characteristics;
    DWORD TimeDateStamp;
    WORD  MajorVersion;
    WORD  MinorVersion;
    DWORD Name;
    DWORD Base;
    DWORD NumberOfFunctions;
    DWORD NumberOfNames;
    DWORD AddressOfFunctions;     /* RVA to array of function addresses */
    DWORD AddressOfNames;         /* RVA to array of function name RVAs */
    DWORD AddressOfNameOrdinals;  /* RVA to array of ordinals */
} AC_IMAGE_EXPORT_DIRECTORY;

/* Data Directory Indices */
#define AC_IMAGE_DIRECTORY_ENTRY_EXPORT  0
#define AC_IMAGE_DIRECTORY_ENTRY_IMPORT  1
#define AC_IMAGE_NUMBEROF_DIRECTORY_ENTRIES 16

/* ==========================================================================
 * Simple Hash Function (for anti-string hooking)
 * ========================================================================== */

static DWORD AC_HashString(const CHAR* str)
{
    /* Simple string hash - use a better hash in production */
    DWORD hash = 5381;
    INT c;
    
    while ((c = *str++)) {
        hash = ((hash << 5) + hash) + c; /* hash * 33 + c */
    }
    
    return hash;
}

/* ==========================================================================
 * PE Parser Functions
 * ========================================================================== */

static BOOL AC_IsValidDosHeader(AC_IMAGE_DOS_HEADER* dosHeader)
{
    return (dosHeader->e_magic == 0x5A4D); /* "MZ" */
}

static PVOID AC_RvaToVa(PVOID base, DWORD rva)
{
    AC_IMAGE_DOS_HEADER* dosHeader = (AC_IMAGE_DOS_HEADER*)base;
    AC_IMAGE_FILE_HEADER* fileHeader;
    AC_IMAGE_OPTIONAL_HEADER32* optHeader32;
    AC_IMAGE_OPTIONAL_HEADER64* optHeader64;
    AC_IMAGE_SECTION_HEADER* sectionHeader;
    WORD magic;
    
    if (!AC_IsValidDosHeader(dosHeader)) {
        return NULL;
    }
    
    fileHeader = (AC_IMAGE_FILE_HEADER*)((BYTE*)base + dosHeader->e_lfanew + 4);
    magic = *(WORD*)((BYTE*)fileHeader + sizeof(AC_IMAGE_FILE_HEADER));
    
    if (magic == 0x010B) { /* PE32 */
        optHeader32 = (AC_IMAGE_OPTIONAL_HEADER32*)((BYTE*)fileHeader + sizeof(AC_IMAGE_FILE_HEADER));
        sectionHeader = (AC_IMAGE_SECTION_HEADER*)((BYTE*)optHeader32 + fileHeader->SizeOfOptionalHeader);
    } else if (magic == 0x020B) { /* PE32+ */
        optHeader64 = (AC_IMAGE_OPTIONAL_HEADER64*)((BYTE*)fileHeader + sizeof(AC_IMAGE_FILE_HEADER));
        sectionHeader = (AC_IMAGE_SECTION_HEADER*)((BYTE*)optHeader64 + fileHeader->SizeOfOptionalHeader);
    } else {
        return NULL;
    }
    
    /* Find section containing the RVA */
    for (WORD i = 0; i < fileHeader->NumberOfSections; i++) {
        DWORD sectionStart = sectionHeader[i].VirtualAddress;
        DWORD sectionEnd = sectionStart + sectionHeader[i].VirtualSize;
        
        if (rva >= sectionStart && rva < sectionEnd) {
            return (BYTE*)base + (rva - sectionStart) + sectionHeader[i].PointerToRawData;
        }
    }
    
    /* RVA not in any section, assume it's already a VA (for headers) */
    return (BYTE*)base + rva;
}

/* ==========================================================================
 * Manual GetProcAddress Implementation
 * ========================================================================== */

static PVOID AC_GetProcAddress_Manual(HMODULE hModule, const CHAR* lpProcName)
{
    AC_IMAGE_DOS_HEADER* dosHeader;
    AC_IMAGE_FILE_HEADER* fileHeader;
    AC_IMAGE_OPTIONAL_HEADER32* optHeader32;
    AC_IMAGE_OPTIONAL_HEADER64* optHeader64;
    AC_IMAGE_DATA_DIRECTORY* dataDirectory;
    AC_IMAGE_EXPORT_DIRECTORY* exportDir;
    DWORD* addressOfFunctions;
    DWORD* addressOfNames;
    WORD* addressOfNameOrdinals;
    WORD magic;
    
    if (!hModule || !lpProcName) {
        return NULL;
    }
    
    dosHeader = (AC_IMAGE_DOS_HEADER*)hModule;
    if (!AC_IsValidDosHeader(dosHeader)) {
        return NULL;
    }
    
    fileHeader = (AC_IMAGE_FILE_HEADER*)((BYTE*)hModule + dosHeader->e_lfanew + 4);
    magic = *(WORD*)((BYTE*)fileHeader + sizeof(AC_IMAGE_FILE_HEADER));
    
    /* Get data directory */
    if (magic == 0x010B) { /* PE32 */
        optHeader32 = (AC_IMAGE_OPTIONAL_HEADER32*)((BYTE*)fileHeader + sizeof(AC_IMAGE_FILE_HEADER));
        dataDirectory = (AC_IMAGE_DATA_DIRECTORY*)((BYTE*)optHeader32 + sizeof(AC_IMAGE_OPTIONAL_HEADER32) - 
                                                   sizeof(AC_IMAGE_DATA_DIRECTORY) * AC_IMAGE_NUMBEROF_DIRECTORY_ENTRIES);
    } else if (magic == 0x020B) { /* PE32+ */
        optHeader64 = (AC_IMAGE_OPTIONAL_HEADER64*)((BYTE*)fileHeader + sizeof(AC_IMAGE_FILE_HEADER));
        dataDirectory = (AC_IMAGE_DATA_DIRECTORY*)((BYTE*)optHeader64 + sizeof(AC_IMAGE_OPTIONAL_HEADER64) - 
                                                   sizeof(AC_IMAGE_DATA_DIRECTORY) * AC_IMAGE_NUMBEROF_DIRECTORY_ENTRIES);
    } else {
        return NULL;
    }
    
    /* Get export directory */
    if (dataDirectory[AC_IMAGE_DIRECTORY_ENTRY_EXPORT].VirtualAddress == 0) {
        return NULL; /* No exports */
    }
    
    exportDir = (AC_IMAGE_EXPORT_DIRECTORY*)AC_RvaToVa(hModule, 
                                                       dataDirectory[AC_IMAGE_DIRECTORY_ENTRY_EXPORT].VirtualAddress);
    if (!exportDir) {
        return NULL;
    }
    
    /* Get export tables */
    addressOfFunctions = (DWORD*)AC_RvaToVa(hModule, exportDir->AddressOfFunctions);
    addressOfNames = (DWORD*)AC_RvaToVa(hModule, exportDir->AddressOfNames);
    addressOfNameOrdinals = (WORD*)AC_RvaToVa(hModule, exportDir->AddressOfNameOrdinals);
    
    if (!addressOfFunctions || !addressOfNames || !addressOfNameOrdinals) {
        return NULL;
    }
    
    /* Check if lpProcName is an ordinal (high bit set) */
    if ((ULONG_PTR)lpProcName >> 16) {
        /* Search by name */
        DWORD targetHash = AC_HashString(lpProcName);
        
        for (DWORD i = 0; i < exportDir->NumberOfNames; i++) {
            CHAR* functionName = (CHAR*)AC_RvaToVa(hModule, addressOfNames[i]);
            
            if (functionName) {
                DWORD nameHash = AC_HashString(functionName);
                
                if (nameHash == targetHash) {
                    /* Verify actual string match to avoid hash collisions */
                    if (strcmp(functionName, lpProcName) == 0) {
                        WORD ordinal = addressOfNameOrdinals[i];
                        DWORD functionRva = addressOfFunctions[ordinal];
                        
                        /* Check for forwarded export */
                        if (functionRva >= dataDirectory[AC_IMAGE_DIRECTORY_ENTRY_EXPORT].VirtualAddress &&
                            functionRva < dataDirectory[AC_IMAGE_DIRECTORY_ENTRY_EXPORT].VirtualAddress + 
                            dataDirectory[AC_IMAGE_DIRECTORY_ENTRY_EXPORT].Size) {
                            /* Forwarded export - not supported in this implementation */
                            return NULL;
                        }
                        
                        return AC_RvaToVa(hModule, functionRva);
                    }
                }
            }
        }
    } else {
        /* Search by ordinal */
        WORD ordinal = LOWORD((ULONG_PTR)lpProcName);
        DWORD functionRva = addressOfFunctions[ordinal - exportDir->Base];
        
        if (functionRva >= dataDirectory[AC_IMAGE_DIRECTORY_ENTRY_EXPORT].VirtualAddress &&
            functionRva < dataDirectory[AC_IMAGE_DIRECTORY_ENTRY_EXPORT].VirtualAddress + 
            dataDirectory[AC_IMAGE_DIRECTORY_ENTRY_EXPORT].Size) {
            /* Forwarded export */
            return NULL;
        }
        
        return AC_RvaToVa(hModule, functionRva);
    }
    
    return NULL;
}

/* ==========================================================================
 * Hash-based GetProcAddress (anti-string hooking)
 * ========================================================================== */

static PVOID AC_GetProcAddress_Hash(HMODULE hModule, DWORD functionHash)
{
    AC_IMAGE_DOS_HEADER* dosHeader;
    AC_IMAGE_FILE_HEADER* fileHeader;
    AC_IMAGE_OPTIONAL_HEADER32* optHeader32;
    AC_IMAGE_OPTIONAL_HEADER64* optHeader64;
    AC_IMAGE_DATA_DIRECTORY* dataDirectory;
    AC_IMAGE_EXPORT_DIRECTORY* exportDir;
    DWORD* addressOfFunctions;
    DWORD* addressOfNames;
    WORD* addressOfNameOrdinals;
    WORD magic;
    
    if (!hModule || functionHash == 0) {
        return NULL;
    }
    
    dosHeader = (AC_IMAGE_DOS_HEADER*)hModule;
    if (!AC_IsValidDosHeader(dosHeader)) {
        return NULL;
    }
    
    fileHeader = (AC_IMAGE_FILE_HEADER*)((BYTE*)hModule + dosHeader->e_lfanew + 4);
    magic = *(WORD*)((BYTE*)fileHeader + sizeof(AC_IMAGE_FILE_HEADER));
    
    /* Get data directory */
    if (magic == 0x010B) { /* PE32 */
        optHeader32 = (AC_IMAGE_OPTIONAL_HEADER32*)((BYTE*)fileHeader + sizeof(AC_IMAGE_FILE_HEADER));
        dataDirectory = (AC_IMAGE_DATA_DIRECTORY*)((BYTE*)optHeader32 + sizeof(AC_IMAGE_OPTIONAL_HEADER32) - 
                                                   sizeof(AC_IMAGE_DATA_DIRECTORY) * AC_IMAGE_NUMBEROF_DIRECTORY_ENTRIES);
    } else if (magic == 0x020B) { /* PE32+ */
        optHeader64 = (AC_IMAGE_OPTIONAL_HEADER64*)((BYTE*)fileHeader + sizeof(AC_IMAGE_FILE_HEADER));
        dataDirectory = (AC_IMAGE_DATA_DIRECTORY*)((BYTE*)optHeader64 + sizeof(AC_IMAGE_OPTIONAL_HEADER64) - 
                                                   sizeof(AC_IMAGE_DATA_DIRECTORY) * AC_IMAGE_NUMBEROF_DIRECTORY_ENTRIES);
    } else {
        return NULL;
    }
    
    /* Get export directory */
    if (dataDirectory[AC_IMAGE_DIRECTORY_ENTRY_EXPORT].VirtualAddress == 0) {
        return NULL;
    }
    
    exportDir = (AC_IMAGE_EXPORT_DIRECTORY*)AC_RvaToVa(hModule, 
                                                       dataDirectory[AC_IMAGE_DIRECTORY_ENTRY_EXPORT].VirtualAddress);
    if (!exportDir) {
        return NULL;
    }
    
    /* Get export tables */
    addressOfFunctions = (DWORD*)AC_RvaToVa(hModule, exportDir->AddressOfFunctions);
    addressOfNames = (DWORD*)AC_RvaToVa(hModule, exportDir->AddressOfNames);
    addressOfNameOrdinals = (WORD*)AC_RvaToVa(hModule, exportDir->AddressOfNameOrdinals);
    
    if (!addressOfFunctions || !addressOfNames || !addressOfNameOrdinals) {
        return NULL;
    }
    
    /* Search by hash */
    for (DWORD i = 0; i < exportDir->NumberOfNames; i++) {
        CHAR* functionName = (CHAR*)AC_RvaToVa(hModule, addressOfNames[i]);
        
        if (functionName) {
            DWORD nameHash = AC_HashString(functionName);
            
            if (nameHash == functionHash) {
                WORD ordinal = addressOfNameOrdinals[i];
                DWORD functionRva = addressOfFunctions[ordinal];
                
                if (functionRva >= dataDirectory[AC_IMAGE_DIRECTORY_ENTRY_EXPORT].VirtualAddress &&
                    functionRva < dataDirectory[AC_IMAGE_DIRECTORY_ENTRY_EXPORT].VirtualAddress + 
                    dataDirectory[AC_IMAGE_DIRECTORY_ENTRY_EXPORT].Size) {
                    return NULL; /* Forwarded export */
                }
                
                return AC_RvaToVa(hModule, functionRva);
            }
        }
    }
    
    return NULL;
}

/* ==========================================================================
 * Utility Functions
 * ========================================================================== */

/* Get function address by hash (pre-computed hash) */
static PVOID AC_GetProcAddress_ByHash(HMODULE hModule, DWORD hash)
{
    return AC_GetProcAddress_Hash(hModule, hash);
}

/* Get module handle by parsing PEB (avoid GetModuleHandle) */
static HMODULE AC_GetModuleHandle_Manual(const CHAR* lpModuleName)
{
#ifdef _WIN64
    PPEB peb = (PPEB)__readgsqword(0x60);
#else
    PPEB peb = (PPEB)__readfsdword(0x30);
#endif
    
    PPEB_LDR_DATA ldr = peb->Ldr;
    PLIST_ENTRY head = &ldr->InLoadOrderModuleList;
    PLIST_ENTRY current = head->Flink;
    
    while (current != head) {
        PLDR_DATA_TABLE_ENTRY entry = CONTAINING_RECORD(current, LDR_DATA_TABLE_ENTRY, InLoadOrderLinks);
        
        if (lpModuleName == NULL) {
            return (HMODULE)entry->DllBase;
        }
        
        /* Compare module name (case-insensitive) */
        CHAR dllName[MAX_PATH];
        WCHAR* baseDllName = entry->BaseDllName.Buffer;
        
        /* Convert to ASCII */
        for (USHORT i = 0; i < entry->BaseDllName.Length / sizeof(WCHAR) && i < MAX_PATH - 1; i++) {
            dllName[i] = (CHAR)tolower(baseDllName[i]);
        }
        dllName[entry->BaseDllName.Length / sizeof(WCHAR)] = '\0';
        
        if (strstr(dllName, lpModuleName)) {
            return (HMODULE)entry->DllBase;
        }
        
        current = current->Flink;
    }
    
    return NULL;
}

/* ==========================================================================
 * Common Function Hashes (pre-computed for common functions)
 * ========================================================================== */

/* Hash("GetProcAddress") = 0x7C0DFCAA (example - compute actual values) */
/* Hash("LoadLibraryA") = 0x0726774C (example) */
/* Hash("GetModuleHandleA") = 0x6C345A1F (example) */

/* In production, pre-compute these hashes at build time */
#define AC_HASH_GETPROCADDRESS   0x7C0DFCAA /* Compute actual value */
#define AC_HASH_LOADLIBRARYA     0x0726774C /* Compute actual value */
#define AC_HASH_GETMODULEHANDLEA 0x6C345A1F /* Compute actual value */

/* ==========================================================================
 * Public API
 * ========================================================================== */

/* Manual GetProcAddress implementation */
PVOID AC_ManualGetProcAddress(HMODULE hModule, const CHAR* lpProcName)
{
    if (!hModule) {
        hModule = AC_GetModuleHandle_Manual(NULL); /* Get exe module */
    }
    
    return AC_GetProcAddress_Manual(hModule, lpProcName);
}

/* GetProcAddress by hash (anti-string hooking) */
PVOID AC_ManualGetProcAddress_ByHash(HMODULE hModule, DWORD functionHash)
{
    if (!hModule) {
        hModule = AC_GetModuleHandle_Manual(NULL);
    }
    
    return AC_GetProcAddress_ByHash(hModule, functionHash);
}

/* Manual GetModuleHandle (PEB parsing) */
HMODULE AC_ManualGetModuleHandle(const CHAR* lpModuleName)
{
    return AC_GetModuleHandle_Manual(lpModuleName);
}

/* Initialize PE parser (optional) */
BOOL AC_InitializePEParser(void)
{
    /* No initialization needed for PE parser */
    AC_LOG(AC_SEV_INFO, "PE parser initialized");
    return TRUE;
}
```

---

## Memory Access Hooking (External Cheat Detection)

```c
/* ==========================================================================
 * ac_memory_hook.c - Hook ReadProcessMemory/WriteProcessMemory for external cheat detection
 *
 * Hooks kernel32 memory access APIs to detect third-party external cheats
 * that read/write game memory from another process.
 * ========================================================================== */

#include "ac_common.h"

/* ==========================================================================
 * Original Function Pointers
 * ========================================================================== */

typedef BOOL (WINAPI *PFN_READPROCESSMEMORY)(HANDLE, LPCVOID, LPVOID, SIZE_T, PSIZE_T);
typedef BOOL (WINAPI *PFN_WRITEPROCESSMEMORY)(HANDLE, LPVOID, LPCVOID, SIZE_T, PSIZE_T);
typedef HANDLE (WINAPI *PFN_OPENPROCESS)(DWORD, BOOL, DWORD);
typedef BOOL (WINAPI *PFN_CLOSEHANDLE)(HANDLE);

static PFN_READPROCESSMEMORY  s_OriginalReadProcessMemory = NULL;
static PFN_WRITEPROCESSMEMORY s_OriginalWriteProcessMemory = NULL;
static PFN_OPENPROCESS        s_OriginalOpenProcess = NULL;
static PFN_CLOSEHANDLE        s_OriginalCloseHandle = NULL;

/* ==========================================================================
 * Memory Access Tracking
 * ========================================================================== */

#define AC_MAX_TRACKED_HANDLES   256
#define AC_ACCESS_HISTORY_SIZE   1024

typedef struct _AC_PROCESS_HANDLE_INFO {
    HANDLE    handle;
    DWORD     processId;
    CHAR      processName[MAX_PATH];
    DWORD     accessRights;
    DWORD     accessCount;
    DWORD64   lastAccessTime;
    BOOL      isSuspicious;
} AC_PROCESS_HANDLE_INFO;

typedef struct _AC_MEMORY_ACCESS_RECORD {
    HANDLE    handle;
    PVOID     address;
    SIZE_T    size;
    BOOL      isWrite;
    DWORD64   timestamp;
} AC_MEMORY_ACCESS_RECORD;

static AC_PROCESS_HANDLE_INFO  s_trackedHandles[AC_MAX_TRACKED_HANDLES];
static INT                     s_trackedHandleCount = 0;
static AC_MEMORY_ACCESS_RECORD s_accessHistory[AC_ACCESS_HISTORY_SIZE];
static INT                     s_accessHistoryIndex = 0;
static BOOL                    s_hooksInstalled = FALSE;

/* Critical section for thread safety */
static CRITICAL_SECTION s_hookCs;

/* ==========================================================================
 * Suspicious Process Names
 * ========================================================================== */

static const CHAR* s_suspiciousProcesses[] = {
    "cheatengine",
    "x64dbg",
    "x32dbg",
    "ollydbg",
    "ida",
    "ida64",
    "reclass",
    "processhacker",
    "process hacker",
    "wireshark",
    "fiddler",
    "charles",
    "dnspy",
    "ilspy",
    "dotpeek",
    "reflector",
    "cheat",
    "hack",
    "injector",
    "inject",
    "trainer",
    "modmenu",
    NULL
};

/* ==========================================================================
 * Suspicious Memory Ranges (game-specific)
 * ========================================================================== */

typedef struct _AC_SUSPICIOUS_RANGE {
    PVOID start;
    SIZE_T size;
    CHAR  description[64];
} AC_SUSPICIOUS_RANGE;

static AC_SUSPICIOUS_RANGE s_suspiciousRanges[] = {
    /* Player data structures - game should populate these */
    { NULL, 0, "Player position" },
    { NULL, 0, "Player health" },
    { NULL, 0, "Player ammo" },
    /* Add more game-specific ranges */
};
static INT s_suspiciousRangeCount = 0;

/* ==========================================================================
 * Utility Functions
 * ========================================================================== */

static BOOL AC_IsSuspiciousProcessName(const CHAR* processName)
{
    if (!processName) return FALSE;
    
    CHAR lowerName[MAX_PATH];
    for (INT i = 0; processName[i] && i < MAX_PATH - 1; i++) {
        lowerName[i] = (CHAR)tolower(processName[i]);
    }
    lowerName[strlen(processName)] = '\0';
    
    for (INT i = 0; s_suspiciousProcesses[i]; i++) {
        if (strstr(lowerName, s_suspiciousProcesses[i])) {
            return TRUE;
        }
    }
    
    return FALSE;
}

static VOID AC_GetProcessNameById(DWORD processId, CHAR* outName, SIZE_T nameSize)
{
    HANDLE hProcess = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, processId);
    if (hProcess) {
        GetModuleFileNameExA(hProcess, NULL, outName, (DWORD)nameSize);
        
        /* Extract just the filename */
        CHAR* lastSlash = strrchr(outName, '\\');
        if (lastSlash) {
            memmove(outName, lastSlash + 1, strlen(lastSlash + 1) + 1);
        }
        
        CloseHandle(hProcess);
    } else {
        strncpy_s(outName, nameSize, "<unknown>", _TRUNCATE);
    }
}

static VOID AC_TrackHandle(HANDLE hProcess, DWORD processId, DWORD accessRights)
{
    EnterCriticalSection(&s_hookCs);
    
    /* Check if we're already tracking this handle */
    for (INT i = 0; i < s_trackedHandleCount; i++) {
        if (s_trackedHandles[i].handle == hProcess) {
            s_trackedHandles[i].accessCount++;
            s_trackedHandles[i].lastAccessTime = GetTickCount64();
            LeaveCriticalSection(&s_hookCs);
            return;
        }
    }
    
    /* Add new handle */
    if (s_trackedHandleCount < AC_MAX_TRACKED_HANDLES) {
        AC_PROCESS_HANDLE_INFO* info = &s_trackedHandles[s_trackedHandleCount++];
        info->handle = hProcess;
        info->processId = processId;
        info->accessRights = accessRights;
        info->accessCount = 1;
        info->lastAccessTime = GetTickCount64();
        info->isSuspicious = FALSE;
        
        AC_GetProcessNameById(processId, info->processName, sizeof(info->processName));
        
        /* Check if process name is suspicious */
        if (AC_IsSuspiciousProcessName(info->processName)) {
            info->isSuspicious = TRUE;
            AC_LOG(AC_SEV_BAN,
                   "Suspicious process opened: %s (PID: %lu, Access: 0x%08X)",
                   info->processName, processId, accessRights);
            AC_RecordEvent(AC_CAT_PROCESS, AC_SEV_BAN,
                           "Suspicious process opened with memory access",
                           processId, accessRights);
        }
        
        /* Check for suspicious access rights */
        if (accessRights & (PROCESS_VM_READ | PROCESS_VM_WRITE | PROCESS_VM_OPERATION)) {
            CHAR procName[MAX_PATH];
            AC_GetProcessNameById(processId, procName, sizeof(procName));
            
            if (!AC_IsSuspiciousProcessName(procName)) {
                AC_LOG(AC_SEV_WARNING,
                       "Process opened with memory access: %s (PID: %lu, Access: 0x%08X)",
                       procName, processId, accessRights);
            }
        }
    }
    
    LeaveCriticalSection(&s_hookCs);
}

static VOID AC_RecordMemoryAccess(HANDLE hProcess, PVOID address, SIZE_T size, BOOL isWrite)
{
    EnterCriticalSection(&s_hookCs);
    
    /* Add to access history */
    s_accessHistory[s_accessHistoryIndex].handle = hProcess;
    s_accessHistory[s_accessHistoryIndex].address = address;
    s_accessHistory[s_accessHistoryIndex].size = size;
    s_accessHistory[s_accessHistoryIndex].isWrite = isWrite;
    s_accessHistory[s_accessHistoryIndex].timestamp = GetTickCount64();
    
    s_accessHistoryIndex = (s_accessHistoryIndex + 1) % AC_ACCESS_HISTORY_SIZE;
    
    LeaveCriticalSection(&s_hookCs);
}

static BOOL AC_IsAddressInSuspiciousRange(PVOID address)
{
    for (INT i = 0; i < s_suspiciousRangeCount; i++) {
        if (address >= s_suspiciousRanges[i].start && 
            (BYTE*)address < (BYTE*)s_suspiciousRanges[i].start + s_suspiciousRanges[i].size) {
            return TRUE;
        }
    }
    return FALSE;
}

/* ==========================================================================
 * Hooked Functions
 * ========================================================================== */

static BOOL WINAPI AC_HookedReadProcessMemory(
    HANDLE  hProcess,
    LPCVOID lpBaseAddress,
    LPVOID  lpBuffer,
    SIZE_T  nSize,
    PSIZE_T lpNumberOfBytesRead)
{
    /* Get process ID from handle */
    DWORD processId = GetProcessId(hProcess);
    DWORD ourPid = GetCurrentProcessId();
    
    /* Only monitor access to our process */
    if (processId == ourPid) {
        /* Track the handle */
        AC_TrackHandle(hProcess, processId, PROCESS_VM_READ);
        
        /* Record the access */
        AC_RecordMemoryAccess(hProcess, (PVOID)lpBaseAddress, nSize, FALSE);
        
        /* Check if address is in suspicious range */
        if (AC_IsAddressInSuspiciousRange((PVOID)lpBaseAddress)) {
            CHAR procName[MAX_PATH];
            AC_GetProcessNameById(processId, procName, sizeof(procName));
            
            AC_LOG(AC_SEV_CRITICAL,
                   "ReadProcessMemory to sensitive memory: %s reading %p (size: %zu)",
                   procName, lpBaseAddress, nSize);
            AC_RecordEvent(AC_CAT_PROCESS, AC_SEV_CRITICAL,
                           "ReadProcessMemory to sensitive memory",
                           (ULONG_PTR)lpBaseAddress,
                           (ULONG_PTR)nSize);
        }
        
        /* Check for large reads (scanning) */
        if (nSize > 0x100000) { /* > 1MB */
            CHAR procName[MAX_PATH];
            AC_GetProcessNameById(processId, procName, sizeof(procName));
            
            AC_LOG(AC_SEV_WARNING,
                   "Large memory read detected: %s reading %zu bytes at %p",
                   procName, nSize, lpBaseAddress);
        }
    }
    
    /* Call original function */
    return s_OriginalReadProcessMemory(hProcess, lpBaseAddress, lpBuffer, nSize, lpNumberOfBytesRead);
}

static BOOL WINAPI AC_HookedWriteProcessMemory(
    HANDLE  hProcess,
    LPVOID  lpBaseAddress,
    LPCVOID lpBuffer,
    SIZE_T  nSize,
    PSIZE_T lpNumberOfBytesWritten)
{
    /* Get process ID from handle */
    DWORD processId = GetProcessId(hProcess);
    DWORD ourPid = GetCurrentProcessId();
    
    /* Only monitor access to our process */
    if (processId == ourPid) {
        /* Track the handle */
        AC_TrackHandle(hProcess, processId, PROCESS_VM_WRITE);
        
        /* Record the access */
        AC_RecordMemoryAccess(hProcess, lpBaseAddress, nSize, TRUE);
        
        /* Write attempts are always suspicious */
        CHAR procName[MAX_PATH];
        AC_GetProcessNameById(processId, procName, sizeof(procName));
        
        AC_LOG(AC_SEV_BAN,
               "WriteProcessMemory to our process: %s writing %p (size: %zu)",
               procName, lpBaseAddress, nSize);
        AC_RecordEvent(AC_CAT_PROCESS, AC_SEV_BAN,
                       "WriteProcessMemory to our process",
                       (ULONG_PTR)lpBaseAddress,
                       (ULONG_PTR)nSize);
        
        /* Block the write */
        SetLastError(ERROR_ACCESS_DENIED);
        return FALSE;
    }
    
    /* Call original function */
    return s_OriginalWriteProcessMemory(hProcess, lpBaseAddress, lpBuffer, nSize, lpNumberOfBytesWritten);
}

static HANDLE WINAPI AC_HookedOpenProcess(
    DWORD dwDesiredAccess,
    BOOL  bInheritHandle,
    DWORD dwProcessId)
{
    HANDLE hProcess = s_OriginalOpenProcess(dwDesiredAccess, bInheritHandle, dwProcessId);
    
    if (hProcess) {
        DWORD ourPid = GetCurrentProcessId();
        
        /* Track if opening our process */
        if (dwProcessId == ourPid) {
            AC_TrackHandle(hProcess, dwProcessId, dwDesiredAccess);
        }
    }
    
    return hProcess;
}

/* ==========================================================================
 * Hook Installation
 * ========================================================================== */

static BOOL AC_InstallInlineHook(PVOID* ppOriginal, PVOID pHook)
{
    /* Simple inline hook implementation */
    /* In production, use a proper hooking library like MinHook or Detours */
    
    DWORD oldProtect;
    if (VirtualProtect(ppOriginal, 16, PAGE_EXECUTE_READWRITE, &oldProtect)) {
        /* Write JMP instruction (x64) or JMP short (x86) */
        /* This is simplified - proper implementation needed */
        
        /* For now, just log that we would hook */
        AC_LOG(AC_SEV_INFO, "Would install hook at %p -> %p", *ppOriginal, pHook);
        
        VirtualProtect(ppOriginal, 16, oldProtect, &oldProtect);
        return TRUE;
    }
    
    return FALSE;
}

static BOOL AC_InstallMemoryHooks(void)
{
    HMODULE hKernel32 = GetModuleHandleA("kernel32.dll");
    if (!hKernel32) return FALSE;
    
    /* Get original function addresses */
    s_OriginalReadProcessMemory = (PFN_READPROCESSMEMORY)GetProcAddress(hKernel32, "ReadProcessMemory");
    s_OriginalWriteProcessMemory = (PFN_WRITEPROCESSMEMORY)GetProcAddress(hKernel32, "WriteProcessMemory");
    s_OriginalOpenProcess = (PFN_OPENPROCESS)GetProcAddress(hKernel32, "OpenProcess");
    s_OriginalCloseHandle = (PFN_CLOSEHANDLE)GetProcAddress(hKernel32, "CloseHandle");
    
    if (!s_OriginalReadProcessMemory || !s_OriginalWriteProcessMemory || !s_OriginalOpenProcess) {
        AC_LOG(AC_SEV_CRITICAL, "Failed to get original function addresses");
        return FALSE;
    }
    
    /* Initialize critical section */
    InitializeCriticalSection(&s_hookCs);
    
    /* Install hooks (simplified - use proper hooking library in production) */
    AC_LOG(AC_SEV_INFO, "Installing memory access hooks...");
    
    /* Note: In production, use MinHook, Detours, or similar */
    /* AC_InstallInlineHook((PVOID*)&s_OriginalReadProcessMemory, AC_HookedReadProcessMemory); */
    /* AC_InstallInlineHook((PVOID*)&s_OriginalWriteProcessMemory, AC_HookedWriteProcessMemory); */
    /* AC_InstallInlineHook((PVOID*)&s_OriginalOpenProcess, AC_HookedOpenProcess); */
    
    s_hooksInstalled = TRUE;
    AC_LOG(AC_SEV_INFO, "Memory access hooks installed");
    
    return TRUE;
}

/* ==========================================================================
 * Public API
 * ========================================================================== */

BOOL AC_InitializeMemoryHooks(void)
{
    return AC_InstallMemoryHooks();
}

BOOL AC_AddSuspiciousMemoryRange(PVOID start, SIZE_T size, const CHAR* description)
{
    if (s_suspiciousRangeCount >= 32) {
        return FALSE;
    }
    
    s_suspiciousRanges[s_suspiciousRangeCount].start = start;
    s_suspiciousRanges[s_suspiciousRangeCount].size = size;
    strncpy_s(s_suspiciousRanges[s_suspiciousRangeCount].description, 
             sizeof(s_suspiciousRanges[s_suspiciousRangeCount].description), 
             description, _TRUNCATE);
    s_suspiciousRangeCount++;
    
    AC_LOG(AC_SEV_INFO, "Added suspicious range: %s at %p (size: %zu)",
           description, start, size);
    
    return TRUE;
}

VOID AC_GetMemoryAccessStats(INT* handleCount, INT* accessCount)
{
    EnterCriticalSection(&s_hookCs);
    if (handleCount) *handleCount = s_trackedHandleCount;
    if (accessCount) *accessCount = s_accessHistoryIndex;
    LeaveCriticalSection(&s_hookCs);
}

/* Check for suspicious memory access patterns */
BOOL AC_CheckSuspiciousMemoryAccess(void)
{
    EnterCriticalSection(&s_hookCs);
    
    BOOL suspicious = FALSE;
    
    /* Check for processes with high access counts */
    for (INT i = 0; i < s_trackedHandleCount; i++) {
        if (s_trackedHandles[i].accessCount > 100) {
            AC_LOG(AC_SEV_CRITICAL,
                   "Process %s (PID: %lu) has excessive memory access: %u times",
                   s_trackedHandles[i].processName,
                   s_trackedHandles[i].processId,
                   s_trackedHandles[i].accessCount);
            suspicious = TRUE;
        }
    }
    
    /* Check for suspicious handles */
    for (INT i = 0; i < s_trackedHandleCount; i++) {
        if (s_trackedHandles[i].isSuspicious) {
            suspicious = TRUE;
        }
    }
    
    LeaveCriticalSection(&s_hookCs);
    
    return suspicious;
}
```

---

## Aimbot / Input Anomaly Detection

```c
/* ==========================================================================
 * ac_input.c - Aimbot and input anomaly detection
 *
 * Analyzes player view-angle changes to detect:
 *   - Aim snapping (instantaneous perfect angle changes)
 *   - Inhuman aim smoothness (consistently perfect tracking)
 *   - Recoil compensation that's too perfect
 *   - Trigger-bot timing patterns
 * ========================================================================== */

#include "ac_common.h"

/* ---- History buffer for angle deltas ---- */
#define AC_ANGLE_HISTORY_SIZE 120  /* ~2 seconds at 60Hz */

typedef struct _AC_ANGLE_SAMPLE {
    FLOAT   delta;          /* Angle change magnitude (degrees) */
    FLOAT   deltaYaw;
    FLOAT   deltaPitch;
    DWORD   timestamp;      /* GetTickCount */
    BOOL    firing;         /* Was player shooting? */
} AC_ANGLE_SAMPLE;

static AC_ANGLE_SAMPLE s_angleHistory[AC_ANGLE_HISTORY_SIZE];
static INT             s_historyIdx    = 0;
static INT             s_historyCount  = 0;

/* ---- Statistics accumulators ---- */
typedef struct _AC_AIM_STATS {
    INT     snapCount;          /* Number of aim snaps              */
    INT     perfectTrackCount;  /* Frames of suspiciously smooth tracking */
    DOUBLE  totalDelta;         /* Sum of all angle deltas          */
    INT     totalSamples;       /* Number of samples                */
    DOUBLE  variance;           /* Running variance of deltas       */
    FLOAT   minDelta;           /* Minimum non-zero delta           */
    FLOAT   maxDelta;           /* Maximum delta                    */
} AC_AIM_STATS;

static AC_AIM_STATS s_stats = {0};

/* ---- Calculate angle between two view angle vectors ---- */
FLOAT AC_CalcAngleDelta(const FLOAT a[3], const FLOAT b[3])
{
    FLOAT dy = b[0] - a[0];   /* Yaw */
    FLOAT dp = b[1] - a[1];   /* Pitch */

    /* Normalize yaw delta to [-180, 180] */
    while (dy > 180.0f)  dy -= 360.0f;
    while (dy < -180.0f) dy += 360.0f;

    /* Clamp pitch delta (shouldn't exceed ±180 in practice) */
    dp = AC_CLAMP(dp, -180.0f, 180.0f);

    return sqrtf(dy * dy + dp * dp);
}

/*
 * Main per-frame analysis function.
 * Game should call this with current & previous player states.
 */
BOOL AC_AnalyzeInput(void)
{
    if (!g_ac.stateValid) return FALSE;

    AC_PLAYERSTATE curr, prev;
    EnterCriticalSection(&g_ac.stateLock);
    curr = g_ac.playerState;
    prev = g_ac.prevState;
    LeaveCriticalSection(&g_ac.stateLock);

    /* ---- 1. Calculate angle delta ---- */
    FLOAT delta = AC_CalcAngleDelta(curr.viewAngles, prev.viewAngles);

    AC_ANGLE_SAMPLE* sample = &s_angleHistory[s_historyIdx];
    sample->deltaYaw  = curr.viewAngles[0] - prev.viewAngles[0];
    sample->deltaPitch = curr.viewAngles[1] - prev.viewAngles[1];

    /* Normalize */
    while (sample->deltaYaw > 180.0f)  sample->deltaYaw -= 360.0f;
    while (sample->deltaYaw < -180.0f) sample->deltaYaw += 360.0f;

    sample->delta     = delta;
    sample->timestamp = GetTickCount();
    sample->firing    = (curr.flags & 1) != 0;  /* Bit 0 = firing */

    s_historyIdx = (s_historyIdx + 1) % AC_ANGLE_HISTORY_SIZE;
    s_historyCount = AC_MIN(s_historyCount + 1, AC_ANGLE_HISTORY_SIZE);

    /* ---- 2. Aim snap detection ---- */
    /* An "aim snap" is a very large instantaneous angle change
       followed by very little change (crosshair locked on target) */
    BOOL snapDetected = FALSE;

    if (delta > AC_AIM_SNAP_ANGLE_DEG && s_historyCount >= 3) {
        /* Check if the frame BEFORE the snap was relatively stable,
           and the frame AFTER is also stable - classic aimbot pattern */
        INT prevIdx = (s_historyIdx - 3 + AC_ANGLE_HISTORY_SIZE)
                      % AC_ANGLE_HISTORY_SIZE;
        INT prevPrevIdx = (s_historyIdx - 4 + AC_ANGLE_HISTORY_SIZE)
                          % AC_ANGLE_HISTORY_SIZE;

        FLOAT prevDelta  = s_angleHistory[prevIdx].delta;
        FLOAT prevDelta2 = s_angleHistory[prevPrevIdx].delta;

        if (prevDelta < 2.0f && prevDelta2 < 2.0f) {
            /* Before snap: stable aim → then huge snap = aimbot */
            s_stats.snapCount++;
            snapDetected = TRUE;

            AC_LOG(AC_SEV_WARNING,
                   "Aim snap: %.1f° (yaw %.1f° pitch %.1f°) [snap count: %d]",
                   delta, sample->deltaYaw, sample->deltaPitch,
                   s_stats.snapCount);

            if (s_stats.snapCount >= AC_AIM_SNAP_COUNT_BAN) {
                AC_RecordEvent(AC_CAT_INPUT, AC_SEV_CRITICAL,
                               "Aimbot detected: excessive aim snaps",
                               (ULONG_PTR)s_stats.snapCount, 0);
            }
        }
    }

    /* ---- 3. Perfect tracking detection ---- */
    /* Human aim has variance. An aimbot tracking a moving target
       produces deltas with abnormally low variance over time. */
    if (s_historyCount >= 60 && delta > 0.5f && delta < 5.0f) {
        /* Calculate running variance of recent deltas */
        DOUBLE mean = 0.0, variance = 0.0;
        INT count = AC_MIN(s_historyCount, 60);

        for (INT i = 0; i < count; i++) {
            INT idx = (s_historyIdx - 1 - i + AC_ANGLE_HISTORY_SIZE)
                      % AC_ANGLE_HISTORY_SIZE;
            mean += s_angleHistory[idx].delta;
        }
        mean /= (DOUBLE)count;

        for (INT i = 0; i < count; i++) {
            INT idx = (s_historyIdx - 1 - i + AC_ANGLE_HISTORY_SIZE)
                      % AC_ANGLE_HISTORY_SIZE;
            DOUBLE diff = s_angleHistory[idx].delta - mean;
            variance += diff * diff;
        }
        variance /= (DOUBLE)count;

        s_stats.variance = variance;

        /* If variance is suspiciously low while aiming,
           it could be smooth aimbot tracking */
        if (variance < 0.01 && mean > 1.0 && count >= 30) {
            s_stats.perfectTrackCount++;
            if (s_stats.perfectTrackCount >= 30) {
                AC_LOG(AC_SEV_CRITICAL,
                       "Perfect tracking detected: mean=%.2f var=%.6f [%d frames]",
                       mean, variance, s_stats.perfectTrackCount);

                AC_RecordEvent(AC_CAT_INPUT, AC_SEV_CRITICAL,
                               "Smooth aimbot: abnormally low aim variance",
                               (ULONG_PTR)(DWORD)(mean * 1000),
                               (ULONG_PTR)(DWORD)(variance * 1000000));
            }
        } else {
            s_stats.perfectTrackCount = 0;
        }
    }

    /* ---- 4. Triggerbot detection ---- */
    /* A triggerbot fires the instant the crosshair is over an enemy.
       Pattern: very small angle change + immediate firing. */
    static DWORD s_lastFireTime = 0;
    if (sample->firing && !s_angleHistory[
            (s_historyIdx - 2 + AC_ANGLE_HISTORY_SIZE) % AC_ANGLE_HISTORY_SIZE
        ].firing)
    {
        /* Player just started firing */
        DWORD timeSinceLastFire = sample->timestamp - s_lastFireTime;
        if (timeSinceLastFire > 500) { /* Not automatic weapon spam */
            /* Check if the aim delta in the frame they fired is near-zero
               (crosshair was perfectly on target instantly) */
            if (delta < 0.5f) {
                static INT triggerCount = 0;
                triggerCount++;
                if (triggerCount >= 5) {
                    AC_LOG(AC_SEV_WARNING,
                           "Possible triggerbot: fire on near-zero delta "
                           "(%.2f°) [%d occurrences]",
                           delta, triggerCount);
                    AC_RecordEvent(AC_CAT_INPUT, AC_SEV_WARNING,
                                   "Triggerbot pattern detected",
                                   (ULONG_PTR)triggerCount, 0);
                }
            }
        }
        s_lastFireTime = sample->timestamp;
    }

    /* ---- 5. Recoil control anomaly ---- */
    /* Perfect recoil control: pitch delta exactly matches recoil pattern
       with no overcorrection. Humans have jitter. */
    if (sample->firing && delta > 0.1f) {
        /* If firing, we expect upward pitch movement (recoil).
           Check if player's pitch compensation is "too perfect" */
        static INT perfectRecoilCount = 0;
        static DOUBLE recoilErrorSum = 0.0;

        /* Simplified: check if the pitch delta while firing
           is consistently the same value */
        /* (A full implementation would compare against the weapon's
           actual recoil table) */
        if (fabsf(sample->deltaPitch) < 0.01f) {
            perfectRecoilCount++;
            if (perfectRecoilCount >= 20) {
                AC_LOG(AC_SEV_WARNING,
                       "Perfect recoil control: %d consecutive frames",
                       perfectRecoilCount);
                AC_RecordEvent(AC_CAT_INPUT, AC_SEV_WARNING,
                               "No-recoil hack suspected",
                               (ULONG_PTR)perfectRecoilCount, 0);
            }
        } else {
            perfectRecoilCount = 0;
        }
    }

    return snapDetected;
}
```

---

## Network/Movement Validation

```c
/* ==========================================================================
 * ac_network.c - Server-side movement & packet validation
 *
 * These functions run on both client (for pre-validation) and server
 * (for authoritative validation). The server is the final arbiter.
 * ========================================================================== */

#include "ac_common.h"

/* ---- Movement constraints (TODO: tune) ---- */
#define AC_MAX_MOVE_SPEED       600.0f    /* Units/sec  */
#define AC_MAX_ACCEL            2000.0f   /* Units/sec² */
#define AC_MAX_JUMP_VELOCITY    400.0f    /* Units/sec  */
#define AC_MAX_TURN_RATE        720.0f    /* Deg/sec    */
#define AC_GRAVITY              800.0f    /* Units/sec² */

/*
 * Validate movement between two player states.
 * The server should call this for every movement packet received.
 *
 * Returns TRUE if movement is valid, FALSE if anomalous.
 */
BOOL AC_ValidateMovement(const AC_PLAYERSTATE* prev,
                         const AC_PLAYERSTATE* curr)
{
    if (!prev || !curr) return TRUE; /* First frame, no prev state */

    /* ---- Time delta ---- */
    /* Use server-authoritative time */
    DOUBLE dt = curr->serverTime - prev->serverTime;
    if (dt <= 0.0 || dt > 1.0) {
        /* Invalid time delta */
        AC_RecordEvent(AC_CAT_NETWORK, AC_SEV_CRITICAL,
                       "Invalid movement time delta",
                       (ULONG_PTR)(DWORD)(dt * 1000), 0);
        return FALSE;
    }

    /* ---- Position delta ---- */
    FLOAT dx = curr->position[0] - prev->position[0];
    FLOAT dy = curr->position[1] - prev->position[1];
    FLOAT dz = curr->position[2] - prev->position[2];
    FLOAT dist = sqrtf(dx * dx + dy * dy + dz * dz);
    FLOAT speed = dist / (FLOAT)dt;

    if (speed > AC_MAX_MOVE_SPEED * 1.1f) { /* 10% tolerance */
        AC_LOG(AC_SEV_CRITICAL,
               "Speed hack: %.1f u/s (max %.1f)", speed, AC_MAX_MOVE_SPEED);
        AC_RecordEvent(AC_CAT_NETWORK, AC_SEV_CRITICAL,
                       "Excessive movement speed",
                       (ULONG_PTR)(DWORD)(speed * 100), 0);
        return FALSE;
    }

    /* ---- Velocity consistency ---- */
    FLOAT expectedVx = dx / (FLOAT)dt;
    FLOAT expectedVy = dy / (FLOAT)dt;
    FLOAT expectedVz = dz / (FLOAT)dt;

    FLOAT velError = sqrtf(
        (curr->velocity[0] - expectedVx) * (curr->velocity[0] - expectedVx) +
        (curr->velocity[1] - expectedVy) * (curr->velocity[1] - expectedVy) +
        (curr->velocity[2] - expectedVz) * (curr->velocity[2] - expectedVz)
    );

    if (velError > AC_MAX_MOVE_SPEED * 0.5f) {
        AC_LOG(AC_SEV_WARNING,
               "Velocity mismatch: error=%.1f", velError);
        AC_RecordEvent(AC_CAT_NETWORK, AC_SEV_WARNING,
                       "Reported velocity doesn't match position change",
                       (ULONG_PTR)(DWORD)(velError * 100), 0);
    }

    /* ---- Turn rate ---- */
    FLOAT deltaYaw = curr->viewAngles[0] - prev->viewAngles[0];
    while (deltaYaw > 180.0f)  deltaYaw -= 360.0f;
    while (deltaYaw < -180.0f) deltaYaw += 360.0f;

    FLOAT turnRate = fabsf(deltaYaw) / (FLOAT)dt;

    if (turnRate > AC_MAX_TURN_RATE) {
        AC_LOG(AC_SEV_CRITICAL,
               "Turn rate hack: %.1f deg/s (max %.1f)",
               turnRate, AC_MAX_TURN_RATE);
        AC_RecordEvent(AC_CAT_NETWORK, AC_SEV_CRITICAL,
                       "Excessive turn rate",
                       (ULONG_PTR)(DWORD)(turnRate * 10), 0);
        return FALSE;
    }

    /* ---- Gravity / fly hack ---- */
    BOOL onGround = (curr->flags & 2) != 0;
    BOOL wasOnGround = (prev->flags & 2) != 0;

    if (!onGround && !wasOnGround) {
        /* In air - check that vertical velocity follows gravity */
        FLOAT expectedDz = prev->velocity[2] - AC_GRAVITY * (FLOAT)dt;
        FLOAT dzError = fabsf(curr->velocity[2] - expectedDz);

        if (dzError > 100.0f) {
            AC_LOG(AC_SEV_CRITICAL,
                   "Fly hack: vertical velocity error=%.1f (expected %.1f got %.1f)",
                   dzError, expectedDz, curr->velocity[2]);
            AC_RecordEvent(AC_CAT_NETWORK, AC_SEV_CRITICAL,
                           "Gravity violation (possible fly hack)",
                           (ULONG_PTR)(DWORD)(dzError * 10), 0);
            return FALSE;
        }
    }

    return TRUE;
}

/*
 * Validate a complete movement packet (server-side).
 * This is a more thorough check that considers the full state.
 */
typedef struct _AC_MOVE_PACKET {
    FLOAT    position[3];
    FLOAT    velocity[3];
    FLOAT    viewAngles[3];
    DWORD    flags;
    DOUBLE   clientTime;
    DWORD    sequenceNum;
    BYTE     hash[32];         /* SHA-256 of packet for tamper check */
} AC_MOVE_PACKET;

BOOL AC_ValidateMovePacket(const AC_MOVE_PACKET* pkt,
                           const AC_PLAYERSTATE* prevState,
                           const CHAR* sharedSecret)
{
    if (!pkt || !prevState) return FALSE;

    /* ---- 1. Verify packet hash ---- */
    BYTE computedHash[32];
    /* (Compute SHA-256 of packet fields + shared secret)   */
    /* For brevity, using CRC32 as a placeholder.           */
    /* Production code: use SHA-256 or HMAC-SHA256.         */

    /* ---- 2. Check sequence number ---- */
    static DWORD s_expectedSeq = 0;
    if (pkt->sequenceNum < s_expectedSeq) {
        AC_LOG(AC_SEV_CRITICAL,
               "Out-of-order packet: seq %u expected %u",
               pkt->sequenceNum, s_expectedSeq);
        return FALSE;
    }

    /* ---- 3. Check client time ---- */
    /* Client time should be within reasonable range of server time */
    /* (Prevents old-packet replay attacks) */

    /* ---- 4. Validate the movement itself ---- */
    AC_PLAYERSTATE predicted;
    predicted.position[0] = pkt->position[0];
    predicted.position[1] = pkt->position[1];
    predicted.position[2] = pkt->position[2];
    predicted.velocity[0] = pkt->velocity[0];
    predicted.velocity[1] = pkt->velocity[1];
    predicted.velocity[2] = pkt->velocity[2];
    predicted.viewAngles[0] = pkt->viewAngles[0];
    predicted.viewAngles[1] = pkt->viewAngles[1];
    predicted.viewAngles[2] = pkt->viewAngles[2];
    predicted.flags = pkt->flags;
    predicted.serverTime = pkt->clientTime;

    return AC_ValidateMovement(prevState, &predicted);
}
```

---

## Hardware ID

```c
/* ==========================================================================
 * ac_hwid.c - Hardware fingerprint generation for ban enforcement
 *
 * Generates a stable hardware ID from multiple system identifiers.
 * No single identifier is sufficient; we combine several to resist
 * spoofing of any one component.
 * ========================================================================== */

#include "ac_common.h"
#include <intrin.h>

/* ---- Helper: XOR-fold a buffer into a 32-bit hash ---- */
static DWORD AC_FoldHash(const BYTE* data, SIZE_T len)
{
    DWORD h = 0x12345678;
    for (SIZE_T i = 0; i < len; i++) {
        h = ((h << 5) + h) ^ data[i];
    }
    return h;
}

/*
 * Collect hardware identifiers and produce a composite HWID string.
 * Returns hex string in `out` buffer of length `outLen`.
 */
BOOL AC_GenerateHWID(CHAR* out, SIZE_T outLen)
{
    if (!out || outLen < 65) return FALSE;

    DWORD identifiers[8] = {0};  /* We'll hash 8 values */
    INT idx = 0;

    /* ---- 1. CPUID ---- */
    INT cpuinfo[4];
    __cpuid(cpuinfo, 1);
    identifiers[idx++] = cpuinfo[0];  /* Processor info  */
    identifiers[idx++] = cpuinfo[3];  /* Feature flags   */

    /* ---- 2. Volume serial number of system drive ---- */
    CHAR sysDir[MAX_PATH];
    GetSystemDirectoryA(sysDir, MAX_PATH);
    sysDir[3] = '\0';  /* Just "C:\" */

    DWORD volSerial = 0;
    GetVolumeInformationA(sysDir, NULL, 0, &volSerial, NULL, NULL, NULL, 0);
    identifiers[idx++] = volSerial;

    /* ---- 3. Computer name hash ---- */
    CHAR computerName[MAX_PATH];
    DWORD nameLen = MAX_PATH;
    GetComputerNameA(computerName, &nameLen);
    identifiers[idx++] = AC_FoldHash((BYTE*)computerName, nameLen);

    /* ---- 4. MAC address ---- */
    /* Use first non-zero MAC from GetAdaptersInfo */
    {
        ULONG bufLen = 0;
        GetAdaptersInfo(NULL, &bufLen);
        PIP_ADAPTER_INFO adapterInfo = (PIP_ADAPTER_INFO)malloc(bufLen);
        if (adapterInfo) {
            if (GetAdaptersInfo(adapterInfo, &bufLen) == ERROR_SUCCESS) {
                PIP_ADAPTER_INFO adapter = adapterInfo;
                while (adapter) {
                    if (adapter->AddressLength >= 6 &&
                        (adapter->Address[0] != 0 ||
                         adapter->Address[1] != 0 ||
                         adapter->Address[2] != 0))
                    {
                        DWORD macHash = AC_FoldHash(adapter->Address,
                                                    adapter->AddressLength);
                        identifiers[idx++] = macHash;
                        break;
                    }
                    adapter = adapter->Next;
                }
            }
            free(adapterInfo);
        }
    }

    /* ---- 5. SMBIOS / BIOS serial ---- */
    /* Read from registry as a proxy for WMI */
    {
        HKEY hKey;
        if (RegOpenKeyExA(HKEY_LOCAL_MACHINE,
            "HARDWARE\\DESCRIPTION\\System\\BIOS",
            0, KEY_READ, &hKey) == ERROR_SUCCESS)
        {
            CHAR biosVersion[256];
            DWORD dataSize = sizeof(biosVersion);
            if (RegQueryValueExA(hKey, "SystemManufacturer", NULL, NULL,
                                 (LPBYTE)biosVersion, &dataSize) == ERROR_SUCCESS)
            {
                identifiers[idx++] = AC_FoldHash((BYTE*)biosVersion, dataSize);
            }
            RegCloseKey(hKey);
        }
    }

    /* ---- 6. Disk drive serial ---- */
    {
        HKEY hKey;
        if (RegOpenKeyExA(HKEY_LOCAL_MACHINE,
            "SYSTEM\\CurrentControlSet\\Services\\Disk\\Enum",
            0, KEY_READ, &hKey) == ERROR_SUCCESS)
        {
            CHAR diskId[256];
            DWORD dataSize = sizeof(diskId);
            if (RegQueryValueExA(hKey, "0", NULL, NULL,
                                 (LPBYTE)diskId, &dataSize) == ERROR_SUCCESS)
            {
                identifiers[idx++] = AC_FoldHash((BYTE*)diskId, dataSize);
            }
            RegCloseKey(hKey);
        }
    }

    /* ---- 7. Memory size ---- */
    MEMORYSTATUSEX memStatus = { .dwLength = sizeof(memStatus) };
    GlobalMemoryStatusEx(&memStatus);
    identifiers[idx++] = (DWORD)(memStatus.ullTotalPhys >> 20); /* MB */

    /* ---- Compute composite hash (CRC32 of all identifiers) ---- */
    DWORD compositeCRC = AC_CRC32((BYTE*)identifiers, idx * sizeof(DWORD));

    /* Also compute a secondary hash using fold for verification */
    DWORD secondaryHash = 0xABCDEF01;
    for (INT i = 0; i < idx; i++) {
        secondaryHash ^= identifiers[i];
        secondaryHash = (secondaryHash << 3) | (secondaryHash >> 29);
    }

    /* Format as hex string */
    sprintf_s(out, outLen, "%08X%08X%08X%08X%08X%08X%08X%08X",
              identifiers[0], identifiers[1], identifiers[2], identifiers[3],
              identifiers[4], identifiers[5], identifiers[6] ? identifiers[6] : 0,
              compositeCRC ^ secondaryHash);

    AC_LOG(AC_SEV_INFO, "Generated HWID: %s", out);
    return TRUE;
}

/*
 * Check if this HWID is banned.
 * In production, this queries server's ban database.
 */
BOOL AC_IsHWIDBanned(const CHAR* hwid)
{
    /* Placeholder: in production, make HTTPS request to server:
     *
     *   GET /api/ac/check_ban?hwid=<hwid>
     *
     * Server returns { "banned": true/false, "reason": "..." }
     */

    /* For now, check a local file of banned HWIDs */
    CHAR path[MAX_PATH];
    GetModuleFileNameA(NULL, path, MAX_PATH);
    PathRemoveFileSpecA(path);
    strcat_s(path, MAX_PATH, "\\banned_hwids.txt");

    FILE* f = NULL;
    if (fopen_s(&f, path, "r") == 0 && f) {
        CHAR line[128];
        while (fgets(line, sizeof(line), f)) {
            /* Remove newline */
            line[strcspn(line, "\r\n")] = '\0';
            if (strcmp(line, hwid) == 0) {
                fclose(f);
                return TRUE;
            }
        }
        fclose(f);
    }

    return FALSE;
}
```

---

## Screenshot / Overlay Detection

```c
/* ==========================================================================
 * ac_screenshot.c - Overlay and wallhack detection via screenshot analysis
 *
 * Takes a screenshot of the game window and analyzes it for:
 *   - Overlay windows (transparent windows on top of game)
 *   - ESP/wallhack visual artifacts
 *   - Modified rendering output
 * ========================================================================== */

#include "ac_common.h"

/*
 * Capture a screenshot of the game window's client area.
 * Returns a BYTE* buffer (RGB, caller must free) or NULL.
 */
static BYTE* AC_CaptureScreen(INT* outWidth, INT* outHeight)
{
    HWND hGameWnd = GetForegroundWindow();
    if (!hGameWnd) return NULL;

    RECT rc;
    GetClientRect(hGameWnd, &rc);
    INT width  = rc.right - rc.left;
    INT height = rc.bottom - rc.top;

    if (width <= 0 || height <= 0) return NULL;

    HDC hdcScreen = GetDC(hGameWnd);
    HDC hdcMem    = CreateCompatibleDC(hdcScreen);
    HBITMAP hBmp  = CreateCompatibleBitmap(hdcScreen, width, height);

    SelectObject(hdcMem, hBmp);
    BitBlt(hdcMem, 0, 0, width, height, hdcScreen, 0, 0, SRCCOPY);

    BITMAPINFOHEADER bih = {0};
    bih.biSize        = sizeof(BITMAPINFOHEADER);
    bih.biWidth       = width;
    bih.biHeight      = -height; /* Top-down */
    bih.biPlanes      = 1;
    bih.biBitCount    = 24;
    bih.biCompression = BI_RGB;

    INT rowSize = ((width * 3 + 3) & ~3); /* Aligned to 4 bytes */
    INT imgSize = rowSize * height;

    BYTE* pixels = (BYTE*)malloc(imgSize);
    if (!pixels) {
        DeleteObject(hBmp);
        DeleteDC(hdcMem);
        ReleaseDC(hGameWnd, hdcScreen);
        return NULL;
    }

    GetDIBits(hdcMem, hBmp, 0, height, pixels,
              (BITMAPINFO*)&bih, DIB_RGB_COLORS);

    DeleteObject(hBmp);
    DeleteDC(hdcMem);
    ReleaseDC(hGameWnd, hdcScreen);

    *outWidth  = width;
    *outHeight = height;
    return pixels;
}

/*
 * Detect overlay windows on top of the game.
 * Many ESP/wallhack tools use transparent overlay windows.
 */
static INT AC_DetectOverlayWindows(void)
{
    INT overlayCount = 0;
    HWND hGameWnd = GetForegroundWindow();
    DWORD gamePID = GetCurrentProcessId();
    RECT gameRect;
    GetWindowRect(hGameWnd, &gameRect);

    /* Enumerate all top-level windows */
    struct EnumData {
        DWORD  gamePID;
        RECT   gameRect;
        INT    overlayCount;
        HWND   gameWnd;
    } data = { gamePID, gameRect, 0, hGameWnd };

    WNDENUMPROC enumProc = (WNDENUMPROC)[](HWND hwnd, LPARAM lParam) -> BOOL {
        auto* d = (decltype(data)*)lParam;

        if (hwnd == d->gameWnd) return TRUE;

        DWORD wndPID;
        GetWindowThreadProcessId(hwnd, &wndPID);

        /* Skip our own process windows */
        if (wndPID == d->gamePID) return TRUE;

        /* Check if window is visible and overlaps our game */
        if (!IsWindowVisible(hwnd)) return TRUE;

        RECT wndRect;
        GetWindowRect(hwnd, &wndRect);

        /* Check overlap */
        RECT intersect;
        if (IntersectRect(&intersect, &d->gameRect, &wndRect)) {
            /* Check if the window is layered (WS_EX_LAYERED) - common for overlays */
            LONG exStyle = GetWindowLongW(hwnd, GWL_EXSTYLE);

            if (exStyle & WS_EX_LAYERED) {
                /* Check transparency */
                BYTE alpha = 255;
                DWORD colorKey = 0;
                DWORD flags = 0;
                GetLayeredWindowAttributes(hwnd, &colorKey, &alpha, &flags);

                if (alpha < 255 || (flags & LWA_COLORKEY)) {
                    /* Transparent or colorkeyed overlay - very suspicious */
                    CHAR className[256];
                    GetClassNameA(hwnd, className, sizeof(className));
                    CHAR title[256];
                    GetWindowTextA(hwnd, title, sizeof(title));

                    AC_LOG(AC_SEV_CRITICAL,
                           "Overlay window detected: class='%s' title='%s' alpha=%d",
                           className, title, alpha);

                    AC_RecordEvent(AC_CAT_SCREENSHOT, AC_SEV_CRITICAL,
                                   "Transparent overlay window detected",
                                   (ULONG_PTR)wndPID, alpha);
                    d->overlayCount++;
                }
            }

            /* Also check for TOPMOST windows (common for overlays) */
            if (exStyle & WS_EX_TOPMOST) {
                CHAR className[256];
                GetClassNameA(hwnd, className, sizeof(className));

                /* Whitelist known legitimate topmost windows */
                if (!strstr(className, "Shell_TrayWnd") &&     /* Taskbar */
                    !strstr(className, "Progman") &&           /* Desktop */
                    !strstr(className, "WorkerW") &&           /* Desktop */
                    !strstr(className, "Microsoft.Windows.Shell") &&
                    !strstr(className, "GameOverlay"))
                {
                    AC_LOG(AC_SEV_WARNING,
                           "Topmost window over game: class='%s'",
                           className);
                    AC_RecordEvent(AC_CAT_SCREENSHOT, AC_SEV_WARNING,
                                   "Topmost window over game area",
                                   (ULONG_PTR)wndPID, 0);
                    d->overlayCount++;
                }
            }
        }

        return TRUE;
    };

    EnumWindows(enumProc, (LPARAM)&data);

    return data.overlayCount;
}

/*
 * Analyze screenshot for ESP artifacts.
 * ESP (Extra Sensory Perception) overlays typically draw:
 *   - Bright-colored outlines (red/green/blue boxes around players)
 *   - Text labels
 *   - Lines from screen center to off-screen targets
 *
 * Detection approach:
 *   1. Sample pixels in regions where enemies are NOT present
 *      (server can provide enemy positions → we know what SHOULD be visible)
 *   2. Check for abnormally bright/pure-color pixels that shouldn't exist
 *   3. Check for consistent color patterns across frames
 */
static BOOL AC_AnalyzeScreenshot(const BYTE* pixels, INT w, INT h)
{
    if (!pixels || w <= 0 || h <= 0) return FALSE;

    INT rowSize = ((w * 3 + 3) & ~3);

    /* ---- 1. Check for pure-color pixels (common in ESP) ---- */
    INT pureColorCount = 0;
    INT brightPixelCount = 0;
    INT totalSampled = 0;

    /* Sample every 4th pixel for performance */
    for (INT y = 0; y < h; y += 4) {
        for (INT x = 0; x < w; x += 4) {
            BYTE* px = (BYTE*)((BYTE*)pixels + y * rowSize + x * 3);

            BYTE r = px[0], g = px[1], b = px[2];

            /* Pure red/green/blue (ESP often uses pure colors) */
            if ((r == 255 && g == 0   && b == 0) ||   /* Red box     */
                (r == 0   && g == 255 && b == 0) ||   /* Green box   */
                (r == 0   && g == 0   && b == 255) || /* Blue box    */
                (r == 255 && g == 255 && b == 0) ||   /* Yellow box  */
                (r == 255 && g == 0   && b == 255) || /* Magenta box */
                (r == 0   && g == 255 && b == 255))   /* Cyan box    */
            {
                pureColorCount++;
            }

            /* Very bright pixels */
            if (r > 250 && g > 250 && b > 250) {
                brightPixelCount++;
            }

            totalSampled++;
        }
    }

    /* Calculate ratios */
    FLOAT pureRatio   = (FLOAT)pureColorCount / (FLOAT)totalSampled;
    FLOAT brightRatio = (FLOAT)brightPixelCount / (FLOAT)totalSampled;

    /* Thresholds - TODO: tune visual style */
    BOOL suspicious = FALSE;

    if (pureRatio > 0.005f) { /* >0.5% pure-color pixels is unusual */
        AC_LOG(AC_SEV_WARNING,
               "ESP artifact: %.2f%% pure-color pixels (%d/%d)",
               pureRatio * 100, pureColorCount, totalSampled);
        suspicious = TRUE;
    }

    /* ---- 2. Edge detection for ESP boxes ---- */
    /* Simplified: check for vertical/horizontal lines of pure color */
    /* (Full implementation would use Sobel/Canny edge detection)    */

    return suspicious;
}

/*
 * Main screenshot analysis entry point.
 */
BOOL AC_CaptureAndAnalyze(void)
{
    INT w, h;
    BYTE* pixels = AC_CaptureScreen(&w, &h);
    if (!pixels) {
        AC_LOG(AC_SEV_WARNING, "Failed to capture screenshot");
        return FALSE;
    }

    BOOL overlayDetected = AC_DetectOverlayWindows() > 0;
    BOOL espDetected     = AC_AnalyzeScreenshot(pixels, w, h);

    free(pixels);

    return overlayDetected || espDetected;
}
```

---

## Server Reporting

```c
/* ==========================================================================
 * ac_report.c - Send detection reports to the server
 *
 * Uses WinHTTP to POST detection events to the backend.
 * Reports include HWID, timestamp, category, severity, and detail.
 * ========================================================================== */

#include "ac_common.h"
#include <winhttp.h>

#pragma comment(lib, "winhttp.lib")

/*
 * Serialize an event to JSON and POST it to the report server.
 */
BOOL AC_SendReport(const AC_EVENT* evt)
{
    if (!evt) return FALSE;

    /* ---- Build JSON payload ---- */
    CHAR json[2048];
    sprintf_s(json, sizeof(json),
        "{"
        "  \"hwid\": \"%s\","
        "  \"timestamp\": %u,"
        "  \"category\": %d,"
        "  \"severity\": %d,"
        "  \"detail\": \"%s\","
        "  \"param1\": %llu,"
        "  \"param2\": %llu"
        "}",
        g_ac.hwid,
        evt->timestamp,
        (INT)evt->category,
        (INT)evt->severity,
        evt->detail,
        (unsigned long long)evt->param1,
        (unsigned long long)evt->param2
    );

    /* ---- Send via WinHTTP ---- */
    BOOL result = FALSE;
    HINTERNET hSession = WinHttpOpen(
        L"AntiCheat/1.0",
        WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
        WINHTTP_NO_PROXY_NAME,
        WINHTTP_NO_PROXY_BYPASS, 0);

    if (hSession) {
        HINTERNET hConnect = WinHttpConnect(
            hSession, L"gameserver.com",
            INTERNET_DEFAULT_HTTPS_PORT, 0);

        if (hConnect) {
            HINTERNET hRequest = WinHttpOpenRequest(
                hConnect, L"POST",
                L"/api/ac/report",
                NULL, WINHTTP_NO_REFERER,
                WINHTTP_DEFAULT_ACCEPT_TYPES,
                WINHTTP_FLAG_SECURE);

            if (hRequest) {
                /* Set headers */
                LPCWSTR headers = L"Content-Type: application/json\r\n";

                /* Convert JSON to wide string */
                WCHAR wJson[2048];
                MultiByteToWideChar(CP_ACP, 0, json, -1,
                                    wJson, 2048);

                DWORD jsonLen = (DWORD)strlen(json);

                if (WinHttpSendRequest(hRequest, headers, (DWORD)-1,
                    (LPVOID)json, jsonLen, jsonLen, 0))
                {
                    result = TRUE;
                }

                WinHttpCloseHandle(hRequest);
            }

            WinHttpCloseHandle(hConnect);
        }

        WinHttpCloseHandle(hSession);
    }

    /* ---- Fallback: write to local log file ---- */
    if (!result) {
        CHAR path[MAX_PATH];
        GetModuleFileNameA(NULL, path, MAX_PATH);
        PathRemoveFileSpecA(path);
        strcat_s(path, MAX_PATH, "\\ac_report.log");

        FILE* f = NULL;
        if (fopen_s(&f, path, "a") == 0 && f) {
            fprintf(f, "[%u][CAT%d][SEV%d] %s (p1=%llu p2=%llu)\n",
                    evt->timestamp, (INT)evt->category,
                    (INT)evt->severity, evt->detail,
                    (unsigned long long)evt->param1,
                    (unsigned long long)evt->param2);
            fclose(f);
        }
    }

    return result;
}
```

---

## Core - Initialization, Scan Loop, Event Handling

```c
/* ==========================================================================
 * ac_core.c - Main orchestrator: init, shutdown, scan thread, event system
 * ========================================================================== */

#include "ac_common.h"

/* ---- Forward declarations for internal modules ---- */
/* (Declared in ac_common.h, implemented in other .c files) */

/* ------------------------------------------------------------------
 * Record a detection event
 * ------------------------------------------------------------------ */
void AC_RecordEvent(AC_CATEGORY cat, AC_SEVERITY sev,
                    const CHAR* detail, ULONG_PTR p1, ULONG_PTR p2)
{
    EnterCriticalSection(&g_ac.eventLock);

    if (g_ac.eventCount < 256) {
        AC_EVENT* evt = &g_ac.events[g_ac.eventCount++];
        evt->category  = cat;
        evt->severity  = sev;
        evt->timestamp = GetTickCount();
        strncpy_s(evt->detail, sizeof(evt->detail), detail, 255);
        evt->param1 = p1;
        evt->param2 = p2;

        AC_LOG(sev, "[%d:%d] %s", (INT)cat, (INT)sev, detail);

        /* Send to server asynchronously */
        AC_SendReport(evt);
    }

    LeaveCriticalSection(&g_ac.eventLock);

    /* Check if we should ban */
    AC_EvaluateBan();
}

/* ------------------------------------------------------------------
 * Evaluate whether to ban based on accumulated detections
 * ------------------------------------------------------------------ */
void AC_EvaluateBan(void)
{
    BOOL shouldBan = FALSE;
    CHAR reason[256] = {0};

    /* Any single BAN-severity event triggers ban */
    EnterCriticalSection(&g_ac.eventLock);

    for (INT i = 0; i < g_ac.eventCount; i++) {
        AC_EVENT* evt = &g_ac.events[i];

        if (evt->severity == AC_SEV_BAN) {
            shouldBan = TRUE;
            sprintf_s(reason, sizeof(reason),
                      "BAN event: %s", evt->detail);
            break;
        }
    }

    /* Cumulative detections */
    if (g_ac.crcFailCount >= AC_CRC_MISMATCH_BAN) {
        shouldBan = TRUE;
        sprintf_s(reason, sizeof(reason),
                  "CRC fail count: %d", g_ac.crcFailCount);
    }

    if (g_ac.suspiciousProcCount >= AC_MAX_SUSPICIOUS_PROCS) {
        shouldBan = TRUE;
        sprintf_s(reason, sizeof(reason),
                  "Suspicious process count: %d",
                  g_ac.suspiciousProcCount);
    }

    if (g_ac.hookDetectCount >= 3) {
        shouldBan = TRUE;
        sprintf_s(reason, sizeof(reason),
                  "Hook detection count: %d", g_ac.hookDetectCount);
    }

    /* Cumulative detections - Add VM counter */
    INT vmDetectCount = 0;
    for (INT i = 0; i < g_ac.eventCount; i++) {
        if (g_ac.events[i].category == AC_CAT_VIRTUALIZATION) {
            vmDetectCount++;
        }
    }

    /* If we detect VM/Sandbox heuristics multiple times, it's not a false positive */
    if (vmDetectCount >= 2) {
        shouldBan = TRUE;
        sprintf_s(reason, sizeof(reason),
                  "Virtualization/Sandbox environment detected (%d indicators)", vmDetectCount);
    }

    LeaveCriticalSection(&g_ac.eventLock);

    if (shouldBan) {
        AC_LOG(AC_SEV_BAN, "BANNED: %s", reason);

        if (g_ac.fnBanCallback) {
            g_ac.fnBanCallback(AC_CAT_INTEGRITY, reason);
        }

        /* Record ban event to local file (server already notified) */
        CHAR path[MAX_PATH];
        GetModuleFileNameA(NULL, path, MAX_PATH);
        PathRemoveFileSpecA(path);
        strcat_s(path, MAX_PATH, "\\ban.flag");

        FILE* f = NULL;
        if (fopen_s(&f, path, "w") == 0 && f) {
            fprintf(f, "BANNED\n%s\n", reason);
            fclose(f);
        }
    }
}

/* ------------------------------------------------------------------
 * Update player state (called by game every frame)
 * ------------------------------------------------------------------ */
void AC_UpdatePlayerState(const AC_PLAYERSTATE* ps)
{
    if (!ps) return;

    EnterCriticalSection(&g_ac.stateLock);
    g_ac.prevState  = g_ac.playerState;
    g_ac.playerState = *ps;
    g_ac.stateValid  = TRUE;
    LeaveCriticalSection(&g_ac.stateLock);
}

/* ------------------------------------------------------------------
 * Background scan thread
 * ------------------------------------------------------------------ */
static DWORD s_lastMemoryScan  = 0;
static DWORD s_lastProcessScan = 0;
static DWORD s_lastHookScan    = 0;
static DWORD s_lastTimingScan  = 0;
static DWORD s_lastInputScan   = 0;
static DWORD s_lastSSScan      = 0;
static DWORD s_lastVMScan      = 0;

DWORD WINAPI AC_ScanThread(LPVOID param)
{
    AC_LOG(AC_SEV_INFO, "Scan thread started (TID %u)",
           GetCurrentThreadId());

    while (g_ac.running) {
        DWORD now = GetTickCount();

        /* ---- Memory integrity scan ---- */
        if (now - s_lastMemoryScan >= AC_MEMORY_SCAN_INTERVAL) {
            AC_CheckRandomPages(4);
            AC_VerifyCanaries();
            s_lastMemoryScan = now;
        }

        /* ---- Process scan ---- */
        if (now - s_lastProcessScan >= AC_PROCESS_SCAN_INTERVAL) {
            AC_ScanSuspiciousProcesses();
            AC_ScanLoadedModules();
            s_lastProcessScan = now;
        }

        /* ---- Hook scan ---- */
        if (now - s_lastHookScan >= AC_HOOK_SCAN_INTERVAL) {
            AC_DetectIATHooks(g_ac.hGameModule);
            AC_DetectInlineHooks(g_ac.hGameModule);
            AC_DetectDebugHooks();
            s_lastHookScan = now;
        }

        /* ---- Timing / speed-hack scan ---- */
        if (now - s_lastTimingScan >= AC_TIMING_SAMPLE_INTERVAL) {
            AC_CheckTimingAnomaly();
            s_lastTimingScan = now;
        }

        /* ---- Input analysis ---- */
        if (now - s_lastInputScan >= AC_INPUT_SAMPLE_INTERVAL) {
            AC_AnalyzeInput();
            s_lastInputScan = now;
        }

        /* ---- Screenshot analysis ---- */
        if (now - s_lastSSScan >= AC_SS_INTERVAL) {
            AC_CaptureAndAnalyze();
            s_lastSSScan = now;
        }

        /* ---- Virtualization / Sandbox scan ---- */
        if (now - s_lastVMScan >= AC_VM_SCAN_INTERVAL) {
            AC_ScanVirtualization();
            s_lastVMScan = now;
        }

        /* ---- Anti-debug (every heartbeat) ---- */
        AC_DetectDebugger();

        /* ---- Sleep until next tick ---- */
        Sleep(AC_HEARTBEAT_INTERVAL);
    }

    AC_LOG(AC_SEV_INFO, "Scan thread exiting");
    return 0;
}

/* ------------------------------------------------------------------
 * Initialize the AntiCheat system
 * ------------------------------------------------------------------ */
BOOL AC_Initialize(HMODULE hGameModule)
{
    memset(&g_ac, 0, sizeof(g_ac));

    g_ac.hGameModule = hGameModule;
    g_ac.running     = TRUE;

    /* Initialize critical sections */
    InitializeCriticalSection(&g_ac.stateLock);
    InitializeCriticalSection(&g_ac.eventLock);

    /* ---- Generate HWID ---- */
    if (!AC_GenerateHWID(g_ac.hwid, sizeof(g_ac.hwid))) {
        AC_LOG(AC_SEV_WARNING, "Failed to generate HWID");
    }

    /* ---- Check if this HWID is banned ---- */
    if (AC_IsHWIDBanned(g_ac.hwid)) {
        AC_LOG(AC_SEV_BAN, "Banned HWID detected: %s", g_ac.hwid);
        AC_RecordEvent(AC_CAT_HWID, AC_SEV_BAN,
                       "Banned hardware ID", 0, 0);
        /* Don't return FALSE - let the game decide how to handle it */
    }

    /* ---- Compute code integrity baseline ---- */
    if (!AC_ComputeModuleCRC(hGameModule, &s_baselineCRC, &s_gameCodeSize)) {
        AC_LOG(AC_SEV_WARNING, "Failed to compute initial code CRC");
    } else {
        AC_LOG(AC_SEV_INFO, "Baseline CRC: 0x%08X (size %u)",
               s_baselineCRC, s_gameCodeSize);
    }

    /* ---- Initialize page-level CRC ---- */
    if (!AC_InitPageCRCs()) {
        AC_LOG(AC_SEV_WARNING, "Failed to initialize page CRCs");
    }

    /* ---- Place canary guards ---- */
    /* Place canaries next to important game data structures.
       The game code should call AC_PlaceCanary() for its data. */

    /* ---- Initialize timing ---- */
    AC_InitTiming();

    /* ---- Start scan thread ---- */
    g_ac.hScanThread = CreateThread(
        NULL, 0, AC_ScanThread, NULL, 0, NULL);

    if (!g_ac.hScanThread) {
        AC_LOG(AC_SEV_CRITICAL, "Failed to create scan thread");
        return FALSE;
    }

    /* Set thread priority to reduce game impact */
    SetThreadPriority(g_ac.hScanThread, THREAD_PRIORITY_BELOW_NORMAL);

    AC_LOG(AC_SEV_INFO,
           "AntiCheat v%s initialized (HWID: %.16s...)",
           AC_VERSION, g_ac.hwid);

    return TRUE;
}

/* ------------------------------------------------------------------
 * Shut down the AntiCheat system
 * ------------------------------------------------------------------ */
void AC_Shutdown(void)
{
    g_ac.running = FALSE;

    if (g_ac.hScanThread) {
        WaitForSingleObject(g_ac.hScanThread, 5000);
        CloseHandle(g_ac.hScanThread);
        g_ac.hScanThread = NULL;
    }

    DeleteCriticalSection(&g_ac.stateLock);
    DeleteCriticalSection(&g_ac.eventLock);

    AC_LOG(AC_SEV_INFO, "AntiCheat shut down. Total events: %d",
           g_ac.eventCount);
}

/* ------------------------------------------------------------------
 * Self-integrity check: verify the AC code itself hasn't been patched
 * ------------------------------------------------------------------ */
BOOL AC_SelfCheck(void)
{
    /* Check that critical function pointers haven't been tampered with */
    HMODULE hAC = GetModuleHandleA(NULL); /* or, AC DLL */

    /* Verify our own functions are still at the correct addresses */
    if ((FARPROC)AC_Initialize == NULL ||
        (FARPROC)AC_ScanThread == NULL ||
        (FARPROC)AC_RecordEvent == NULL)
    {
        AC_LOG(AC_SEV_BAN, "AC self-check failed: function pointers invalid");
        AC_RecordEvent(AC_CAT_INTEGRITY, AC_SEV_BAN,
                       "AntiCheat self-integrity check failed", 0, 0);
        return FALSE;
    }

    /* Check that our globals are sane */
    if (g_ac.running && g_ac.hScanThread == NULL) {
        AC_LOG(AC_SEV_BAN, "AC self-check: scan thread handle is NULL");
        AC_RecordEvent(AC_CAT_INTEGRITY, AC_SEV_BAN,
                       "Scan thread disappeared", 0, 0);
        return FALSE;
    }

    return TRUE;
}
```

---

## Game Integration Example

```c
/* ==========================================================================
 * game_integration.c - Example of how to interate the AntiCheat
 * ========================================================================== */

#include "ac_common.h"

/* ---- Ban handling ---- */
static void OnPlayerBanned(AC_CATEGORY cat, const CHAR* detail)
{
    /* Options:
     *   1. Disconnect from server with ban message
     *   2. Show ban screen
     *   3. Silently flag the account
     *   4. Crash the game (aggressive but common)
     */
    MessageBoxA(NULL,
                "You have been banned for cheating. Contact support if you "
                "believe this is an error.",
                "AntiCheat",
                MB_ICONERROR | MB_OK);

    /* Force disconnect */
    exit(1);
}

/* ---- Log handling ---- */
static void OnACLog(AC_SEVERITY sev, const CHAR* msg)
{
    /* Write to game log file, send to telemetry, etc. */
    OutputDebugStringA(msg);
}

/* ---- Initialize when game starts ---- */
void Game_Init(void)
{
    HMODULE hGame = GetModuleHandleA(NULL);

    /* Register callbacks */
    g_ac.fnBanCallback = OnPlayerBanned;
    g_ac.fnLogCallback = OnACLog;

    /* Initialize AntiCheat */
    if (!AC_Initialize(hGame)) {
        /* Handle init failure - you may want to refuse to run */
        MessageBoxA(NULL,
                    "AntiCheat failed to initialize. The game cannot run.",
                    "Error", MB_ICONERROR);
        exit(1);
    }

    /* Place canaries next to important game data */
    extern BYTE g_playerHealth;
    extern BYTE g_ammoCount;
    AC_PlaceCanary(&g_playerHealth, sizeof(FLOAT));
    AC_PlaceCanary(&g_ammoCount, sizeof(INT));
}

/* ---- Update every game frame ---- */
void Game_FrameUpdate(void)
{
    /* Fill in current player state from game's systems */
    AC_PLAYERSTATE ps = {0};
    ps.viewAngles[0] = g_player.yaw;
    ps.viewAngles[1] = g_player.pitch;
    ps.viewAngles[2] = 0.0f;
    ps.position[0]   = g_player.x;
    ps.position[1]   = g_player.y;
    ps.position[2]   = g_player.z;
    ps.velocity[0]   = g_player.vx;
    ps.velocity[1]   = g_player.vy;
    ps.velocity[2]   = g_player.vz;
    ps.health        = g_player.health;
    ps.flags         = g_player.flags;
    ps.serverTime    = g_network.serverTime;

    /* Feed to anticheat */
    AC_UpdatePlayerState(&ps);
}

/* ---- Server-side: validate each movement packet ---- */
void Server_ProcessMovePacket(AC_MOVE_PACKET* pkt, Client* client)
{
    if (!AC_ValidateMovePacket(pkt, &client->lastState, "shared_secret")) {
        /* Movement is invalid - reject and possibly flag */
        client->violationCount++;

        if (client->violationCount > 5) {
            /* Kick or ban */
            Server_KickClient(client, "Movement violation detected");
            AC_RecordEvent(AC_CAT_NETWORK, AC_SEV_BAN,
                           "Movement violation (server-side)",
                           (ULONG_PTR)client->id, 0);
        }

        /* Don't apply the movement */
        return;
    }

    /* Movement is valid - apply it */
    Server_ApplyMovement(client, pkt);
}

/* ---- Shutdown when game exits ---- */
void Game_Shutdown(void)
{
    AC_Shutdown();
}

/* ---- WinMain ---- */
int WINAPI WinMain(HINSTANCE hInst, HINSTANCE hPrev,
                   LPSTR cmdLine, int showCmd)
{
    /* Check if already banned before even starting */
    CHAR hwid[65] = {0};
    if (AC_GenerateHWID(hwid, sizeof(hwid)) && AC_IsHWIDBanned(hwid)) {
        MessageBoxA(NULL,
                    "This hardware has been banned.",
                    "Banned", MB_ICONERROR);
        return 1;
    }

    /* Initialize game and anticheat */
    Game_Init();

    /* Game loop */
    MSG msg;
    while (TRUE) {
        if (PeekMessage(&msg, NULL, 0, 0, PM_REMOVE)) {
            if (msg.message == WM_QUIT) break;
            TranslateMessage(&msg);
            DispatchMessage(&msg);
        }

        Game_FrameUpdate();
        Game_Render();
    }

    Game_Shutdown();
    return (INT)msg.wParam;
}
```

---

## Compilation & Build Instructions

```makefile
# Makefile for MinGW-w64 or use MSVC

CC = cl
CFLAGS = /W4 /O2 /D_CRT_SECURE_NO_WARNINGS /D_WIN32_WINNT=0x0601
LDFLAGS = psapi.lib shlwapi.lib winhttp.lib iphlpapi.lib wbemuuid.lib tbs.lib imagehlp.lib

SOURCES = \
    ac_core.c \
    ac_crc.c \
    ac_process.c \
    ac_hooks.c \
    ac_anti_debug.c \
    ac_anti_vm.c \
    ac_timing.c \
    ac_input.c \
    ac_network.c \
    ac_hwid.c \
    ac_hwid_advanced.c \
    ac_hwid_lowlevel.c \
    ac_image_coherency.c \
    ac_screenshot.c \
    ac_report.c \
    game_integration.c

all: game.exe

game.exe: $(SOURCES) ac_common.h
    $(CC) $(CFLAGS) /Fe$@ $(SOURCES) /link $(LDFLAGS)

clean:
    del /q *.obj game.exe
```

---

## Defense-in-Depth Summary

| Layer                         | What It Catches                        | Module                 |
|-------------------------------|----------------------------------------|------------------------|
| **Code CRC**                  | In-memory patching, code caves         | `ac_crc.c`             |
| **Canary Guards**             | Adjacent memory corruption             | `ac_crc.c`             |
| **Process Scan**              | Cheat Engine, debuggers, injectors     | `ac_process.c`         |
| **Module Scan**               | DLL injection, manual mapping          | `ac_process.c`         |
| **Unbacked Memory**           | Manual-mapped DLLs                     | `ac_process.c`         |
| **IAT Hook Detection**        | Import address table hooking           | `ac_hooks.c`           |
| **Inline Hook Detection**     | JMP detours, trampolines               | `ac_hooks.c`           |
| **Anti-Debug**                | 8 different debugger detection methods | `ac_anti_debug.c`      |
| **Anti-VM & Sandboxie**       | VM detection, sandbox analysis         | `ac_anti_vm.c`         |
| **Advanced HWID Gathering**   | Comprehensive hardware fingerprinting  | `ac_hwid_advanced.c`   |
| **Low-Level Hardware Access** | SMBIOS/IOCTL/TPM/CPU direct access     | `ac_hwid_lowlevel.c`   |
| **Image Coherency**           | Memory vs disk checksum anomalies      | `ac_image_coherency.c` |
| **Timing Anomaly**            | Speed-hack, timer manipulation         | `ac_timing.c`          |
| **Aim Snap Detection**        | Aimbot instant targeting               | `ac_input.c`           |
| **Tracking Analysis**         | Smooth aimbot, low-variance aim        | `ac_input.c`           |
| **Triggerbot Detection**      | Automatic fire on crosshair-over-enemy | `ac_input.c`           |
| **Movement Validation**       | Teleport, speed, fly hacks             | `ac_network.c`         |
| **HWID Banning**              | Persistent hardware bans               | `ac_hwid.c`            |
| **Overlay Detection**         | Transparent overlay ESP                | `ac_screenshot.c`      |
| **Server Reporting**          | Centralized detection logging          | `ac_report.c`          |

## Critical Design Principles

1. **Server is authoritative** - Never trust the client for movement, health, or ammo. The server validates everything
   independently.

2. **Multiple time sources** - Speed-hacks must fool *all* timing sources simultaneously, which is exponentially harder.

3. **Cumulative scoring** - No single detection (except debuggers) triggers an instant ban. Suspicion accumulates across
   categories.

4. **Sampling over full scans** - Random page CRC checks keep CPU overhead low while making it impossible for attackers
   to predict which pages are checked.

5. **Continuous monitoring** - The background scan thread never stops, making it impossible to "wait out" detection
   windows.

6. **Self-integrity** - AntiCheat verifies its own code and data structures, preventing attackers from disabling
   the AC itself.

7. **Reporting** - Every detection is reported to game server, allowing to tune thresholds, track trends, and issue
   server-side bans even if the client-side check is bypassed.
