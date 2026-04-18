#!/usr/bin/env pwsh

# Author: Cheatoid ~ https://github.com/Cheatoid
# License: MIT

param(
	[string[]]$SubmodulePaths,
	[switch]$DryRun,
	[switch]$Verbose
)

function Log {
	param([string]$msg)
	if ($Verbose) { Write-Host "[VERBOSE] $msg" -ForegroundColor DarkGray }
}

# Detect repo root
$repoRoot = git rev-parse --show-toplevel
if ($LASTEXITCODE -ne 0) {
	Write-Host "❌ Not inside a Git repository."
	exit 1
}

Push-Location $repoRoot

try {
	# Auto-detect submodules if none provided
	if (-not $SubmodulePaths -or $SubmodulePaths.Count -eq 0) {
		Write-Host "🔍 Detecting submodules..."
		$submodules = git config --file .gitmodules --get-regexp path | ForEach-Object {
			($_ -split " ")[1]
		}

		if ($submodules.Count -eq 0) {
			Write-Host "❌ No submodules found."
			exit 1
		}

		Write-Host "📁 Found submodules:"
		for ($i = 0; $i -lt $submodules.Count; $i++) {
			Write-Host " [$i] $($submodules[$i])"
		}

		$choices = Read-Host "Enter numbers of submodules to remove (comma-separated)"
		$indices = $choices -split "," | ForEach-Object { $_.Trim() }

		$SubmodulePaths = @()
		foreach ($idx in $indices) {
			if ($idx -notmatch '^\d+$' -or $idx -ge $submodules.Count) {
				Write-Host "❌ Invalid selection: $idx"
				exit 1
			}
			$SubmodulePaths += $submodules[$idx]
		}
	}

	Write-Host "➡️ Submodules selected:"
	$SubmodulePaths | ForEach-Object { Write-Host " - $_" }

	# Confirmation prompt
	$confirm = Read-Host "Proceed with removal? (yes/no)"
	if ($confirm -ne "yes") {
		Write-Host "❌ Aborted."
		exit 0
	}

	# Create rollback branch
	$rollbackBranch = "rollback-submodule-removal-" + (Get-Date -Format "yyyyMMddHHmmss")
	Log "Creating rollback branch: $rollbackBranch"

	if (-not $DryRun) {
		git branch $rollbackBranch
	}

	foreach ($SubmodulePath in $SubmodulePaths) {
		Write-Host "🧹 Removing submodule: $SubmodulePath"

		# 1. Deinit
		Log "Running: git submodule deinit -f $SubmodulePath"
		if (-not $DryRun) { git submodule deinit -f $SubmodulePath }

		# 2. Remove from index
		Log "Running: git rm -f $SubmodulePath"
		if (-not $DryRun) { git rm -f $SubmodulePath }

		if ($LASTEXITCODE -ne 0) {
			Write-Host "⚠️ git rm -f failed, trying git rm --cached..."
			Log "Running: git rm --cached $SubmodulePath"
			if (-not $DryRun) { git rm --cached $SubmodulePath }
		}

		# 3. Remove metadata
		$moduleMeta = ".git/modules/$SubmodulePath"
		if (Test-Path $moduleMeta) {
			Log "Removing metadata: $moduleMeta"
			if (-not $DryRun) { Remove-Item -Recurse -Force $moduleMeta }
		}

		# 4. Remove working directory
		if (Test-Path $SubmodulePath) {
			Log "Removing directory: $SubmodulePath"
			if (-not $DryRun) { Remove-Item -Recurse -Force $SubmodulePath }
		}
	}

	# Commit changes
	if (-not $DryRun) {
		git add -A
		git commit -m "Remove submodules: $($SubmodulePaths -join ', ')"
	}

	Write-Host "✅ Submodule removal complete."

	if ($DryRun) {
		Write-Host "🧪 Dry-run mode: No changes were made."
	}
 else {
		Write-Host "🛟 Rollback available:"
		Write-Host "   git checkout $rollbackBranch"
	}
}
finally {
	Pop-Location
}
