#!/usr/bin/env pwsh
# Requires -Version 7.0
# Git Worktree Manager (gwk) - Standalone PowerShell TUI
# One-time install: gwk.ps1 --setup (copies to ~/Scripts, updates PATH, installs launchers/alias)
# Requires Git 2.17+ for full functionality (worktree move/repair); older Git degrades gracefully
[CmdletBinding()]
param(
  [Alias('s')][switch]$Setup,
  [Alias('h')][switch]$Help,
  [Alias('v')][switch]$Version,
  [switch]$Doctor,
  [string]$ConfigPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
Remove-Item Env:GIT_DIR -ErrorAction SilentlyContinue
Remove-Item Env:GIT_WORK_TREE -ErrorAction SilentlyContinue
Remove-Item Env:GIT_INDEX_FILE -ErrorAction SilentlyContinue
Remove-Item Env:GIT_COMMON_DIR -ErrorAction SilentlyContinue
$env:GIT_TERMINAL_PROMPT = '0'
$env:GIT_OPTIONAL_LOCKS = '0'
$env:GIT_PAGER = 'cat'
$env:LC_ALL = 'C'
$script:NoColor = -not [string]::IsNullOrEmpty($env:NO_COLOR)
$script:NoColor = $script:NoColor -or $env:TERM -eq 'dumb'
$script:GitCwd = ''
$script:Verbose = -not [string]::IsNullOrEmpty($env:GWK_VERBOSE)

if ($PSVersionTable.PSVersion.Major -lt 7) {
  throw 'gwk requires PowerShell 7 or newer. Install PowerShell 7+ and run with pwsh.'
}
if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) {
  throw 'gwk TUI requires an interactive console.'
}
if ($Host.Name -match 'ISE') {
  throw 'gwk requires a real console terminal. PowerShell ISE is not supported.'
}

$script:AppVersion = '1.1.1'
$script:ConfigPath = if ($ConfigPath) { $ConfigPath } elseif ($env:GWK_CONFIG) { $env:GWK_CONFIG } else { Join-Path $HOME '.gwk.json' }
$script:RepoRoot = ''
$script:RepoName = ''
$script:ConfigLoadError = $null

$script:State = @{
  Worktrees = @()
  Selected = 0
  Scroll = 0
  Message = ''
  MessageKind = 'info'
  Running = $true
  Config = $null
  Filter = ''
  FilteredWorktrees = $null
}
$script:UiTooSmall = $false
$script:WorktreeCache = @{}
$script:CacheTTL = 5
$script:KeyBindings = @{
  Footer1 = "`e[1mUp/Down`e[0m Select  `e[1mEnter`e[0m Open  `e[1mN`e[0m New  `e[1mD`e[0m Del  `e[1mM`e[0m Move  `e[1mB`e[0m Branch  `e[1mY`e[0m Copy Path"
  Footer2 = "`e[1mO`e[0m Open with  `e[1mE`e[0m Openers  `e[1mL`e[0m Lock  `e[1mU`e[0m Unlock  `e[1mP`e[0m Prune  `e[1mX`e[0m Repair  `e[1mR`e[0m Refresh  `e[1m?`e[0m Help  `e[1mQ`e[0m Quit"
  Help = @(
    'J / K           Select worktree'
    'PageUp / PgDn   Scroll 5 worktrees'
    'Home / End      Jump to first / last worktree'
    'Enter           Open selected worktree with first configured (default @) opener'
    'O               Open with... (choose from configured openers or press 1-9)'
    'Y               Copy full path of selected worktree to clipboard'
    'N               Create / add new worktree (with smart branch auto-detection)'
    'D / Del         Remove selected worktree (checks for dirty files first)'
    'M               Move / rename worktree path'
    'B               Switch / bind branch in selected worktree'
    'L / U           Lock / unlock worktree from being pruned or deleted'
    'P               Prune stale worktree references (deleted folders)'
    'X               Repair worktree administrative links (reconnect moved/broken worktrees)'
    'E               Manage / configure workspace openers & presets'
    'R               Refresh worktree status from Git'
    '?               Show this help screen'
    'Q / Esc         Quit'
  )
}

function Write-Ansi([string]$Text) {
  if ($script:NoColor) {
    $Text = $Text -replace '\x1b\[[0-9;?]*[A-Za-z]', ''
  }
  [Console]::Write($Text)
}

function Write-Status([string]$Text, [int]$BgColor = 44) {
  if ($script:NoColor) {
    [Console]::Write($Text)
  } else {
    [Console]::Write("`e[30;48;5;${BgColor}m${Text}`e[0m")
  }
}

function Move-Cursor([int]$Row, [int]$Col = 1) { Write-Ansi "`e[${Row};${Col}H" }
function Clear-Screen { Write-Ansi "`e[2J`e[H" }
function Hide-Cursor {
  try { [Console]::CursorVisible = $false } catch {}
  Write-Ansi "`e[?25l"
}
function Show-Cursor {
  try { [Console]::CursorVisible = $true } catch {}
  Write-Ansi "`e[?25h"
}
function Reset-Terminal { Write-Ansi "`e[0m" }
function Enter-AlternateScreen { Write-Ansi "`e[?1049h"; Clear-Screen; Hide-Cursor }
function Exit-AlternateScreen { Show-Cursor; Write-Ansi "`e[?1049l" }

function Set-Message([string]$Text, [ValidateSet('info','ok','warn','error')] [string]$Kind = 'info') {
  $script:State.Message = $Text
  $script:State.MessageKind = $Kind
}

function Invalidate-WorktreeCache([string]$Path = '') {
  if ($Path) {
    $script:WorktreeCache.Remove($Path)
  } else {
    $script:WorktreeCache.Clear()
  }
}

function Test-WorktreePath {
  param(
    [Parameter(Mandatory)][string]$Path,
    [switch]$MustBeEmpty,
    [switch]$MustNotExist
  )
  $resolved = Resolve-UserPath $Path
  $normalized = Normalize-Path $resolved

  if ([string]::IsNullOrWhiteSpace($resolved)) {
    return @{ Valid = $false; Error = 'Path cannot be empty.'; Resolved = $resolved }
  }

  # Check path length (OS limits)
  if ($IsWindows -and $resolved.Length -gt 260) {
    return @{ Valid = $false; Error = "Path exceeds Windows 260-character limit ($($resolved.Length) chars). Use a shorter path."; Resolved = $resolved }
  }

  # Check if path is inside itself
  if ($script:RepoRoot) {
    $normRepo = Normalize-Path $script:RepoRoot
    if ($normalized -ieq $normRepo -or $normalized.StartsWith($normRepo + [IO.Path]::DirectorySeparatorChar)) {
      return @{ Valid = $false; Error = 'Cannot create a worktree inside the repository itself.'; Resolved = $resolved }
    }
  }

  if (Test-Path -LiteralPath $resolved) {
    if ($MustNotExist) {
      return @{ Valid = $false; Error = "Path already exists: $resolved"; Resolved = $resolved }
    }
    if (-not (Test-Path -LiteralPath $resolved -PathType Container)) {
      return @{ Valid = $false; Error = "Path exists and is not a directory: $resolved"; Resolved = $resolved }
    }
    if ($MustBeEmpty) {
      $items = Get-ChildItem -LiteralPath $resolved -Force -ErrorAction SilentlyContinue
      if ($items) {
        return @{ Valid = $false; Error = "Target directory is not empty: $resolved"; Resolved = $resolved }
      }
    }
  }

  # Validate parent directory exists or can be created
  $parentDir = Split-Path -Parent $resolved
  if ($parentDir -and -not (Test-Path -LiteralPath $parentDir -PathType Container)) {
    try {
      New-Item -ItemType Directory -Path $parentDir -Force -ErrorAction Stop | Out-Null
    } catch {
      return @{ Valid = $false; Error = "Cannot create parent directory: $($_.Exception.Message)"; Resolved = $resolved }
    }
  }

  return @{ Valid = $true; Error = ''; Resolved = $resolved }
}

function Test-BranchName {
  param([Parameter(Mandatory)][string]$Branch)
  $r = Invoke-Git @('check-ref-format', '--branch', $Branch)
  if ($r.ExitCode -ne 0) {
    return @{ Valid = $false; Error = "Invalid branch name '$Branch'." }
  }
  return @{ Valid = $true; Error = '' }
}

function Get-DefaultOpeners {
  $list = [System.Collections.Generic.List[object]]::new()
  $list.Add([ordered]@{ name = 'VS Code'; command = 'code --reuse-window "{path}"' })
  if ($IsWindows) {
    $list.Add([ordered]@{ name = 'File Explorer'; command = 'explorer "{path}"' })
    $list.Add([ordered]@{ name = 'Windows Terminal'; command = 'wt.exe -d "{path}"' })
  } elseif ($IsMacOS) {
    $list.Add([ordered]@{ name = 'Finder'; command = 'open "{path}"' })
    $list.Add([ordered]@{ name = 'Terminal'; command = 'open -a Terminal "{path}"' })
  } else {
    $list.Add([ordered]@{ name = 'File Manager'; command = 'xdg-open "{path}"' })
  }
  return @($list)
}

function Get-OpenerPresets {
  return @(
    [ordered]@{ name = 'VS Code'; command = 'code --reuse-window "{path}"'; desc = 'Visual Studio Code' },
    [ordered]@{ name = 'Cursor'; command = 'cursor "{path}"'; desc = 'Cursor AI Editor' },
    [ordered]@{ name = 'Windsurf'; command = 'windsurf "{path}"'; desc = 'Windsurf Editor' },
    [ordered]@{ name = 'JetBrains (IntelliJ)'; command = 'idea "{path}"'; desc = 'IntelliJ IDEA' },
    [ordered]@{ name = 'JetBrains (PyCharm)'; command = 'pycharm "{path}"'; desc = 'PyCharm' },
    [ordered]@{ name = 'JetBrains (WebStorm)'; command = 'webstorm "{path}"'; desc = 'WebStorm' },
    [ordered]@{ name = 'Neovim'; command = $(if ($IsWindows) { 'wt.exe -w 0 nvim "{path}"' } else { 'nvim "{path}"' }); desc = 'Neovim in terminal'; interactive = $true },
    [ordered]@{ name = 'Sublime Text'; command = 'subl "{path}"'; desc = 'Sublime Text' },
    [ordered]@{ name = 'File Manager'; command = $(if ($IsWindows) { 'explorer "{path}"' } elseif ($IsMacOS) { 'open "{path}"' } else { 'xdg-open "{path}"' }); desc = 'System File Explorer / Finder' },
    [ordered]@{ name = 'New Terminal Tab'; command = $(if ($IsWindows) { 'wt.exe -d "{path}"' } elseif ($IsMacOS) { 'open -a Terminal "{path}"' } elseif ($env:TMUX) { 'tmux new-window -c "{path}"' } elseif ($env:ZELLIJ) { 'zellij action new-tab --cwd "{path}"' } else { 'x-terminal-emulator --working-directory="{path}"' }); desc = 'Open folder in new terminal'; interactive = $true }
  )
}

function Get-Config {
  $defaults = [ordered]@{
    version = 1
    openers = Get-DefaultOpeners
    autoPrune = $false
  }

  if (-not (Test-Path -LiteralPath $script:ConfigPath)) {
    return $defaults
  }

  try {
    $json = Get-Content -LiteralPath $script:ConfigPath -Raw
    if ([string]::IsNullOrWhiteSpace($json)) { return $defaults }

    $loaded = $json | ConvertFrom-Json -AsHashtable
    if ($loaded -isnot [System.Collections.IDictionary]) {
      return $defaults
    }
    $ops = @()
    foreach ($op in @($loaded.openers)) {
      try {
        if ($op -is [hashtable] -or $op -is [System.Collections.IDictionary]) {
          $name = if ($op['name']) { [string]$op['name'] } else { 'Unnamed' }
          $cmd = if ($op['command']) { [string]$op['command'] } else { '' }
          if ($cmd) { $ops += [ordered]@{ name = $name; command = $cmd } }
        }
      } catch {}
    }
    if ($ops.Count -gt 0) { $loaded.openers = $ops }

    $hasOpeners = $null -ne $loaded.PSObject.Properties['openers']
    if (-not $hasOpeners -or $null -eq $loaded.openers -or @($loaded.openers).Count -eq 0) {
      $loaded.openers = $defaults.openers
    }
    $hasVersion = $null -ne $loaded.PSObject.Properties['version']
    if (-not $hasVersion) {
      $loaded['version'] = 1
    }
    return $loaded
  } catch {
    $script:ConfigLoadError = $_.Exception.Message
    return $defaults
  }
}

function Save-Config {
  $encoding = [System.Text.UTF8Encoding]::new($false)
  $tmpPath = "$script:ConfigPath.$([System.IO.Path]::GetRandomFileName()).tmp"
  try {
    $json = $script:State.Config | ConvertTo-Json -Depth 8
    # Validate JSON before writing
    $null = $json | ConvertFrom-Json -AsHashtable
    $json | Set-Content -LiteralPath $tmpPath -Encoding $encoding -Force
    if (Test-Path -LiteralPath $script:ConfigPath) {
      Remove-Item -LiteralPath $script:ConfigPath -Force
    }
    Move-Item -LiteralPath $tmpPath -Destination $script:ConfigPath -Force
  } catch {
    if (Test-Path -LiteralPath $tmpPath) { Remove-Item -LiteralPath $tmpPath -Force -ErrorAction SilentlyContinue }
    throw
  }
}

function Invoke-Git {
  param(
    [Parameter(Mandatory)][string[]]$Arguments,
    [string]$Cwd = ''
  )
  if (-not $Cwd) { $Cwd = Get-RepoCwd }
  if ($script:Verbose) {
    $argStr = $Arguments -join ' '
    Write-Host "[gwk] git -C $Cwd $argStr" -ForegroundColor DarkGray
  }
  try {
    $raw = & git -C $Cwd @Arguments 2>&1
    $exit = if ($null -eq $global:LASTEXITCODE) { 0 } else { $global:LASTEXITCODE }

    $stdout = @(
      $raw |
        Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] } |
        ForEach-Object { if ($null -ne $_) { $_.ToString() } }
    )
    $stderr = @(
      $raw |
        Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } |
        ForEach-Object { $_.ToString() }
    )
    $output = if ($exit -eq 0) { $stdout } else { @($stderr + $stdout) }

    return [pscustomobject]@{
      ExitCode = $exit
      Output = @($output | Where-Object { $null -ne $_ })
      StdOut = $stdout
      Errors = $stderr
    }
  } catch {
    if ($script:Verbose) { Write-Host "[gwk] git failed: $($_.Exception.Message)" -ForegroundColor DarkYellow }
    return [pscustomobject]@{ ExitCode = 1; Output = @($_.Exception.Message); StdOut = @(); Errors = @($_.Exception.Message) }
  }
}

function Assert-GitRepository {
  $gitCmd = Get-Command git -ErrorAction SilentlyContinue
  if (-not $gitCmd) {
    throw 'Git is not installed or not found in PATH. Please install Git to use gwk.'
  }
  $r = Invoke-Git @('rev-parse','--git-dir')
  if ($r.ExitCode -ne 0) {
    $details = ($r.Output -join [Environment]::NewLine).Trim()
    throw "Current directory is not inside a Git repository.`n$details"
  }
}

function Ensure-GitRepository {
  $gitCmd = Get-Command git -ErrorAction SilentlyContinue
  if (-not $gitCmd) {
    throw 'Git is not installed or not found in PATH. Please install Git to use gwk.'
  }
  $r = Invoke-Git @('rev-parse', '--git-dir')
  if ($r.ExitCode -ne 0) {
    $details = ($r.Output -join [Environment]::NewLine).Trim()
    $curDir = [Environment]::CurrentDirectory
    Clear-Screen
    Move-Cursor 1 1
    Write-Ansi "`e[1;38;5;45mGit Worktree Manager (gwk)`e[0m`n`n"
    Write-Host "The current directory is not a Git repository:" -ForegroundColor Yellow
    Write-Host "  $curDir`n" -ForegroundColor Cyan
    if ($details) { Write-Host "  Git says: $details`n" -ForegroundColor DarkGray }

    $shouldInit = Confirm-Choice 'Would you like to initialize a new Git repository here?' $true
    if ($shouldInit) {
      $rInit = Invoke-Git @('init')
      if ($rInit.ExitCode -eq 0) {
        Write-Host "`nSuccessfully initialized Git repository in '$curDir'." -ForegroundColor Green
        Start-Sleep -Milliseconds 600
        return
      } else {
        throw "Failed to initialize Git repository: $(($rInit.Output -join ' ').Trim())"
      }
    } else {
      throw 'Current directory is not inside a Git repository.'
    }
  }
}

function Get-RepositoryRoot {
  $r = Invoke-Git @('rev-parse','--show-toplevel')
  if ($r.ExitCode -ne 0) {
    $r2 = Invoke-Git @('rev-parse','--git-dir')
    if ($r2.ExitCode -eq 0) { return ($r2.Output -join '').Trim() }
    throw (($r.Output -join [Environment]::NewLine).Trim())
  }
  return ($r.Output -join [Environment]::NewLine).Trim()
}

function Get-RepoCwd {
  if (-not [string]::IsNullOrEmpty($script:GitCwd)) {
    if (Test-Path -LiteralPath $script:GitCwd -PathType Container) { return $script:GitCwd }
  }
  if (-not [string]::IsNullOrEmpty($script:RepoRoot) -and (Test-Path -LiteralPath $script:RepoRoot -PathType Container)) {
    return $script:RepoRoot
  }
  return [Environment]::CurrentDirectory
}

function Get-Worktrees {
  $r = Invoke-Git @('worktree','list','--porcelain')
  if ($r.ExitCode -ne 0) { throw (($r.Output -join [Environment]::NewLine).Trim()) }

  $items = [System.Collections.Generic.List[object]]::new()
  $current = $null
  foreach ($rawLine in $r.Output) {
    $line = $rawLine.TrimEnd("`r")
    if ([string]::IsNullOrWhiteSpace($line)) {
      if ($null -ne $current) { Enrich-WorktreeStatus $current; $items.Add([pscustomobject]$current); $current = $null }
      continue
    }
    if ($line.StartsWith('worktree ')) {
      if ($null -ne $current) { Enrich-WorktreeStatus $current; $items.Add([pscustomobject]$current) }
      $rawPath = $line.Substring(9).Trim()
      if ($rawPath.StartsWith('"') -and $rawPath.EndsWith('"') -and $rawPath.Length -ge 2) {
        $rawPath = $rawPath.Substring(1, $rawPath.Length - 2)
        # Handle C-style escape sequences
        $rawPath = $rawPath -replace '\\n', "`n"
        $rawPath = $rawPath -replace '\\t', "`t"
        $rawPath = $rawPath -replace '\\r', "`r"
        $rawPath = $rawPath -replace '\\"', '"'
        $rawPath = $rawPath -replace '\\\\', '\'
      }
      $normPath = Normalize-Path $rawPath
      $current = [ordered]@{
        Path = $normPath
        RawPath = $rawPath
        Head = ''
        Branch = ''
        SymbolicRef = ''
        BindingValid = $true
        BindingStatus = 'Valid'
        Detached = $false
        Bare = $false
        Locked = $false
        Prunable = $false
        Reason = ''
        Main = $false
        Ahead = 0
        Behind = 0
        Dirty = 0
        Untracked = 0
        TotalChanges = 0
        CommitSummary = ''
        HasUpstream = $false
        UpstreamGone = $false
      }
    } elseif ($null -ne $current -and $line.StartsWith('HEAD ')) {
      $current.Head = $line.Substring(5).Trim()
    } elseif ($null -ne $current -and $line.StartsWith('branch ')) {
      $ref = $line.Substring(7).Trim()
      $current.Branch = if ($ref.StartsWith('refs/heads/')) { $ref.Substring(11) } else { $ref }
    } elseif ($null -ne $current -and $line -eq 'detached') {
      $current.Detached = $true
    } elseif ($null -ne $current -and $line -eq 'bare') {
      $current.Bare = $true
    } elseif ($null -ne $current -and $line -eq 'locked') {
      $current.Locked = $true
    } elseif ($null -ne $current -and $line.StartsWith('locked ')) {
      $current.Locked = $true
      $current.Reason = $line.Substring(7).Trim()
    } elseif ($null -ne $current -and $line -eq 'prunable') {
      $current.Prunable = $true
    } elseif ($null -ne $current -and $line.StartsWith('prunable ')) {
      $current.Prunable = $true
      $current.Reason = $line.Substring(9).Trim()
    }
  }
  if ($null -ne $current) { Enrich-WorktreeStatus $current; $items.Add([pscustomobject]$current) }

  if ($items.Count -gt 0 -and -not $items[0].Bare) {
    $items[0].Main = $true
  }

  return @($items)
}

function Enrich-WorktreeStatus($wt) {
  $wt.Ahead = 0
  $wt.Behind = 0
  $wt.Dirty = 0
  $wt.Untracked = 0
  $wt.TotalChanges = 0
  $wt.CommitSummary = ''
  $wt.SymbolicRef = ''
  $wt.BindingValid = $true
  $wt.BindingStatus = 'Valid'
  $wt.UpstreamGone = $false

  if ([string]::IsNullOrEmpty($wt.Path) -or $wt.Bare -or $wt.Prunable) {
    if ($wt.Bare) { $wt.BindingStatus = 'Bare' }
    if ($wt.Prunable) { $wt.BindingStatus = 'Prunable' }
    return
  }

  $cacheKey = $wt.Path
  $now = [DateTime]::UtcNow
  if ($script:WorktreeCache.ContainsKey($cacheKey)) {
    $entry = $script:WorktreeCache[$cacheKey]
    $age = ($now - $entry.Timestamp).TotalSeconds
    if ($age -lt $script:CacheTTL) {
      $wt.Ahead = $entry.Ahead
      $wt.Behind = $entry.Behind
      $wt.Dirty = $entry.Dirty
      $wt.Untracked = $entry.Untracked
      $wt.TotalChanges = $entry.TotalChanges
      $wt.HasChanges = $entry.HasChanges
      $wt.CommitSummary = $entry.CommitSummary
      $wt.SymbolicRef = $entry.SymbolicRef
      $wt.BindingValid = $entry.BindingValid
      $wt.BindingStatus = $entry.BindingStatus
      $wt.UpstreamGone = $entry.UpstreamGone
      $wt.Detached = $entry.Detached
      $wt.HasUpstream = $entry.HasUpstream
      return
    }
  }

  if (-not (Test-Path -LiteralPath $wt.Path -PathType Container)) {
    $wt.Prunable = $true
    if (Test-Path -LiteralPath $wt.Path) {
      $wt.Reason = 'Path exists but is not a directory'
    } else {
      if (-not $wt.Reason) { $wt.Reason = 'Directory missing' }
    }
    $wt.BindingStatus = $wt.Reason
    return
  }

  # Validate branch binding via git symbolic-ref HEAD
  $rSym = Invoke-Git @('symbolic-ref', 'HEAD') -Cwd $wt.Path
  if ($rSym.ExitCode -eq 0 -and $rSym.Output.Count -gt 0) {
    $symRef = ($rSym.Output -join '').Trim()
    $wt.SymbolicRef = $symRef
    if ($symRef.StartsWith('refs/heads/')) {
      $actualBranch = $symRef.Substring(11)
      if ($wt.Branch -and $wt.Branch -ne $actualBranch) {
        $wt.BindingValid = $false
        $wt.BindingStatus = "Mismatch (expected $($wt.Branch), got $actualBranch)"
        $wt.Branch = $actualBranch
      } else {
        $wt.Branch = $actualBranch
        $wt.BindingValid = $true
        $wt.BindingStatus = "$symRef (Valid)"
      }
      $wt.Detached = $false
    } else {
      $wt.BindingValid = $false
      $wt.BindingStatus = "Non-branch ref ($symRef)"
    }
  } else {
    if (-not $wt.Detached -and (Test-Path -LiteralPath $wt.Path -PathType Container)) {
      $wt.BindingValid = $false
      $wt.BindingStatus = 'symbolic-ref failed (possible corruption)'
    } elseif ($wt.Detached) {
      $wt.BindingValid = $true
      $wt.BindingStatus = 'Detached HEAD'
    }
    $wt.SymbolicRef = ''
  }

  # symbolic-ref success is authoritative - HEAD is not detached
  if ($rSym.ExitCode -eq 0 -and $rSym.Output.Count -gt 0) {
    $wt.Detached = $false
  }

  $r = Invoke-Git @('-c', 'status.showUntrackedFiles=all', '--no-optional-locks', 'status', '--porcelain', '-b') -Cwd $wt.Path
  if ($r.ExitCode -eq 0) {
    $wt.HasUpstream = $false
    foreach ($line in $r.Output) {
      if ($line.StartsWith('## ')) {
        if ($line -match 'ahead (\d+)') { $wt.Ahead = [int]$matches[1] }
        if ($line -match 'behind (\d+)') { $wt.Behind = [int]$matches[1] }
        if ($line -match '\.\.\.') { $wt.HasUpstream = $true }
        if ($line -match '\[gone\]') { $wt.UpstreamGone = $true }
      } elseif ($line.StartsWith('??')) {
        $wt.Untracked = $wt.Untracked + 1
      } else {
        $wt.Dirty = $wt.Dirty + 1
      }
    }
  }
  $wt.TotalChanges = $wt.Dirty + $wt.Untracked
  $wt.HasChanges = $wt.TotalChanges -gt 0

  if ($wt.Head -and $wt.Head -ne '0000000000000000000000000000000000000000') {
    $rCommit = Invoke-Git @('log', '-1', '--format=%h %s (%cr)', $wt.Head) -Cwd $wt.Path
    if ($rCommit.ExitCode -eq 0 -and $rCommit.Output.Count -gt 0) {
      $wt.CommitSummary = ($rCommit.Output -join ' ').Trim()
    }
  } else {
    $wt.CommitSummary = 'No commits yet'
  }

  $script:WorktreeCache[$cacheKey] = @{
    Timestamp = $now
    Ahead = $wt.Ahead
    Behind = $wt.Behind
    Dirty = $wt.Dirty
    Untracked = $wt.Untracked
    TotalChanges = $wt.TotalChanges
    HasChanges = $wt.HasChanges
    CommitSummary = $wt.CommitSummary
    SymbolicRef = $wt.SymbolicRef
    BindingValid = $wt.BindingValid
    BindingStatus = $wt.BindingStatus
    UpstreamGone = $wt.UpstreamGone
    Detached = $wt.Detached
    HasUpstream = $wt.HasUpstream
  }
}

function Format-WorktreeState($wt) {
  if ($wt.Bare) { return 'BARE' }
  if ($wt.Prunable) { return 'PRUNABLE' }
  if ($wt.Locked) {
    if ($wt.Detached) { return 'LOCK/DET' }
    return 'LOCKED'
  }
  if ($wt.Detached) {
    $headShort = if ($wt.Head) { $wt.Head.Substring(0, [Math]::Min(7, $wt.Head.Length)) } else { '???' }
    return "DET $headShort"
  }
  if ($wt.PSObject.Properties['BindingValid'] -and $wt.BindingValid -eq $false) {
    return 'MISCONFIG'
  }

  $parts = @()
  if ($wt.Ahead -gt 0) { $parts += "+$($wt.Ahead)" }
  if ($wt.Behind -gt 0) { $parts += "-$($wt.Behind)" }
  $totalChanges = $wt.TotalChanges
  if ($totalChanges -gt 0) { $parts += "*$totalChanges" }

  if ($parts.Count -eq 0) {
    if ($wt.Main) { return 'MAIN' }
    return 'READY'
  }

  $syncStr = $parts -join ' '
  if ($wt.Main) { return "MAIN $syncStr" }
  return $syncStr
}

function Format-SyncStatus($wt) {
  if ($wt.Prunable) { return 'Worktree path missing (run Prune)' }
  if ($wt.Bare) { return 'Bare repository' }
  if ($wt.Head -eq '0000000000000000000000000000000000000000') { return 'No commits yet' }
  if ($wt.HasUpstream -and $wt.UpstreamGone) { return 'Upstream gone' }
  if (-not $wt.HasUpstream) { return 'Local only (no upstream)' }
  $bits = @()
  if ($wt.Ahead -gt 0) { $bits += "ahead $($wt.Ahead)" }
  if ($wt.Behind -gt 0) { $bits += "behind $($wt.Behind)" }
  if ($bits.Count -eq 0) { return 'Up to date with remote' }
  return $bits -join ', '
}

function Refresh-Data {
  try {
    Assert-GitRepository

    $script:State.Worktrees = Get-Worktrees

    $main = $script:State.Worktrees |
      Where-Object { $_.Main -and -not $_.Bare } |
      Select-Object -First 1

    if (-not $main) {
      $main = $script:State.Worktrees |
        Where-Object {
        -not $_.Bare -and
        (Test-Path -LiteralPath $_.Path -PathType Container)
      } |
        Select-Object -First 1
    }

    if ($main) {
      $script:RepoRoot = $main.Path
      $script:GitCwd = $main.Path
    }
    else {
      $script:RepoRoot = Get-RepositoryRoot
    }

    $script:RepoName = Split-Path -Leaf $script:RepoRoot

    if ($script:State.Selected -ge $script:State.Worktrees.Count) {
      $script:State.Selected = [Math]::Max(0, $script:State.Worktrees.Count - 1)
    }

    # Reapply filter if active
    if ($script:State.Filter) {
      $escaped = [regex]::Escape($script:State.Filter)
      $script:State.FilteredWorktrees = @($script:State.Worktrees | Where-Object {
        $_.Path -imatch $escaped -or
        $_.Branch -imatch $escaped -or
        $_.Head -imatch $escaped
      })
      if ($script:State.FilteredWorktrees.Count -eq 0) {
        $script:State.Filter = ''
        $script:State.FilteredWorktrees = $null
      } elseif ($script:State.Selected -ge $script:State.FilteredWorktrees.Count) {
        $script:State.Selected = [Math]::Max(0, $script:State.FilteredWorktrees.Count - 1)
      }
    }

    Set-Message "Loaded $($script:State.Worktrees.Count) worktree(s) in $script:RepoName." 'ok'
    $maxScroll = [Math]::Max(0, $script:State.Worktrees.Count - 1)
    $script:State.Selected = [Math]::Max(0, [Math]::Min($script:State.Selected, $maxScroll))
    $script:State.Scroll = [Math]::Max(0, [Math]::Min($script:State.Scroll, $maxScroll))
  } catch {
    Set-Message $_.Exception.Message 'error'
  }
}

function Start-Filter {
  $input = Read-UserLine '/' ''
  if ($null -eq $input) {
    $script:State.Filter = ''
    $script:State.FilteredWorktrees = $null
    return
  }
  $query = $input.Trim()
  if ([string]::IsNullOrEmpty($query)) {
    $script:State.Filter = ''
    $script:State.FilteredWorktrees = $null
    return
  }
  $script:State.Filter = $query
  $escaped = [regex]::Escape($query)
  $script:State.FilteredWorktrees = @($script:State.Worktrees | Where-Object {
    $_.Path -imatch $escaped -or
    $_.Branch -imatch $escaped -or
    $_.Head -imatch $escaped
  })
  $script:State.Selected = 0
  $script:State.Scroll = 0
  if ($script:State.FilteredWorktrees.Count -eq 0) {
    Set-Message "No worktrees match '$query'." 'warn'
  } else {
    Set-Message "Filter: $($script:State.FilteredWorktrees.Count)/$($script:State.Worktrees.Count) match(es)." 'ok'
  }
}

function Clear-Filter {
  $script:State.Filter = ''
  $script:State.FilteredWorktrees = $null
  $script:State.Selected = 0
  $script:State.Scroll = 0
  Set-Message "Filter cleared." 'info'
}

function Get-DisplayList {
  if ($script:State.FilteredWorktrees) { return $script:State.FilteredWorktrees }
  return $script:State.Worktrees
}

function Get-SelectedWorktree {
  $list = Get-DisplayList
  if ($list.Count -eq 0) { return $null }
  $idx = [Math]::Min($script:State.Selected, $list.Count - 1)
  return $list[$idx]
}

function Get-TerminalSize {
  try { return [pscustomobject]@{ Width = [Console]::WindowWidth; Height = [Console]::WindowHeight } }
catch { return [pscustomobject]@{ Width = 120; Height = 30 } }
}

function Get-DisplayWidth([string]$Text) {
  if ([string]::IsNullOrEmpty($Text)) { return 0 }
  $width = 0
  # NOTE: This width logic covers CJK + common emoji ranges but not full Unicode East-Asian Width
  # or emoji ZWJ sequences. Watch for .NET/PowerShell improvements in StringInfo or consider
  # using a dedicated Unicode width library if precision becomes critical.
  $charEnum = [System.Globalization.StringInfo]::GetTextElementEnumerator($Text)
  while ($charEnum.MoveNext()) {
    $elem = $charEnum.GetTextElement()
    $cp = [int][char]$elem[0]
    if ($cp -ge 0x1100 -and (
      ($cp -ge 0x1100 -and $cp -le 0x115F) -or
      ($cp -eq 0x2329) -or ($cp -eq 0x232A) -or
      ($cp -ge 0x2E80 -and $cp -le 0x303E) -or
      ($cp -ge 0x3040 -and $cp -le 0x33BF) -or
      ($cp -ge 0x3400 -and $cp -le 0x4DBF) -or
      ($cp -ge 0x4E00 -and $cp -le 0xA4CF) -or
      ($cp -ge 0xA960 -and $cp -le 0xA97C) -or
      ($cp -ge 0xAC00 -and $cp -le 0xD7A3) -or
      ($cp -ge 0xF900 -and $cp -le 0xFAFF) -or
      ($cp -ge 0xFE30 -and $cp -le 0xFE6F) -or
      ($cp -ge 0xFF01 -and $cp -le 0xFF60) -or
      ($cp -ge 0xFFE0 -and $cp -le 0xFFE6) -or
      ($cp -ge 0x20000 -and $cp -le 0x2FFFD) -or
      ($cp -ge 0x30000 -and $cp -le 0x3FFFD)
    )) {
      $width += 2
    } else {
      $cat = [System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($elem[0])
      if ($cat -ne [System.Globalization.UnicodeCategory]::NonSpacingMark -and
          $cat -ne [System.Globalization.UnicodeCategory]::SpacingCombiningMark -and
          $cat -ne [System.Globalization.UnicodeCategory]::EnclosingMark) {
        $width += 1
      }
    }
  }
  return $width
}

function Fit-Text([string]$Text, [int]$Width) {
  if ($Width -le 0) { return '' }
  if ($null -eq $Text) { $Text = '' }
  $displayWidth = Get-DisplayWidth $Text
  if ($displayWidth -le $Width) { return $Text.PadRight($Width - $displayWidth + $Text.Length) }
  if ($Width -le 1) { return '…'.Substring(0, [Math]::Min(1, $Width)) }
  $result = [System.Text.StringBuilder]::new()
  $currentWidth = 0
  $charEnum = [System.Globalization.StringInfo]::GetTextElementEnumerator($Text)
  while ($charEnum.MoveNext() -and $currentWidth -lt ($Width - 1)) {
    $elem = $charEnum.GetTextElement()
    $cp = [int][char]$elem[0]
    $charWidth = 1
    if ($cp -ge 0x1100 -and (
      ($cp -ge 0x1100 -and $cp -le 0x115F) -or
      ($cp -eq 0x2329) -or ($cp -eq 0x232A) -or
      ($cp -ge 0x2E80 -and $cp -le 0x303E) -or
      ($cp -ge 0x3040 -and $cp -le 0x33BF) -or
      ($cp -ge 0x3400 -and $cp -le 0x4DBF) -or
      ($cp -ge 0x4E00 -and $cp -le 0xA4CF) -or
      ($cp -ge 0xA960 -and $cp -le 0xA97C) -or
      ($cp -ge 0xAC00 -and $cp -le 0xD7A3) -or
      ($cp -ge 0xF900 -and $cp -le 0xFAFF) -or
      ($cp -ge 0xFE30 -and $cp -le 0xFE6F) -or
      ($cp -ge 0xFF01 -and $cp -le 0xFF60) -or
      ($cp -ge 0xFFE0 -and $cp -le 0xFFE6) -or
      ($cp -ge 0x20000 -and $cp -le 0x2FFFD) -or
      ($cp -ge 0x30000 -and $cp -le 0x3FFFD)
    )) {
      $charWidth = 2
    }
    if ($currentWidth + $charWidth -gt ($Width - 1)) { break }
    [void]$result.Append($elem)
    $currentWidth += $charWidth
  }
  [void]$result.Append('…')
  return $result.ToString()
}

function Normalize-Path([string]$p) {
  if ([string]::IsNullOrWhiteSpace($p)) { return $p }
  try {
    $full = [System.IO.Path]::GetFullPath($p)
    $full = $full.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    # Normalize Windows drive-letter case and \\?\ prefix
    if ($IsWindows) {
      $full = $full -replace '^(.):', { $_.Groups[1].Value.ToUpper() + ':' }
      $full = $full -replace '^\\\\\?\\', ''
    }
    return $full
  } catch { return $p }
}

function PathsEqual([string]$a, [string]$b) {
  return (Normalize-Path $a) -ieq (Normalize-Path $b)
}

function Resolve-UserPath([string]$Path) {
  if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
  if ($Path.StartsWith('~')) {
    $Path = Join-Path $HOME $Path.Substring(1).TrimStart('/', '\')
  }
  try { return [System.IO.Path]::GetFullPath($Path) } catch { return $Path }
}

function Draw-Box([int]$Top, [int]$Left, [int]$Width, [int]$Height) {
  if ($Width -lt 2 -or $Height -lt 2) { return }
  Move-Cursor $Top $Left
  Write-Ansi ('┌' + ('─' * ($Width - 2)) + '┐')
  for ($i = 1; $i -lt ($Height - 1); $i++) {
    Move-Cursor ($Top + $i) $Left
    Write-Ansi '│'
    Move-Cursor ($Top + $i) ($Left + $Width - 1)
    Write-Ansi '│'
  }
  Move-Cursor ($Top + $Height - 1) $Left
  Write-Ansi ('└' + ('─' * ($Width - 2)) + '┘')
}

function Draw-DetailPane($displayList, $listTop, $detailLeft, $detailWidth) {
  Draw-Box $listTop $detailLeft $detailWidth ($script:State.Height - 9)
  Move-Cursor ($listTop + 1) ($detailLeft + 2)
  Write-Ansi "`e[1mDETAILS`e[0m"
  if ($displayList.Count -gt 0) {
    $wt = $displayList[$script:State.Selected]
    $lockText = 'Unlocked'
    if ($wt.Locked) {
      if ($wt.Reason) { $lockText = 'Locked: ' + $wt.Reason } else { $lockText = 'Locked' }
    }
    $changedText = 'Clean'
    if ($wt.TotalChanges -gt 0) {
      $changedText = "$($wt.TotalChanges) change(s)"
      if ($wt.Untracked -gt 0) {
        $changedText += " ($($wt.Untracked) untracked)"
      }
    }

    $commitDisplay = if ($wt.CommitSummary) { $wt.CommitSummary } elseif ($wt.Head) { $wt.Head } else { 'N/A' }
    $prunableDisplay = if ($wt.Prunable) { if ($wt.Reason) { $wt.Reason } else { 'Yes (missing directory)' } } else { 'No' }

    $lines = @(
      @('Path', $wt.Path),
      @('Branch', $(if ($wt.Bare) { '(bare)' } elseif ($wt.Detached) { '(detached HEAD)' } else { $wt.Branch })),
      @('Binding', $wt.BindingStatus),
      @('Commit', $commitDisplay),
      @('Sync', $(Format-SyncStatus $wt)),
      @('Changes', $changedText),
      @('Type', $(if ($wt.Main) { 'Main worktree' } elseif ($wt.Bare) { 'Bare repository' } else { 'Linked worktree' })),
      @('Lock', $lockText),
      @('Prunable', $prunableDisplay)
    )
    $r = $listTop + 3
    foreach ($pair in $lines) {
      Move-Cursor $r ($detailLeft + 2)
      Write-Ansi (' ' * ($detailWidth - 4))
      Move-Cursor $r ($detailLeft + 2)
      Write-Ansi "`e[2m$($pair[0].PadRight(10))`e[0m $(Fit-Text ([string]$pair[1]) ($detailWidth - 14))"
      $r++
    }
  } else {
    Move-Cursor ($listTop + 4) ($detailLeft + 2)
    Write-Ansi (' ' * ($detailWidth - 4))
    Move-Cursor ($listTop + 4) ($detailLeft + 2)
    Write-Ansi "No worktrees found."
  }
}

function Get-EnterCommand {
  $wt = Get-SelectedWorktree
  if ($null -eq $wt -or $null -eq $script:State.Config) { return $null }

  $openers = @($script:State.Config.openers)
  if ($openers.Count -eq 0 -or $null -eq $openers[0]) { return $null }

  $opener = $openers[0]
  if (-not $opener.command) { return $null }
  $expanded = Expand-Template ([string]$opener.command) $wt
  return [pscustomobject]@{ Name = [string]$opener.name; Command = $expanded }
}

function Draw-UI {
  Move-Cursor 1 1
  $term = Get-TerminalSize
  $w = $term.Width
  $h = $term.Height
  $script:State.Height = $h
  if ($w -lt 60 -or $h -lt 10) {
    $script:UiTooSmall = $true
    Clear-Screen
    Move-Cursor 1 1
    Write-Ansi "Terminal too small. Need at least 60x10 (current ${w}x${h})."
    return
  }
  $script:UiTooSmall = $false

  $displayList = Get-DisplayList
  $title = " Git Worktree Manager v$script:AppVersion "
  $repoInfo = if ($script:RepoName) { "$script:RepoName ($script:RepoRoot)" } else { [Environment]::CurrentDirectory }
  Move-Cursor 1 1
  Write-Ansi "`e[1;38;5;45m$title`e[0m"
  Write-Ansi (' ' * [Math]::Max(0, $w - $title.Length - $repoInfo.Length - 2))
  Write-Ansi "`e[2m$(Fit-Text $repoInfo ([Math]::Max(10, $w - $title.Length - 3)))`e[0m"

  $listTop = 3
  $listHeight = $h - 9
  $showDetails = $w -ge 90
  if ($showDetails) {
    $listWidth = [Math]::Min(74, [Math]::Max(46, [int]($w * 0.60)))
    $detailLeft = $listWidth + 4
    $detailWidth = $w - $detailLeft - 1
  } else {
    $listWidth = $w - 2
    $detailLeft = 0
    $detailWidth = 0
  }
  $pathCol = [Math]::Max(12, [int]($listWidth * 0.38))
  $branchCol = [Math]::Max(8, [int]($listWidth * 0.24))
  $stateCol = [Math]::Max(8, $listWidth - $pathCol - $branchCol - 8)

  Draw-Box $listTop 1 $listWidth $listHeight
  Move-Cursor ($listTop + 1) 3
  Write-Ansi "`e[1mWORKTREES`e[0m"

  $headerRow = $listTop + 3
  Move-Cursor $headerRow 3
  Write-Ansi "`e[2m   PATH$((' ' * ($pathCol - 1)))BRANCH$((' ' * ($branchCol - 1)))STATUS`e[0m"

  $visible = $listHeight - 5
  if ($visible -lt 1) { $visible = 1 }
  if ($script:State.Selected -lt $script:State.Scroll) { $script:State.Scroll = $script:State.Selected }
  if ($script:State.Selected -ge ($script:State.Scroll + $visible)) { $script:State.Scroll = $script:State.Selected - $visible + 1 }

  for ($i = 0; $i -lt $visible; $i++) {
    $index = $script:State.Scroll + $i
    $row = $headerRow + 1 + $i
    Move-Cursor $row 2
    Write-Ansi (' ' * ($listWidth - 2))
    Move-Cursor $row 2
    if ($index -ge $displayList.Count) { continue }
    $wt = $displayList[$index]
    $selected = $index -eq $script:State.Selected
    $isCurrent = $false
    try { $isCurrent = PathsEqual ([Environment]::CurrentDirectory) $wt.Path } catch {}
    $prefix = if ($selected) { '›' } elseif ($isCurrent) { '•' } else { ' ' }
    $state = Format-WorktreeState $wt

    $pathPart = Split-Path -Leaf ($wt.Path.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar))
    if ([string]::IsNullOrEmpty($pathPart)) { $pathPart = $wt.Path }
    $pathPart = Fit-Text $pathPart $pathCol

    $branch = if ($wt.Bare) { '(bare)' } elseif ($wt.Detached) {
      $headShort = if ($wt.Head) { $wt.Head.Substring(0, [Math]::Min(8, $wt.Head.Length)) } else { '???' }
      "($headShort)"
    } else { $wt.Branch }
    $branch = Fit-Text $branch $branchCol
    $statePart = Fit-Text $state $stateCol

    if ($selected) {
      $rowText = "$prefix $pathPart $branch $statePart"
      $rowWidth = Get-DisplayWidth $rowText
      $availWidth = $listWidth - 2
      $pad = if ($rowWidth -lt $availWidth) { ' ' * ($availWidth - $rowWidth) } else { '' }
      Write-Ansi "`e[48;5;24;38;5;255m $rowText$pad `e[0m"
    } else {
      $colorState = switch ($state) {
        'MAIN'     { "`e[36m$statePart`e[0m" }
        'READY'    { "`e[32m$statePart`e[0m" }
        { $_ -match '^\*' } { "`e[33m$statePart`e[0m" }
        { $_ -match '^\+' } { "`e[92m$statePart`e[0m" }
        { $_ -match '^\-' } { "`e[35m$statePart`e[0m" }
        { $_ -eq 'LOCKED' -or $_ -match '^LOCK' } { "`e[33m$statePart`e[0m" }
        { $_ -eq 'PRUNABLE' } { "`e[91m$statePart`e[0m" }
        default { $statePart }
      }
      Write-Ansi " $prefix $pathPart $branch $colorState "
    }
  }

  if ($showDetails) {
    Draw-DetailPane $displayList $listTop $detailLeft $detailWidth
  }

  $msgRow = $h - 5
  Move-Cursor $msgRow 1
  $idxStr = if ($displayList.Count -gt 0) { "$($script:State.Selected + 1)/$($displayList.Count) " } else { '' }
  $msg = Fit-Text (" $idxStr$($script:State.Message)") ($w - 1)
  $msgColor = switch ($script:State.MessageKind) { 'ok' { 42 } 'warn' { 43 } 'error' { 41 } default { 44 } }
  Write-Status $msg $msgColor

  # Show the exact expanded command Enter will execute.
  Move-Cursor ($h - 4) 1
  Write-Ansi (' ' * ($w - 1))
  Move-Cursor ($h - 4) 1
  $enterInfo = Get-EnterCommand
  if ($enterInfo) {
    $preview = "ENTER `e[1m$($enterInfo.Name)`e[0m `e[2m$($enterInfo.Command)`e[0m"
    Write-Ansi "`e[2m  $(Fit-Text $preview ($w - 4))`e[0m"
  }

  Move-Cursor ($h - 3) 1
  Write-Ansi (' ' * ($w - 1))
  Move-Cursor ($h - 3) 1
  $filterLine = if ($script:State.Filter) { "  `e[1m/`e[0m Filter: $(Fit-Text $script:State.Filter 20) (Esc clear)" } else { "  `e[1m/`e[0m Filter" }
  Write-Ansi "$($script:KeyBindings.Footer1)$filterLine"

  Move-Cursor ($h - 2) 1
  Write-Ansi (' ' * ($w - 1))
  Move-Cursor ($h - 2) 1
  Write-Ansi $script:KeyBindings.Footer2

  Move-Cursor $h 1
  Write-Ansi (' ' * ($w - 1))
}

function Read-UserLine([string]$Prompt, [string]$Default = '') {
  Show-Cursor
  $buffer = [System.Collections.Generic.List[System.String]]::new()
  if ($Default) { foreach ($c in $Default.ToCharArray()) { $buffer.Add($c.ToString()) } }
  $cursor = $buffer.Count

  $term = Get-TerminalSize
  $h = $term.Height
  $w = $term.Width
  $windowStart = 0

  $drawInput = {
    $bufStr = [string]::Join('', @($buffer.ToArray()))
    $maxInputWidth = $w - 1 - $Prompt.Length
    if ($maxInputWidth -lt 1) { $maxInputWidth = 1 }
    if ($cursor -lt $windowStart) { $windowStart = $cursor }
    if ($cursor -gt ($windowStart + $maxInputWidth)) { $windowStart = $cursor - $maxInputWidth }
    if ($windowStart -lt 0) { $windowStart = 0 }
    $visibleStr = $bufStr.Substring($windowStart, [Math]::Min($maxInputWidth, $bufStr.Length - $windowStart))
    $padding = ' ' * ($w - 1 - $Prompt.Length - $visibleStr.Length)
    Move-Cursor $h 1
    Write-Ansi (' ' * ($w - 1))
    Move-Cursor $h 1
    Write-Ansi "`e[1;36m$Prompt`e[0m"
    Write-Ansi $visibleStr
    Write-Ansi $padding
    $col = 1 + $Prompt.Length + ($cursor - $windowStart)
    if ($col -lt 1) { $col = 1 }
    if ($col -gt $w) { $col = $w }
    Move-Cursor $h $col
  }

  $cancelled = $false
  $done = $false
  while (-not $done) {
    $drawInput.Invoke()
    $k = [Console]::ReadKey($true)

    $isCtrl = ($k.Modifiers -band [ConsoleModifiers]::Control) -ne 0
    if ($isCtrl) {
      switch ($k.Key) {
        'C' { $cancelled = $true; $done = $true }
        'A' { $cursor = 0 }
        'E' { $cursor = $buffer.Count }
        'U' { $buffer.Clear(); $cursor = 0; $windowStart = 0 }
        'K' { if ($cursor -lt $buffer.Count) { $buffer.RemoveRange($cursor, $buffer.Count - $cursor) } }
        'W' {
          if ($cursor -gt 0) {
            $idx = $cursor - 1
            while ($idx -gt 0 -and $buffer[$idx] -eq ' ') { $idx-- }
            while ($idx -gt 0 -and $buffer[$idx] -ne ' ') { $idx-- }
            $delCount = $cursor - $idx
            $buffer.RemoveRange($idx, $delCount)
            $cursor = $idx
          }
        }
        'V' {
          if (Get-Command Get-Clipboard -ErrorAction SilentlyContinue) {
            try {
              $clip = Get-Clipboard
              if ($clip -is [array]) { $clip = $clip -join ' ' }
              if (-not [string]::IsNullOrEmpty($clip)) {
                $hasNewlines = $clip -match '[\r\n]'
                $cleanClip = ($clip -replace '[\r\n]', '').Trim()
                if ($hasNewlines -and $cleanClip.Length -gt 0) {
                  Set-Message "Multi-line paste collapsed to single line." 'warn'
                }
                foreach ($ch in $cleanClip.ToCharArray()) {
                  if (-not [char]::IsControl($ch)) {
                    $buffer.Insert($cursor, $ch.ToString())
                    $cursor++
                  }
                }
              }
            } catch {}
          }
        }
      }
      continue
    }

    switch ($k.Key) {
      'Enter' { $done = $true }
      'Escape' { $cancelled = $true; $done = $true }
      'Backspace' { if ($cursor -gt 0) { $buffer.RemoveAt($cursor - 1); $cursor-- } }
      'Delete' { if ($cursor -lt $buffer.Count) { $buffer.RemoveAt($cursor) } }
      'LeftArrow' { if ($cursor -gt 0) { $cursor-- } }
      'RightArrow' { if ($cursor -lt $buffer.Count) { $cursor++ } }
      'Home' { $cursor = 0 }
      'End' { $cursor = $buffer.Count }
      default {
        if (-not [char]::IsControl($k.KeyChar)) {
          if ($cursor -eq $buffer.Count) {
            $buffer.Add($k.KeyChar.ToString())
          } else {
            $buffer.Insert($cursor, $k.KeyChar.ToString())
          }
          $cursor++
        }
      }
    }
  }

  Move-Cursor $h 1
  Write-Ansi (' ' * ($w - 1))
  Hide-Cursor

  if ($cancelled) { return $null }
  return [string]::Join('', @($buffer.ToArray()))
}

function Confirm-Choice([string]$Question, [bool]$DefaultYes = $false) {
  $hint = if ($DefaultYes) { '[Y/n]' } else { '[y/N]' }
  $answer = Read-UserLine "$Question $hint "
  if ($null -eq $answer) { return $false }
  if ([string]::IsNullOrWhiteSpace($answer)) { return $DefaultYes }
  return $answer.Trim() -match '^(?i)y(?:es)?$'
}

function New-Worktree {
  $rHead = Invoke-Git @('rev-parse', '--verify', '--quiet', 'HEAD')
  if ($rHead.ExitCode -ne 0) {
    Set-Message 'This repository has no commits yet. Create an initial commit before adding worktrees.' 'warn'
    return
  }

  # 1. Fetch available branches for suggestions / auto-detection
  $localBranches = @()
  $remoteBranches = @()
  $rLocal = Invoke-Git @('branch', '--list', '--format=%(refname:short)')
  if ($rLocal.ExitCode -eq 0) { $localBranches = @($rLocal.Output | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
  $rRemote = Invoke-Git @('branch', '-r', '--format=%(refname:short)')
  if ($rRemote.ExitCode -eq 0) { $remoteBranches = @($rRemote.Output | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.Contains('/HEAD') }) }

  $branch = Read-UserLine 'Branch name (existing or new): '
  if ($null -eq $branch) { Set-Message 'Create cancelled.' 'info'; return }
  $branch = $branch.Trim()
  if ([string]::IsNullOrWhiteSpace($branch)) { Set-Message 'A branch name is required.' 'warn'; return }

  $branchCheck = Test-BranchName $branch
  if (-not $branchCheck.Valid) { Set-Message $branchCheck.Error 'warn'; return }

  $isLocal = $localBranches -contains $branch
  $remoteMatch = $remoteBranches | Where-Object {
    $_ -eq $branch -or ($_ -split '/' | Select-Object -Last 1) -eq $branch
  } | Select-Object -First 1
  $isRemote = $null -ne $remoteMatch
  $isNew = (-not $isLocal) -and (-not $isRemote)

  $createBranch = $false
  $startPoint = ''

  if ($isLocal) {
    $alreadyInUse = $script:State.Worktrees | Where-Object { $_.Branch -eq $branch } | Select-Object -First 1
    if ($alreadyInUse) {
      if ($alreadyInUse.Prunable) {
        Set-Message "Branch '$branch' is registered to a prunable worktree at '$($alreadyInUse.Path)'. Press 'P' to prune stale worktrees first." 'warn'
      } else {
        Set-Message "Branch '$branch' is already checked out in '$($alreadyInUse.Path)'." 'error'
      }
      return
    }
  } elseif ($isRemote) {
    $createBranch = $true
    $startPoint = $remoteMatch
  } else {
    $confirmNew = Confirm-Choice "Branch '$branch' is new. Create it?" $true
    if (-not $confirmNew) { Set-Message 'Create cancelled.' 'info'; return }
    $createBranch = $true
    $startInput = Read-UserLine 'Start point (blank = HEAD): '
    if ($null -eq $startInput) { Set-Message 'Create cancelled.' 'info'; return }
    $startPoint = if ([string]::IsNullOrWhiteSpace($startInput)) { 'HEAD' } else { $startInput.Trim() }
  }

  # Generate smart default path: sibling folder ../<repoName>-<sanitizedBranch>
  $repoRoot = if ($script:RepoRoot) { $script:RepoRoot } else { Get-RepositoryRoot }
  $repoName = if ($script:RepoName) { $script:RepoName } else { Split-Path -Leaf $repoRoot }
  $sanitizedBranch = ($branch -replace '[\\/:*?"<>|]', '-')
  $sanitizedBranch = $sanitizedBranch -replace '-+', '-'
  $sanitizedBranch = $sanitizedBranch.TrimEnd('-').TrimStart('.')
  if ($sanitizedBranch.Length -gt 50) { $sanitizedBranch = $sanitizedBranch.Substring(0, 50) }
  if ([string]::IsNullOrWhiteSpace($sanitizedBranch)) { $sanitizedBranch = 'worktree' }
  $parentDir = Split-Path -Parent $repoRoot
  $baseDir = if ($parentDir) { Join-Path $parentDir "$repoName.worktrees" } else { "../$repoName.worktrees" }
  # Collision-resistant: append numeric suffix if path already exists
  $suggestedPath = Join-Path $baseDir $sanitizedBranch
  $suffix = 1
  while (Test-Path -LiteralPath $suggestedPath) {
    $candidate = Join-Path $baseDir "$sanitizedBranch-$suffix"
    $suggestedPath = $candidate
    $suffix++
    if ($suffix -gt 999) { break }
  }

  $pathInput = Read-UserLine "Path for worktree (default: $suggestedPath): "
  if ($null -eq $pathInput) { Set-Message 'Create cancelled.' 'info'; return }
  $path = if ([string]::IsNullOrWhiteSpace($pathInput)) { $suggestedPath } else { $pathInput.Trim() }
  $pathResult = Test-WorktreePath $path -MustBeEmpty
  if (-not $pathResult.Valid) { Set-Message $pathResult.Error 'error'; return }
  $path = $pathResult.Resolved

  # Execute git worktree add
  if ($createBranch) {
    if ($startPoint) {
      $r = Invoke-Git @('worktree', 'add', '-b', $branch, $path, $startPoint)
    } else {
      $r = Invoke-Git @('worktree', 'add', '-b', $branch, $path)
    }
  } else {
    $r = Invoke-Git @('worktree', 'add', $path, $branch)
  }

  if ($r.ExitCode -eq 0) {
    Set-Message "Created worktree '$branch' at '$path'." 'ok'
    Invalidate-WorktreeCache
    Refresh-Data
    for ($i = 0; $i -lt $script:State.Worktrees.Count; $i++) {
      if ($script:State.Worktrees[$i].Branch -eq $branch) {
        $script:State.Selected = $i
        break
      }
    }
  } else {
    Set-Message (($r.Output -join ' ').Trim()) 'error'
  }
}

function Remove-SelectedWorktree {
  $wt = Get-SelectedWorktree
  if (-not $wt) { return }
  if ($wt.Bare) { Set-Message 'The bare repository entry cannot be removed.' 'warn'; return }
  if ($wt.Main) { Set-Message 'The main worktree cannot be removed.' 'warn'; return }
  if ($wt.Locked) {
    if (-not (Confirm-Choice "Worktree is locked. Force remove (unlocks and deletes)? This is irreversible." $false)) {
      Set-Message 'Remove cancelled.' 'info'
      return
    }
    $r = Invoke-Git @('worktree', 'remove', '--force', '--', $wt.Path)
    if ($r.ExitCode -ne 0) {
      Set-Message (($r.Output -join ' ').Trim()) 'error'
      return
    }
    Set-Message 'Locked worktree force-removed.' 'ok'
    Refresh-Data
    return
  }

  if ($wt.Dirty -gt 0 -or $wt.Untracked -gt 0) {
    $total = $wt.TotalChanges
    $confirmDirty = Confirm-Choice "WARNING: '$($wt.Path)' has $total uncommitted change(s) (incl. $($wt.Untracked) untracked)! Force delete and LOSE CHANGES?" $false
    if (-not $confirmDirty) { Set-Message 'Remove cancelled.' 'info'; return }
    $r = Invoke-Git @('worktree', 'remove', '--force', '--', $wt.Path)
  } else {
    if (-not (Confirm-Choice "Remove worktree at '$($wt.Path)'?" $false)) {
      Set-Message 'Remove cancelled.' 'info'
      return
    }
    $r = Invoke-Git @('worktree', 'remove', '--', $wt.Path)
    if ($r.ExitCode -ne 0 -and ($r.Output -join ' ') -match 'contains modified or untracked files') {
      if (Confirm-Choice "Worktree contains untracked files. Force remove? This will permanently delete ALL files including untracked data." $false) {
        $r = Invoke-Git @('worktree', 'remove', '--force', '--', $wt.Path)
      } else {
        Set-Message 'Remove cancelled.' 'info'
        return
      }
    }
  }

  if ($r.ExitCode -eq 0) {
    Set-Message 'Worktree removed.' 'ok'
    Invalidate-WorktreeCache $wt.Path
    $next = $script:State.Worktrees |
      Where-Object {
      $_.Path -ne $wt.Path -and
      -not $_.Bare -and
      (Test-Path -LiteralPath $_.Path -PathType Container)
    } |
      Select-Object -First 1
    $script:GitCwd = if ($next) { $next.Path } elseif ($script:RepoRoot -and (Test-Path -LiteralPath $script:RepoRoot -PathType Container)) { $script:RepoRoot } else { [Environment]::CurrentDirectory }

    Refresh-Data

    # Post-remove: verify directory is actually gone; attempt cleanup if not
    if (Test-Path -LiteralPath $wt.Path) {
      $dirInfo = Get-Item -LiteralPath $wt.Path -ErrorAction SilentlyContinue
      if ($dirInfo -and $dirInfo.PSIsContainer) {
        try {
          Remove-Item -LiteralPath $wt.Path -Recurse -Force -ErrorAction Stop
          Set-Message 'Worktree removed and leftover directory cleaned up.' 'ok'
        } catch {
          Set-Message "Worktree unlinked but directory remains. Close programs using '$($wt.Path)', then press 'P' to prune." 'warn'
        }
      }
    }

    # Prompt for optional branch deletion
    if ($wt.Branch -and -not $wt.Detached) {
      $branchExists = Invoke-Git @('rev-parse', '--verify', '--quiet', "refs/heads/$($wt.Branch)")
      if ($branchExists.ExitCode -eq 0) {
        $mainWt = $script:State.Worktrees | Where-Object { $_.Main -and -not $_.Bare } | Select-Object -First 1
        $mainCwd = if ($mainWt -and (Test-Path -LiteralPath $mainWt.Path -PathType Container)) { $mainWt.Path } else { $script:GitCwd }
        $isDefault = Invoke-Git @('symbolic-ref', '-q', 'HEAD') -Cwd $mainCwd
        $isDefaultBranch = ($isDefault.ExitCode -eq 0) -and (($isDefault.Output -join '').TrimEnd() -eq "refs/heads/$($wt.Branch)")
        if (-not $isDefaultBranch) {
          $otherWt = $script:State.Worktrees | Where-Object { $_.Branch -eq $wt.Branch -and $_.Path -ne $wt.Path } | Select-Object -First 1
          if (-not $otherWt) {
            if (Confirm-Choice "Branch '$($wt.Branch)' no longer checked out anywhere. Delete it too?" $false) {
              $dr = Invoke-Git @('branch', '-D', $wt.Branch)
              if ($dr.ExitCode -eq 0) {
                Set-Message "Branch '$($wt.Branch)' deleted." 'ok'
                Refresh-Data
              } else {
                Set-Message "Failed to delete branch: $(($dr.Output -join ' ').Trim())" 'warn'
              }
            }
          }
        }
      }
    }
  } else {
    $errMsg = ($r.Output -join ' ').Trim()
    if ($errMsg -match 'Permission denied' -or $errMsg -match 'Access is denied' -or $errMsg -match 'being used by another process') {
      Set-Message "Remove failed: close all programs using the worktree directory (Explorer, editor, antivirus), then retry. You may also try 'X' to repair." 'error'
    } else {
      Set-Message $errMsg 'error'
    }
  }
}

function Rename-SelectedWorktree {
  $wt = Get-SelectedWorktree
  if (-not $wt) { return }
  if ($wt.Bare) { Set-Message 'The bare repository entry cannot be moved.' 'warn'; return }
  if ($wt.Main) { Set-Message 'The main worktree cannot be moved.' 'warn'; return }
  if ($wt.Locked) { Set-Message 'Worktree is locked. Unlock it before moving.' 'warn'; return }

  $newPath = Read-UserLine 'New path for worktree: ' $wt.Path
  if ($null -eq $newPath -or [string]::IsNullOrWhiteSpace($newPath) -or $newPath.Trim() -eq $wt.Path) {
    Set-Message 'Move cancelled.' 'info'
    return
  }
  $newPath = $newPath.Trim()
  $pathResult = Test-WorktreePath $newPath
  if (-not $pathResult.Valid) { Set-Message $pathResult.Error 'error'; return }
  $newPath = $pathResult.Resolved
  $normNew = Normalize-Path $newPath
  $normOld = Normalize-Path $wt.Path
  if ($normNew -ieq $normOld -or $normNew.StartsWith($normOld + [IO.Path]::DirectorySeparatorChar)) {
    Set-Message 'Cannot move a worktree into itself or a subfolder of itself.' 'error'
    return
  }
  $r = Invoke-Git @('worktree', 'move', '--', $wt.Path, $newPath)
  if ($r.ExitCode -eq 0) {
    Set-Message "Worktree moved to '$newPath'." 'ok'
    Invalidate-WorktreeCache $wt.Path
    try {
      if (PathsEqual ([Environment]::CurrentDirectory) $wt.Path) {
        $script:GitCwd = $newPath
        [Environment]::CurrentDirectory = $newPath
      }
    } catch {}
    Refresh-Data
  } else {
    $errMsg = ($r.Output -join ' ').Trim()
    if ($errMsg -match 'Permission denied' -or $errMsg -match 'Access is denied' -or $errMsg -match 'being used by another process') {
      Set-Message "Move failed: close all programs using the worktree directory, then retry." 'error'
    } else {
      Set-Message $errMsg 'error'
    }
  }
}

function Lock-SelectedWorktree {
  $wt = Get-SelectedWorktree
  if (-not $wt) { return }
  if ($wt.Bare) { Set-Message 'The bare repository entry cannot be locked.' 'warn'; return }
  if ($wt.Main) { Set-Message 'The main worktree cannot be locked.' 'warn'; return }
  if ($wt.Locked) { Set-Message 'This worktree is already locked.' 'warn'; return }
  $reason = Read-UserLine 'Lock reason (optional, Enter to skip): '
  if ($null -eq $reason) { Set-Message 'Lock cancelled.' 'info'; return }
  $reason = $reason.Trim()
  if ($reason) {
    $r = Invoke-Git @('worktree', 'lock', '--reason', $reason, '--', $wt.Path)
  } else {
    $r = Invoke-Git @('worktree', 'lock', '--', $wt.Path)
  }
  if ($r.ExitCode -eq 0) {
    Set-Message 'Worktree locked.' 'ok'
    Invalidate-WorktreeCache $wt.Path
    Refresh-Data
  } else {
    Set-Message (($r.Output -join ' ').Trim()) 'error'
  }
}

function Unlock-SelectedWorktree {
  $wt = Get-SelectedWorktree
  if (-not $wt) { return }
  if ($wt.Bare) { Set-Message 'The bare repository entry cannot be unlocked.' 'warn'; return }
  if (-not $wt.Locked) { Set-Message 'This worktree is not locked.' 'warn'; return }
  $r = Invoke-Git @('worktree', 'unlock', '--', $wt.Path)
  if ($r.ExitCode -eq 0) {
    Set-Message 'Worktree unlocked.' 'ok'
    Invalidate-WorktreeCache $wt.Path
    Refresh-Data
  } else {
    Set-Message (($r.Output -join ' ').Trim()) 'error'
  }
}

function Prune-Worktrees {
  $dryRun = Invoke-Git @('worktree', 'prune', '--dry-run', '--verbose')
  if ($dryRun.ExitCode -eq 0 -and $dryRun.Output.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace(($dryRun.Output -join ''))) {
    $preview = ($dryRun.Output -join "`n").Trim()
    Set-Message "Would prune: $preview" 'info'
    if (-not (Confirm-Choice "Prune stale worktrees? This will remove $($dryRun.Output.Count) stale entry/entries." $true)) {
      Set-Message 'Prune cancelled.' 'info'
      return
    }
  } else {
    if (-not (Confirm-Choice 'Prune all stale worktrees whose folders were deleted?' $true)) {
      Set-Message 'Prune cancelled.' 'info'
      return
    }
  }
  $r = Invoke-Git @('worktree', 'prune', '--verbose')
  if ($r.ExitCode -eq 0) {
    $count = $r.Output.Count
    if ($count -gt 0 -and -not [string]::IsNullOrWhiteSpace(($r.Output -join ''))) {
      Set-Message "Pruned stale worktrees: $(($r.Output -join ', ').Trim())" 'ok'
    } else {
      Set-Message 'No stale worktrees to prune.' 'ok'
    }
    Invalidate-WorktreeCache
    Refresh-Data
  } else {
    Set-Message (($r.Output -join ' ').Trim()) 'error'
  }
}

function Repair-Worktrees {
  $wt = Get-SelectedWorktree
  $repairPath = Read-UserLine "Repair path (blank = selected worktree): "
  if ($null -ne $repairPath -and -not [string]::IsNullOrWhiteSpace($repairPath)) {
    $repairPath = $repairPath.Trim()
    $repairPath = Resolve-UserPath $repairPath
    if (-not (Test-Path -LiteralPath $repairPath)) {
      Set-Message "Path does not exist: $repairPath" 'error'
      return
    }
  } else {
    $repairPath = ''
  }

  if (-not (Confirm-Choice 'Repair worktree administrative links (reconnect moved/broken worktrees)?' $true)) {
    Set-Message 'Repair cancelled.' 'info'
    return
  }

  $gitArgs = @('worktree', 'repair')
  if ($repairPath) {
    $gitArgs += '--'
    $gitArgs += $repairPath
  } elseif ($wt -and (Test-Path -LiteralPath $wt.Path)) {
    $gitArgs += '--'
    $gitArgs += $wt.Path
  }

  $r = Invoke-Git $gitArgs
  if ($r.ExitCode -eq 0) {
    $msg = if ($r.Output.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace(($r.Output -join ''))) {
      "Repaired: $(($r.Output -join '; ').Trim())"
    } else {
      'Worktree administrative links are healthy.'
    }
    Set-Message $msg 'ok'
    Invalidate-WorktreeCache
    Refresh-Data
  } else {
    Set-Message (($r.Output -join ' ').Trim()) 'error'
  }
}

function Copy-WorktreePath {
  $wt = Get-SelectedWorktree
  if (-not $wt) { return }
  if (Get-Command Set-Clipboard -ErrorAction SilentlyContinue) {
    try {
      Set-Clipboard -Value $wt.Path
      Set-Message "Copied '$($wt.Path)' to clipboard." 'ok'
    } catch {
      Set-Message "Clipboard error: $($_.Exception.Message)" 'error'
    }
  } else {
    Set-Message "Clipboard not available (install xclip/wl-copy on Linux)." 'warn'
  }
}

function Switch-WorktreeBranch {
  $wt = Get-SelectedWorktree
  if (-not $wt) { return }
  if ($wt.Bare) { Set-Message 'Cannot switch branches on a bare repository.' 'warn'; return }
  if ($wt.Prunable) { Set-Message 'Worktree directory is missing. Prune stale worktrees first.' 'warn'; return }

  $targetBranch = Read-UserLine 'Switch/bind branch (prefix with -b to create): '
  if ($null -eq $targetBranch) { Set-Message 'Switch cancelled.' 'info'; return }
  $targetBranch = $targetBranch.Trim()
  if ([string]::IsNullOrWhiteSpace($targetBranch)) { Set-Message 'A branch name is required.' 'warn'; return }

  # Warn if dirty
  $totalChanges = $wt.TotalChanges
  if ($totalChanges -gt 0) {
    if (-not (Confirm-Choice "Worktree has $totalChanges uncommitted change(s). Switch anyway?" $false)) {
      Set-Message 'Switch cancelled.' 'info'
      return
    }
  }

  $createNew = $false
  $branchName = $targetBranch
  if ($targetBranch -match '^-b\s+(.+)$') {
    $createNew = $true
    $branchName = $matches[1]
  }

  if ($createNew) {
    $branchCheck = Test-BranchName $branchName
    if (-not $branchCheck.Valid) { Set-Message $branchCheck.Error 'warn'; return }
    $r = Invoke-Git @('switch', '-c', $branchName) -Cwd $wt.Path
  } else {
    # Check if branch is already checked out in another worktree
    $inUse = $script:State.Worktrees | Where-Object {
      $_.Path -ne $wt.Path -and (
        $_.Branch -eq $targetBranch -or
        ($_.SymbolicRef -and $_.SymbolicRef -eq "refs/heads/$targetBranch")
      )
    } | Select-Object -First 1
    if ($inUse) {
      if ($inUse.Prunable) {
        Set-Message "Branch '$targetBranch' is registered to a prunable worktree at '$($inUse.Path)'. Press 'P' to prune stale worktrees first." 'warn'
      } else {
        Set-Message "Branch '$targetBranch' is already checked out in '$($inUse.Path)'." 'error'
      }
      return
    }
    $r = Invoke-Git @('switch', $targetBranch) -Cwd $wt.Path
  }
  if ($r.ExitCode -eq 0) {
    Set-Message "Worktree bound to branch '$branchName'." 'ok'
    Invalidate-WorktreeCache $wt.Path
    Refresh-Data
  } else {
    Set-Message (($r.Output -join ' ').Trim()) 'error'
  }
}

# ==============================================================================
# Opener Execution & Management
# ==============================================================================

function ConvertTo-ShellSingleQuoted([string]$Text) {
  if ($null -eq $Text) { $Text = '' }
  return "'" + ($Text -replace "'", "'\''") + "'"
}

function ConvertTo-CmdQuoted([string]$Text) {
  if ($null -eq $Text) { $Text = '' }
  return '"' + ($Text -replace '"', '""') + '"'
}

function Expand-Template([string]$Template, $Worktree) {
  $path = $Worktree.Path
  $branch = if ($Worktree.Detached -or $Worktree.Bare) { '' } else { $Worktree.Branch }
  $head = if ($Worktree.Head) { $Worktree.Head } else { '' }

  if ($IsWindows) {
    $qpath = ConvertTo-CmdQuoted $path
    $qbranch = ConvertTo-CmdQuoted $branch
    $qhead = ConvertTo-CmdQuoted $head
  } else {
    $qpath = ConvertTo-ShellSingleQuoted $path
    $qbranch = ConvertTo-ShellSingleQuoted $branch
    $qhead = ConvertTo-ShellSingleQuoted $head
  }

  return $Template.Replace('{path}', $path).Replace('{branch}', $branch).Replace('{head}', $head).Replace('{qpath}', $qpath).Replace('{qbranch}', $qbranch).Replace('{qhead}', $qhead)
}

function Invoke-Opener($Opener, $Worktree) {
  if ($null -eq $Opener) {
    Set-Message 'No opener configured.' 'warn'
    return
  }
  if ($Worktree.Bare) { Set-Message 'Bare repositories cannot be opened as a workspace.' 'warn'; return }
  if ($Worktree.Prunable -or -not (Test-Path -LiteralPath $Worktree.Path -PathType Container)) {
    Set-Message 'Worktree path is missing. Prune stale worktrees first.' 'warn'; return
  }
  $command = Expand-Template $Opener.command $Worktree
  $isInteractive = $null -ne $Opener.PSObject.Properties['interactive'] -and $Opener.interactive -eq $true
  try {
    if ($isInteractive) {
      Exit-AlternateScreen
    }
    try {
      $psi = [Diagnostics.ProcessStartInfo]::new()
      if ($IsWindows) {
        $needsShell = $false
        $parts = Split-CommandLine $command
        if ($parts.Count -gt 0) {
          $exe = $parts[0]
          $resolved = Get-Command $exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
          if (-not $resolved) {
            $needsShell = $true
          } elseif ($resolved.Source -match '\.(?:cmd|bat)$') {
            $needsShell = $true
          } elseif ($command -match '\s' -and $command -notmatch '^\s*\"') {
            $needsShell = $true
          }
        } else {
          $needsShell = $true
        }
        if ($needsShell) {
          $psi.FileName = "$env:SystemRoot\System32\cmd.exe"
          $psi.ArgumentList.Add('/d')
          $psi.ArgumentList.Add('/s')
          $psi.ArgumentList.Add('/c')
          $psi.ArgumentList.Add($command)
        } elseif ($resolved -and $resolved.Source -match '\.(?:cmd|bat)$') {
          $cmdPath = $resolved.Source
          $restArgs = if ($parts.Count -gt 1) { $parts[1..($parts.Count - 1)] -join ' ' } else { '' }
          $quotedCmd = "$cmdPath $restArgs"
          $psi.FileName = "$env:SystemRoot\System32\cmd.exe"
          $psi.ArgumentList.Add('/d')
          $psi.ArgumentList.Add('/s')
          $psi.ArgumentList.Add('/c')
          $psi.ArgumentList.Add($quotedCmd)
        } else {
          $psi.FileName = $resolved.Source
          for ($i = 1; $i -lt $parts.Count; $i++) {
            $psi.ArgumentList.Add($parts[$i])
          }
        }
      } elseif ($IsMacOS) {
        $psi.FileName = '/bin/zsh'
        $psi.ArgumentList.Add('-lc')
        $psi.ArgumentList.Add($command)
      } else {
        $psi.FileName = '/bin/sh'
        $psi.ArgumentList.Add('-lc')
        $psi.ArgumentList.Add($command)
      }
      $psi.WorkingDirectory = $Worktree.Path
      $psi.UseShellExecute = $false
      if ($IsWindows) { $psi.CreateNoWindow = $true }
      $proc = [Diagnostics.Process]::Start($psi)
      if ($proc -and -not $isInteractive) { $proc.Dispose() }
      elseif ($proc) { $proc.WaitForExit(); $proc.Dispose() }
      Set-Message "Launched '$($Opener.name)'." 'ok'
    } finally {
      if ($isInteractive) {
        Enter-AlternateScreen
        Draw-UI
      }
    }
  } catch {
    if ($isInteractive) {
      try { Enter-AlternateScreen } catch {}
      try { Draw-UI } catch {}
    }
    Set-Message "Failed to open workspace: $($_.Exception.Message)" 'error'
  }
}

function Split-CommandLine([string]$Command) {
  $parts = [System.Collections.Generic.List[string]]::new()
  $current = [System.Text.StringBuilder]::new()
  $inQuotes = $false
  $chars = $Command.ToCharArray()
  $i = 0
  while ($i -lt $chars.Count) {
    $char = $chars[$i]
    if ($char -eq '"') {
      if ($inQuotes -and $i + 1 -lt $chars.Count -and $chars[$i + 1] -eq '"') {
        [void]$current.Append('"')
        $i += 2
        continue
      }
      $inQuotes = -not $inQuotes
      $i++
      continue
    }
    if ($char -match '\s' -and -not $inQuotes) {
      if ($current.Length -gt 0) {
        $parts.Add($current.ToString())
        [void]$current.Clear()
      }
    } else {
      [void]$current.Append($char)
    }
    $i++
  }
  if ($current.Length -gt 0) { $parts.Add($current.ToString()) }
  return @($parts)
}

function Get-QuickIndex([ConsoleKeyInfo]$Key, [int]$Count) {
  if (-not [char]::IsDigit($Key.KeyChar)) { return -1 }
  $digit = [int][char]$Key.KeyChar - [int][char]'0'
  if ($digit -ge 1 -and $digit -le [Math]::Min(9, $Count)) {
    return $digit - 1
  }
  return -1
}

function Choose-Opener {
  $wt = Get-SelectedWorktree
  if (-not $wt) { return }
  $openers = @($script:State.Config.openers)
  if ($openers.Count -eq 0) {
    Set-Message "No openers configured. Press 'O' to add one." 'warn'
    return
  }
  $sel = 0
  $scroll = 0
  $running = $true
  while ($running) {
    Clear-Screen
    $term = Get-TerminalSize
    $w = $term.Width
    $h = $term.Height
    if ($w -lt 60 -or $h -lt 10) {
      Move-Cursor 1 1
      Write-Ansi "Terminal too small."
      Start-Sleep -Milliseconds 800
      return
    }
    $title = " Open workspace with...  ($(Fit-Text ([string]$wt.Path) 45)) "
    Move-Cursor 1 1
    Write-Ansi "`e[1;38;5;45m$title`e[0m"

    $maxVisible = [Math]::Min($openers.Count, $h - 6)
    if ($sel -lt $scroll) { $scroll = $sel }
    if ($sel -ge ($scroll + $maxVisible)) { $scroll = $sel - $maxVisible + 1 }
    for ($i = 0; $i -lt $maxVisible; $i++) {
      $idx = $scroll + $i
      Move-Cursor (3 + $i) 1
      Write-Ansi (' ' * ($w - 1))
      Move-Cursor (3 + $i) 1
      $op = $openers[$idx]
      $line = "  $($idx + 1). $($op.name.PadRight(20)) -  `e[2m$($op.command)`e[0m"
      if ($idx -eq $sel) {
        Write-Ansi "`e[48;5;75;38;5;255m› $line`e[0m"
      } else {
        Write-Ansi "  $line"
      }
    }
    Move-Cursor ($h - 2) 1
    Write-Ansi "`e[1mUp/Down`e[0m Select   `e[1mEnter`e[0m Open   `e[1mP`e[0m Preview   `e[1m1-$([Math]::Min(9, $openers.Count))`e[0m Quick   `e[1mEsc`e[0m Cancel"

    $k = [Console]::ReadKey($true)
    switch ($k.Key) {
      'UpArrow'   { $sel = ($sel - 1 + $openers.Count) % $openers.Count }
      'DownArrow' { $sel = ($sel + 1) % $openers.Count }
      'PageUp'    { $sel = [Math]::Max(0, $sel - 5) }
      'PageDown'  { $sel = [Math]::Min(($openers.Count - 1), $sel + 5) }
      'Home'      { $sel = 0 }
      'End'       { $sel = $openers.Count - 1 }
      'Enter'     { Invoke-Opener $openers[$sel] $wt; $running = $false }
      'Escape'    { $running = $false }
      default {
        switch ($k.KeyChar.ToString().ToUpperInvariant()) {
          'P' {
            $expanded = Expand-Template $openers[$sel].command $wt
            Set-Message "Preview: $expanded" 'info'
          }
          default {
            $quick = Get-QuickIndex $k $openers.Count
            if ($quick -ge 0) {
              Invoke-Opener $openers[$quick] $wt
              $running = $false
            }
          }
        }
      }
    }
  }
  Hide-Cursor
  Clear-Screen
}

function Add-Opener {
  $presets = Get-OpenerPresets
  $sel = 0
  $scroll = 0
  $running = $true

  while ($running) {
    Clear-Screen
    $term = Get-TerminalSize
    $w = $term.Width
    $h = $term.Height
    if ($w -lt 60 -or $h -lt 10) {
      Move-Cursor 1 1
      Write-Ansi "Terminal too small."
      Start-Sleep -Milliseconds 800
      return
    }
    $title = " Add Workspace Opener (Choose Preset or Custom) "
    Move-Cursor 1 1
    Write-Ansi "`e[1;38;5;45m$title`e[0m"
    Move-Cursor 2 1
    Write-Ansi "`e[2mSelect an editor/tool preset or create a custom command:`e[0m"

    $totalItems = $presets.Count + 1
    $maxVisible = [Math]::Min($totalItems, $h - 6)
    if ($sel -lt $scroll) { $scroll = $sel }
    if ($sel -ge ($scroll + $maxVisible)) { $scroll = $sel - $maxVisible + 1 }

    for ($i = 0; $i -lt $maxVisible; $i++) {
      $idx = $scroll + $i
      Move-Cursor (4 + $i) 1
      Write-Ansi (' ' * ($w - 1))
      Move-Cursor (4 + $i) 1
      if ($idx -lt $presets.Count) {
        $p = $presets[$idx]
        $line = "  $($idx + 1). $($p.name.PadRight(26)) `e[2m$($p.desc)`e[0m"
      } else {
        $line = "  $($idx + 1). Custom Command...             `e[2mEnter your own command template`e[0m"
      }
      if ($idx -eq $sel) {
        Write-Ansi "`e[48;5;75;38;5;255m› $line`e[0m"
      } else {
        Write-Ansi "  $line"
      }
    }

    Move-Cursor ($h - 2) 1
    Write-Ansi "`e[1mUp/Down`e[0m Select   `e[1mEnter`e[0m Choose preset   `e[1m1-$([Math]::Min(9, $totalItems))`e[0m Quick select   `e[1mEsc`e[0m Cancel"

    $k = [Console]::ReadKey($true)
    switch ($k.Key) {
      'UpArrow'   { $sel = ($sel - 1 + $totalItems) % $totalItems }
      'DownArrow' { $sel = ($sel + 1) % $totalItems }
      'PageUp'    { $sel = [Math]::Max(0, $sel - 5) }
      'PageDown'  { $sel = [Math]::Min(($totalItems - 1), $sel + 5) }
      'Home'      { $sel = 0 }
      'End'       { $sel = $totalItems - 1 }
      'Escape'    { $running = $false; return }
      'Enter' {
        $running = $false
        if ($sel -lt $presets.Count) {
          $chosen = $presets[$sel]
          $script:State.Config.openers = @($script:State.Config.openers) + @([ordered]@{ name = $chosen.name; command = $chosen.command })
          try { Save-Config } catch { Set-Message "Failed to save config: $($_.Exception.Message)" 'error'; return }
          Set-Message "Added opener '$($chosen.name)'." 'ok'
        } else {
          $name = Read-UserLine 'Opener name: '
          if ($null -eq $name -or [string]::IsNullOrWhiteSpace($name)) { Set-Message 'Add cancelled.' 'info'; return }
          $command = Read-UserLine 'Command template ({path}, {qpath}, {branch}, {head}): '
          if ($null -eq $command -or [string]::IsNullOrWhiteSpace($command)) { Set-Message 'Add cancelled.' 'info'; return }
          if ($command -notmatch '\{(path|qpath|branch|qbranch|head|qhead)\}') {
            Set-Message 'Warning: command template has no path placeholder.' 'warn'
          }
          $script:State.Config.openers = @($script:State.Config.openers) + @([ordered]@{ name = $name.Trim(); command = $command.Trim() })
          try { Save-Config } catch { Set-Message "Failed to save config: $($_.Exception.Message)" 'error'; return }
          Set-Message "Added custom opener '$($name.Trim())'." 'ok'
        }
      }
      default {
        $quick = Get-QuickIndex $k $totalItems
        if ($quick -ge 0) {
          $running = $false
          if ($quick -lt $presets.Count) {
            $chosen = $presets[$quick]
            $script:State.Config.openers = @($script:State.Config.openers) + @([ordered]@{ name = $chosen.name; command = $chosen.command })
            try { Save-Config } catch { Set-Message "Failed to save config: $($_.Exception.Message)" 'error'; return }
            Set-Message "Added opener '$($chosen.name)'." 'ok'
          } else {
            $name = Read-UserLine 'Opener name: '
            if ($null -eq $name -or [string]::IsNullOrWhiteSpace($name)) { Set-Message 'Add cancelled.' 'info'; return }
            $command = Read-UserLine 'Command template ({path}, {qpath}, {branch}, {head}): '
            if ($null -eq $command -or [string]::IsNullOrWhiteSpace($command)) { Set-Message 'Add cancelled.' 'info'; return }
            if ($command -notmatch '\{(path|qpath|branch|qbranch|head|qhead)\}') {
              Set-Message 'Warning: command template has no path placeholder.' 'warn'
            }
            $script:State.Config.openers = @($script:State.Config.openers) + @([ordered]@{ name = $name.Trim(); command = $command.Trim() })
            try { Save-Config } catch { Set-Message "Failed to save config: $($_.Exception.Message)" 'error'; return }
            Set-Message "Added custom opener '$($name.Trim())'." 'ok'
          }
        }
      }
    }
  }
}

function Edit-Opener($Index) {
  $list = @($script:State.Config.openers)
  if ($Index -lt 0 -or $Index -ge $list.Count) { return }
  $old = $list[$Index]
  $newName = Read-UserLine 'Opener name: ' $old.name
  if ($null -eq $newName) { Set-Message 'Edit cancelled.' 'info'; return }
  if ([string]::IsNullOrWhiteSpace($newName)) { $newName = $old.name }

  $newCommand = Read-UserLine 'Command template ({path}, {qpath}, {branch}, {head}): ' $old.command
  if ($null -eq $newCommand) { Set-Message 'Edit cancelled.' 'info'; return }
  if ([string]::IsNullOrWhiteSpace($newCommand)) { $newCommand = $old.command }

  $list[$Index] = [ordered]@{ name = $newName.Trim(); command = $newCommand.Trim() }
  $script:State.Config.openers = $list
  try { Save-Config } catch { Set-Message "Failed to save config: $($_.Exception.Message)" 'error'; return }
  Set-Message "Updated opener '$newName'." 'ok'
}

function Delete-Opener($Index) {
  $list = [System.Collections.Generic.List[object]]::new()
  foreach ($item in @($script:State.Config.openers)) { $list.Add($item) }

  if ($Index -lt 0 -or $Index -ge $list.Count) { return }
  if ($list.Count -le 1) { Set-Message 'Keep at least one opener configured.' 'warn'; return }

  $target = [string]$list[$Index].name
  if (-not (Confirm-Choice "Delete opener '$target'?" $false)) { Set-Message 'Delete cancelled.' 'info'; return }

  $list.RemoveAt($Index)
  $script:State.Config.openers = @($list)
  try { Save-Config } catch { Set-Message "Failed to save config: $($_.Exception.Message)" 'error'; return }
  Set-Message "Deleted opener '$target'." 'ok'
}

function Make-OpenerDefault($Index) {
  $list = @($script:State.Config.openers)
  if ($Index -lt 0 -or $Index -ge $list.Count) { return }
  if ($Index -eq 0) { Set-Message 'This opener is already the default.' 'ok'; return }
  $item = $list[$Index]
  $newList = [System.Collections.Generic.List[object]]::new()
  $newList.Add($item)
  for ($i = 0; $i -lt $list.Count; $i++) { if ($i -ne $Index) { $newList.Add($list[$i]) } }
  $script:State.Config.openers = @($newList)
  try { Save-Config } catch { Set-Message "Failed to save config: $($_.Exception.Message)" 'error'; return }
  Set-Message "Default opener set to '$($item.name)'." 'ok'
}

function Manage-Openers {
  if ($script:State.Config.openers.Count -eq 0) {
    $script:State.Config.openers = Get-DefaultOpeners
    try { Save-Config } catch {}
  }
  $sel = 0
  $scroll = 0
  $running = $true
  while ($running) {
    Clear-Screen
    $term = Get-TerminalSize
    $w = $term.Width
    $h = $term.Height
    if ($w -lt 70 -or $h -lt 18) {
      Move-Cursor 1 1
      Write-Ansi "Terminal too small. Need at least 70x18 (current ${w}x${h})."
      break
    }
    $openers = @($script:State.Config.openers)
    if ($sel -ge $openers.Count) { $sel = [Math]::Max(0, $openers.Count - 1) }

    $title = " Configured Workspace Openers "
    Move-Cursor 1 1
    Write-Ansi "`e[1;38;5;45m$title`e[0m"
    Write-Ansi (' ' * [Math]::Max(0, ($w - $title.Length - 1)))

    $listTop = 3
    $listHeight = $h - 8
    $boxWidth = [Math]::Min(76, [Math]::Max(52, [int]($w * 0.65)))
    $boxLeft = [Math]::Max(2, [int](($w - $boxWidth) / 2))
    Draw-Box $listTop $boxLeft $boxWidth $listHeight
    Move-Cursor ($listTop + 1) ($boxLeft + 2)
    Write-Ansi "`e[1mWORKSPACE OPENERS`e[0m"
    Write-Ansi "`e[2m  (@ = default, opened by Enter in main list)`e[0m"

    $visible = $listHeight - 3
    if ($sel -lt $scroll) { $scroll = $sel }
    if ($sel -ge ($scroll + $visible)) { $scroll = $sel - $visible + 1 }

    for ($i = 0; $i -lt $visible; $i++) {
      $index = $scroll + $i
      $row = $listTop + 2 + $i
      Move-Cursor $row ($boxLeft + 1)
      Write-Ansi (' ' * ($boxWidth - 2))
      Move-Cursor $row ($boxLeft + 1)
      if ($index -ge $openers.Count) { continue }
      $op = $openers[$index]
      $selected = $index -eq $sel
      $marker = if ($selected) { ' › ' } else { '   ' }
      $defaultMark = if ($index -eq 0) { '@ ' } else { '  ' }
      $line = " $($marker)$(($index + 1).ToString().PadLeft(2)) $defaultMark$($op.name)"
      $cmdPart = "  -  $($op.command)"
      $fullLine = Fit-Text ($line + $cmdPart) ($boxWidth - 2)
      if ($selected) {
        Write-Ansi "`e[48;5;75;38;5;255m$fullLine`e[0m"
      } else {
        Write-Ansi $fullLine
      }
    }

    $msgRow = $h - 5
    Move-Cursor $msgRow 1
    $msg = Fit-Text (" " + $script:State.Message) ($w - 1)
    $msgColor = switch ($script:State.MessageKind) { 'ok' { 42 } 'warn' { 43 } 'error' { 41 } default { 44 } }
  Write-Status $msg $msgColor

    Move-Cursor ($h - 3) 1
    Write-Ansi "`e[1mUp/Down`e[0m Select  `e[1mEnter/E`e[0m Edit  `e[1mA`e[0m Add (presets)  `e[1mD`e[0m Delete"
    Move-Cursor ($h - 2) 1
    Write-Ansi "`e[1mF`e[0m Set default (@)  `e[1mHome/End`e[0m Jump  `e[1mEsc`e[0m Return to worktrees"

    $k = [Console]::ReadKey($true)
    switch ($k.Key) {
      'UpArrow'   { $sel = ($sel - 1 + $openers.Count) % $openers.Count }
      'DownArrow' { $sel = ($sel + 1) % $openers.Count }
      'PageUp'    { $sel = [Math]::Max(0, $sel - 5) }
      'PageDown'  { $sel = [Math]::Min(($openers.Count - 1), $sel + 5) }
      'Home'      { $sel = 0 }
      'End'       { $sel = $openers.Count - 1 }
      'Escape'    { $running = $false }
      'Delete'    { Delete-Opener $sel }
      'Enter'     { Edit-Opener $sel }
      default {
        switch ($k.KeyChar.ToString().ToUpperInvariant()) {
          'A' { Add-Opener }
          'E' { Edit-Opener $sel }
          'D' { Delete-Opener $sel }
          'F' { Make-OpenerDefault $sel }
        }
      }
    }
  }
  Hide-Cursor
  Clear-Screen
}

# ==============================================================================
# Help Reference
# ==============================================================================

function Show-Help {
  Clear-Screen
  $helpBindings = ($script:KeyBindings.Help | ForEach-Object { "  $_" }) -join "`n"
  Write-Ansi @"
`e[1;38;5;45mGit Worktree Manager (gwk) v$script:AppVersion`e[0m

A standalone terminal interface for managing Git worktrees in your repository.

`e[1mWhat is a Git Worktree?`e[0m
  Worktrees allow you to check out multiple branches simultaneously in separate
  folders, sharing the exact same repository history without needing to re-clone.

`e[1mWorktree Navigation & Actions`e[0m
$helpBindings

`e[1mStatus Indicators`e[0m
  `e[36mMAIN`e[0m            Primary repository worktree
  `e[32mREADY`e[0m           Clean working directory, fully up to date
  `e[92m+N`e[0m              N commit(s) ahead of remote tracking branch
  `e[35m-N`e[0m              N commit(s) behind remote tracking branch
  `e[33m*N`e[0m              N modified or staged file(s) in working directory
  `e[33mLOCKED`e[0m          Worktree is locked against accidental pruning
  `e[91mPRUNABLE`e[0m        Worktree directory is missing from disk (run 'p' to clean up)
  `e[31mMISCONFIG`e[0m       HEAD points to an unexpected ref (not a local branch)

`e[1mBranch Binding Validation`e[0m
  Each linked worktree is tied to exactly one branch (git symbolic-ref HEAD).
  If HEAD is detached or points to an unexpected ref, gwk flags it as misconfigured.
  Press 'B' to re-bind or switch the branch.

`e[1mOpener Template Variables`e[0m
  {path}          Full path to the worktree
  {qpath}         Safely quoted path (use in shell commands)
  {branch}        Current branch name (empty for detached HEAD)
  {qbranch}       Safely quoted branch name
  {head}          Commit SHA of HEAD
  {qhead}         Safely quoted HEAD SHA

`e[1mSecurity Note`e[0m
  `e[31mIMPORTANT: Opener commands expand {path}, {qpath}, etc. and execute via shell.`e[0m
  `e[31mOnly configure trusted command templates in your config file.`e[0m
  `e[31mNever add untrusted or community-shared openers without reviewing them.`e[0m
  Prefer {qpath} over {path} in shell commands for proper quoting.

`e[1mConfig File`e[0m
  $script:ConfigPath

Press any key to return to worktree manager...
"@
  [Console]::ReadKey($true) | Out-Null
  Clear-Screen
}

function Show-CliHelp {
  Write-Host @"
Git Worktree Manager (gwk) v$script:AppVersion
==============================================
A fast, standalone Git worktree manager for PowerShell 7+.

Usage:
  gwk  (or gwt)            Launch the interactive worktree manager
  gwk --setup (or -s)      One-time installation:
                             * Copies script to ~/Scripts/gwk.ps1
                             * Adds ~/Scripts to your PATH
                             * Creates 'gwk' and 'gwt' launchers
                             * Adds 'gwt' alias to PowerShell profile
  gwk --help  (or -h)      Show this command-line help
  gwk --version (or -v)    Display version info
  gwk --doctor             Run environment diagnostics

Interactive TUI:
  Inside the TUI, press '?' at any time for the full key reference.
"@
}

# ==============================================================================
# One-Time Setup Script
# ==============================================================================

function Run-Setup {
  try {
    Write-Ansi "`e[1;38;5;45mGit Worktree Manager - One-Time Setup`e[0m`n`n"
    $targetDir = Join-Path $HOME 'Scripts'
    New-Item -ItemType Directory -Path $targetDir -Force -ErrorAction Stop | Out-Null
    $target = Join-Path $targetDir 'gwk.ps1'

    $scriptSource = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
    if ($scriptSource -and (Test-Path -LiteralPath $scriptSource) -and ($scriptSource -ne $target)) {
      Copy-Item -LiteralPath $scriptSource -Destination $target -Force
    }
    Write-Host "  [1/4] Script installed : $target" -ForegroundColor Green

    # Setup launchers
    $psExe = 'pwsh'
    $pwshCmd = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($pwshCmd) { $psExe = $pwshCmd.Source }
    if ($IsWindows) {
      $launcherBody = "@echo off`r`n`"$psExe`" -NoProfile -ExecutionPolicy RemoteSigned -File `"$target`" %*`r`n"
      foreach ($name in @('gwk', 'gwt')) {
        Set-Content -LiteralPath (Join-Path $targetDir ($name + '.cmd')) -Value $launcherBody -Encoding ascii
      }
      Write-Host "  [2/4] Launchers created: gwk.cmd, gwt.cmd in $targetDir" -ForegroundColor Green
    } else {
      $shLauncher = "#!/usr/bin/env sh`nexec `"$psExe`" -NoProfile -File `"$target`" `"$@`"`n"
      foreach ($name in @('gwk', 'gwt')) {
        $shPath = Join-Path $targetDir $name
        Set-Content -LiteralPath $shPath -Value $shLauncher -Encoding utf8
        if (-not $IsWindows) {
          try { & chmod +x $shPath } catch {}
        }
      }
      Write-Host "  [2/4] Shell scripts    : gwk, gwt in $targetDir" -ForegroundColor Green
    }

    # PATH setup
    if ($IsWindows) {
      try {
        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        if (-not $userPath) { $userPath = '' }
        $paths = $userPath.Split(';', [StringSplitOptions]::RemoveEmptyEntries)
        $found = $false
        foreach ($p in $paths) {
          if ($p.TrimEnd('\', '/') -ieq $targetDir.TrimEnd('\', '/')) { $found = $true; break }
        }
        if (-not $found) {
          $newPath = if ($userPath) { "$userPath;$targetDir" } else { $targetDir }
          [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
          Write-Host "  [3/4] User PATH        : Added '$targetDir'" -ForegroundColor Green
        } else {
          Write-Host "  [3/4] User PATH        : '$targetDir' already in PATH" -ForegroundColor Yellow
        }
      } catch {
        Write-Host "  [3/4] User PATH        : Could not update automatically ($($_.Exception.Message))" -ForegroundColor Yellow
      }
    } else {
      Write-Host "  [3/4] Unix PATH        : Ensure '$targetDir' is in your `$PATH in ~/.bashrc or ~/.zshrc" -ForegroundColor Cyan
    }

    # Profile alias setup
    if (Confirm-Choice 'Add "gwk" and "gwt" functions to your PowerShell profile?' $true) {
      try {
        $profilePath = $PROFILE
        if (-not $profilePath) {
          $docs = Join-Path $HOME 'Documents'
          $profDir = Join-Path $docs $(if ($PSVersionTable.PSVersion.Major -ge 7) { 'PowerShell' } else { 'WindowsPowerShell' })
          $profilePath = Join-Path $profDir 'Microsoft.PowerShell_profile.ps1'
        }
        $profileDir = Split-Path -Parent $profilePath
        if (-not (Test-Path -LiteralPath $profileDir)) {
          New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
        }
        if (-not (Test-Path -LiteralPath $profilePath)) {
          Set-Content -LiteralPath $profilePath -Value '' -Encoding utf8
        }
        $profContent = Get-Content -LiteralPath $profilePath -Raw
        if ($null -eq $profContent) { $profContent = '' }
        if (-not $profContent.Contains('# gwk worktree manager')) {
          $aliasBlock = "`r`n# gwk worktree manager`r`nfunction gwk { & `"$target`" @args }`r`nfunction gwt { & `"$target`" @args }`r`n"
          Add-Content -LiteralPath $profilePath -Value $aliasBlock -Encoding utf8
          Write-Host "  [4/4] PowerShell profile: Added functions to $profilePath" -ForegroundColor Green
        } else {
          Write-Host "  [4/4] PowerShell profile: Functions already configured" -ForegroundColor Yellow
        }
      } catch {
        Write-Host "  [4/4] PowerShell profile: $($_.Exception.Message)" -ForegroundColor Yellow
      }
    }

    if ($IsWindows) {
      if (Confirm-Choice 'Set PowerShell Execution Policy to RemoteSigned for CurrentUser?' $true) {
        try {
          Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
          Write-Host "  Execution Policy   : RemoteSigned" -ForegroundColor Green
        } catch {
          Write-Host "  Execution Policy   : $($_.Exception.Message)" -ForegroundColor Yellow
        }
      }
    }

    Write-Host
    Write-Host 'Setup completed! Restart your terminal or reload your profile.' -ForegroundColor Cyan
    Write-Host 'Inside any Git repository, run:   gwk   or   gwt' -ForegroundColor Green
  } finally {
    Show-Cursor
  }
}

function Show-Doctor {
  Write-Host "gwk doctor - environment diagnostics`n" -ForegroundColor Cyan
  $ok = $true

  $psVer = $PSVersionTable.PSVersion
  Write-Host "PowerShell: $($psVer.Major).$($psVer.Minor)" -NoNewline
  if ($psVer.Major -ge 7) {
    Write-Host " (ok)" -ForegroundColor Green
  } else {
    Write-Host " (requires 7+)" -ForegroundColor Red
    $ok = $false
  }

  $gitCmd = Get-Command git -ErrorAction SilentlyContinue
  if ($gitCmd) {
    $gitVer = & git --version
    Write-Host "Git: $gitVer (ok)" -ForegroundColor Green
    $wtHelp = & git worktree -h 2>&1
    if ($wtHelp -match 'usage:') {
      Write-Host "Git worktree: supported (ok)" -ForegroundColor Green
    } else {
      Write-Host "Git worktree: not available (very old Git?)" -ForegroundColor Yellow
    }
    # Check for git worktree move support (requires Git 2.17+)
    $moveHelp = & git worktree move -h 2>&1
    if ($moveHelp -match 'usage:') {
      Write-Host "Git worktree move: supported (ok, Git 2.17+)" -ForegroundColor Green
    } else {
      Write-Host "Git worktree move: NOT available (requires Git 2.17+)" -ForegroundColor Yellow
      $ok = $false
    }
    # Check for git worktree repair support (requires Git 2.17+)
    $repairHelp = & git worktree repair -h 2>&1
    if ($repairHelp -match 'usage:') {
      Write-Host "Git worktree repair: supported (ok, Git 2.17+)" -ForegroundColor Green
    } else {
      Write-Host "Git worktree repair: NOT available (requires Git 2.17+)" -ForegroundColor Yellow
      $ok = $false
    }
    # Test git worktree list --porcelain against a temp bare repo
    $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "gwk-doctor-$(Get-Random)"
    try {
      New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
      & git -C $tmpDir init --bare 2>$null | Out-Null
      $testOutput = & git -C $tmpDir worktree list --porcelain 2>&1
      if ($testOutput -match 'worktree') {
        Write-Host "Git worktree porcelain: works (ok)" -ForegroundColor Green
      } else {
        Write-Host "Git worktree porcelain: unexpected output" -ForegroundColor Yellow
      }
    } catch {
      Write-Host "Git worktree porcelain: test failed" -ForegroundColor Yellow
    } finally {
      if (Test-Path -LiteralPath $tmpDir) { Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue }
    }
  } else {
    Write-Host "Git: not found" -ForegroundColor Red
    $ok = $false
  }

  $term = Get-TerminalSize
  Write-Host "Terminal: $($term.Width)x$($term.Height)" -NoNewline
  if ($term.Width -ge 110 -and $term.Height -ge 24) {
    Write-Host " (ok - full layout)" -ForegroundColor Green
  } elseif ($term.Width -ge 60 -and $term.Height -ge 10) {
    Write-Host " (ok - compact layout, details pane hidden)" -ForegroundColor Yellow
  } else {
    Write-Host " (too small, need 60x10 minimum)" -ForegroundColor Red
  }

  # Console redirection check
  Write-Host "Console interactive: " -NoNewline
  if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) {
    Write-Host "redirected (TUI will not work)" -ForegroundColor Red
    $ok = $false
  } else {
    Write-Host "ok" -ForegroundColor Green
  }

  # Console encoding check
  try {
    $enc = [Console]::OutputEncoding.EncodingName
    Write-Host "Console encoding: $enc" -NoNewline
    if ($enc -match 'UTF') {
      Write-Host " (ok)" -ForegroundColor Green
    } else {
      Write-Host " (may garble box-drawing characters)" -ForegroundColor Yellow
    }
  } catch {
    Write-Host "Console encoding: unknown" -ForegroundColor Yellow
  }

  if (Test-Path -LiteralPath $script:ConfigPath) {
    Write-Host "Config: $script:ConfigPath (ok)" -ForegroundColor Green
    if ($env:GWK_CONFIG) {
      Write-Host "Config source: GWK_CONFIG env var" -ForegroundColor Cyan
    }
    # Validate config JSON
    try {
      $json = Get-Content -LiteralPath $script:ConfigPath -Raw
      $null = $json | ConvertFrom-Json -AsHashtable
      Write-Host "Config format: valid JSON (ok)" -ForegroundColor Green
    } catch {
      Write-Host "Config format: INVALID JSON ($($_.Exception.Message))" -ForegroundColor Red
      $ok = $false
    }
  } else {
    Write-Host "Config: missing (will use defaults)" -ForegroundColor Yellow
  }

  $profileDir = Split-Path -Parent $PROFILE
  if (Test-Path -LiteralPath $profileDir) {
    Write-Host "Profile dir: $profileDir (ok)" -ForegroundColor Green
  } else {
    Write-Host "Profile dir: missing" -ForegroundColor Yellow
  }

  if ($gitCmd) {
    $r = Invoke-Git @('rev-parse', '--git-dir')
    if ($r.ExitCode -eq 0) {
      Write-Host "Current dir: inside a Git repo (ok)" -ForegroundColor Green
    } else {
      Write-Host "Current dir: not inside a Git repo" -ForegroundColor Yellow
    }
  }

  # GIT_DIR / GIT_WORK_TREE check
  if ($env:GIT_DIR) {
    Write-Host "GIT_DIR: set to '$($env:GIT_DIR)' (may interfere)" -ForegroundColor Yellow
  }
  if ($env:GIT_WORK_TREE) {
    Write-Host "GIT_WORK_TREE: set to '$($env:GIT_WORK_TREE)' (may interfere)" -ForegroundColor Yellow
  }

  if ($IsWindows) {
    Write-Host "Clipboard: Windows native (ok)" -ForegroundColor Green
  } else {
    $clipTool = Get-Command xclip,wl-copy,pbcopy -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($clipTool) {
      Write-Host "Clipboard: $($clipTool.Name) found (ok)" -ForegroundColor Green
    } else {
      Write-Host "Clipboard: no tool found (install xclip/wl-copy)" -ForegroundColor Yellow
    }
  }

  # Opener dry-run check
  if (Test-Path -LiteralPath $script:ConfigPath) {
    try {
      $cfg = Get-Content -LiteralPath $script:ConfigPath -Raw | ConvertFrom-Json -AsHashtable
      $openerCount = @($cfg.openers).Count
      Write-Host "Openers: $openerCount configured" -NoNewline
      if ($openerCount -gt 0) {
        $firstOpener = @($cfg.openers)[0]
        $exeName = ($firstOpener.command -split '\s+')[0]
        $exePath = Get-Command $exeName -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($exePath) {
          Write-Host " (default '$($firstOpener.name)' resolves to $($exePath.Source))" -ForegroundColor Green
        } else {
          $exePath = Get-Command $exeName -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
          if ($exePath) {
            Write-Host " (ok)" -ForegroundColor Green
          } else {
            Write-Host " (warning: '$exeName' not found in PATH)" -ForegroundColor Yellow
          }
        }
      } else {
        Write-Host " (using defaults)" -ForegroundColor Yellow
      }
    } catch {
      Write-Host "Openers: could not validate ($($_.Exception.Message))" -ForegroundColor Yellow
    }
  }

  if ($ok) { Write-Host "`nAll checks passed." -ForegroundColor Green }
else { Write-Host "`nSome checks need attention." -ForegroundColor Yellow }
}

# ==============================================================================
# CLI Entry Point
# ==============================================================================

if ($Doctor) {
  Show-Cursor
  Reset-Terminal
  Show-Doctor
  exit 0
}
if ($Setup) {
  Show-Cursor
  Reset-Terminal
  Run-Setup
  exit 0
}
if ($Help) {
  Show-Cursor
  Reset-Terminal
  Show-CliHelp
  exit 0
}
if ($Version) {
  $gitVer = try { & git --version 2>$null } catch { 'git not found' }
  $psVer = "$($PSVersionTable.PSVersion)"
  Write-Host "gwk v$script:AppVersion"
  Write-Host "PowerShell $psVer"
  Write-Host "$gitVer"
  exit 0
}

# ==============================================================================
# Main Interactive TUI Loop
# ==============================================================================

function Invoke-MainKeyDispatch([ConsoleKeyInfo]$key, $displayList) {
  if ($key.Modifiers -band [ConsoleModifiers]::Control -and $key.Key -eq 'L') {
    Clear-Screen
    Draw-UI
    return
  }
  switch ($key.Key) {
    'UpArrow'   { if ($displayList.Count -gt 0) { $script:State.Selected = ($script:State.Selected - 1 + $displayList.Count) % $displayList.Count } }
    'DownArrow' { if ($displayList.Count -gt 0) { $script:State.Selected = ($script:State.Selected + 1) % $displayList.Count } }
    'PageUp'    { $script:State.Selected = [Math]::Max(0, $script:State.Selected - 5) }
    'PageDown'  { $script:State.Selected = [Math]::Min([Math]::Max(0, $displayList.Count - 1), $script:State.Selected + 5) }
    'Home'      { $script:State.Selected = 0 }
    'End'       { $script:State.Selected = [Math]::Max(0, $displayList.Count - 1) }
    'Enter'     {
      $openers = @($script:State.Config.openers)
      $selWt = Get-SelectedWorktree
      if ($openers.Count -gt 0 -and $selWt) {
        Invoke-Opener $openers[0] $selWt
      } elseif ($openers.Count -eq 0) {
        Set-Message "No openers configured. Press 'O' to configure openers." 'warn'
      }
    }
    'Delete'    { Remove-SelectedWorktree }
    'F5'        { Refresh-Data }
    'Escape'    {
      if ($script:State.Filter) { Clear-Filter } else { $script:State.Running = $false }
    }
    default {
      switch ($key.KeyChar.ToString().ToUpperInvariant()) {
        '/' { Start-Filter }
        'K' { if ($displayList.Count -gt 0) { $script:State.Selected = ($script:State.Selected - 1 + $displayList.Count) % $displayList.Count } }
        'J' { if ($displayList.Count -gt 0) { $script:State.Selected = ($script:State.Selected + 1) % $displayList.Count } }
        'N' { New-Worktree }
        'D' { Remove-SelectedWorktree }
        'M' { Rename-SelectedWorktree }
        'B' { Switch-WorktreeBranch }
        'Y' { Copy-WorktreePath }
        'O' { Choose-Opener }
        'E' { Manage-Openers }
        'L' { Lock-SelectedWorktree }
        'U' { Unlock-SelectedWorktree }
        'P' { Prune-Worktrees }
        'X' { Repair-Worktrees }
        'R' { Refresh-Data }
        '?' { Show-Help }
        'Q' { $script:State.Running = $false }
      }
    }
  }
}

$script:FatalError = $null
try {
  Enter-AlternateScreen
  $script:State.Config = Get-Config
  if ($script:ConfigLoadError) {
    Set-Message "Config load failed: $($script:ConfigLoadError) (using defaults)" 'warn'
  }
  Ensure-GitRepository
  Refresh-Data

  # Auto-prune prunable worktrees on startup if configured
  if ($script:State.Config.autoPrune -eq $true) {
    $prunable = $script:State.Worktrees | Where-Object { $_.Prunable }
    if ($prunable -and $prunable.Count -gt 0) {
      $prunedNames = ($prunable | ForEach-Object { Split-Path -Leaf $_.Path }) -join ', '
      Set-Message "Auto-pruning $($prunable.Count) stale worktree(s): $prunedNames" 'info'
      Start-Sleep -Milliseconds 800
      Invoke-Git @('worktree', 'prune', '--verbose') | Out-Null
      Refresh-Data
      Set-Message "Pruned $($prunable.Count) stale worktree(s)." 'ok'
    }
  }

  while ($script:State.Running) {
    Draw-UI
    $displayList = Get-DisplayList
    $key = [Console]::ReadKey($true)
    if ($script:UiTooSmall) {
      if ($key.Key -eq 'Escape' -or $key.KeyChar.ToString().ToUpperInvariant() -eq 'Q') {
        $script:State.Running = $false
      }
      continue
    }
    Invoke-MainKeyDispatch $key $displayList
  }
} catch {
  $script:FatalError = $_.Exception.Message
} finally {
  Exit-AlternateScreen
  if ($script:FatalError) {
    Write-Host "gwk error: $script:FatalError" -ForegroundColor Red
    exit 1
  }
}
