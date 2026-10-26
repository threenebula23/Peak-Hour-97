# run_all_tests.ps1 - headless test runner for PEAK HOUR 97 v2 (Windows).
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File scripts/run_all_tests.ps1
#   $env:GODOT_BIN = "D:\path\Godot_v4.7.2-stable_win64_console.exe"
#   powershell -ExecutionPolicy Bypass -File scripts/run_all_tests.ps1
#
# Each test is a separate Godot process with a per-test timeout. Missing test
# files are skipped (SKIP), not failed. APPDATA is redirected to a temp folder
# for the run so tests never touch the real user save. The final parse check
# runs `--headless --path <root> --quit`.

[CmdletBinding()]
param(
    [string]$GodotBin = $env:GODOT_BIN,
    [int]$TimeoutSec = 180
)

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $Root

if ([string]::IsNullOrWhiteSpace($GodotBin)) {
    $GodotBin = "D:\Apps\godot\Godot_v4.7.2-stable_win64_console.exe"
}
if (-not (Test-Path -LiteralPath $GodotBin -PathType Leaf)) {
    $fallback = Get-Command godot4 -ErrorAction SilentlyContinue
    if (-not $fallback) { $fallback = Get-Command godot -ErrorAction SilentlyContinue }
    if ($fallback) { $GodotBin = $fallback.Source }
}
if (-not (Test-Path -LiteralPath $GodotBin -PathType Leaf)) {
    Write-Host "FAIL: Godot binary not found: $GodotBin" -ForegroundColor Red
    Write-Host "Set GODOT_BIN or pass -GodotBin <path>."
    exit 1
}

$Tests = @(
    "res://tests/run_tests.gd",
    "res://tests/test_hour.gd",
    "res://tests/test_economy.gd",
    "res://tests/test_save.gd",
    "res://tests/test_slots.gd",
    "res://tests/test_shop.gd",
    "res://tests/test_minigame.gd",
    "res://tests/test_send_games.gd",
    "res://tests/test_attack_games.gd",
    "res://tests/test_file_grid.gd",
    "res://tests/test_shop_modal.gd",
    "res://tests/test_audio.gd",
    "res://tests/test_ambient.gd",
    "res://tests/test_fuzz.gd",
    "res://tests/test_integration.gd",
    "res://tests/test_attacks.gd",
    "res://tests/test_controller.gd",
    "res://tests/test_main_prep.gd",
    "res://tests/test_main_hour.gd",
    "res://tests/test_main_interactions.gd",
    "res://tests/test_main_attacks.gd",
    "res://tests/test_main_pause.gd",
    "res://tests/test_main_fullscreen.gd",
    "res://tests/test_main_polish.gd",
    "res://tests/test_toast.gd",
    "res://tests/test_full_playthrough.gd",
    "res://scripts/ui/ui_smoke.gd"
)

$ErrorRe = 'SCRIPT ERROR|Parse Error|USER ERROR|Failed to load|Cannot open file|FAIL|SMOKE FAILED'
$LeakRe  = 'ObjectDB instances leaked|leaked at exit'

function Quote-Arg([string]$Value) {
    return '"' + $Value.Replace('"', '\"') + '"'
}

function Invoke-Godot([string]$Arguments, [int]$Timeout) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $GodotBin
    $psi.Arguments = $Arguments
    $psi.WorkingDirectory = $Root
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    $null = $process.Start()
    $outTask = $process.StandardOutput.ReadToEndAsync()
    $errTask = $process.StandardError.ReadToEndAsync()
    $exited = $process.WaitForExit($Timeout * 1000)
    if (-not $exited) {
        try { $process.Kill() } catch { }
        try { $process.WaitForExit(5000) | Out-Null } catch { }
    }
    $stdout = ""
    $stderr = ""
    try { $stdout = $outTask.Result } catch { }
    try { $stderr = $errTask.Result } catch { }
    $code = -1
    if ($exited) { $code = $process.ExitCode }
    return @{
        ExitCode = $code
        TimedOut = (-not $exited)
        Output = ($stdout + "`n" + $stderr)
    }
}

function Write-Tail([string]$Text, [int]$Count = 40) {
    $lines = $Text -split "`r?`n"
    if ($lines.Count -gt $Count) { $lines = $lines[($lines.Count - $Count)..($lines.Count - 1)] }
    Write-Host "----- output (last $Count lines) -----"
    foreach ($line in $lines) { Write-Host $line }
    Write-Host "-------------------------------------"
}

function Test-Log([string]$Text, [string]$Pattern) {
    # Case-sensitive on purpose: test summaries print "fails=0", which must not
    # be mistaken for the uppercase FAIL marker.
    return [bool]([regex]::IsMatch($Text, $Pattern))
}

$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("peak-hour-tests-" + [guid]::NewGuid().ToString("N"))
$LogDir = Join-Path $Tmp "logs"
$OldAppData = $env:APPDATA
New-Item -ItemType Directory -Path $Tmp -Force | Out-Null
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
$env:APPDATA = Join-Path $Tmp "appdata"
New-Item -ItemType Directory -Path $env:APPDATA -Force | Out-Null

$Passed = 0
$Failed = 0
$Skipped = @()
$FailedNames = @()

Write-Host "PEAK HOUR 97 - headless tests (v2, Windows)"
Write-Host "Godot: $GodotBin"
Write-Host "APPDATA (temp): $env:APPDATA"
Write-Host ""

try {
    foreach ($script in $Tests) {
        $localPath = Join-Path $Root ($script -replace '^res://', '' -replace '/', '\')
        $name = [System.IO.Path]::GetFileNameWithoutExtension($script)
        if (-not (Test-Path -LiteralPath $localPath -PathType Leaf)) {
            $Skipped += $name
            Write-Host "SKIP  $name (no file)"
            continue
        }

        Write-Host ""
        Write-Host ">>> $script"
        $godotArgs = "--headless --path $(Quote-Arg $Root) --script $(Quote-Arg $script)"
        $result = Invoke-Godot $godotArgs $TimeoutSec
        $logPath = Join-Path $LogDir ($name + ".log")
        Set-Content -LiteralPath $logPath -Value $result.Output -Encoding UTF8

        if ($result.TimedOut) {
            Write-Host "FAIL  $name (timeout ${TimeoutSec}s)"
            Write-Tail $result.Output
            $Failed++
            $FailedNames += $name
            continue
        }

        if ($result.ExitCode -eq 0) {
            if (Test-Log $result.Output $ErrorRe) {
                Write-Host "FAIL  $name (exit 0, but errors in log)"
                Write-Tail $result.Output
                $Failed++
                $FailedNames += $name
            } else {
                Write-Host "PASS  $name"
                $Passed++
            }
            continue
        }

        if (Test-Log $result.Output $ErrorRe) {
            Write-Host "FAIL  $name (exit $($result.ExitCode))"
            Write-Tail $result.Output
            $Failed++
            $FailedNames += $name
            continue
        }

        if ((Test-Log $result.Output $LeakRe) -and -not (Test-Log $result.Output 'ERROR:')) {
            Write-Host "PASS  $name (exit $($result.ExitCode), harmless ObjectDB leak warning)"
            $Passed++
            continue
        }

        Write-Host "FAIL  $name (exit $($result.ExitCode))"
        Write-Tail $result.Output
        $Failed++
        $FailedNames += $name
    }

    Write-Host ""
    Write-Host ">>> parse check: --headless --path . --quit"
    $parseArgs = "--headless --path $(Quote-Arg $Root) --quit"
    $parse = Invoke-Godot $parseArgs $TimeoutSec
    Set-Content -LiteralPath (Join-Path $LogDir "parse_check.log") -Value $parse.Output -Encoding UTF8
    $parseOk = $false
    if (-not $parse.TimedOut) {
        if ($parse.ExitCode -eq 0) {
            $parseOk = $true
        } elseif ((Test-Log $parse.Output $LeakRe) -and -not (Test-Log $parse.Output 'ERROR:')) {
            $parseOk = $true
        }
    }
    if ($parseOk) {
        Write-Host "PASS  parse-check"
        $Passed++
    } else {
        Write-Host "FAIL  parse-check (exit $($parse.ExitCode))"
        Write-Tail $parse.Output
        $Failed++
        $FailedNames += "parse-check"
    }
}
finally {
    $env:APPDATA = $OldAppData
    try {
        Remove-Item -LiteralPath $Tmp -Recurse -Force -ErrorAction SilentlyContinue
    } catch { }
}

Write-Host ""
Write-Host "================================"
Write-Host "Total: PASS=$Passed FAIL=$Failed SKIP=$($Skipped.Count)"
if ($Skipped.Count -gt 0) {
    Write-Host "Skipped: $($Skipped -join ', ')"
}
if ($Failed -ne 0) {
    Write-Host "Failed: $($FailedNames -join ', ')" -ForegroundColor Red
    exit 1
}
Write-Host "All tests passed." -ForegroundColor Green
exit 0
