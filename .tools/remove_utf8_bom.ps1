#!/usr/bin/env pwsh
#Requires -Version 7.0

# Author: Cheatoid ~ https://github.com/Cheatoid
# License: MIT

<#
.SYNOPSIS
	Removes UTF-8 BOM headers from all Lua files under the search path.

.DESCRIPTION
	This script recursively finds all .lua files under the search path,
	checks if they have a UTF-8 BOM (Byte Order Mark) header, and removes it if present.
	The BOM consists of the three bytes: 0xEF, 0xBB, 0xBF.
	Reports how many files were checked and how many had a BOM removed.

.PARAMETER Path
	The path to search for Lua files (default: parent directory, i.e. the
	@cheatoid root when run from .tools).

.PARAMETER DryRun
	If specified, shows what files would be modified without making changes.

.EXAMPLE
	.\remove_utf8_bom.ps1
	Removes BOM from all Lua files in the parent directory and subdirectories.

.EXAMPLE
	.\remove_utf8_bom.ps1 -DryRun
	Shows which files have BOM without modifying them.

.EXAMPLE
	.\remove_utf8_bom.ps1 -Path "C:\Lua.Scripts"
	Removes BOM from all Lua files in the specified path.
#>

param(
	[string]$Path = "..",
	[switch]$DryRun
)

if ($PSVersionTable.PSVersion.Major -lt 7) {
	throw 'remove_utf8_bom.ps1 requires PowerShell 7 or newer. Install PowerShell 7+ and run with pwsh.'
}

# UTF-8 BOM bytes
$BOM = [byte[]](0xEF, 0xBB, 0xBF)

Write-Host "Searching for Lua files in: $Path" -ForegroundColor Green

# Get all Lua files recursively
$luaFiles = Get-ChildItem -Path $Path -Filter "*.lua" -Recurse -File

if ($luaFiles.Count -eq 0) {
	Write-Host "No Lua files found." -ForegroundColor Yellow
	exit 0
}

Write-Host "Found $( $luaFiles.Count ) Lua files. Checking for UTF-8 BOM..." -ForegroundColor Green

$filesWithBom = 0
$filesProcessed = 0

foreach ($file in $luaFiles) {
	$filesProcessed++

	try {
		# Read file as bytes to check for BOM
		$bytes = [System.IO.File]::ReadAllBytes($file.FullName)

		# Check if file starts with UTF-8 BOM
		if ($bytes.Length -ge 3 -and
			$bytes[0] -eq $BOM[0] -and
			$bytes[1] -eq $BOM[1] -and
			$bytes[2] -eq $BOM[2]) {

			$filesWithBom++
			$relativePath = Resolve-Path -Path $file.FullName -Relative

			if ($DryRun) {
				Write-Host "[DRY RUN] Would remove BOM from: $relativePath" -ForegroundColor Cyan
			}
			else {
				# Remove BOM by creating new byte array without first 3 bytes
				$contentWithoutBom = $bytes[3..($bytes.Length - 1)]

				# Write back to file
				[System.IO.File]::WriteAllBytes($file.FullName, $contentWithoutBom)

				Write-Host "Removed BOM from: $relativePath" -ForegroundColor Green
			}
		}
	}
	catch {
		Write-Host "Error processing file $( $file.FullName ): $( $_.Exception.Message )" -ForegroundColor Red
	}

	# Progress indicator
	if ($filesProcessed % 10 -eq 0) {
		Write-Progress -Activity "Processing Lua files" -Status "Checked $filesProcessed of $( $luaFiles.Count ) files" -PercentComplete (($filesProcessed / $luaFiles.Count) * 100)
	}
}

Write-Progress -Activity "Processing Lua files" -Completed

Write-Host "Processing complete!" -ForegroundColor Green
Write-Host "Total Lua files processed: $( $luaFiles.Count )" -ForegroundColor White
Write-Host "Files with UTF-8 BOM found: $filesWithBom" -ForegroundColor White

if ($DryRun) {
	Write-Host "Dry run mode - no files were modified." -ForegroundColor Yellow
}
else {
	Write-Host "BOM headers removed from $filesWithBom files." -ForegroundColor Green
}
