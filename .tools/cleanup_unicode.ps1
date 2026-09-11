#!/usr/bin/env pwsh
#Requires -Version 7.0

# Author: Cheatoid ~ https://github.com/Cheatoid
# License: MIT

<#
.SYNOPSIS
	TUI to find and replace common Unicode characters (em-dash, etc.) with ASCII versions.

.DESCRIPTION
	Scans text files recursively for known Unicode characters using the built-in
	mapping table, lists every matching line, prints a per-file summary, then
	offers interactive replacement per file: replace all, line-by-line, skip, or quit.
	Modified files get a .bak backup next to the original before saving.

.PARAMETER SearchPath
	Root folder to scan (default: current directory).

.PARAMETER FileExtensions
	Array of file extensions to include (case-insensitive, default: .cs, .lua,
	.csv, .md, .json, .html, .xml, .yml, .yaml, .ini, .cfg).

.EXAMPLE
	.\cleanup_unicode.ps1
	Scans the current directory with the default extensions.

.EXAMPLE
	.\cleanup_unicode.ps1 -SearchPath "C:\MyProject" -FileExtensions .md,.ps1
	Scans only Markdown and PowerShell files under C:\MyProject.
#>

param(
	[string]$SearchPath = ".",
	[string[]]$FileExtensions = @(".cs", ".lua", ".csv", ".md", ".json", ".html", ".xml", ".yml", ".yaml", ".ini", ".cfg")
	#,[string]$ReplacementChar = "-"
)

if ($PSVersionTable.PSVersion.Major -lt 7) {
	throw 'cleanup_unicode.ps1 requires PowerShell 7 or newer. Install PowerShell 7+ and run with pwsh.'
}

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
	([char]0x2018) = "'"   # U+2018 LEFT SINGLE QUOTATION MARK
	([char]0x2019) = "'"   # U+2019 RIGHT SINGLE QUOTATION MARK
	([char]0x201C) = '"'   # U+201C LEFT DOUBLE QUOTATION MARK
	([char]0x201D) = '"'   # U+201D RIGHT DOUBLE QUOTATION MARK
	([char]0x2039) = '<'   # U+2039 SINGLE LEFT-POINTING ANGLE QUOTATION MARK
	([char]0x203A) = '>'   # U+203A SINGLE RIGHT-POINTING ANGLE QUOTATION MARK
	([char]0x00AB) = '<<'  # U+00AB LEFT-POINTING DOUBLE ANGLE QUOTATION MARK
	([char]0x00BB) = '>>'  # U+00BB RIGHT-POINTING DOUBLE ANGLE QUOTATION MARK

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

	# ---------- Quotes ----------
	([char]0x201A) = "'"  # U+201A SINGLE LOW-9 QUOTATION MARK
	([char]0x201B) = "'"  # U+201B SINGLE HIGH-REVERSED-9 QUOTATION MARK
	([char]0x201E) = '"'  # U+201E DOUBLE LOW-9 QUOTATION MARK
	([char]0x201F) = '"'  # U+201F DOUBLE HIGH-REVERSED-9 QUOTATION MARK

	# ---------- Hyphens / Dashes ----------
	'‐'   = '-'   # U+2010 HYPHEN
	'‖'   = '||'  # U+2016 DOUBLE VERTICAL LINE
	'‗'   = '_'   # U+2017 DOUBLE LOW LINE

	# ---------- Periods / Ellipsis ----------
	'․'   = '.'   # U+2024 ONE DOT LEADER
	'‥'   = '..'  # U+2025 TWO DOT LEADER

	# ---------- Arrows ----------
	'↖'   = '^'    # U+2196 NORTH WEST ARROW
	'↗'   = '^'    # U+2197 NORTH EAST ARROW
	'↘'   = 'v'    # U+2198 SOUTH EAST ARROW
	'↙'   = 'v'    # U+2199 SOUTH WEST ARROW
	'↚'   = '<-'   # U+219A LEFTWARDS ARROW WITH STROKE
	'↛'   = '->'   # U+219B RIGHTWARDS ARROW WITH STROKE
	'↜'   = '<~'   # U+219C LEFTWARDS WAVE ARROW
	'↝'   = '~>'   # U+219D RIGHTWARDS WAVE ARROW
	'↞'   = '<<-'  # U+219E LEFTWARDS TWO HEADED ARROW
	'↟'   = '^'    # U+219F UPWARDS TWO HEADED ARROW
	'↠'   = '->>'  # U+21A0 RIGHTWARDS TWO HEADED ARROW
	'↡'   = 'v'    # U+21A1 DOWNWARDS TWO HEADED ARROW
	'↢'   = '<--'  # U+21A2 LEFTWARDS ARROW WITH TAIL
	'↣'   = '-->'  # U+21A3 RIGHTWARDS ARROW WITH TAIL
	'↤'   = '<-|'  # U+21A4 LEFTWARDS ARROW FROM BAR
	'↥'   = '^|'   # U+21A5 UPWARDS ARROW FROM BAR
	'↦'   = '|>'   # U+21A6 RIGHTWARDS ARROW FROM BAR
	'↧'   = 'v|'   # U+21A7 DOWNWARDS ARROW FROM BAR
	'↨'   = '^|v'  # U+21A8 UP DOWN ARROW WITH BASE

	# ---------- Triangles (directional) ----------
	'▲'   = '^'   # U+25B2 BLACK UP-POINTING TRIANGLE
	'△'   = '^'   # U+25B3 WHITE UP-POINTING TRIANGLE
	'▴'   = '^'   # U+25B4 BLACK UP-POINTING SMALL TRIANGLE
	'▵'   = '^'   # U+25B5 WHITE UP-POINTING SMALL TRIANGLE
	'▼'   = 'v'   # U+25BC BLACK DOWN-POINTING TRIANGLE
	'▽'   = 'v'   # U+25BD WHITE DOWN-POINTING TRIANGLE
	'▾'   = 'v'   # U+25BE BLACK DOWN-POINTING SMALL TRIANGLE
	'▿'   = 'v'   # U+25BF WHITE DOWN-POINTING SMALL TRIANGLE
	'◀'   = '<'   # U+25C0 BLACK LEFT-POINTING TRIANGLE
	'◁'   = '<'   # U+25C1 WHITE LEFT-POINTING TRIANGLE
	'◂'   = '<'   # U+25C2 BLACK LEFT-POINTING SMALL TRIANGLE
	'◃'   = '<'   # U+25C3 WHITE LEFT-POINTING SMALL TRIANGLE
	'▶'   = '>'   # U+25B6 BLACK RIGHT-POINTING TRIANGLE
	'▷'   = '>'   # U+25B7 WHITE RIGHT-POINTING TRIANGLE
	'▸'   = '>'   # U+25B8 BLACK RIGHT-POINTING SMALL TRIANGLE
	'▹'   = '>'   # U+25B9 WHITE RIGHT-POINTING SMALL TRIANGLE

	# ---------- Bullets / Operators ----------
	'◦'   = '*'    # U+25E6 WHITE BULLET
	'‣'   = '*'    # U+2023 TRIANGULAR BULLET
	'⋅'   = '.'    # U+22C5 DOT OPERATOR
	'≃'   = '~='   # U+2243 ASYMPTOTICALLY EQUAL TO
	'≅'   = '~=='  # U+2245 APPROXIMATELY EQUAL TO
	'≡'   = '==='  # U+2261 IDENTICAL TO

	# ---------- Subscripts ----------
	'₀'   = '0'   # U+2080 SUBSCRIPT ZERO
	'₁'   = '1'   # U+2081 SUBSCRIPT ONE
	'₂'   = '2'   # U+2082 SUBSCRIPT TWO
	'₃'   = '3'   # U+2083 SUBSCRIPT THREE
	'₄'   = '4'   # U+2084 SUBSCRIPT FOUR
	'₅'   = '5'   # U+2085 SUBSCRIPT FIVE
	'₆'   = '6'   # U+2086 SUBSCRIPT SIX
	'₇'   = '7'   # U+2087 SUBSCRIPT SEVEN
	'₈'   = '8'   # U+2088 SUBSCRIPT EIGHT
	'₉'   = '9'   # U+2089 SUBSCRIPT NINE
	'₊'   = '+'   # U+208A SUBSCRIPT PLUS SIGN
	'₋'   = '-'   # U+208B SUBSCRIPT MINUS
	'₌'   = '='   # U+208C SUBSCRIPT EQUALS SIGN
	'₍'   = '('   # U+208D SUBSCRIPT LEFT PARENTHESIS
	'₎'   = ')'   # U+208E SUBSCRIPT RIGHT PARENTHESIS
	'ₐ'   = 'a'   # U+2090 LATIN SUBSCRIPT SMALL LETTER A
	'ₑ'   = 'e'   # U+2091 LATIN SUBSCRIPT SMALL LETTER E
	'ₒ'   = 'o'   # U+2092 LATIN SUBSCRIPT SMALL LETTER O
	'ₓ'   = 'x'   # U+2093 LATIN SUBSCRIPT SMALL LETTER X
	'ₕ'   = 'h'   # U+2095 LATIN SUBSCRIPT SMALL LETTER H
	'ₖ'   = 'k'   # U+2096 LATIN SUBSCRIPT SMALL LETTER K
	'ₗ'   = 'l'   # U+2097 LATIN SUBSCRIPT SMALL LETTER L
	'ₘ'   = 'm'   # U+2098 LATIN SUBSCRIPT SMALL LETTER M
	'ₙ'   = 'n'   # U+2099 LATIN SUBSCRIPT SMALL LETTER N
	'ₚ'   = 'p'   # U+209A LATIN SUBSCRIPT SMALL LETTER P
	'ₛ'   = 's'   # U+209B LATIN SUBSCRIPT SMALL LETTER S
	'ₜ'   = 't'   # U+209C LATIN SUBSCRIPT SMALL LETTER T
	'ⱼ'   = 'j'   # U+2C7C LATIN SUBSCRIPT SMALL LETTER J
	'ᵢ'   = 'i'   # U+1D62 LATIN SUBSCRIPT SMALL LETTER I
	'ᵣ'   = 'r'   # U+1D63 LATIN SUBSCRIPT SMALL LETTER R
	'ᵤ'   = 'u'   # U+1D64 LATIN SUBSCRIPT SMALL LETTER U
	'ᵥ'   = 'v'   # U+1D65 LATIN SUBSCRIPT SMALL LETTER V
	'ᵦ'   = 'b'   # U+1D66 GREEK SUBSCRIPT SMALL LETTER BETA
	'ᵧ'   = 'y'   # U+1D67 GREEK SUBSCRIPT SMALL LETTER GAMMA
	'ᵨ'   = 'p'   # U+1D68 GREEK SUBSCRIPT SMALL LETTER RHO
	'ᵪ'   = 'x'   # U+1D6A GREEK SUBSCRIPT SMALL LETTER CHI

	# ---------- Superscripts ----------
	'⁰'   = '0'   # U+2070 SUPERSCRIPT ZERO
	'¹'   = '1'   # U+00B9 SUPERSCRIPT ONE
	'⁴'   = '4'   # U+2074 SUPERSCRIPT FOUR
	'⁵'   = '5'   # U+2075 SUPERSCRIPT FIVE
	'⁶'   = '6'   # U+2076 SUPERSCRIPT SIX
	'⁷'   = '7'   # U+2077 SUPERSCRIPT SEVEN
	'⁸'   = '8'   # U+2078 SUPERSCRIPT EIGHT
	'⁹'   = '9'   # U+2079 SUPERSCRIPT NINE
	'⁺'   = '+'   # U+207A SUPERSCRIPT PLUS SIGN
	'⁻'   = '-'   # U+207B SUPERSCRIPT MINUS
	'⁼'   = '='   # U+207C SUPERSCRIPT EQUALS SIGN
	'⁽'   = '('   # U+207D SUPERSCRIPT LEFT PARENTHESIS
	'⁾'   = ')'   # U+207E SUPERSCRIPT RIGHT PARENTHESIS
	'ⁱ'   = 'i'   # U+2071 SUPERSCRIPT LATIN SMALL LETTER I
	'ⁿ'   = 'n'   # U+207F SUPERSCRIPT LATIN SMALL LETTER N

	# ---------- Geometric Shapes - Diamonds ----------
	'◆'   = '*'   # U+25C6 BLACK DIAMOND
	'◇'   = '<>'  # U+25C7 WHITE DIAMOND
	'◈'   = '<>'  # U+25C8 WHITE DIAMOND CONTAINING BLACK SMALL DIAMOND
	'◊'   = '<>'  # U+25CA LOZENGE
	'❖'   = '<>'  # U+2756 BLACK DIAMOND MINUS WHITE X
	'⬖'   = '<>'  # U+2B16 BLACK DIAMOND WITH LEFT HALF BLACK
	'⬗'   = '<>'  # U+2B17 BLACK DIAMOND WITH RIGHT HALF BLACK
	'⬘'   = '<>'  # U+2B18 BLACK DIAMOND WITH TOP HALF BLACK
	'⬙'   = '<>'  # U+2B19 BLACK DIAMOND WITH BOTTOM HALF BLACK
	'⬥'   = '<>'  # U+2B25 BLACK MEDIUM DIAMOND
	'⬦'   = '<>'  # U+2B26 WHITE MEDIUM DIAMOND

	# ---------- Geometric Shapes - Hexagons / Pentagons ----------
	'⬟'   = '*'   # U+2B1F BLACK PENTAGON
	'⬠'   = '*'   # U+2B20 WHITE PENTAGON
	'⬡'   = '*'   # U+2B21 WHITE HEXAGON
	'⬢'   = '*'   # U+2B22 BLACK HEXAGON
	'⬣'   = '*'   # U+2B23 HORIZONTAL BLACK HEXAGON

	# ---------- Geometric Shapes - Squares ----------
	'■'   = '[]'  # U+25A0 BLACK SQUARE
	'□'   = '[]'  # U+25A1 WHITE SQUARE
	'▢'   = '[]'  # U+25A2 WHITE SQUARE WITH ROUNDED CORNERS
	'▣'   = '[]'  # U+25A3 WHITE SQUARE CONTAINING BLACK SMALL SQUARE
	'▪'   = '*'   # U+25AA BLACK SMALL SQUARE
	'▫'   = '*'   # U+25AB WHITE SMALL SQUARE
	'▬'   = '[]'  # U+25AC BLACK RECTANGLE
	'▭'   = '[]'  # U+25AD WHITE RECTANGLE
	'▮'   = '[]'  # U+25AE BLACK VERTICAL RECTANGLE
	'▯'   = '[]'  # U+25AF WHITE VERTICAL RECTANGLE
	'▰'   = '*'   # U+25B0 BLACK PARALLELOGRAM
	'▱'   = '*'   # U+25B1 WHITE PARALLELOGRAM

	# ---------- Geometric Shapes - Pointers ----------
	'►'   = '>'   # U+25BA BLACK RIGHT-POINTING POINTER
	'▻'   = '>'   # U+25BB WHITE RIGHT-POINTING POINTER
	'◄'   = '<'   # U+25C4 BLACK LEFT-POINTING POINTER
	'◅'   = '<'   # U+25C5 WHITE LEFT-POINTING POINTER

	# ---------- Geometric Shapes - Circles ----------
	'○'   = 'o'   # U+25CB WHITE CIRCLE
	'◌'   = 'o'   # U+25CC DOTTED CIRCLE
	'◍'   = 'o'   # U+25CD CIRCLE WITH VERTICAL FILL
	'◎'   = 'o'   # U+25CE BULLSEYE
	'●'   = '*'   # U+25CF BLACK CIRCLE
	'◐'   = 'o'   # U+25D0 CIRCLE WITH LEFT HALF BLACK
	'◑'   = 'o'   # U+25D1 CIRCLE WITH RIGHT HALF BLACK
	'◒'   = 'o'   # U+25D2 CIRCLE WITH LOWER HALF BLACK
	'◓'   = 'o'   # U+25D3 CIRCLE WITH UPPER HALF BLACK
	'◔'   = 'o'   # U+25D4 CIRCLE WITH UPPER RIGHT QUADRANT BLACK
	'◕'   = 'o'   # U+25D5 CIRCLE WITH ALL BUT UPPER LEFT QUADRANT BLACK
	'◖'   = 'o'   # U+25D6 LEFT HALF BLACK CIRCLE
	'◗'   = 'o'   # U+25D7 RIGHT HALF BLACK CIRCLE
	'◘'   = '*'   # U+25D8 INVERSE BULLET
	'◙'   = 'o'   # U+25D9 INVERSE WHITE CIRCLE
	'◚'   = 'o'   # U+25DA UPPER HALF INVERSE WHITE CIRCLE
	'◛'   = 'o'   # U+25DB LOWER HALF INVERSE WHITE CIRCLE
	'◜'   = 'o'   # U+25DC UPPER LEFT QUADRANT CIRCULAR ARC
	'◝'   = 'o'   # U+25DD UPPER RIGHT QUADRANT CIRCULAR ARC
	'◞'   = 'o'   # U+25DE LOWER RIGHT CIRCULAR QUADRANT
	'◟'   = 'o'   # U+25DF LOWER LEFT CIRCULAR QUADRANT
	'◠'   = 'o'   # U+25E0 UPPER HALF CIRCLE
	'◡'   = 'o'   # U+25E1 LOWER HALF CIRCLE
	'◢'   = 'v'   # U+25E2 BLACK LOWER RIGHT TRIANGLE
	'◣'   = 'v'   # U+25E3 BLACK LOWER LEFT TRIANGLE
	'◤'   = '^'   # U+25E4 BLACK UPPER LEFT TRIANGLE
	'◥'   = '^'   # U+25E5 BLACK UPPER RIGHT TRIANGLE
	'☆'   = '*'   # U+2606 WHITE STAR

	# ---------- Braille Patterns ----------
	'⠂'   = '*'   # U+2802 BRAILLE PATTERN DOTS-2
	([char]0x2810) = '*' # U+2810 BRAILLE PATTERN DOTS-4

	# ---------- Box Drawing ----------
	'─'   = '-'   # U+2500 BOX DRAWINGS LIGHT HORIZONTAL
	'═'   = '='   # U+2550 BOX DRAWINGS DOUBLE HORIZONTAL

	# ---------- Symbols ----------
	'©'   = '(C)'   # U+00A9 COPYRIGHT SIGN
	'®'   = '(R)'   # U+00AE REGISTERED SIGN
	'™'   = '(TM)'  # U+2122 TRADE MARK SIGN
	'°'   = ' deg ' # U+00B0 DEGREE SIGN
	'︰'  = ':'     # U+FE30 PRESENTATION FORM FOR VERTICAL COLON

	# ---------- Unicode Spaces (invisible look-alikes, keyed by codepoint) ----------
	([char]0x1680) = ' ' # U+1680 OGHAM SPACE MARK
	([char]0x2000) = ' ' # U+2000 EN QUAD
	([char]0x2001) = ' ' # U+2001 EM QUAD
	([char]0x2004) = ' ' # U+2004 THREE-PER-EM SPACE
	([char]0x2005) = ' ' # U+2005 FOUR-PER-EM SPACE
	([char]0x2006) = ' ' # U+2006 SIX-PER-EM SPACE
	([char]0x2007) = ' ' # U+2007 FIGURE SPACE
	([char]0x2008) = ' ' # U+2008 PUNCTUATION SPACE
	([char]0x200A) = ' ' # U+200A HAIR SPACE
	([char]0x205F) = ' ' # U+205F MEDIUM MATHEMATICAL SPACE
	([char]0x3000) = ' ' # U+3000 IDEOGRAPHIC SPACE

	# ---------- Zero-Width / Invisible ----------
	([char]0x200B) = '' # U+200B ZERO WIDTH SPACE
	([char]0x200C) = '' # U+200C ZERO WIDTH NON-JOINER
	([char]0x200D) = '' # U+200D ZERO WIDTH JOINER
	([char]0x2060) = '' # U+2060 WORD JOINER
	([char]0xFEFF) = '' # U+FEFF ZERO WIDTH NO-BREAK SPACE (BOM)

	# ---------- Bidirectional Controls ----------
	([char]0x202A) = '' # U+202A LEFT-TO-RIGHT EMBEDDING
	([char]0x202B) = '' # U+202B RIGHT-TO-LEFT EMBEDDING
	([char]0x202C) = '' # U+202C POP DIRECTIONAL FORMATTING
	([char]0x202D) = '' # U+202D LEFT-TO-RIGHT OVERRIDE
	([char]0x202E) = '' # U+202E RIGHT-TO-LEFT OVERRIDE
	([char]0x2066) = '' # U+2066 LEFT-TO-RIGHT ISOLATE
	([char]0x2067) = '' # U+2067 RIGHT-TO-LEFT ISOLATE
	([char]0x2068) = '' # U+2068 FIRST STRONG ISOLATE
	([char]0x2069) = '' # U+2069 POP DIRECTIONAL ISOLATE

	# ---------- Miscellaneous Invisible Characters ----------
	([char]0x00AD) = ''  # U+00AD SOFT HYPHEN
	([char]0x034F) = ''  # U+034F COMBINING GRAPHEME JOINER
	([char]0x061C) = ''  # U+061C ARABIC LETTER MARK
	([char]0x180E) = ''  # U+180E MONGOLIAN VOWEL SEPARATOR
	([char]0x2028) = ' ' # U+2028 LINE SEPARATOR
	([char]0x2029) = ' ' # U+2029 PARAGRAPH SEPARATOR
	([char]0x200E) = ''  # U+200E LEFT-TO-RIGHT MARK
	([char]0x200F) = ''  # U+200F RIGHT-TO-LEFT MARK
	([char]0x2061) = ''  # U+2061 FUNCTION APPLICATION
	([char]0x2062) = ''  # U+2062 INVISIBLE TIMES
	([char]0x2063) = ''  # U+2063 INVISIBLE SEPARATOR
	([char]0x2064) = ''  # U+2064 INVISIBLE PLUS
	([char]0x206A) = ''  # U+206A INHIBIT SYMMETRIC SWAPPING
	([char]0x206B) = ''  # U+206B ACTIVATE SYMMETRIC SWAPPING
	([char]0x206C) = ''  # U+206C INHIBIT ARABIC FORM SHAPING
	([char]0x206D) = ''  # U+206D ACTIVATE ARABIC FORM SHAPING
	([char]0x206E) = ''  # U+206E NATIONAL DIGIT SHAPES
	([char]0x206F) = ''  # U+206F NOMINAL DIGIT SHAPES

	# ---------- Variation Selectors ----------
	([char]0xFE00) = '' # U+FE00 VARIATION SELECTOR-1
	([char]0xFE01) = '' # U+FE01 VARIATION SELECTOR-2
	([char]0xFE02) = '' # U+FE02 VARIATION SELECTOR-3
	([char]0xFE03) = '' # U+FE03 VARIATION SELECTOR-4
	([char]0xFE04) = '' # U+FE04 VARIATION SELECTOR-5
	([char]0xFE05) = '' # U+FE05 VARIATION SELECTOR-6
	([char]0xFE06) = '' # U+FE06 VARIATION SELECTOR-7
	([char]0xFE07) = '' # U+FE07 VARIATION SELECTOR-8
	([char]0xFE08) = '' # U+FE08 VARIATION SELECTOR-9
	([char]0xFE09) = '' # U+FE09 VARIATION SELECTOR-10
	([char]0xFE0A) = '' # U+FE0A VARIATION SELECTOR-11
	([char]0xFE0B) = '' # U+FE0B VARIATION SELECTOR-12
	([char]0xFE0C) = '' # U+FE0C VARIATION SELECTOR-13
	([char]0xFE0D) = '' # U+FE0D VARIATION SELECTOR-14
	([char]0xFE0E) = '' # U+FE0E VARIATION SELECTOR-15
	([char]0xFE0F) = '' # U+FE0F VARIATION SELECTOR-16

	# ---------- Blank/filler glyphs ----------
	([char]0x115F) = '' # U+115F HANGUL CHOSEONG FILLER
	([char]0x1160) = '' # U+1160 HANGUL JUNGSEONG FILLER
	([char]0x3164) = '' # U+3164 HANGUL FILLER
	([char]0xFFA0) = '' # U+FFA0 HALFWIDTH HANGUL FILLER
	([char]0x2800) = '' # U+2800 BRAILLE PATTERN BLANK
	([char]0x17B4) = '' # U+17B4 KHMER VOWEL INHERENT AQ
	([char]0x17B5) = '' # U+17B5 KHMER VOWEL INHERENT AA
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
