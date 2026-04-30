#!/usr/bin/env pwsh

# Author: Cheatoid ~ https://github.com/Cheatoid
# License: MIT

<#
.SYNOPSIS
		TUI to find and replace common Unicode characters (em-dash, etc.) with ASCII version.

.DESCRIPTION
		Scans text files recursively, shows matches, and interactively replaces them.

.PARAMETER SearchPath
		Root folder to scan (default: current directory)

.PARAMETER FileExtensions
		Array of file extensions to include (case-insensitive)

.PARAMETER ReplacementChar
		The ASCII character to use as replacement (default: '-')

.EXAMPLE
		.\cleanup_unicode.ps1 -SearchPath "C:\MyProject" -FileExtensions .md,.ps1 -ReplacementChar '-'
#>

param(
	[string]$SearchPath = ".",
	[string[]]$FileExtensions = @(".cs", ".lua", ".csv", ".md", ".json", ".html", ".xml", ".yml", ".yaml", ".ini", ".cfg")
	#,[string]$ReplacementChar = "-"
)

# ---------- DEFAULT MAPPING ----------
$defaultMap = @{
	# ---------- Dashes / hyphens ----------
	'—'   = '-'   # EM DASH
	'–'   = '-'   # EN DASH
	'―'   = '-'   # HORIZONTAL BAR
	'‒'   = '-'   # FIGURE DASH
	'−'   = '-'   # MINUS SIGN
	'‑'   = '-'   # NON-BREAKING HYPHEN

	# ---------- Arrows ----------
	'↔'   = '<->'   # LEFT RIGHT ARROW
	'→'   = '->'
	'←'   = '<-'
	'↑'   = '^'   # UPWARDS ARROW
	'↓'   = 'v'   # DOWNWARDS ARROW
	'↕'   = '|'   # UP DOWN ARROW
	'⇄'   = '<->' # LEFTWARDS ARROW OVER RIGHTWARDS ARROW
	'⇆'   = '-><-' # left/right arrows
	'⇒'   = '=>'
	'⇐'   = '<='
	'⇔'   = '<=>'

	# ---------- Quotation marks / apostrophes ----------
	'‘'   = ''''   # LEFT SINGLE QUOTATION MARK
	'’'   = "'"   # RIGHT SINGLE QUOTATION MARK
	'“'   = '\"'   # LEFT DOUBLE QUOTATION MARK
	'”'   = '"'   # RIGHT DOUBLE QUOTATION MARK
	'‹'   = '<'   # SINGLE LEFT-POINTING ANGLE QUOTATION MARK
	'›'   = '>'   # SINGLE RIGHT-POINTING ANGLE QUOTATION MARK
	'«'   = '<<'
	'»'   = '>>'

	# ---------- Spaces and breaks ----------
	' '   = ' '   # NO-BREAK SPACE
	' '   = ' '   # NARROW NO-BREAK SPACE
	' '   = ' '   # EM SPACE (often used in formatting)
	' '   = ' '   # EN SPACE
	' '   = ' '   # THIN SPACE

	# ---------- Other typographic / mathematical ----------
	'…'   = '...' # HORIZONTAL ELLIPSIS
	'•'   = '*'   # BULLET
	'·'   = '*'   # MIDDLE DOT
	'†'   = '+'   # DAGGER
	'‡'   = '++'  # DOUBLE DAGGER
	'±'   = '+/-' # PLUS-MINUS SIGN
	'×'   = 'x'   # MULTIPLICATION SIGN
	'÷'   = '/'   # DIVISION SIGN
	'≤'   = '<='
	'≥'   = '>='
	'≠'   = '!='
	'≈'   = '~='  # ALMOST EQUAL TO
	#'∞'   = 'oo'  # INFINITY
	#'√'   = 'sqrt' # SQUARE ROOT
	'²'   = '^2'  # SUPERSCRIPT TWO
	'³'   = '^3'  # SUPERSCRIPT THREE
	#'€'   = 'EUR' # EURO SIGN
	#'£'   = 'GBP' # POUND SIGN
	#'¥'   = 'JPY' # YEN SIGN
	#'©'   = '(C)'
	#'®'   = '(R)'
	#'™'   = '(TM)'
}

# ---------- HELPER: colour write ----------
function Write-Color {
	param([string]$Text, [ConsoleColor]$ForegroundColor = [ConsoleColor]::White, [switch]$NoNewline)
	$prev = $host.UI.RawUI.ForegroundColor
	$host.UI.RawUI.ForegroundColor = $ForegroundColor
	if ($NoNewline) { Write-Host $Text -NoNewline } else { Write-Host $Text }
	$host.UI.RawUI.ForegroundColor = $prev
}

# ---------- Find files ----------
Write-Color "Scanning '$SearchPath' for text files..." Cyan
try {
	$files = Get-ChildItem -Path $SearchPath -Recurse -File -ErrorAction Stop |
		Where-Object { $_.Extension -in $FileExtensions }
}
catch {
	Write-Color "ERROR: $($_.Exception.Message)" Red
	exit
}

if ($files.Count -eq 0) {
	Write-Color "No matching files found." Yellow
	exit
}

# ---------- Scan for target characters ----------
$fileMatches = @{}   # file fullname -> ordered list of { lineNumber, lineText, matches }

foreach ($file in $files) {
	$content = Get-Content -Path $file.FullName -Raw -ErrorAction SilentlyContinue
	if (-not $content) { continue }

	# Build regex from all mapping keys (escape them)
	$escapedKeys = $defaultMap.Keys | ForEach-Object { [regex]::Escape($_) }
	$pattern = ($escapedKeys -join '|')
	if ($content -match $pattern) {
		$lines = Get-Content -Path $file.FullName
		$lineInfos = @()
		for ($i = 0; $i -lt $lines.Count; $i++) {
			$matches = [regex]::Matches($lines[$i], $pattern)
			if ($matches.Count -gt 0) {
				$lineInfos += [PSCustomObject]@{
					LineNumber = $i + 1
					Text	   = $lines[$i]
					Matches	= @($matches | ForEach-Object { $_.Value })
				}
			}
		}
		$fileMatches[$file.FullName] = $lineInfos
	}
}

if ($fileMatches.Count -eq 0) {
	Write-Color "No target characters found in any file." Green
	exit
}

# ---------- SUMMARY ----------
Write-Host ""
Write-Color "=== SUMMARY ===" Cyan
Write-Color "Files containing target characters: $($fileMatches.Count)" Yellow
foreach ($f in $fileMatches.Keys | Sort-Object) {
	$totalMatches = ($fileMatches[$f] | ForEach-Object { $_.Matches.Count } | Measure-Object -Sum).Sum
	Write-Host "  $f  ($totalMatches matches)"
}

# ---------- INTERACTIVE REPLACEMENT LOOP ----------
Write-Host ""
Write-Color "Entering interactive mode. For each file you can:" Cyan
Write-Color "  [A] Replace All   [L] Line-by-line   [S] Skip   [Q] Quit" Magenta

foreach ($f in ($fileMatches.Keys | Sort-Object)) {
	$infos = $fileMatches[$f]
	Write-Host ""
	Write-Color "File: $f" Yellow
	Write-Color "Lines with matches: $($infos.Count)  Total match count: $(($infos | %{$_.Matches.Count} | Measure-Object -Sum).Sum)" White

	do {
		$choice = Read-Host "Action? [A/L/S/Q]"
		$choice = $choice.Trim().ToUpper()
		if ($choice -in @('A','L','S','Q')) { break }
		Write-Color "  Invalid choice." Red
	} while ($true)

	if ($choice -eq 'Q') {
		Write-Color "Quitting..." Yellow
		exit
	}
	if ($choice -eq 'S') {
		Write-Color "Skipped." Gray
		continue
	}

	# ---------- Backup ----------
	$backupPath = "$f.bak"
	Copy-Item -Path $f -Destination $backupPath -Force
	Write-Color "Backup created: $backupPath" Gray

	# Read entire file content as array for in-place editing
	$allLines = Get-Content -Path $f
	$modified = $false

	if ($choice -eq 'A') {
		# Replace all occurrences in the file
		foreach ($info in $infos) {
			$line = $allLines[$info.LineNumber - 1]
			foreach ($key in $defaultMap.Keys) {
				$line = $line.Replace($key, $defaultMap[$key])
			}
			$allLines[$info.LineNumber - 1] = $line
		}
		$modified = $true
		Write-Color "All target characters replaced." Green
	}
	elseif ($choice -eq 'L') {
		# Line-by-line confirmation
		foreach ($info in $infos) {
			$lineBefore = $allLines[$info.LineNumber - 1]
			# Highlight matches
			$highlighted = $lineBefore
			foreach ($m in ($info.Matches | Select-Object -Unique)) {
				$highlighted = $highlighted -replace [regex]::Escape($m), "$([char]0x1B)[91m$m$([char]0x1B)[0m"  # red ANSI
			}
			Write-Host "`nLine $($info.LineNumber):" -NoNewline
			Write-Host " $highlighted"
			Write-Host "  Matches: $($info.Matches -join ', ')"

			do {
				$lnChoice = Read-Host "  Replace this line? [Y/N]"
				$lnChoice = $lnChoice.Trim().ToUpper()
				if ($lnChoice -in @('Y','N')) { break }
				Write-Color "	Y or N, please." Red
			} while ($true)

			if ($lnChoice -eq 'Y') {
				$newLine = $lineBefore
				foreach ($key in $defaultMap.Keys) {
					$newLine = $newLine.Replace($key, $defaultMap[$key])
				}
				$allLines[$info.LineNumber - 1] = $newLine
				$modified = $true
				Write-Color "  Replaced." Green
			}
			else {
				Write-Color "  Kept unchanged." Gray
			}
		}
	}

	# Save if modified
	if ($modified) {
		$allLines | Set-Content -Path $f -Encoding UTF8
		Write-Color "File saved: $f" Green
	}
}

Write-Color "`nAll done. Backups (.bak) were created for modified files." Cyan
