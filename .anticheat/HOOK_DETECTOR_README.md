# Win32 API Hook Detector

## Overview

This tool provides comprehensive detection of Win32 API hooks by comparing in-memory function implementations against original Windows DLLs on disk. It can detect:

- **IAT Hooks**: Import Address Table modifications
- **Inline Hooks**: Direct function prologue patches (JMP instructions, detours)
- **Memory Patches**: Any modifications to function code
- **Detour Patterns**: Common hooking framework signatures

## Features

### Comprehensive API Coverage
The tool checks over 150 critical Win32 APIs across multiple categories:

- **System APIs**: Timing, process, memory management functions
- **Input APIs**: Keyboard, mouse, window management
- **Graphics APIs**: DirectX, OpenGL, GDI functions
- **Network APIs**: Winsock functions for network manipulation
- **File APIs**: File operations commonly targeted by cheats
- **Registry APIs**: Registry access functions
- **Cryptography APIs**: Encryption/decryption functions
- **Debug APIs**: Anti-debug and debugger detection functions

### Hook Detection Methods

1. **Disk Comparison**: Compares in-memory function bytes with original DLL on disk
2. **IAT Scanning**: Checks Import Address Table for redirected function pointers
3. **Inline Analysis**: Detects JMP instructions, detour patterns, and breakpoints
4. **Signature Matching**: Identifies common hooking framework patterns

## Building

### Prerequisites
- Visual Studio (any version with C compiler)
- Windows SDK

### Build Steps
1. Open a Developer Command Prompt for Visual Studio
2. Navigate to the `.anticheat` directory
3. Run the build script:
   ```batch
   build_hook_detector.bat
   ```

### Manual Compilation
If the build script doesn't work, compile manually:
```batch
cl /O2 /W3 /D_CRT_SECURE_NO_WARNINGS /Fe:win32_api_hook_detector.exe win32_api_hook_detector.c psapi.lib shlwapi.lib advapi32.lib /link /SUBSYSTEM:CONSOLE
```

## Usage

### Basic Usage
```batch
win32_api_hook_detector.exe
```

### Output Format
The tool provides:
- Real-time detection of hooked APIs
- Hook type classification
- Byte-by-byte comparison (memory vs disk)
- Summary statistics

### Example Output
```
Win32 API Hook Detector
=======================

Scanning Win32 APIs for hooks...
=====================================
HOOKED: kernel32.dll!GetTickCount
  Type: Inline Hook
  Address: 00007FFA12345678
  Current: E9 12 34 56 78 90 12 34 
  Disk:    48 8B C4 48 89 58 08 48 

HOOKED: user32.dll!GetAsyncKeyState
  Type: IAT Hook
  Address: 00007FFA87654321
  Current: 48 8B C4 48 89 58 08 48 
  Disk:    48 8B C4 48 89 58 08 48 

=== WIN32 API HOOK DETECTION REPORT ===
Total APIs Scanned: 152
APIs Hooked: 2
IAT Hooks: 1
Inline Hooks: 1
Memory Patches: 0

=== SUMMARY ===
⚠ 2 Win32 API hooks detected - Potential cheat activity
```

## Hook Types Explained

### IAT Hook
The Import Address Table entry has been modified to point to a different location. This is commonly used by:
- API hooking libraries (Detours, EasyHook, etc.)
- Simple function redirection
- Some anti-virus software

### Inline Hook
The function's first bytes have been patched with a JMP instruction. This includes:
- Direct JMP patches (E9 xx xx xx xx)
- Indirect JMP patches (FF 25 xx xx xx xx)
- Detour trampolines
- INT3 breakpoints (0xCC)

### Detour
Specific patterns used by common hooking frameworks:
- Microsoft Detours patterns
- MinHook patterns
- Custom detour implementations

### Memory Patch
Any modification detected by disk comparison that doesn't match known hook patterns. This could be:
- Manual code patching
- Memory modifications
- Unknown hooking techniques

## Integration with Anti-Cheat System

This detector can be integrated into the existing anti-cheat system:

```c
// In your anti-cheat initialization
HOOK_REPORT report = {0};
if (DetectWin32ApiHooks(&report)) {
    if (report.hookedFunctions > 0) {
        // Log hook detection
        AC_RecordEvent(AC_CAT_HOOK, AC_SEV_CRITICAL,
                      "Win32 API hooks detected", 
                      report.hookedFunctions, 0);
        
        // Optional: Take action based on hook count
        if (report.hookedFunctions > 5) {
            // High hook count - likely cheat activity
            AC_RecordEvent(AC_CAT_HOOK, AC_SEV_BAN,
                          "Excessive Win32 API hooks", 
                          report.hookedFunctions, 0);
        }
    }
}
```

## False Positives

Some legitimate software may hook APIs:
- Anti-virus programs
- Overlay software (Discord, Steam overlay)
- Debugging tools
- System monitoring software

Consider the context and hook patterns when evaluating results.

## Performance Considerations

- The tool scans ~150 APIs, which takes ~100-500ms
- Disk I/O is the main performance factor
- Consider running periodically rather than continuously
- Cache results for short periods if needed

## Security Notes

- Requires read access to system DLLs
- May trigger some anti-virus heuristics (hook detection)
- Run with appropriate privileges
- Consider code signing for production use

## Troubleshooting

### "Access Denied" Errors
- Run as Administrator
- Check antivirus isn't blocking the tool
- Ensure system DLLs are accessible

### "Compilation Failed"
- Verify Visual Studio is properly installed
- Run from Developer Command Prompt
- Check Windows SDK installation

### No Hooks Detected (but expected)
- Verify target process is actually running hooks
- Check if hooks are in a different process
- Some advanced hooks may evade detection

## Extending the Tool

### Adding New APIs
Add to the `CRITICAL_APIS` array:
```c
{"yourdll.dll", "YourFunction"},
```

### Custom Hook Patterns
Add to `IsDetourPattern()`:
```c
if (addr[0] == 0xXX && addr[1] == 0xYY) return TRUE;
```

### Additional Detection Methods
Implement new detection functions and call them from `DetectWin32ApiHooks()`.

## License

This tool is part of the nanos-world anti-cheat system. Use according to your project's licensing terms.
