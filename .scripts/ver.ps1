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

	[switch]$promote,

	[switch]$release
)

if ($args.Count -gt 0)
{
	Write-Host "ERROR: Unexpected positional argument: $( $args[0] )"
	Write-Host "Use named parameters like: -next rc"
	exit 1
}

# Validate that only one version modification method is used
$versionMethods = @($major, $minor, $patch, $suffix, $next, $promote, $release)
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
if ($release)
{
	$activeMethods += "-release"
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

	# If prerelease exists, then increment it
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

	# No prerelease => normal patch bump
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

# Handle release: move existing tag to main HEAD
if ($release)
{
	if (-not $LatestTag)
	{
		Write-Host "No existing v* tag found to release."
		exit 0
	}

	# Get current branch
	$currentBranch = git branch --show-current

	# Helper function to check git command exit code
	function Test-GitSuccess($message)
	{
		if ($LASTEXITCODE -ne 0)
		{
			Write-Host "ERROR: $message"
			exit 1
		}
	}

	# Switch to main and pull latest
	git fetch --tags origin
	Test-GitSuccess "Failed to fetch tags from origin"
	git fetch --prune origin
	Test-GitSuccess "Failed to prune origin refs"
	git checkout main | Out-Null
	Test-GitSuccess "Failed to checkout main branch"
	git pull origin main | Out-Null
	Test-GitSuccess "Failed to pull latest from origin/main"

	# Check for pending changes (clean working directory required before modifications)
	$status = git status --porcelain
	if ($status)
	{
		Write-Host "ERROR: Working directory has uncommitted changes. Please commit or stash them first."
		git status --short
		exit 1
	}

	# This should be fine if we are in-sync (ensure packager has run)
	git push origin main
	Test-GitSuccess "Failed to push changes to origin/main"

	# Remove 'v' prefix for version number
	$VersionNumber = $LatestTag.TrimStart("v")

	# Update Package.toml version
	$packageToml = Join-Path $PSScriptRoot "..\library\Package.toml"
	if (Test-Path $packageToml)
	{
		$content = Get-Content $packageToml -Raw
		$content = [regex]::Replace($content, '^(\s*version\s*=\s*")[^"]*("\s*)$', { param($m) $m.Groups[1].Value + $VersionNumber + $m.Groups[2].Value }, [System.Text.RegularExpressions.RegexOptions]::Multiline)
		Set-Content $packageToml $content -NoNewline
		git add $packageToml
		git commit -m "Bump version to $VersionNumber"
		Write-Host "Updated Package.toml version to $VersionNumber"
	}

	# Delete the tag first
	#git push origin ":refs/tags/$LatestTag" 2>$null | Out-Null
	git tag -d "$LatestTag" | Out-Null
	Write-Host "Deleted local tag: $LatestTag"

	# Recreate tag on main HEAD (use actual commit hash)
	$headCommit = git rev-parse HEAD
	git tag -a "$LatestTag" -m "$LatestTag" $headCommit
	Write-Host "Recreated tag '$LatestTag' on commit $headCommit"

	# Push the tag
	#git push --tags
	git push origin "$LatestTag"
	Write-Host "Pushed tag: $LatestTag"

	# Switch back to original branch if different
	if ($currentBranch -ne "main")
	{
		git checkout "$currentBranch" | Out-Null
	}

	exit 0
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
