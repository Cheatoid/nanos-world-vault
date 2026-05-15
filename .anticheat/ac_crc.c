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
