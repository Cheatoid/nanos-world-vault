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
#include <intrin.h> // For __cpuid, __rdtsc
#include <iphlpapi.h> // For GetAdaptersInfo
#include <wbemidl.h> // For WMI queries (needs COM initialization)

#pragma comment(lib, "psapi.lib")
#pragma comment(lib, "shlwapi.lib")
#pragma comment(lib, "ntdll.lib")
#pragma comment(lib, "iphlpapi.lib")
#pragma comment(lib, "wbemuuid.lib")
#pragma comment(lib, "comsuppw.lib") // Required for some COM usage in newer MSVC, though wbemuuid.lib should pull in most

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
#define AC_LOG(sev, fmt, ...) do {                                      
    CHAR _buf[512];                                                     
    sprintf_s(_buf, sizeof(_buf), "[AC][%s] " fmt "
",                 
              (sev)==AC_SEV_INFO?"INFO":(sev)==AC_SEV_WARNING?"WARN":   
              (sev)==AC_SEV_CRITICAL?"CRIT":"BAN", ##__VA_ARGS__);       
    OutputDebugStringA(_buf);                                           
    if (g_ac.fnLogCallback) g_ac.fnLogCallback(sev, _buf);             
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
BOOL  AC_InitPageCRCs(void); // Declared in the provided CRC code
BOOL  AC_CheckRandomPages(int count); // Declared in the provided CRC code
BOOL  AC_PlaceCanary(BYTE* nearAddr, SIZE_T nearSize); // Declared in the provided CRC code
BOOL  AC_VerifyCanaries(void); // Declared in the provided CRC code


/* ac_process.c - Process & module scanning */
BOOL  AC_ScanSuspiciousProcesses(void);
BOOL  AC_ScanLoadedModules(void);
BOOL  AC_IsBlacklistedProcess(DWORD pid);
int   AC_ScanUnbackedMemory(void); // Declared in the provided Process code

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
static BOOL AC_CheckSoftwareBreakpoints(void); // Declared in the provided Anti-Debug code

/* ac_anti_vm.c - Anti-VM & Anti-Sandboxie */
BOOL  AC_DetectVirtualMachine(void);
BOOL  AC_DetectSandboxie(void);
BOOL  AC_ScanVirtualization(void); /* Combined entry point */
static BOOL AC_CheckCPUIDHypervisor(void); // Declared in the provided Anti-VM code
static BOOL AC_CheckHypervisorVendor(void); // Declared in the provided Anti-VM code
static BOOL AC_CheckMACPrefix(void); // Declared in the provided Anti-VM code
static BOOL AC_CheckVMRegistryKeys(void); // Declared in the provided Anti-VM code
static BOOL AC_CheckSandboxiePEB(void); // Declared in the provided Anti-VM code
static BOOL AC_CheckSandboxieDrivers(void); // Declared in the provided Anti-VM code
static BOOL AC_CheckTimingAnomaly(void); // Declared in the provided Anti-VM code
static BOOL AC_CheckVMProcesses(void); // Declared in the provided Anti-VM code
static BOOL AC_CheckSandboxieDLL(void); // Declared in the provided Anti-VM code
static BOOL AC_CheckVirtualHardware(void); // Declared in the provided Anti-VM code
static BOOL AC_CheckSystemResources(void); // Declared in the provided Anti-VM code
static BOOL AC_CheckRedPill(void); // Declared in the provided Advanced VM code
static BOOL AC_CheckVMwareBackdoor(void); // Declared in the provided Advanced VM code
static BOOL AC_CheckAdvancedTiming(void); // Declared in the provided Advanced VM code
static BOOL AC_CheckWMIHardware(void); // Declared in the provided Advanced VM code

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
