#!/usr/bin/env pwsh

# Author: Cheatoid ~ https://github.com/Cheatoid
# License: MIT

param(
	[Parameter(Mandatory = $false)]
	[ValidatePattern("^v\d+\.\d+\.\d+(-[a-z]+\.\d+)?$")]
	[string]$Version,

	[switch]$major,
	[switch]$minor,
	[switch]$patch,

	[ValidateSet("preview", "alpha", "beta", "rc", "dev", "nightly")]
	[string]$suffix,

	[ValidateSet("preview", "alpha", "beta", "rc", "dev", "nightly")]
	[string]$next,

	[switch]$promote
)

if ($args.Count -gt 0)
{
	Write-Host "ERROR: Unexpected positional argument: $( $args[0] )"
	Write-Host "Use named parameters like: -next rc"
	exit 1
}

# Validate that only one version modification method is used
$versionMethods = @($major, $minor, $patch, $suffix, $next, $promote)
$activeMethods = @()
if ($major)
{
	$activeMethods += "-major"
}
if ($minor)
{
	$activeMethods += "-minor"
}
if ($patch)
{
	$activeMethods += "-patch"
}
if (-not [string]::IsNullOrWhiteSpace($suffix))
{
	$activeMethods += "-suffix"
}
if (-not [string]::IsNullOrWhiteSpace($next))
{
	$activeMethods += "-next"
}
if ($promote)
{
	$activeMethods += "-promote"
}

if ($activeMethods.Count -gt 1)
{
	Write-Host "ERROR: Only one version modification method can be used at a time."
	Write-Host "Conflicting methods: $( $activeMethods -join ', ' )"
	exit 1
}

# Supported prerelease identifiers
$PreIds = "preview", "alpha", "beta", "rc", "dev", "nightly"

# Get latest tag (if any)
$LatestTag = git describe --tags --abbrev=0 2> $null

function Update-Version($tag, $majorFlag, $minorFlag, $patchFlag, $suffix, $next, $promote)
{
	$clean = $tag.TrimStart("v")

	# Split prerelease if present
	$main, $pre = $clean.Split("-", 2)

	# Parse main version
	$parts = $main.Split(".")
	if ($parts.Count -ne 3)
	{
		throw "Tag '$tag' is not valid SemVer (expected vX.Y.Z or vX.Y.Z-suffix.N)"
	}

	$Major = [int]$parts[0]
	$Minor = [int]$parts[1]
	$Patch = [int]$parts[2]

	# --promote: strip prerelease
	if ($promote)
	{
		return "v$Major.$Minor.$Patch"
	}

	# --next <suffix>: bump patch, start prerelease series
	if (-not [string]::IsNullOrWhiteSpace($next))
	{
		if ($next -notin $PreIds)
		{
			throw "Unsupported --next value '$next'. Allowed: $PreIds"
		}
		return "v$Major.$Minor.$( $Patch + 1 )-$next.1"
	}

	# --suffix <id>: start prerelease series without bumping patch
	if (-not [string]::IsNullOrWhiteSpace($suffix))
	{
		if ($suffix -notin $PreIds)
		{
			throw "Unsupported suffix '$suffix'. Allowed: $PreIds"
		}
		return "v$Major.$Minor.$Patch-$suffix.1"
	}

	# Flags override prerelease logic
	if ($majorFlag)
	{
		return "v$( $Major + 1 ).0.0"
	}
	if ($minorFlag)
	{
		return "v$Major.$( $Minor + 1 ).0"
	}
	if ($patchFlag)
	{
		return "v$Major.$Minor.$( $Patch + 1 )"
	}

	# If prerelease exists → increment it
	if ($pre)
	{
		foreach ($id in $PreIds)
		{
			if ($pre -match "^$id\.(\d+)$")
			{
				$num = [int]$Matches[1] + 1
				return "v$Major.$Minor.$Patch-$id.$num"
			}
		}
	}

	# No prerelease → normal patch bump
	return "v$Major.$Minor.$( $Patch + 1 )"
}

# Determine version
if ( [string]::IsNullOrWhiteSpace($Version))
{
	if (-not $LatestTag)
	{
		Write-Host "No existing tags found. Starting at v0.0.1"
		$Version = "v0.0.1"
	}
	else
	{
		$Version = Update-Version $LatestTag $major $minor $patch $suffix $next $promote
	}
}

$stashCreated = $false

# Check if there are any changes at all
if (git status --porcelain)
{
	#git stash push --include-untracked --keep-index -m "ver-script-temp" | Out-Null
	# Stash EVERYTHING including staged, unstaged, untracked
	git stash push --include-untracked -m "ver-script-temp" | Out-Null
	$stashCreated = $true
}

# Create an empty commit without running pre-commit hook
git commit --allow-empty --no-verify -m "$Version"

if ($stashCreated)
{
	# Pop the stash
	git stash pop | Out-Null
}

# Extract commit message (subject only)
$TagName = (git log -1 --pretty=%s).Trim()

# Create tag
git tag -a "$TagName" -m "$TagName"

# Push commit + tag
#git push
#git push --tags

Write-Host "Created version: $TagName"
