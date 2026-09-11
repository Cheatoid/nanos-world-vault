#!/usr/bin/env pwsh
#Requires -Version 7.0

# Author: Cheatoid ~ https://github.com/Cheatoid
# License: MIT

<#
.SYNOPSIS
	Unified Git Submodule Manager (submodule_manager.ps1).

.DESCRIPTION
	Manages Git submodules. When no command is given, offers an interactive
	TUI picker (arrow keys to move, Enter to select, Esc to exit).
	Commands:
	  add     – Add submodules
	  remove  – Remove submodules (with TUI picker)
	  list    – List submodules
	  help    – Show help

.PARAMETER Command
	Command to run: add, remove, list, or help (default: interactive picker).

.PARAMETER Urls
	Repository URLs for the add command.

.PARAMETER Paths
	Submodule paths for the add and remove commands.

.PARAMETER Branches
	Branches to track for the add command.

.PARAMETER DryRun
	Show what would change without modifying anything.

.EXAMPLE
	.\submodule_manager.ps1 list
	Lists the configured submodules.

.EXAMPLE
	.\submodule_manager.ps1 add -Urls "https://github.com/org/repo.git" -Paths "libs/repo"
	Adds a submodule (use -DryRun first to preview).
#>

param(
	[Parameter(Mandatory = $false)]
	[string]$Command,

	[string[]]$Urls,
	[string[]]$Paths,
	[string[]]$Branches,

	[switch]$DryRun
)

if ($PSVersionTable.PSVersion.Major -lt 7) {
	throw 'submodule_manager.ps1 requires PowerShell 7 or newer. Install PowerShell 7+ and run with pwsh.'
}

### ------------------------------------------------------------
### Logging Helpers
### ------------------------------------------------------------

function Info($msg) { Write-Host "[INFO]  $msg" -ForegroundColor Cyan }
function Warn($msg) { Write-Host "[WARN]  $msg" -ForegroundColor Yellow }
function Err($msg) { Write-Host "[ERROR] $msg" -ForegroundColor Red }
function Verb($msg) { if ($VerbosePreference -eq 'Continue') { Write-Host "[VERBOSE] $msg" -ForegroundColor DarkGray } }

### ------------------------------------------------------------
### URL Normalization + Validation
### ------------------------------------------------------------

function ConvertTo-NormalizedUrl($Url) {
	if ($Url -match '^git@' -or $Url -match '^https?://') { return $Url }

	if ($Url -match '^[\w\.\-]+/[\w\.\-]+(\.git)?$') {
		Verb "Normalizing to HTTPS: https://$Url"
		return "https://$Url"
	}

	return $Url
}

function Test-Url($Url) {
	if ($Url -match '^git@[\w\.\-]+:[\w\.\-]+/[\w\.\-]+(\.git)?$') { return $true }
	if ($Url -match '^https?://[\w\.\-]+/[\w\.\-]+/[\w\.\-]+(\.git)?$') { return $true }
	return $false
}

### ------------------------------------------------------------
### Repo Root Detection
### ------------------------------------------------------------

$repoRoot = git rev-parse --show-toplevel 2>$null
if ($LASTEXITCODE -ne 0) {
	Err "Not inside a Git repository."
	exit 1
}

Push-Location $repoRoot

### ------------------------------------------------------------
### TUI Picker (Arrow‑Key Multi‑Select)
### ------------------------------------------------------------

function Tui-Pick-Single($items, $title) {
	$index = 0

	function Draw-Single {
		Clear-Host
		if ($title) { Info $title }
		""
		for ($i = 0; $i -lt $items.Count; $i++) {
			if ($i -eq $index) {
				Write-Host "> $($items[$i])" -ForegroundColor Green
			}
			else {
				Write-Host "  $($items[$i])"
			}
		}
	}

	Draw-Single

	while ($true) {
		$key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

		switch ($key.VirtualKeyCode) {
			38 { if ($index -gt 0) { $index-- } }   # Up
			40 { if ($index -lt $items.Count - 1) { $index++ } } # Down
			13 { return $items[$index] } # Enter
			27 { return $null } # Escape
		}

		Draw-Single
	}
}

function Tui-Pick($items) {
	$index = 0
	$selected = @{}

	Draw-Tui $index $selected $items

	$done = $false
	while (-not $done) {
		$key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

		switch ($key.VirtualKeyCode) {
			38 { if ($index -gt 0) { $index-- } }   # Up
			40 { if ($index -lt $items.Count - 1) { $index++ } } # Down
			32 {
				# Space
				if ($selected.ContainsKey($index)) {
					$selected.Remove($index)
				}
				else {
					$selected[$index] = $true
				}
			}
			13 { $done = $true } # Enter
		}

		Draw-Tui $index $selected $items
	}

	$selectedIndices = @($selected.Keys) | Sort-Object
	$result = [string[]]($selectedIndices | ForEach-Object { [string]$items[$_] })
	return $result
}

function Draw-Tui($idx, $sel, $itms) {
	Clear-Host
	Info "Select submodules to remove (↑↓ to move, Space to toggle, Enter to confirm)"
	""
	for ($i = 0; $i -lt $itms.Count; $i++) {
		$prefix = if ($sel.ContainsKey($i)) { "[x]" } else { "[ ]" }
		if ($i -eq $idx) {
			Write-Host "> $prefix $($itms[$i])" -ForegroundColor Green
		}
		else {
			Write-Host "  $prefix $($itms[$i])"
		}
	}
}

### ------------------------------------------------------------
### Submodule Listing
### ------------------------------------------------------------

function Get-Submodules {
	$raw = git config --file .gitmodules --get-regexp path 2>$null
	$result = [string[]]($raw |
		ForEach-Object {
			$parts = $_ -split '\s+', 2
			if ($parts.Count -ge 2) { $parts[1] }
		} |
		Where-Object { $_ -and $_.Trim() })
	return ,$result
}

### ------------------------------------------------------------
### Rollback Branch
### ------------------------------------------------------------

function Create-Rollback {
	$branch = "rollback-submodule-" + (Get-Date -Format "yyyyMMddHHmmss")
	Verb "Creating rollback branch: $branch"
	if (-not $DryRun) { git branch $branch | Out-Null }
	return $branch
}

### ------------------------------------------------------------
### ADD SUBMODULE
### ------------------------------------------------------------

function Do-Add {
	if (-not $Urls) {
		Info "Interactive add mode"
		$Urls = @()
		$Paths = @()
		$Branches = @()

		while ($true) {
			$u = Read-Host "Enter URL (blank to finish)"
			if (-not $u) { break }
			$p = Read-Host "Enter path"
			$b = Read-Host "Enter branch (default: main)"
			if (-not $b) { $b = "main" }

			$Urls += $u
			$Paths += $p
			$Branches += $b
		}
	}

	if ($Urls.Count -ne $Paths.Count -or $Urls.Count -ne $Branches.Count) {
		Err "Urls, Paths, and Branches must match in length."
		exit 1
	}

	# Normalize + validate
	for ($i = 0; $i -lt $Urls.Count; $i++) {
		$Urls[$i] = ConvertTo-NormalizedUrl $Urls[$i]
		if (-not (Test-Url $Urls[$i])) {
			Err "Invalid URL: $($Urls[$i])"
			exit 1
		}
	}

	Info "Submodules to add:"
	for ($i = 0; $i -lt $Urls.Count; $i++) {
		Write-Host "  URL: $($Urls[$i])"
		Write-Host "  Path: $($Paths[$i])"
		Write-Host "  Branch: $($Branches[$i])"
		""
	}

	if ((Read-Host "Proceed? (yes/no)") -ne "yes") {
		Warn "Aborted."
		exit 0
	}

	$rollback = Create-Rollback

	for ($i = 0; $i -lt $Urls.Count; $i++) {
		$url = $Urls[$i]
		$path = $Paths[$i]
		$branch = $Branches[$i]

		Info "Adding $path (branch: $branch)"

		Verb "git submodule deinit -f $path"
		if (-not $DryRun) { git submodule deinit -f $path 2>$null }

		$meta = ".git/modules/$path"
		if (Test-Path $meta) {
			Verb "Removing git metadata: $meta"
			if (-not $DryRun) { Remove-Item -Recurse -Force $meta }
		}

		if (Test-Path $path) {
			Verb "Removing directory: $path"
			if (-not $DryRun) { Remove-Item -Recurse -Force $path }
		}

		Verb "git rm --cached -r --ignore-unmatch $path"
		if (-not $DryRun) { git rm --cached -r --ignore-unmatch $path }

		Verb "git submodule add -b $branch $url $path"
		if (-not $DryRun) { git submodule add -b $branch $url $path }

		Verb "git submodule update --init --recursive $path"
		if (-not $DryRun) { git submodule update --init --recursive $path }

		Verb "git submodule update --remote $path"
		if (-not $DryRun) { git submodule update --remote $path }
	}

	if (-not $DryRun) {
		git add .gitmodules | Out-Null
		git add $Paths | Out-Null
		git commit -m "Add submodules: $($Paths -join ', ')" | Out-Null
	}

	Info "Submodules added."

	if ($DryRun) {
		Warn "Dry-run: no changes made."
	}
 else {
		Info "Rollback available: git checkout $rollback"
	}
}

### ------------------------------------------------------------
### REMOVE SUBMODULE
### ------------------------------------------------------------

function Do-Remove {
	$existing = Get-Submodules
	if ($existing.Count -eq 0) {
		Err "No submodules found."
		exit 1
	}

	if ($PSBoundParameters.ContainsKey('Paths') -and $Paths -and $Paths.Count -gt 0) {
		$pathsToRemove = $Paths
	} else {
		$tuiResult = Tui-Pick $existing
		$pathsToRemove = [string[]]($tuiResult | Where-Object { $_ -and $_.Trim() })
	}

	Info "Removing:"
	$pathsToRemove | Where-Object { $_ -and $_.Trim() } | ForEach-Object { Write-Host " - '$_'" }

	if ((Read-Host "Proceed? (yes/no)") -ne "yes") {
		Warn "Aborted."
		exit 0
	}

	$rollback = Create-Rollback

	foreach ($path in $pathsToRemove) {
		if (-not $path -or $path.Trim() -eq '') { continue }
		Info "Removing $path"

		Verb "git submodule deinit -f $path"
		if (-not $DryRun) { git submodule deinit -f $path }

		Verb "git rm -f $path"
		if (-not $DryRun) { git rm -f $path }

		if ($LASTEXITCODE -ne 0) {
			Warn "git rm -f failed, trying cached"
			Verb "git rm --cached $path"
			if (-not $DryRun) { git rm --cached $path }
		}

		$meta = ".git/modules/$path"
		if (Test-Path $meta) {
			Verb "Removing metadata: $meta"
			if (-not $DryRun) { Remove-Item -Recurse -Force $meta }
		}

		if (Test-Path $path) {
			Verb "Removing directory: $path"
			if (-not $DryRun) { Remove-Item -Recurse -Force $path }
		}
	}

	if (-not $DryRun) {
		git add -A | Out-Null
		$validPaths = $pathsToRemove | Where-Object { $_ -and $_.Trim() }
		git commit -m "Remove submodules: $($validPaths -join ', ')" | Out-Null
	}

	Info "Submodules removed."

	if ($DryRun) {
		Warn "Dry-run: no changes made."
	}
 else {
		Info "Rollback available: git checkout $rollback"
	}
}

### ------------------------------------------------------------
### LIST SUBMODULES
### ------------------------------------------------------------

function Do-List {
	$mods = Get-Submodules
	if ($mods.Count -eq 0) {
		Warn "No submodules found."
		return
	}

	Info "Submodules:"
	$mods | ForEach-Object { Write-Host " - $_" }
}

### ------------------------------------------------------------
### HELP
### ------------------------------------------------------------

function Do-Help {
	@"
submodule_manager.ps1 <command> [options]

Commands:
  add       Add submodules
  remove    Remove submodules (with TUI picker)
  list      List submodules
  help      Show this help

Common options:
  -DryRun
  -Verbose
"@ | Write-Host
}

### ------------------------------------------------------------
### Interactive Mode (No Command Provided)
### ------------------------------------------------------------

if (-not $Command) {
	$commands = @("add", "remove", "list", "help")
	$selectedCommand = Tui-Pick-Single $commands "Select a command (↑↓ to move, Enter to select, Esc to exit)"
	if (-not $selectedCommand) {
		Warn "No command selected. Exiting."
		exit 0
	}
	$Command = $selectedCommand.Trim()
	Clear-Host
	Info "Selected command: $Command"
	""
}

### ------------------------------------------------------------
### Command Dispatch
### ------------------------------------------------------------

$validCommands = @("add", "remove", "list", "help")
$Command = $Command.Trim()
if ($Command -and $Command -notin $validCommands) {
	Err "Invalid command: '$Command'. Valid commands: $($validCommands -join ', ')"
	exit 1
}

switch ($Command) {
	"add" { Do-Add }
	"remove" { Do-Remove }
	"list" { Do-List }
	"help" { Do-Help }
}

Pop-Location
