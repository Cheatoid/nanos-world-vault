/* ==========================================================================
 * ac_anti_vm.c - Virtual Machine and Sandboxie detection
 *
 * Detects common analysis environments (VMware, VirtualBox, Hyper-V)
 * and sandbox environments (Sandboxie, BitBlender, Cuckoo).
 * ========================================================================== */

#include "ac_common.h"

#pragma comment(lib, "iphlpapi.lib")
#pragma comment(lib, "wbemuuid.lib")

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
        "HARDWARE\DEVICEMAP\Scsi\Scsi Port 0\Scsi Bus 0\Target Id 0\Logical Unit Id 0",
        "HARDWARE\Description\System\SystemBiosVersion", /* VMs often append info here */
        "SOFTWARE\VMware, Inc.\VMware Tools",
        "SOFTWARE\Oracle\VirtualBox Guest Additions",
        "SOFTWARE\Wine", /* Wine/Proton check */
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
    HANDLE hFile = CreateFileW(L"\.\SandboxieApi", GENERIC_READ,
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
            "SYSTEM\CurrentControlSet\Services\SbieDrv",
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
        "SYSTEM\CurrentControlSet\Services\Disk\Enum",
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

// Advanced VM/Sandboxie Detection Techniques

#### **Red Pill / SIDT Detection**

static BOOL AC_CheckRedPill(void)
{
    /* SIDT instruction stores IDTR in memory */
    struct { WORD limit; DWORD base; } idtr;
    
#if defined(_M_IX86) // Only for 32-bit compilation
    __asm {
        sidt idtr
    }
#else // For 64-bit, use intrinsics or external assembly
    // _sgdt and _sidt intrinsics return a pointer to a 6-byte structure.
    // The base address is stored in bytes 2-5 (for 32-bit base) or 2-9 (for 64-bit base)
    // For simplicity and matching the provided snippet, we'll assume 32-bit base for now.
    // A proper 64-bit implementation would need more careful handling of IDTR.
    unsigned char idtr_bytes[10];
    __sidt(idtr_bytes);
    idtr.base = *(DWORD*)&idtr_bytes[2]; // Assuming 32-bit base for now
#endif
    
    /* In VMs, IDT base is typically above 0x80000000 */
    if (idtr.base > 0x80000000) {
        AC_LOG(AC_SEV_WARNING, "Red Pill: IDT base at 0x%08X (possible VM)", idtr.base);
        return TRUE;
    }
    return FALSE;
}

#### **VMware I/O Port Backdoor**

static BOOL AC_CheckVMwareBackdoor(void)
{
    /* VMware magic I/O port */
    DWORD result = 0;
    
#if defined(_M_IX86) // Only for 32-bit compilation
    __asm {
        mov eax, 0x564D5868  /* VMware magic number */
        mov ebx, 0x0
        mov ecx, 0x0A       /* Get version */
        mov edx, 0x5658     /* VMware I/O port */
        in  dx, eax
        mov result, eax
    }
#else // For 64-bit, inline assembly is not supported. Use __inbyte/_outbyte intrinsics or external assembly.
    // This is a simplified placeholder and would require a more robust 64-bit implementation.
    // For example, using __inbyte and similar intrinsics.
    // __outdword(0x5658, 0x564D5868);
    // result = __indword(0x5658);
    // For now, we'll return false in 64-bit to avoid compilation errors.
    result = 0; 
#endif
    
    /* If VMware is present, EBX will contain version info */
    if (result != 0) {
        AC_LOG(AC_SEV_CRITICAL, "VMware backdoor detected");
        return TRUE;
    }
    return FALSE;
}

#### **Advanced Timing Correlation**

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

#### **WMI Queries for Virtual Hardware**

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
        hr = pLoc->ConnectServer(L"root\cimv2", NULL, NULL, 0,
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

    // Clean up COM resources
    if (pEnumerator) pEnumerator->Release();
    if (pSvc) pSvc->Release();
    if (pLoc) pLoc->Release();
    CoUninitialize();

    return detected;
}
