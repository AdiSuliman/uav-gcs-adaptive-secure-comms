# Backup of everything that is not fully in git, before the system drive swap.
# Copies only (robocopy /E). Never deletes, never moves: no /MIR, /MOV, /MOVE or /PURGE.
#
# Usage (Windows PowerShell, run from any folder):
#   powershell -ExecutionPolicy Bypass -File backup_to_external.ps1 -Dest 'E:\uav_backup_20261006' -WhatIf
#   powershell -ExecutionPolicy Bypass -File backup_to_external.ps1 -Dest 'E:\uav_backup_20261006'
# Options:
#   -WhatIf      dry run (robocopy /L): lists, copies nothing
#   -SkipCaches  skip slprj\ (Simulink build cache, regenerated automatically, ~1.8 GB)
#   -Only        copy only some items by key, e.g. -Only temp_claude,dot_claude,desktop_project
# Items run in priority order (most irreplaceable first). Safe to re-run: robocopy copies
# only new or changed files, so a second run after the MATLAB runs end refreshes the copy.

param(
    [string]$Dest = '',
    [switch]$WhatIf,
    [switch]$SkipCaches,
    [string[]]$Only = @()
)

if ([string]::IsNullOrWhiteSpace($Dest)) {
    Write-Host "Usage: backup_to_external.ps1 -Dest 'E:\uav_backup_20261006' [-WhatIf] [-SkipCaches] [-Only key1,key2]"
    exit 1
}

$Only = @($Only | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$U = 'C:\Users\Adi Suliman'
# Project folder on the Desktop (Hebrew name; note the double space after the first word).
$DesktopProject = Join-Path $U 'Desktop\תואר ראשון  הנדסת חשמל ואלקטרוניקה\שנה ד\פרוייקט גמר'

# key, source, destination subfolder. Order = priority.
$Items = @(
    @{ Key = 'temp_claude';      Src = "$U\AppData\Local\Temp\claude";                Sub = '01_temp_claude_scratchpad' },
    @{ Key = 'dot_claude';       Src = "$U\.claude";                                  Sub = '02_dot_claude_memory_sessions' },
    @{ Key = 'appdata_claude';   Src = "$U\AppData\Roaming\Claude";                   Sub = '03_appdata_roaming_claude' },
    @{ Key = 'desktop_project';  Src = $DesktopProject;                               Sub = '04_desktop_final_project' },
    @{ Key = 'matlab_prefs';     Src = "$U\AppData\Roaming\MathWorks\MATLAB\R2026a";  Sub = '05_matlab_prefdir_R2026a' },
    @{ Key = 'matlab_docs';      Src = "$U\Documents\MATLAB";                         Sub = '06_documents_matlab' },
    @{ Key = 'git_config';       Src = $U;                                            Sub = '07_user_root_files'; Files = @('.gitconfig', '.bash_history', '.bashrc', '.bash_profile') },
    @{ Key = 'main_repo';        Src = "$U\uav-gcs-adaptive-secure-comms";            Sub = '10_uav-gcs-adaptive-secure-comms' },
    @{ Key = 'v7';               Src = "$U\uav-gcs-v7";                               Sub = '11_uav-gcs-v7' },
    @{ Key = 'v7_p3';            Src = 'D:\uav-gcs-v7-p3';                            Sub = '12_D_uav-gcs-v7-p3' },
    @{ Key = 'v7_p2';            Src = 'D:\uav-gcs-v7-p2';                            Sub = '13_D_uav-gcs-v7-p2' },
    @{ Key = 'v7_merge';         Src = "$U\uav-gcs-v7-merge";                         Sub = '14_uav-gcs-v7-merge' },
    @{ Key = 'v7_gaps';          Src = "$U\uav-gcs-v7-gaps";                          Sub = '15_uav-gcs-v7-gaps' },
    @{ Key = 'v7_gapsB';         Src = "$U\uav-gcs-v7-gapsB";                         Sub = '16_uav-gcs-v7-gapsB' },
    @{ Key = 'v7_g4rx';          Src = "$U\uav-gcs-v7-g4rx";                          Sub = '17_uav-gcs-v7-g4rx' },
    @{ Key = 'v6';               Src = "$U\uav-gcs-v6";                               Sub = '18_uav-gcs-v6' },
    @{ Key = 'v6_p2';            Src = "$U\uav-gcs-v6-p2";                            Sub = '19_uav-gcs-v6-p2' }
)

function Get-SizeGB([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $m = Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum
    return [Math]::Round(($m.Sum / 1GB), 2)
}

$LogDir = Join-Path $Dest '_logs'
if (-not $WhatIf) { New-Item -ItemType Directory -Force -Path $LogDir | Out-Null }
$Log = Join-Path $LogDir ('backup_{0}.log' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))

$drive = Split-Path -Qualifier $Dest
$free = (Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$drive'" -ErrorAction SilentlyContinue).FreeSpace
if ($free) { Write-Host ('Free space on {0}: {1:N1} GB (full backup needs ~82 GB)' -f $drive, ($free / 1GB)) }

$Results = @()
foreach ($it in $Items) {
    if ($Only.Count -gt 0 -and ($Only -notcontains $it.Key)) { continue }
    $src = $it.Src
    $dst = Join-Path $Dest $it.Sub
    if (-not (Test-Path -LiteralPath $src)) {
        Write-Host "SKIP (missing): $src" -ForegroundColor Yellow
        $Results += [pscustomobject]@{ Key = $it.Key; Source = $src; SrcGB = $null; DestGB = $null; RC = 'missing' }
        continue
    }
    $rcArgs = @($src, $dst)
    if ($it.Files) { $rcArgs += $it.Files } else { $rcArgs += '/E' }
    $rcArgs += @('/COPY:DAT', '/DCOPY:T', '/R:1', '/W:1', '/MT:16', '/XJ', '/NP', '/NFL', '/NDL', '/TEE')
    if ($SkipCaches) { $rcArgs += @('/XD', 'slprj') }
    if ($WhatIf) { $rcArgs += '/L' } else { $rcArgs += "/LOG+:$Log" }
    Write-Host ''
    Write-Host ("==> [{0}] {1}  ->  {2}" -f $it.Key, $src, $dst) -ForegroundColor Cyan
    & robocopy.exe @rcArgs | Out-Host
    $rc = $LASTEXITCODE
    if ($rc -ge 8) { Write-Host "robocopy FAILED for $src (exit $rc)" -ForegroundColor Red }
    $srcGB = if ($it.Files) { $null } else { Get-SizeGB $src }
    $dstGB = if ($WhatIf -or $it.Files) { $null } else { Get-SizeGB $dst }
    $Results += [pscustomobject]@{ Key = $it.Key; Source = $src; SrcGB = $srcGB; DestGB = $dstGB; RC = $rc }
}

Write-Host ''
Write-Host '==================== SUMMARY ====================' -ForegroundColor Green
$Results | Format-Table Key, SrcGB, DestGB, RC, Source -AutoSize | Out-String -Width 250 | Write-Host
$totSrc = ($Results | Where-Object { $_.SrcGB } | Measure-Object SrcGB -Sum).Sum
$totDst = ($Results | Where-Object { $_.DestGB } | Measure-Object DestGB -Sum).Sum
Write-Host ('Total source: {0:N2} GB   Total copied at destination: {1:N2} GB' -f $totSrc, $totDst)
Write-Host 'robocopy exit codes 0-7 = OK (1 = files copied, 2/3 = extra files at destination); 8+ = errors.'
if (-not $WhatIf) { Write-Host "Log: $Log" }
if ($WhatIf) { Write-Host 'Dry run only (robocopy /L): nothing was copied.' -ForegroundColor Yellow }
