#!/usr/bin/env pwsh

# Author: Cheatoid ~ https://github.com/Cheatoid
# License: MIT

<#
.SYNOPSIS
		Launch VS Code or VS Code Insiders with an isolated profile and no extensions (cross-platform).

.PARAMETER TempBase
		Optional path to use as the base folder for temp user-data and extensions directories.
		If provided, two subfolders will be created: <TempBase>/user-data and <TempBase>/extensions.

.PARAMETER KeepTemp
		Keep the temporary directories after the editor exits. Mutually exclusive with -TempBase.

.PARAMETER Insiders
		Force using VS Code Insiders. If Insiders is not available the script will error.

.PARAMETER NoInsiders
		Force using stable VS Code (do not use Insiders even if present).

.EXAMPLE
		.\launcher-code.ps1 -Insiders
		Force open VS Code Insiders with a clean profile.

.EXAMPLE
		.\launcher-code.ps1 -NoInsiders -TempBase C:\tmp\vscode-clean
		Force open stable VS Code and use the provided TempBase for user-data and extensions.
#>

param(
	[string]$TempBase,
	[switch]$KeepTemp,
	[switch]$Insiders,
	[switch]$NoInsiders
)

# Validate mutual exclusivity
if ($TempBase -and $KeepTemp)
{
	Write-Error "Parameters -TempBase and -KeepTemp are mutually exclusive. Choose one."
	exit 2
}
if ($Insiders -and $NoInsiders)
{
	Write-Error "Parameters -Insiders and -NoInsiders are mutually exclusive. Choose one."
	exit 2
}

function New-UniqueTempDir
{
	param([string]$prefix = "vscode-clean")
	$base = [System.IO.Path]::GetTempPath()
	$name = "$prefix-$([guid]::NewGuid().ToString('N') )"
	$path = Join-Path $base $name
	New-Item -ItemType Directory -Path $path -Force | Out-Null
	return $path
}

function Find-CodeBinary
{
	param(
		[switch]$preferInsiders, # if set, prefer Insiders
		[switch]$forceInsiders,  # if set, require Insiders
		[switch]$forceStable     # if set, require stable (skip Insiders)
	)

	# Helper to return structured result
	function _result($path, $flavor)
	{
		return @{ Path = $path; Mode = "cli"; Flavor = $flavor }
	}

	# If CLI on PATH, prefer according to flags
	$insidersCmd = Get-Command "code-insiders" -ErrorAction SilentlyContinue
	$stableCmd = Get-Command "code" -ErrorAction SilentlyContinue

	if ($forceInsiders)
	{
		if ($insidersCmd)
		{
			return _result $insidersCmd.Source "insiders"
		}
		# try common user-local/system locations for Insiders before failing
	}
	if ($forceStable)
	{
		if ($stableCmd)
		{
			return _result $stableCmd.Source "stable"
		}
		# try common user-local/system locations for stable before failing
	}

	# If neither forced, respect preferInsiders flag or default prefer Insiders
	$preferIns = $preferInsiders -or (-not $forceStable -and -not $forceInsiders)

	if ($preferIns)
	{
		if ($insidersCmd)
		{
			return _result $insidersCmd.Source "insiders"
		}
		if ($stableCmd)
		{
			return _result $stableCmd.Source "stable"
		}
	}
	else
	{
		if ($stableCmd)
		{
			return _result $stableCmd.Source "stable"
		}
		if ($insidersCmd)
		{
			return _result $insidersCmd.Source "insiders"
		}
	}

	# Platform-specific candidate lists, preferring user-local installs and Insiders first (or stable first if forced)
	if ($IsWindows)
	{
		$candidatesInsiders = @(
			"$env:LOCALAPPDATA\Programs\Microsoft VS Code Insiders\bin\code-insiders.cmd",
			"$env:ProgramFiles\Microsoft VS Code Insiders\bin\code-insiders.cmd",
			"$env:ProgramFiles(x86)\Microsoft VS Code Insiders\bin\code-insiders.cmd"
		)
		$candidatesStable = @(
			"$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin\code.cmd",
			"$env:ProgramFiles\Microsoft VS Code\bin\code.cmd",
			"$env:ProgramFiles(x86)\Microsoft VS Code\bin\code.cmd"
		)

		if ($forceInsiders)
		{
			foreach ($p in $candidatesInsiders)
			{
				if ($p -and (Test-Path $p))
				{
					return _result $p "insiders"
				}
			}
			return $null
		}
		if ($forceStable)
		{
			foreach ($p in $candidatesStable)
			{
				if ($p -and (Test-Path $p))
				{
					return _result $p "stable"
				}
			}
			return $null
		}

		# Default: prefer Insiders
		foreach ($p in $candidatesInsiders)
		{
			if ($p -and (Test-Path $p))
			{
				return _result $p "insiders"
			}
		}
		foreach ($p in $candidatesStable)
		{
			if ($p -and (Test-Path $p))
			{
				return _result $p "stable"
			}
		}
	}
	elseif ($IsMacOS)
	{
		$candidatesInsiders = @(
			"$HOME/.local/bin/code-insiders",
			"/usr/local/bin/code-insiders",
			"/opt/homebrew/bin/code-insiders",
			"/Applications/Visual Studio Code - Insiders.app/Contents/Resources/app/bin/code",
			"$HOME/Applications/Visual Studio Code - Insiders.app/Contents/Resources/app/bin/code"
		)
		$candidatesStable = @(
			"$HOME/.local/bin/code",
			"/usr/local/bin/code",
			"/opt/homebrew/bin/code",
			"/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code",
			"$HOME/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
		)

		if ($forceInsiders)
		{
			foreach ($p in $candidatesInsiders)
			{
				if ($p -and (Test-Path $p))
				{
					return _result $p "insiders"
				}
			}
			return $null
		}
		if ($forceStable)
		{
			foreach ($p in $candidatesStable)
			{
				if ($p -and (Test-Path $p))
				{
					return _result $p "stable"
				}
			}
			return $null
		}

		if ($preferIns)
		{
			foreach ($p in $candidatesInsiders)
			{
				if ($p -and (Test-Path $p))
				{
					return _result $p "insiders"
				}
			}
			foreach ($p in $candidatesStable)
			{
				if ($p -and (Test-Path $p))
				{
					return _result $p "stable"
				}
			}
		}
		else
		{
			foreach ($p in $candidatesStable)
			{
				if ($p -and (Test-Path $p))
				{
					return _result $p "stable"
				}
			}
			foreach ($p in $candidatesInsiders)
			{
				if ($p -and (Test-Path $p))
				{
					return _result $p "insiders"
				}
			}
		}

		return $null
	}
	else
	{
		# Linux
		$candidatesInsiders = @(
			"$HOME/.local/bin/code-insiders",
			"/usr/bin/code-insiders",
			"/usr/local/bin/code-insiders",
			"/snap/bin/code-insiders"
		)
		$candidatesStable = @(
			"$HOME/.local/bin/code",
			"/usr/bin/code",
			"/usr/local/bin/code",
			"/snap/bin/code"
		)

		if ($forceInsiders)
		{
			foreach ($p in $candidatesInsiders)
			{
				if ($p -and (Test-Path $p))
				{
					return _result $p "insiders"
				}
			}
			return $null
		}
		if ($forceStable)
		{
			foreach ($p in $candidatesStable)
			{
				if ($p -and (Test-Path $p))
				{
					return _result $p "stable"
				}
			}
			return $null
		}

		if ($preferIns)
		{
			foreach ($p in $candidatesInsiders)
			{
				if ($p -and (Test-Path $p))
				{
					return _result $p "insiders"
				}
			}
			foreach ($p in $candidatesStable)
			{
				if ($p -and (Test-Path $p))
				{
					return _result $p "stable"
				}
			}
		}
		else
		{
			foreach ($p in $candidatesStable)
			{
				if ($p -and (Test-Path $p))
				{
					return _result $p "stable"
				}
			}
			foreach ($p in $candidatesInsiders)
			{
				if ($p -and (Test-Path $p))
				{
					return _result $p "insiders"
				}
			}
		}
	}

	return $null
}

# Prepare temp dirs
$createdTempBase = $false
if ($TempBase)
{
	try
	{
		if (-not (Test-Path -LiteralPath $TempBase))
		{
			New-Item -ItemType Directory -Path $TempBase -Force | Out-Null
			$createdTempBase = $true
		}
		$userDataDir = Join-Path $TempBase "user-data"
		$extensionsDir = Join-Path $TempBase "extensions"
		New-Item -ItemType Directory -Path $userDataDir -Force | Out-Null
		New-Item -ItemType Directory -Path $extensionsDir -Force | Out-Null
	}
	catch
	{
		Write-Error "Failed to create TempBase directories: $_"
		exit 3
	}
}
else
{
	$userDataDir = New-UniqueTempDir "vscode-user"
	$extensionsDir = New-UniqueTempDir "vscode-ext"
}

Write-Host "User data dir: $userDataDir"
Write-Host "Extensions dir: $extensionsDir"

# Determine find options from switches
$findParams = @{ }
if ($Insiders)
{
	$findParams["forceInsiders"] = $true
}
elseif ($NoInsiders)
{
	$findParams["forceStable"] = $true
}
else
{
	$findParams["preferInsiders"] = $true
}

$found = Find-CodeBinary @findParams

try
{
	if ($found)
	{
		$exe = $found.Path
		$args = @(
			"--user-data-dir", $userDataDir,
			"--extensions-dir", $extensionsDir,
			"--disable-extensions"
		)

		Write-Host "Launching: $exe $( $args -join ' ' )"
		$proc = Start-Process -FilePath $exe -ArgumentList $args -PassThru
		Wait-Process -Id $proc.Id
	}
	else
	{
		if ($IsMacOS)
		{
			# macOS fallback: prefer Insiders app if Insiders forced or available, else stable
			$insidersApp = "Visual Studio Code - Insiders"
			$stableApp = "Visual Studio Code"
			$args = @("--user-data-dir", $userDataDir, "--extensions-dir", $extensionsDir, "--disable-extensions")

			if ($Insiders)
			{
				if (Test-Path "/Applications/Visual Studio Code - Insiders.app")
				{
					$appToOpen = $insidersApp
				}
				else
				{
					Write-Error "Insiders requested but not found on this system."
					exit 6
				}
			}
			elseif ($NoInsiders)
			{
				if (Test-Path "/Applications/Visual Studio Code.app")
				{
					$appToOpen = $stableApp
				}
				else
				{
					Write-Error "Stable VS Code requested but not found on this system."
					exit 7
				}
			}
			else
			{
				if (Test-Path "/Applications/Visual Studio Code - Insiders.app")
				{
					$appToOpen = $insidersApp
				}
				elseif (Test-Path "/Applications/Visual Studio Code.app")
				{
					$appToOpen = $stableApp
				}
				else
				{
					Write-Error "Neither VS Code Insiders nor stable app found."
					exit 4
				}
			}

			Write-Host "CLI not found. Using 'open -a' fallback for macOS: $appToOpen"
			$proc = Start-Process -FilePath "open" -ArgumentList "-a", $appToOpen, "--args", $args -PassThru
			Wait-Process -Id $proc.Id
		}
		else
		{
			Write-Error "'code-insiders' and 'code' not found on PATH and no known fallback available for this OS."
			Write-Host "Install the CLI or run the editor manually with:"
			Write-Host "  --user-data-dir $userDataDir --extensions-dir $extensionsDir --disable-extensions"
			exit 5
		}
	}
}
finally
{
	# Cleanup logic
	if ($KeepTemp)
	{
		Write-Host "Kept temp dirs (requested):"
		Write-Host "  $userDataDir"
		Write-Host "  $extensionsDir"
	}
	elseif ($TempBase)
	{
		Write-Host "TempBase was provided; leaving directories in place:"
		Write-Host "  $userDataDir"
		Write-Host "  $extensionsDir"
	}
	else
	{
		try
		{
			Remove-Item -LiteralPath $userDataDir -Recurse -Force -ErrorAction SilentlyContinue
			Remove-Item -LiteralPath $extensionsDir -Recurse -Force -ErrorAction SilentlyContinue
		}
		catch
		{
			Write-Warning "Failed to remove temp dirs: $_"
		}
	}
}
