# DWC Shell — Interactive Management Panel
# Usage: dwc

$esc = [char]27
. "$PSScriptRoot\utils.ps1"

# ── Helpers ──────────────────────────────────────────────────────────────────

function Write-Color([string]$Text, [string]$Ansi = '37') {
    Write-Host "$esc[${Ansi}m$Text$esc[0m" -NoNewline
}

function Write-ColorLine([string]$Text, [string]$Ansi = '37') {
    Write-Host "$esc[${Ansi}m$Text$esc[0m"
}

function Hide-Cursor  { Write-Host "$esc[?25l" -NoNewline }
function Show-Cursor  { Write-Host "$esc[?25h" -NoNewline }
function Clear-Screen { Write-Host "$esc[2J$esc[H" -NoNewline }

function Get-DaemonStatus([string]$Name) {
    [bool](Get-Process $Name -ErrorAction SilentlyContinue)
}

function Get-GitDir {
    if (Test-Path "$HOME\.dwc-shell")  { return "$HOME\.dwc-shell" }
    if (Test-Path "$HOME\.wdc-shell")  { return "$HOME\.wdc-shell" }
    if (Test-Path "$HOME\.dotfiles")   { return "$HOME\.dotfiles" }
    return $null
}

function Invoke-Git {
    $dir = Get-GitDir
    if (-not $dir) { Write-Warning "No dwc-shell repository found."; return }
    git --git-dir="$dir" --work-tree="$HOME" @args
}

function Clear-InputBuffer {
    try {
        while ($Host.UI.RawUI.KeyAvailable) {
            $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown,IncludeKeyUp')
        }
    } catch {}
}

function Wait-Key {
    Show-Cursor
    Clear-InputBuffer
    Write-Host ""
    Write-ColorLine '  Press Esc to return...' '90'
    while ($true) {
        $k = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown,IncludeKeyUp')
        if ($k.KeyDown -and ($k.VirtualKeyCode -in 27, 81)) { break } # Esc or q
    }
}

# ── Health Data ──────────────────────────────────────────────────────────────

function Get-HealthData {
    $gitDir = Get-GitDir

    $daemons = @(
        @{
            Name      = 'Komorebi'
            Process   = 'komorebi'
            Installed = [bool](Get-Command komorebi -ErrorAction SilentlyContinue)
        }
        @{
            Name      = 'WHKD'
            Process   = 'whkd'
            Installed = [bool](Get-Command whkd -ErrorAction SilentlyContinue)
        }
        @{
            Name      = 'YASB'
            Process   = 'yasb'
            Installed = [bool](Get-Command yasb -ErrorAction SilentlyContinue)
        }
        @{
            Name      = 'PowerToys'
            Process   = 'PowerToys'
            Installed = [bool](Get-PowerToysPath)
        }
        @{
            Name      = 'AutoHotkey'
            Process   = 'AutoHotkey64'
            Installed = [bool](Get-Command autohotkey, autohotkey64 -ErrorAction SilentlyContinue)
        }
    )
    foreach ($d in $daemons) {
        $d.Running = Get-DaemonStatus $d.Process
    }

    $dirty = $false
    $behind = 0
    if ($gitDir) {
        $statusOutput = git --git-dir="$gitDir" --work-tree="$HOME" status --porcelain 2>$null
        $dirty = [bool]$statusOutput

        $behindOutput = git --git-dir="$gitDir" --work-tree="$HOME" rev-list --count "HEAD..origin/main" 2>$null
        if ($LASTEXITCODE -eq 0 -and $behindOutput) {
            $behind = [int]$behindOutput
        }
    }

    return @{
        Daemons = $daemons
        Dirty   = $dirty
        Behind  = $behind
        GitDir  = $gitDir
    }
}

# ── Shared UI ────────────────────────────────────────────────────────────────

function Show-Header {
    Write-Host ""
    Write-ColorLine "  ┌──────────────────────────────────────────────────┐" '36'
    Write-ColorLine "  │   DWC Shell · Dorville Windows Custom Shell     │" '36'
    Write-ColorLine "  └──────────────────────────────────────────────────┘" '36'
    Write-Host ""
}

function Show-PageHeader([string]$Title) {
    Clear-Screen
    Show-Header
    Write-ColorLine "  ─── $Title ───" '36'
    Write-Host ""
}

function Render-MenuLines([int]$Selected, [array]$Items) {
    $maxHint = 48
    try {
        $winW = [Console]::WindowWidth
        if ($winW -gt 0) { $maxHint = [Math]::Max(12, $winW - 26) }
    } catch {}

    for ($i = 0; $i -lt $Items.Count; $i++) {
        # Pad to fixed width so shorter text overwrites longer previous text
        $label = $Items[$i].Label.PadRight(18)
        $hint  = $Items[$i].Hint
        if ($hint.Length -gt $maxHint) { $hint = $hint.Substring(0, $maxHint - 1) + '…' }
        if ($i -eq $Selected) {
            Write-Color '    ► ' '36'
            Write-Color $label '1;36'
            Write-Color $hint '90'
        } else {
            Write-Color '      ' '37'
            Write-Color $label '37'
            Write-Color $hint '90'
        }
        Write-Host "$esc[K"  # clear rest of line
    }

    Write-Host "$esc[K"
    $footer = '  ↑/↓ or j/k navigate · Enter select · Esc quit'
    if ($maxHint -lt 28) { $footer = '  ↑/↓ · Enter · Esc' }
    Write-Color $footer '90'
    Write-Host "$esc[K" -NoNewline
}

# ── Screens ──────────────────────────────────────────────────────────────────

function Show-HomeScreen([int]$Selected, [array]$MenuItems) {
    Clear-Screen
    Hide-Cursor
    Show-Header

    $health = Get-HealthData

    foreach ($d in $health.Daemons) {
        if (-not $d.Installed) {
            $icon  = '✖'
            $color = '31'
            $state = 'not installed'
        } elseif ($d.Running) {
            $icon  = '●'
            $color = '32'
            $state = 'running'
        } else {
            $icon  = '○'
            $color = '33'
            $state = 'stopped'
        }
        $pad   = '.' * (22 - $d.Name.Length)
        Write-Color "    $icon " $color
        Write-Color "$($d.Name) " '37'
        Write-Color "$pad " '90'
        Write-ColorLine $state $color
    }

    Write-Host ""

    if ($health.GitDir) {
        $repoIcon  = if ($health.Dirty) { '⚠' } else { '✔' }
        $repoColor = if ($health.Dirty) { '33' } else { '32' }
        $repoState = if ($health.Dirty) { 'Modified' } else { 'Clean' }
        $syncState = if ($health.Behind -gt 0) { "$($health.Behind) behind origin/main" } else { 'Up to date' }
        Write-Color "    $repoIcon " $repoColor
        Write-Color "Repo: $repoState" $repoColor
        Write-ColorLine " · $syncState" '90'
    }

    Write-ColorLine '  ──────────────────────────────────────────────────' '90'
    Write-Host ""

    Render-MenuLines $Selected $MenuItems
}

function Redraw-Menu([int]$Selected, [array]$MenuItems) {
    Hide-Cursor
    $up = $MenuItems.Count + 1
    Write-Host "$esc[${up}A`r" -NoNewline
    Render-MenuLines $Selected $MenuItems
}

function Show-UpdateScreen {
    Show-Cursor
    Show-PageHeader 'Update'

    Write-ColorLine '  Pulling latest changes and running setup...' '33'
    Write-Host ""

    & "$HOME\scripts\update.ps1"

    Wait-Key
}

function Show-HealthScreen {
    Show-PageHeader 'Health Report'

    $health = Get-HealthData

    Write-ColorLine '  Daemons' '1;37'
    Write-Host ""
    foreach ($d in $health.Daemons) {
        if (-not $d.Installed) {
            $icon  = '✖'
            $color = '31'
            $state = 'Not installed'
        } elseif ($d.Running) {
            $icon  = '✔'
            $color = '32'
            $state = 'Installed & Running'
        } else {
            $icon  = '⚠'
            $color = '33'
            $state = 'Installed (Stopped)'
        }
        Write-Color "    $icon " $color
        Write-ColorLine "$($d.Name): $state" $color
    }

    Write-Host ""

    Write-ColorLine '  Symlinks' '1;37'
    Write-Host ""
    $links = @(
        @{ Name = 'PowerShell profile'; Path = $PROFILE }
        @{ Name = 'Windows Terminal';   Path = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json" }
    )
    foreach ($l in $links) {
        $item = Get-Item $l.Path -ErrorAction SilentlyContinue
        $isLink = $item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
        $icon  = if ($isLink) { '✔' } else { '✖' }
        $color = if ($isLink) { '32' } else { '31' }
        $state = if ($isLink) { 'Linked' } else { 'Not linked' }
        Write-Color "    $icon " $color
        Write-ColorLine "$($l.Name): $state" $color
    }

    Write-Host ""

    # Startup shortcuts
    Write-ColorLine '  Startup Shortcuts' '1;37'
    Write-Host ""
    $startup = [Environment]::GetFolderPath('Startup')
    $shortcuts = @('win-hotkeys', 'komorebi', 'yasb')
    foreach ($name in $shortcuts) {
        $lnk = Join-Path $startup "$name.lnk"
        $exists = Test-Path $lnk
        $icon  = if ($exists) { '✔' } else { '✖' }
        $color = if ($exists) { '32' } else { '31' }
        $state = if ($exists) { 'Present' } else { 'Missing' }
        Write-Color "    $icon " $color
        Write-ColorLine "$name.lnk: $state" $color
    }

    # PowerToys startup (managed via settings.json → Task Scheduler, not shell:startup)
    $ptInstalled = [bool](Get-PowerToysPath)
    $ptSettingsFile = "$env:LOCALAPPDATA\Microsoft\PowerToys\settings.json"
    if (Test-Path $ptSettingsFile) {
        try {
            $ptCfg = Get-Content $ptSettingsFile -Raw | ConvertFrom-Json
            $ptStartup = [bool]$ptCfg.startup
        } catch {}
    }
    $ptIcon  = if (-not $ptInstalled) { '✖' } elseif ($ptStartup) { '✔' } else { '✖' }
    $ptColor = if (-not $ptInstalled) { '31' } elseif ($ptStartup) { '32' } else { '33' }
    $ptState = if (-not $ptInstalled) { 'Not installed' } elseif ($ptStartup) { 'Enabled (Task Scheduler)' } else { 'Disabled' }
    Write-Color "    $ptIcon " $ptColor
    Write-ColorLine "PowerToys: $ptState" $ptColor

    Wait-Key
}

function Show-ResourceScreen {
    Clear-Screen
    Hide-Cursor

    # Drain any leftover key events from menu selection
    try {
        while ($Host.UI.RawUI.KeyAvailable) {
            $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown,IncludeKeyUp')
        }
    } catch {}

    $targets = @(
        @{ Name = 'Komorebi';   Filter = 'komorebi*' }
        @{ Name = 'WHKD';       Filter = 'whkd*' }
        @{ Name = 'YASB';       Filter = 'yasb*' }
        @{ Name = 'AutoHotkey'; Filter = 'AutoHotkey*' }
        @{ Name = 'PowerToys';  Filter = @('PowerToys*', 'Microsoft.CmdPal*') }
    )

    $cores = [Environment]::ProcessorCount
    $prevCpu = @{}
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    foreach ($t in $targets) {
        $procs = Get-Process -Name $t.Filter -ErrorAction SilentlyContinue
        foreach ($p in $procs) {
            $prevCpu[$p.Id] = $p.TotalProcessorTime.TotalMilliseconds
        }
    }

    $spinners = @('⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏')
    $frame = 0

    $runningLive = $true
    while ($runningLive) {
        $elapsedSec = $sw.Elapsed.TotalSeconds
        $sw.Restart()

        $results = @()
        $totalMB = 0
        $totalCpuPct = 0
        $currentCpu = @{}

        foreach ($t in $targets) {
            $procs = Get-Process -Name $t.Filter -ErrorAction SilentlyContinue
            $count = ($procs | Measure-Object).Count
            $ramMB = 0
            $procCpuPct = 0

            if ($procs) {
                $ramMB = [math]::Round(($procs | Measure-Object -Property WorkingSet64 -Sum).Sum / 1MB, 1)
                foreach ($p in $procs) {
                    $currMs = $p.TotalProcessorTime.TotalMilliseconds
                    $currentCpu[$p.Id] = $currMs
                    $prevMs = if ($prevCpu.ContainsKey($p.Id)) { $prevCpu[$p.Id] } else { $currMs }
                    $diffMs = [math]::Max(0, $currMs - $prevMs)
                    if ($elapsedSec -gt 0) {
                        $pct = ($diffMs / 1000) / ($elapsedSec * $cores) * 100
                        $procCpuPct += $pct
                    }
                }
            }
            $totalMB += $ramMB
            $totalCpuPct += $procCpuPct

            $results += [PSCustomObject]@{
                Name       = $t.Name
                Running    = ($count -gt 0)
                Count      = $count
                RamMB      = $ramMB
                CpuPercent = [math]::Round($procCpuPct, 1)
            }
        }
        $prevCpu = $currentCpu

        $totalSysBytes = [System.GC]::GetGCMemoryInfo().TotalAvailableMemoryBytes
        $totalSysMB = if ($totalSysBytes -gt 0) { $totalSysBytes / 1MB } else { 16384 }
        $ramPercent = [math]::Round(($totalMB / $totalSysMB) * 100, 2)
        $sysGB = [math]::Round($totalSysMB / 1024, 1)
        $totalCpuDisplay = [math]::Round($totalCpuPct, 1)

        $spinnerChar = $spinners[$frame % $spinners.Count]
        $frame++
        $timeStr = (Get-Date).ToString("HH:mm:ss")

        # Reposition to top-left of terminal screen
        try {
            [Console]::SetCursorPosition(0, 0)
        } catch {
            Write-Host "$esc[H" -NoNewline
        }

        Show-Header
        Write-Color "  ─── Resource Usage ─── " '36'
        Write-Color "$spinnerChar LIVE $timeStr" '1;32'
        Write-Host "$esc[K"
        Write-Host "$esc[K"

        Write-ColorLine "  Daemon                  RAM             CPU %          Status$esc[K" '1;37'
        Write-ColorLine "  ─────────────────────────────────────────────────────────────$esc[K" '90'

        foreach ($r in $results) {
            $daemonCol = if ($r.Count -gt 1) { "$($r.Name) ($($r.Count) procs)" } else { $r.Name }
            $daemonCol = $daemonCol.PadRight(22)

            $ramCol = "$($r.RamMB) MB".PadRight(16)
            $cpuCol = "$($r.CpuPercent)%".PadRight(15)

            if ($r.Running) {
                $statusText = 'running'
                $statusColor = '32'
            } else {
                $statusText = 'stopped'
                $statusColor = '33'
            }

            Write-Color "  $daemonCol" '37'
            Write-Color $ramCol '36'
            Write-Color $cpuCol '37'
            Write-ColorLine "$statusText$esc[K" $statusColor
        }

        Write-ColorLine "  ─────────────────────────────────────────────────────────────$esc[K" '90'
        Write-Host "$esc[K"
        Write-ColorLine "  DWC Shell Footprint:$esc[K" '1;37'
        Write-Color "    Total Memory:  " '37'
        Write-Color "$totalMB MB" '1;36'
        Write-ColorLine " (~$ramPercent% of $sysGB GB system RAM)$esc[K" '90'

        Write-Color "    Total CPU:     " '37'
        Write-Color "$totalCpuDisplay%" '1;36'
        Write-ColorLine " active CPU usage$esc[K" '90'

        Write-Host "$esc[K"
        Write-ColorLine "  Updating live · Press Esc to return...$esc[K" '90'

        for ($i = 0; $i -lt 10; $i++) {
            while ($Host.UI.RawUI.KeyAvailable) {
                $k = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown,IncludeKeyUp')
                if ($k.KeyDown -and ($k.VirtualKeyCode -in 27, 81)) {
                    $runningLive = $false
                    break
                }
            }
            if (-not $runningLive) { break }
            Start-Sleep -Milliseconds 100
        }
    }

    Show-Cursor
}

function Show-ChangelogScreen {
    Show-PageHeader 'Changelog'

    $logs = Invoke-Git log --oneline --decorate -15 2>$null
    if ($logs) {
        foreach ($line in $logs) {
            if ($line -match '^([a-f0-9]+)\s(.*)$') {
                Write-Color "    $($Matches[1]) " '33'
                Write-ColorLine $Matches[2] '37'
            } else {
                Write-ColorLine "    $line" '37'
            }
        }
    } else {
        Write-ColorLine '    No commits found.' '90'
    }

    Wait-Key
}

function Show-StatusScreen {
    Show-PageHeader 'Repository Status'

    $output = Invoke-Git status 2>$null
    if ($output) {
        foreach ($line in $output) {
            Write-ColorLine "    $line" '37'
        }
    } else {
        Write-ColorLine '    Working tree clean.' '32'
    }

    Wait-Key
}

function Get-ThemeVars([string]$Css) {
    $vars = @{}
    foreach ($m in [regex]::Matches($Css, '--([\w-]+):\s*([^;]+);')) {
        $vars[$m.Groups[1].Value] = $m.Groups[2].Value.Trim()
    }
    $vars
}

function Get-YasbThemes {
    $yasbDir   = Join-Path $HOME '.config\yasb'
    $themesDir = Join-Path $yasbDir 'themes'
    $activeFile = Join-Path $yasbDir 'theme.css'

    if (-not (Test-Path $themesDir)) { return @() }

    $activeVars = if (Test-Path $activeFile) {
        Get-ThemeVars ([IO.File]::ReadAllText($activeFile))
    } else {
        @{}
    }

    $ti = (Get-Culture).TextInfo
    $list = @()
    foreach ($file in (Get-ChildItem $themesDir -Filter '*.css' | Sort-Object Name)) {
        $css  = [IO.File]::ReadAllText($file.FullName)
        $vars = Get-ThemeVars $css
        $desc = ''
        if ($css -match '/\*\s*[^:]+:\s*(.+?)\s*\*/') {
            $desc = $Matches[1].Trim()
        }
        $isCurrent = ($vars.Count -gt 0) -and ($activeVars.Count -eq $vars.Count) -and (-not ($vars.Keys | Where-Object { $activeVars[$_] -ne $vars[$_] }))
        $list += [PSCustomObject]@{
            Id          = $file.BaseName
            Name        = $ti.ToTitleCase($file.BaseName)
            Description = $desc
            Current     = $isCurrent
        }
    }
    return $list
}

function Render-ThemeList([int]$Selected, [array]$Themes, [string]$StatusMsg = '', [bool]$StatusOk = $true) {
    $maxDesc = 44
    $maxLine = 76
    try {
        $winW = [Console]::WindowWidth
        if ($winW -gt 0) {
            $maxDesc = [Math]::Max(12, [Math]::Min(48, $winW - 32))
            $maxLine = [Math]::Max(20, $winW - 5)
        }
    } catch {}

    for ($i = 0; $i -lt $Themes.Count; $i++) {
        $t = $Themes[$i]
        $nameCol = $t.Name.PadRight(12)
        if ($i -eq $Selected) {
            Write-Color '    ► ' '36'
            Write-Color $nameCol '1;36'
        } else {
            Write-Color '      ' '37'
            Write-Color $nameCol '37'
        }

        if ($t.Current) {
            Write-Color '● active   ' '32'
        } else {
            Write-Color '           ' '90'
        }

        if ($t.Description) {
            $d = $t.Description
            if ($d.Length -gt $maxDesc) { $d = $d.Substring(0, $maxDesc - 1) + '…' }
            Write-Color $d '90'
        }
        Write-Host "$esc[K"
    }

    Write-Host "$esc[K"
    if ($StatusMsg) {
        $msg = $StatusMsg
        if ($msg.Length -gt $maxLine) { $msg = $msg.Substring(0, $maxLine - 1) + '…' }
        if ($StatusOk) {
            Write-Color "  ✔ $msg" '32'
        } else {
            Write-Color "  ✖ $msg" '31'
        }
    }
    Write-Host "$esc[K"

    $footer = '  ↑/↓ or j/k navigate · Enter/1-9 apply · Esc return'
    if ($footer.Length -gt $maxLine) { $footer = '  ↑/↓ · Enter apply · Esc' }
    Write-Color $footer '90'
    Write-Host "$esc[K" -NoNewline
}

function Redraw-ThemeList([int]$Selected, [array]$Themes, [string]$StatusMsg = '', [bool]$StatusOk = $true) {
    Hide-Cursor
    $up = $Themes.Count + 2
    Write-Host "$esc[${up}A`r" -NoNewline
    Render-ThemeList $Selected $Themes $StatusMsg $StatusOk
}

function Set-YasbThemeChoice([string]$SetScript, [object]$Theme) {
    try {
        & $SetScript $Theme.Id
        return [PSCustomObject]@{
            Themes = @(Get-YasbThemes)
            Status = "Applied '$($Theme.Name)' (YASB reloads automatically)"
            Ok     = $true
        }
    } catch {
        return [PSCustomObject]@{
            Themes = @(Get-YasbThemes)
            Status = "Failed: $($_.Exception.Message)"
            Ok     = $false
        }
    }
}

function Show-ThemeScreen {
    $yasbDir   = Join-Path $HOME '.config\yasb'
    $setScript = Join-Path $yasbDir 'set-theme.ps1'

    Show-PageHeader 'YASB Themes'
    Hide-Cursor
    Clear-InputBuffer

    $themes = @(Get-YasbThemes)
    if ($themes.Count -eq 0) {
        Write-ColorLine '  No theme files found in .config\yasb\themes.' '33'
        Wait-Key
        return
    }

    if (-not (Test-Path $setScript)) {
        Write-ColorLine '  Missing .config\yasb\set-theme.ps1.' '31'
        Wait-Key
        return
    }

    $idx = 0
    for ($i = 0; $i -lt $themes.Count; $i++) {
        if ($themes[$i].Current) { $idx = $i; break }
    }

    $status   = ''
    $statusOk = $true
    Render-ThemeList $idx $themes $status $statusOk

    while ($true) {
        $k  = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        $ch = $k.Character
        $vk = $k.VirtualKeyCode

        if ($vk -eq 38 -or $ch -in 'k', 'K') {
            $idx = if ($idx -gt 0) { $idx - 1 } else { $themes.Count - 1 }
            Redraw-ThemeList $idx $themes $status $statusOk
        } elseif ($vk -eq 40 -or $ch -in 'j', 'J') {
            $idx = if ($idx -lt ($themes.Count - 1)) { $idx + 1 } else { 0 }
            Redraw-ThemeList $idx $themes $status $statusOk
        } elseif ($vk -in 13, 32) {
            $res      = Set-YasbThemeChoice $setScript $themes[$idx]
            $themes   = $res.Themes
            $status   = $res.Status
            $statusOk = $res.Ok
            Redraw-ThemeList $idx $themes $status $statusOk
        } elseif ([char]::IsDigit($ch) -and $ch -ne '0') {
            $n = [int][string]$ch - 1
            if ($n -lt $themes.Count) {
                $idx      = $n
                $res      = Set-YasbThemeChoice $setScript $themes[$idx]
                $themes   = $res.Themes
                $status   = $res.Status
                $statusOk = $res.Ok
                Redraw-ThemeList $idx $themes $status $statusOk
            }
        } elseif ($vk -eq 27 -or $ch -in 'q', 'Q') {
            return
        }
    }
}

function Show-CodeScreen {
    Show-PageHeader 'Open in VS Code'

    $gitDir = Get-GitDir
    if (Get-Process Code -ErrorAction SilentlyContinue) {
        Write-ColorLine '    ⚠ Close VS Code first, or the git panel will not see dwc-shell.' '33'
        Wait-Key
        return
    }

    Write-ColorLine '    Launching VS Code...' '32'
    $env:GIT_DIR = $gitDir; $env:GIT_WORK_TREE = $HOME
    try { code $HOME } finally { Remove-Item Env:GIT_DIR, Env:GIT_WORK_TREE }

    Wait-Key
}

# ── Main Loop ────────────────────────────────────────────────────────────────

$menuItems = @(
    @{ Label = 'Update';          Hint = 'Pull latest, run setup, reload Komorebi';  Action = 'Update' }
    @{ Label = 'Health Report';   Hint = 'Check daemons, symlinks, and startup';     Action = 'Health' }
    @{ Label = 'Resource Usage';  Hint = 'Memory and CPU consumption breakdown';     Action = 'Resources' }
    @{ Label = 'YASB Themes';     Hint = 'Switch bar theme (Glass, Amoled, Opaque)'; Action = 'Themes' }
    @{ Label = 'Changelog';       Hint = 'Show recent commits';                      Action = 'Changelog' }
    @{ Label = 'Status';          Hint = 'Show modified files in the repository';    Action = 'Status' }
    @{ Label = 'Open in VS Code'; Hint = 'Launch VS Code scoped to dwc-shell';       Action = 'Code' }
    @{ Label = 'Quit';            Hint = 'Exit the panel';                           Action = 'Quit' }
)

$invokeAction = {
    param([string]$Action)
    switch ($Action) {
        'Update'    { Show-UpdateScreen;    $script:needsRedraw = $true }
        'Health'    { Show-HealthScreen;    $script:needsRedraw = $true }
        'Resources' { Show-ResourceScreen;  $script:needsRedraw = $true }
        'Themes'    { Show-ThemeScreen;     $script:needsRedraw = $true }
        'Changelog' { Show-ChangelogScreen; $script:needsRedraw = $true }
        'Status'    { Show-StatusScreen;    $script:needsRedraw = $true }
        'Code'      { Show-CodeScreen;      $script:needsRedraw = $true }
        'Quit'      { $script:running = $false }
    }
}

$selected    = 0
$running     = $true
$needsRedraw = $true

try {
    Clear-InputBuffer
    while ($running) {
        if ($needsRedraw) {
            Show-HomeScreen $selected $menuItems
            Clear-InputBuffer
            $needsRedraw = $false
        }

        $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        $ch  = $key.Character
        $vk  = $key.VirtualKeyCode

        if ($vk -eq 38 -or $ch -in 'k', 'K') {
            $selected = if ($selected -gt 0) { $selected - 1 } else { $menuItems.Count - 1 }
            Redraw-Menu $selected $menuItems
        } elseif ($vk -eq 40 -or $ch -in 'j', 'J') {
            $selected = if ($selected -lt ($menuItems.Count - 1)) { $selected + 1 } else { 0 }
            Redraw-Menu $selected $menuItems
        } elseif ($vk -in 13, 32) {
            & $invokeAction $menuItems[$selected].Action
        } elseif ([char]::IsDigit($ch) -and $ch -ne '0') {
            $n = [int][string]$ch - 1
            if ($n -lt $menuItems.Count) {
                $selected = $n
                & $invokeAction $menuItems[$selected].Action
            }
        } elseif ($vk -eq 27 -or $ch -in 'q', 'Q') {
            $running = $false
        }
    }
} finally {
    Show-Cursor
    Clear-Screen
}
