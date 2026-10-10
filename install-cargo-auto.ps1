<#
.SYNOPSIS
    Cargo 镜像自动化 - 一键安装/配置脚本
.DESCRIPTION
    自动完成：
      1. 检查并加入 PATH（E:\code\scripts）
      2. 设置 PowerShell 执行策略（仅当前用户）
      3. 写入 cargo 包装函数（自动刷新镜像）
      4. 设置 cm 别名
      5. 可选：立即跑一次镜像测速
.EXAMPLE
    .\install-cargo-auto.ps1
    .\install-cargo-auto.ps1 -SkipMirrorTest
#>

param(
    [switch]$SkipMirrorTest
)

$ErrorActionPreference = 'Continue'

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Cargo Mirror Automation - Installer" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

$scriptsDir = "E:\code\scripts"
$mirrorScript = Join-Path $scriptsDir "cargo-mirror.ps1"
$profilePath = $PROFILE

# ============ 0. 前置检查 ============
Write-Host "[0] Pre-check" -ForegroundColor Yellow

if (-not (Test-Path $mirrorScript)) {
    Write-Host "   ERROR: cargo-mirror.ps1 not found at $mirrorScript" -ForegroundColor Red
    Write-Host "   Please create it first before running this installer." -ForegroundColor Yellow
    exit 1
}
Write-Host "   OK: cargo-mirror.ps1 found" -ForegroundColor Green

# ============ 1. 加入 PATH ============
Write-Host ""
Write-Host "[1] PATH configuration" -ForegroundColor Yellow

$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -notlike "*$scriptsDir*") {
    $newPath = $userPath.TrimEnd(';') + ";$scriptsDir"
    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
    Write-Host "   OK: added to User PATH" -ForegroundColor Green
    Write-Host "       $scriptsDir" -ForegroundColor Gray
} else {
    Write-Host "   SKIP: already in PATH" -ForegroundColor Gray
}

# 当前会话也加上，立即生效（不用新开窗口）
if ($env:Path -notlike "*$scriptsDir*") {
    $env:Path += ";$scriptsDir"
    Write-Host "   OK: added to current session PATH" -ForegroundColor Green
}

# ============ 2. 执行策略 ============
Write-Host ""
Write-Host "[2] Execution policy" -ForegroundColor Yellow

$currentPolicy = Get-ExecutionPolicy -Scope CurrentUser
if ($currentPolicy -in @('Restricted', 'Undefined', 'AllSigned')) {
    try {
        Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
        Write-Host "   OK: set to RemoteSigned (CurrentUser)" -ForegroundColor Green
    } catch {
        Write-Host "   WARN: could not set policy: $($_.Exception.Message)" -ForegroundColor Yellow
    }
} else {
    Write-Host "   SKIP: current policy is $currentPolicy" -ForegroundColor Gray
}

# ============ 3. 写入 $PROFILE ============
Write-Host ""
Write-Host "[3] PowerShell profile" -ForegroundColor Yellow

# 确保 profile 文件存在
$profileDir = Split-Path $profilePath -Parent
if (-not (Test-Path $profileDir)) {
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
}
if (-not (Test-Path $profilePath)) {
    New-Item -ItemType File -Path $profilePath -Force | Out-Null
    Write-Host "   OK: created profile file" -ForegroundColor Green
}

$profileContent = Get-Content $profilePath -Raw -ErrorAction SilentlyContinue
if (-not $profileContent) { $profileContent = "" }

$marker = "# ==== Cargo Mirror Automation (auto-generated) ===="
$block = @"

$marker
# cm  -> 手动切换镜像
Set-Alias cm '$mirrorScript'

# cargo 包装函数：配置超 1 小时自动刷新
function cargo {
    `$cfg = "`$env:USERPROFILE\.cargo\config.toml"
    `$mirrorScript = '$mirrorScript'

    `$needRefresh = `$true
    if (Test-Path `$cfg) {
        `$ageHours = ((Get-Date) - (Get-Item `$cfg).LastWriteTime).TotalHours
        if (`$ageHours -lt 1) {
            `$needRefresh = `$false
        }
    }

    if (`$needRefresh -and (Test-Path `$mirrorScript)) {
        Write-Host "[cargo] Refreshing mirror..." -ForegroundColor DarkGray
        & `$mirrorScript -Rounds 1 | Out-Null
    }

    & "`$env:USERPROFILE\.cargo\bin\cargo.exe" @args
}
# ==== end Cargo Mirror Automation ====
"@

if ($profileContent -notlike "*$marker*") {
    Add-Content -Path $profilePath -Value $block -Encoding UTF8
    Write-Host "   OK: appended cargo automation block to profile" -ForegroundColor Green
} else {
    Write-Host "   SKIP: block already exists in profile" -ForegroundColor Gray
    Write-Host "         (delete the block manually to reinstall)" -ForegroundColor DarkGray
}

Write-Host "   Profile: $profilePath" -ForegroundColor Gray

# ============ 4. 立即在当前会话生效 ============
Write-Host ""
Write-Host "[4] Activating in current session" -ForegroundColor Yellow

Set-Alias cm $mirrorScript -Scope Global -Force
Write-Host "   OK: cm alias set" -ForegroundColor Green

# 定义 cargo 函数（当前会话）
function global:cargo {
    $cfg = "$env:USERPROFILE\.cargo\config.toml"
    $ms = $mirrorScript
    $needRefresh = $true
    if (Test-Path $cfg) {
        $ageHours = ((Get-Date) - (Get-Item $cfg).LastWriteTime).TotalHours
        if ($ageHours -lt 1) { $needRefresh = $false }
    }
    if ($needRefresh -and (Test-Path $ms)) {
        Write-Host "[cargo] Refreshing mirror..." -ForegroundColor DarkGray
        & $ms -Rounds 1 | Out-Null
    }
    & "$env:USERPROFILE\.cargo\bin\cargo.exe" @args
}
Write-Host "   OK: cargo function set" -ForegroundColor Green

# ============ 5. 可选：立即跑镜像测速 ============
if (-not $SkipMirrorTest) {
    Write-Host ""
    Write-Host "[5] Running mirror test now..." -ForegroundColor Yellow
    & $mirrorScript
} else {
    Write-Host ""
    Write-Host "[5] Skipped mirror test (-SkipMirrorTest)" -ForegroundColor Gray
}

# ============ 完成 ============
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  INSTALLATION COMPLETE" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Usage:" -ForegroundColor White
Write-Host "  cargo build       " -NoNewline -ForegroundColor Yellow
Write-Host "-> auto-refresh mirror if stale, then build" -ForegroundColor Gray
Write-Host "  cm                " -NoNewline -ForegroundColor Yellow
Write-Host "-> force re-test all mirrors now" -ForegroundColor Gray
Write-Host ""
Write-Host "Note: open a NEW PowerShell window for PATH to take effect globally." -ForegroundColor DarkGray
Write-Host ""