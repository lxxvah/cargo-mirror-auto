<#
.SYNOPSIS
    Cargo mirror auto-selector (no build)
.DESCRIPTION
    Test all mirrors via TCP:443, pick fastest, write cargo config.
    Does NOT build anything.
.EXAMPLE
    cargo-mirror.ps1
    cargo-mirror.ps1 -Rounds 3
#>

param(
    [int]$Rounds = 2,
    [switch]$ShowAll
)

$ErrorActionPreference = 'Continue'

$Mirrors = [ordered]@{
    'tuna'     = @{ Name='Tsinghua TUNA';   Host='mirrors.tuna.tsinghua.edu.cn'; Sparse='sparse+https://mirrors.tuna.tsinghua.edu.cn/crates.io-index/' }
    'ustc'     = @{ Name='USTC';            Host='mirrors.ustc.edu.cn';           Sparse='sparse+https://mirrors.ustc.edu.cn/crates.io-index/' }
    'aliyun'   = @{ Name='Aliyun';          Host='mirrors.aliyun.com';            Sparse='sparse+https://mirrors.aliyun.com/crates.io-index/' }
    'rsproxy'  = @{ Name='rsproxy.cn';      Host='rsproxy.cn';                    Sparse='sparse+https://rsproxy.cn/index/' }
    'sjtu'     = @{ Name='SJTU';            Host='mirrors.sjtug.sjtu.edu.cn';     Sparse='sparse+https://mirrors.sjtug.sjtu.edu.cn/crates.io-index/' }
    'nju'      = @{ Name='NJU';             Host='mirror.nju.edu.cn';             Sparse='sparse+https://mirror.nju.edu.cn/crates.io-index/' }
    'official' = @{ Name='crates.io';       Host='index.crates.io';               Sparse='sparse+https://index.crates.io/' }
}

$ConfigPath = "$env:USERPROFILE\.cargo\config.toml"
$Port = 443
$TimeoutMs = 3000

function Test-TcpPort {
    param([string]$Ip, [int]$Port = 443, [int]$TimeoutMs = 3000)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $task = $client.ConnectAsync($Ip, $Port)
        $waited = $task.Wait($TimeoutMs)
        $sw.Stop()
        if ($waited -and $client.Connected) {
            return [PSCustomObject]@{ OK=$true; Ms=$sw.ElapsedMilliseconds }
        }
        return [PSCustomObject]@{ OK=$false; Ms=$sw.ElapsedMilliseconds }
    } catch {
        $sw.Stop()
        return [PSCustomObject]@{ OK=$false; Ms=$sw.ElapsedMilliseconds }
    } finally {
        $client.Close()
    }
}

function Test-Mirror {
    param([string]$Key, [hashtable]$Mirror, [int]$Rounds = 2)

    Write-Host ("  Testing {0,-10} {1,-22} ... " -f $Key, $Mirror.Name) -NoNewline -ForegroundColor Yellow

    $ips = @()
    try {
        $ips = [System.Net.Dns]::GetHostAddresses($Mirror.Host) |
               Where-Object { $_.AddressFamily -eq 'InterNetwork' } |
               ForEach-Object { $_.IPAddressToString }
    } catch { }

    if ($ips.Count -eq 0) {
        Write-Host "DNS FAIL" -ForegroundColor Red
        return [PSCustomObject]@{ Key=$Key; Name=$Mirror.Name; OK=$false; Ms=0; IPs=@() }
    }

    $bestMs = [int]::MaxValue
    $anyOK = $false

    for ($i = 0; $i -lt $Rounds; $i++) {
        foreach ($ip in $ips) {
            $r = Test-TcpPort -Ip $ip -Port $Port -TimeoutMs $TimeoutMs
            if ($r.OK -and $r.Ms -lt $bestMs) {
                $bestMs = $r.Ms
                $anyOK = $true
            }
        }
        if ($anyOK -and $i -lt ($Rounds - 1)) {
            Start-Sleep -Milliseconds 100
        }
    }

    if ($anyOK) {
        Write-Host ("OK  {0,5} ms  ({1} IP)" -f $bestMs, $ips.Count) -ForegroundColor Green
    } else {
        Write-Host ("FAIL  ({0} IP tried)" -f $ips.Count) -ForegroundColor Red
    }

    return [PSCustomObject]@{
        Key  = $Key
        Name = $Mirror.Name
        OK   = $anyOK
        Ms   = $bestMs
        IPs  = $ips
    }
}

# ============ Main ============
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Cargo mirror selector (no build)" -ForegroundColor Cyan
Write-Host "  TCP:443 test  |  IPv4 only  |  $Rounds rounds" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

$results = @()
foreach ($key in $Mirrors.Keys) {
    $results += Test-Mirror -Key $key -Mirror $Mirrors[$key] -Rounds $Rounds
}

$available = $results | Where-Object { $_.OK } | Sort-Object Ms

Write-Host ""
Write-Host "--- Summary ---" -ForegroundColor Cyan
foreach ($r in $results) {
    if ($r.OK) {
        Write-Host ("  [OK]   {0,-10} {1,-22} {2,5} ms" -f $r.Key, $r.Name, $r.Ms) -ForegroundColor Green
    } else {
        Write-Host ("  [FAIL] {0,-10} {1,-22} {2}" -f $r.Key, $r.Name, "TCP:443 unreachable") -ForegroundColor Red
    }
}

if (-not $available) {
    Write-Host ""
    Write-Host "ERROR: No reachable mirror found!" -ForegroundColor Red
    Write-Host "Check your network or firewall." -ForegroundColor Yellow
    exit 1
}

$best = $available | Select-Object -First 1
Write-Host ""
Write-Host ("BEST: {0} ({1}) - {2} ms" -f $best.Key, $best.Name, $best.Ms) -ForegroundColor Green

# 检查当前配置是否已经是这个镜像
$alreadySet = $false
if (Test-Path $ConfigPath) {
    $current = Get-Content $ConfigPath -Raw
    if ($current -match "replace-with\s*=\s*'$($best.Key)'") {
        $alreadySet = $true
    }
}

if ($alreadySet -and -not $ShowAll) {
    (Get-Item $ConfigPath).LastWriteTime = Get-Date
    Write-Host ""
    Write-Host "ℹ️  Config already set to $($best.Key), no change needed." -ForegroundColor Gray
    Write-Host "    (use -ShowAll to force rewrite)" -ForegroundColor DarkGray
    exit 0
}

# ============ Write config ============
Write-Host ""
Write-Host "=== Writing cargo config ===" -ForegroundColor Cyan

$cargoDir = Split-Path $ConfigPath -Parent
if (-not (Test-Path $cargoDir)) {
    New-Item -ItemType Directory -Path $cargoDir -Force | Out-Null
}

if (Test-Path $ConfigPath) {
    Copy-Item $ConfigPath "$ConfigPath.bak" -Force
    Write-Host "  Backup: config.toml.bak" -ForegroundColor Gray
}

$m = $Mirrors[$best.Key]
if ($best.Key -eq 'official') {
    $content = @"
# Cargo official source - generated $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
[net]
retry = 5
git-fetch-with-cli = true
"@
} else {
    $content = @"
# Cargo mirror: $($m.Name) - generated $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

[source.crates-io]
replace-with = '$($best.Key)'

[source.$($best.Key)]
registry = "$($m.Sparse)"

[net]
retry = 5
git-fetch-with-cli = true
"@
}

$content | Out-File -Encoding utf8 $ConfigPath
Write-Host ("  ✅ Switched to: {0}" -f $m.Name) -ForegroundColor Green
Write-Host ("  Config: {0}" -f $ConfigPath) -ForegroundColor Gray
Write-Host ""
Write-Host "Now run 'cargo build' in your project - it will use the fastest mirror." -ForegroundColor Cyan
