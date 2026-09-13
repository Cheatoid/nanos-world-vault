#!/usr/bin/env pwsh
#Requires -Version 7.0

# Author: Cheatoid ~ https://github.com/Cheatoid
# License: MIT

<#
.SYNOPSIS
	Commits + pushes this vault checkout and forces a GitHub Pages rebuild.

.DESCRIPTION
	Run this after copying a fresh `out/` export into `pages/webaudio/`.

	Pushing alone does not guarantee GitHub Pages builds the new HEAD --
	rapid pushes can race and leave Pages frozen on an older commit (assets
	404 while index.html looks new). This script pushes, then POSTs
	`repos/Cheatoid/nanos-world-vault/pages/builds` to queue a build of the
	pushed HEAD, polls until it reports `built`, and probes the live site.

.PARAMETER Message
	Commit message used when the working tree has changes.

.PARAMETER ProbeUrl
	Live URL probed with HTTP GET after the build reports `built`.

.EXAMPLE
	.\!push.ps1
	Commits, pushes, rebuilds Pages, and probes the default webaudio URL.

.EXAMPLE
	.\!push.ps1 -Message 'Update WebAudio player'
	Same, with a custom commit message.
#>

param(
	[Parameter(Mandatory = $false)]
	[string]$Message = 'Update pages',

	[Parameter(Mandatory = $false)]
	[string]$ProbeUrl = 'https://cheatoid.github.io/nanos-world-vault/pages/webaudio/'
)

if ($PSVersionTable.PSVersion.Major -lt 7) {
	throw '!push.ps1 requires PowerShell 7 or newer. Install PowerShell 7+ and run with pwsh.'
}

### ------------------------------------------------------------
### Logging Helpers
### ------------------------------------------------------------

function Info($msg) { Write-Host "[INFO]  $msg" -ForegroundColor Cyan }
function Warn($msg) { Write-Host "[WARN]  $msg" -ForegroundColor Yellow }
function Err($msg) { Write-Host "[ERROR] $msg" -ForegroundColor Red }

### ------------------------------------------------------------
### Repo Root Detection
### ------------------------------------------------------------

$repoRoot = git rev-parse --show-toplevel 2>$null
if ($LASTEXITCODE -ne 0) {
	Err 'Not inside a Git repository.'
	exit 1
}

Push-Location $repoRoot

### ------------------------------------------------------------
### Commit + Push
### ------------------------------------------------------------

$status = git status --porcelain=v1 --untracked-files=all
if ($status) {
	Info 'Committing working tree changes.'
	git add -A
	git commit -m $Message
}
else {
	Info 'Nothing to commit -- working tree clean.'
}

$head = (git rev-parse --short HEAD).Trim()
Info "HEAD: $head -- pushing."
git push origin main

### ------------------------------------------------------------
### Force Pages Build
### ------------------------------------------------------------

Info 'Requesting Pages build.'
$queued = gh api -X POST repos/Cheatoid/nanos-world-vault/pages/builds | ConvertFrom-Json
Info "Build queued (status=$($queued.status)). Waiting."

$deadline = (Get-Date).AddMinutes(10)
while ((Get-Date) -lt $deadline) {
	Start-Sleep -Seconds 15
	$b = gh api repos/Cheatoid/nanos-world-vault/pages/builds/latest | ConvertFrom-Json
	$short = $b.commit.Substring(0, 7)
	Info "commit=$short status=$($b.status)"
	if ($b.status -eq 'built' -and $b.commit.StartsWith($head)) { break }
	if ($b.status -eq 'errored') {
		Err "Pages build failed: $($b.error.message)"
		exit 1
	}
}

$latest = gh api repos/Cheatoid/nanos-world-vault/pages/builds/latest | ConvertFrom-Json
if (-not $latest.commit.StartsWith($head) -or $latest.status -ne 'built') {
	Err "Timed out waiting for Pages to build $head."
	exit 1
}

### ------------------------------------------------------------
### Live Probe
### ------------------------------------------------------------

$probe = $ProbeUrl + '?pages-push=' + $head
$code = (curl.exe -s -o NUL -w '%{http_code}' --max-time 30 $probe).Trim()
Info "Live probe $ProbeUrl -> HTTP $code."
if ($code -ne '200') {
	Err "Live site probe returned HTTP $code."
	exit 1
}

Info "$head built and live. Hard-refresh your browser (Ctrl+Shift+R)."

Pop-Location
