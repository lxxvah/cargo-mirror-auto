\# Cargo 镜像自动化脚本 - 使用手册



版本: v2

平台: Windows 10/11

依赖: PowerShell 5.1+ / Rust



\---



\## 一、这是什么



一套 PowerShell 脚本，自动完成：



1\. 测试所有国内 Cargo 镜像（TCP:443 连通性）

2\. 自动选最快的镜像

3\. 写入 \~/.cargo/config.toml

4\. 每次执行 cargo 时自动检查镜像新鲜度（默认 1 小时）



效果：cargo build、cargo install、cargo add 都走最快镜像，无需手动切换。



\---



\## 二、前置条件



| 组件 | 要求 | 验证命令 |

|------|------|---------|

| Windows | 10 / 11 | - |

| PowerShell | 5.1+ | $PSVersionTable.PSVersion |

| Rust / Cargo | 已安装 | cargo --version |



未装 Rust：



winget install Rustlang.Rustup



装完必须新开 PowerShell 再继续。



\---



\## 三、安装步骤



\### 3.1 创建脚本目录



New-Item -ItemType Directory -Path "E:\\code\\scripts" -Force



如路径不同，后续所有 E:\\code\\scripts 都要同步替换。



\### 3.2 创建 cargo-mirror.ps1



用记事本打开新文件：



notepad "E:\\code\\scripts\\cargo-mirror.ps1"



把下面内容完整粘贴进去，保存时选择 UTF-8 编码：



<#

.SYNOPSIS

&#x20;   Cargo mirror auto-selector (no build)

.DESCRIPTION

&#x20;   Test all mirrors via TCP:443, pick fastest, write cargo config.

&#x20;   Does NOT build anything.

\#>



param(

&#x20;   \[int]$Rounds = 2,

&#x20;   \[switch]$ShowAll

)



$ErrorActionPreference = 'Continue'



$Mirrors = \[ordered]@{

&#x20;   'tuna'     = @{ Name='Tsinghua TUNA';   Host='mirrors.tuna.tsinghua.edu.cn'; Sparse='sparse+https://mirrors.tuna.tsinghua.edu.cn/crates.io-index/' }

&#x20;   'ustc'     = @{ Name='USTC';            Host='mirrors.ustc.edu.cn';           Sparse='sparse+https://mirrors.ustc.edu.cn/crates.io-index/' }

&#x20;   'aliyun'   = @{ Name='Aliyun';          Host='mirrors.aliyun.com';            Sparse='sparse+https://mirrors.aliyun.com/crates.io-index/' }

&#x20;   'rsproxy'  = @{ Name='rsproxy.cn';      Host='rsproxy.cn';                    Sparse='sparse+https://rsproxy.cn/index/' }

&#x20;   'sjtu'     = @{ Name='SJTU';            Host='mirrors.sjtug.sjtu.edu.cn';     Sparse='sparse+https://mirrors.sjtug.sjtu.edu.cn/crates.io-index/' }

&#x20;   'nju'      = @{ Name='NJU';             Host='mirror.nju.edu.cn';             Sparse='sparse+https://mirror.nju.edu.cn/crates.io-index/' }

&#x20;   'official' = @{ Name='crates.io';       Host='index.crates.io';               Sparse='sparse+https://index.crates.io/' }

}



$ConfigPath = "$env:USERPROFILE\\.cargo\\config.toml"

$Port = 443

$TimeoutMs = 3000



function Test-TcpPort {

&#x20;   param(\[string]$Ip, \[int]$Port = 443, \[int]$TimeoutMs = 3000)

&#x20;   $sw = \[System.Diagnostics.Stopwatch]::StartNew()

&#x20;   $client = New-Object System.Net.Sockets.TcpClient

&#x20;   try {

&#x20;       $task = $client.ConnectAsync($Ip, $Port)

&#x20;       $waited = $task.Wait($TimeoutMs)

&#x20;       $sw.Stop()

&#x20;       if ($waited -and $client.Connected) {

&#x20;           return \[PSCustomObject]@{ OK=$true; Ms=$sw.ElapsedMilliseconds }

&#x20;       }

&#x20;       return \[PSCustomObject]@{ OK=$false; Ms=$sw.ElapsedMilliseconds }

&#x20;   } catch {

&#x20;       $sw.Stop()

&#x20;       return \[PSCustomObject]@{ OK=$false; Ms=$sw.ElapsedMilliseconds }

&#x20;   } finally {

&#x20;       $client.Close()

&#x20;   }

}



function Test-Mirror {

&#x20;   param(\[string]$Key, \[hashtable]$Mirror, \[int]$Rounds = 2)



&#x20;   Write-Host ("  Testing {0,-10} {1,-22} ... " -f $Key, $Mirror.Name) -NoNewline -ForegroundColor Yellow



&#x20;   $ips = @()

&#x20;   try {

&#x20;       $ips = \[System.Net.Dns]::GetHostAddresses($Mirror.Host) |

&#x20;              Where-Object { $\_.AddressFamily -eq 'InterNetwork' } |

&#x20;              ForEach-Object { $\_.IPAddressToString }

&#x20;   } catch { }



&#x20;   if ($ips.Count -eq 0) {

&#x20;       Write-Host "DNS FAIL" -ForegroundColor Red

&#x20;       return \[PSCustomObject]@{ Key=$Key; Name=$Mirror.Name; OK=$false; Ms=0; IPs=@() }

&#x20;   }



&#x20;   $bestMs = \[int]::MaxValue

&#x20;   $anyOK = $false



&#x20;   for ($i = 0; $i -lt $Rounds; $i++) {

&#x20;       foreach ($ip in $ips) {

&#x20;           $r = Test-TcpPort -Ip $ip -Port $Port -TimeoutMs $TimeoutMs

&#x20;           if ($r.OK -and $r.Ms -lt $bestMs) {

&#x20;               $bestMs = $r.Ms

&#x20;               $anyOK = $true

&#x20;           }

&#x20;       }

&#x20;       if ($anyOK -and $i -lt ($Rounds - 1)) {

&#x20;           Start-Sleep -Milliseconds 100

&#x20;       }

&#x20;   }



&#x20;   if ($anyOK) {

&#x20;       Write-Host ("OK  {0,5} ms  ({1} IP)" -f $bestMs, $ips.Count) -ForegroundColor Green

&#x20;   } else {

&#x20;       Write-Host ("FAIL  ({0} IP tried)" -f $ips.Count) -ForegroundColor Red

&#x20;   }



&#x20;   return \[PSCustomObject]@{

&#x20;       Key  = $Key

&#x20;       Name = $Mirror.Name

&#x20;       OK   = $anyOK

&#x20;       Ms   = $bestMs

&#x20;       IPs  = $ips

&#x20;   }

}



Write-Host ""

Write-Host "============================================" -ForegroundColor Cyan

Write-Host "  Cargo mirror selector (no build)" -ForegroundColor Cyan

Write-Host "  TCP:443 test  |  IPv4 only  |  $Rounds rounds" -ForegroundColor Cyan

Write-Host "============================================" -ForegroundColor Cyan

Write-Host ""



$results = @()

foreach ($key in $Mirrors.Keys) {

&#x20;   $results += Test-Mirror -Key $key -Mirror $Mirrors\[$key] -Rounds $Rounds

}



$available = $results | Where-Object { $\_.OK } | Sort-Object Ms



Write-Host ""

Write-Host "--- Summary ---" -ForegroundColor Cyan

foreach ($r in $results) {

&#x20;   if ($r.OK) {

&#x20;       Write-Host ("  \[OK]   {0,-10} {1,-22} {2,5} ms" -f $r.Key, $r.Name, $r.Ms) -ForegroundColor Green

&#x20;   } else {

&#x20;       Write-Host ("  \[FAIL] {0,-10} {1,-22} {2}" -f $r.Key, $r.Name, "TCP:443 unreachable") -ForegroundColor Red

&#x20;   }

}



if (-not $available) {

&#x20;   Write-Host ""

&#x20;   Write-Host "ERROR: No reachable mirror found!" -ForegroundColor Red

&#x20;   Write-Host "Check your network or firewall." -ForegroundColor Yellow

&#x20;   exit 1

}



$best = $available | Select-Object -First 1

Write-Host ""

Write-Host ("BEST: {0} ({1}) - {2} ms" -f $best.Key, $best.Name, $best.Ms) -ForegroundColor Green



$alreadySet = $false

if (Test-Path $ConfigPath) {

&#x20;   $current = Get-Content $ConfigPath -Raw

&#x20;   if ($current -match "replace-with\\s\*=\\s\*'$($best.Key)'") {

&#x20;       $alreadySet = $true

&#x20;   }

}



if ($alreadySet -and -not $ShowAll) {

&#x20;   (Get-Item $ConfigPath).LastWriteTime = Get-Date

&#x20;   Write-Host ""

&#x20;   Write-Host "Config already set to $($best.Key), no change needed." -ForegroundColor Gray

&#x20;   exit 0

}



Write-Host ""

Write-Host "=== Writing cargo config ===" -ForegroundColor Cyan



$cargoDir = Split-Path $ConfigPath -Parent

if (-not (Test-Path $cargoDir)) {

&#x20;   New-Item -ItemType Directory -Path $cargoDir -Force | Out-Null

}



if (Test-Path $ConfigPath) {

&#x20;   Copy-Item $ConfigPath "$ConfigPath.bak" -Force

&#x20;   Write-Host "  Backup: config.toml.bak" -ForegroundColor Gray

}



$m = $Mirrors\[$best.Key]

if ($best.Key -eq 'official') {

&#x20;   $content = @"

\# Cargo official source - generated $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

\[net]

retry = 5

git-fetch-with-cli = true

"@

} else {

&#x20;   $content = @"

\# Cargo mirror: $($m.Name) - generated $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')



\[source.crates-io]

replace-with = '$($best.Key)'



\[source.$($best.Key)]

registry = "$($m.Sparse)"



\[net]

retry = 5

git-fetch-with-cli = true

"@

}



$content | Out-File -Encoding utf8 $ConfigPath

Write-Host "  Switched to: $($m.Name)" -ForegroundColor Green

Write-Host "  Config: $ConfigPath" -ForegroundColor Gray

Write-Host ""

Write-Host "Now run 'cargo build' in your project - it will use the fastest mirror." -ForegroundColor Cyan



\### 3.3 创建 install-cargo-auto.ps1



notepad "E:\\code\\scripts\\install-cargo-auto.ps1"



粘贴下面内容，保存为 UTF-8：



<#

.SYNOPSIS

&#x20;   Cargo mirror automation - one-click installer

.DESCRIPTION

&#x20;   Steps:

&#x20;     1. Check \& add scripts dir to PATH

&#x20;     2. Set execution policy

&#x20;     3. Write cargo wrapper function

&#x20;     4. Set cm alias

&#x20;     5. Optional: run mirror test immediately

\#>



param(

&#x20;   \[switch]$SkipMirrorTest

)



$ErrorActionPreference = 'Continue'



Write-Host ""

Write-Host "============================================" -ForegroundColor Cyan

Write-Host "  Cargo Mirror Automation - Installer" -ForegroundColor Cyan

Write-Host "============================================" -ForegroundColor Cyan

Write-Host ""



$scriptsDir = "E:\\code\\scripts"

$mirrorScript = Join-Path $scriptsDir "cargo-mirror.ps1"

$profilePath = $PROFILE



Write-Host "\[0] Pre-check" -ForegroundColor Yellow

if (-not (Test-Path $mirrorScript)) {

&#x20;   Write-Host "   ERROR: cargo-mirror.ps1 not found" -ForegroundColor Red

&#x20;   exit 1

}

Write-Host "   OK: cargo-mirror.ps1 found" -ForegroundColor Green



Write-Host ""

Write-Host "\[1] PATH configuration" -ForegroundColor Yellow

$userPath = \[Environment]::GetEnvironmentVariable("Path", "User")

if ($userPath -notlike "\*$scriptsDir\*") {

&#x20;   \[Environment]::SetEnvironmentVariable("Path", $userPath.TrimEnd(';') + ";$scriptsDir", "User")

&#x20;   Write-Host "   OK: added to User PATH" -ForegroundColor Green

} else {

&#x20;   Write-Host "   SKIP: already in PATH" -ForegroundColor Gray

}

if ($env:Path -notlike "\*$scriptsDir\*") {

&#x20;   $env:Path += ";$scriptsDir"

}



Write-Host ""

Write-Host "\[2] Execution policy" -ForegroundColor Yellow

$currentPolicy = Get-ExecutionPolicy -Scope CurrentUser

if ($currentPolicy -in @('Restricted', 'Undefined', 'AllSigned')) {

&#x20;   Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force

&#x20;   Write-Host "   OK: set to RemoteSigned" -ForegroundColor Green

} else {

&#x20;   Write-Host "   SKIP: current policy is $currentPolicy" -ForegroundColor Gray

}



Write-Host ""

Write-Host "\[3] PowerShell profile" -ForegroundColor Yellow

$profileDir = Split-Path $profilePath -Parent

if (-not (Test-Path $profileDir)) {

&#x20;   New-Item -ItemType Directory -Path $profileDir -Force | Out-Null

}

if (-not (Test-Path $profilePath)) {

&#x20;   New-Item -ItemType File -Path $profilePath -Force | Out-Null

}



$profileContent = Get-Content $profilePath -Raw -ErrorAction SilentlyContinue

if (-not $profileContent) { $profileContent = "" }



$marker = "# ==== Cargo Mirror Automation (auto-generated) ===="

$block = @"



$marker

\# cm -> force refresh mirrors now

Set-Alias cm '$mirrorScript'



\# cargo wrapper: auto refresh mirror if config is older than 1 hour

function cargo {

&#x20;   `$cfg = "`$env:USERPROFILE\\.cargo\\config.toml"

&#x20;   `$mirrorScript = '$mirrorScript'



&#x20;   `$needRefresh = `$true

&#x20;   if (Test-Path `$cfg) {

&#x20;       `$ageHours = ((Get-Date) - (Get-Item `$cfg).LastWriteTime).TotalHours

&#x20;       if (`$ageHours -lt 1) {

&#x20;           `$needRefresh = `$false

&#x20;       }

&#x20;   }



&#x20;   if (`$needRefresh -and (Test-Path `$mirrorScript)) {

&#x20;       Write-Host "\[cargo] Refreshing mirror..." -ForegroundColor DarkGray

&#x20;       \& `$mirrorScript -Rounds 1 | Out-Null

&#x20;   }



&#x20;   \& "`$env:USERPROFILE\\.cargo\\bin\\cargo.exe" @args

}

\# ==== end Cargo Mirror Automation ====

"@



if ($profileContent -notlike "\*$marker\*") {

&#x20;   Add-Content -Path $profilePath -Value $block -Encoding UTF8

&#x20;   Write-Host "   OK: appended to profile" -ForegroundColor Green

} else {

&#x20;   Write-Host "   SKIP: block already exists" -ForegroundColor Gray

}



Write-Host ""

Write-Host "\[4] Activating in current session" -ForegroundColor Yellow

Set-Alias cm $mirrorScript -Scope Global -Force



function global:cargo {

&#x20;   $cfg = "$env:USERPROFILE\\.cargo\\config.toml"

&#x20;   $ms = $mirrorScript

&#x20;   $needRefresh = $true

&#x20;   if (Test-Path $cfg) {

&#x20;       $ageHours = ((Get-Date) - (Get-Item $cfg).LastWriteTime).TotalHours

&#x20;       if ($ageHours -lt 1) { $needRefresh = $false }

&#x20;   }

&#x20;   if ($needRefresh -and (Test-Path $ms)) {

&#x20;       Write-Host "\[cargo] Refreshing mirror..." -ForegroundColor DarkGray

&#x20;       \& $ms -Rounds 1 | Out-Null

&#x20;   }

&#x20;   \& "$env:USERPROFILE\\.cargo\\bin\\cargo.exe" @args

}

Write-Host "   OK: cm alias + cargo function set" -ForegroundColor Green



if (-not $SkipMirrorTest) {

&#x20;   Write-Host ""

&#x20;   Write-Host "\[5] Running mirror test now..." -ForegroundColor Yellow

&#x20;   \& $mirrorScript

}



Write-Host ""

Write-Host "============================================" -ForegroundColor Cyan

Write-Host "  INSTALLATION COMPLETE" -ForegroundColor Green

Write-Host "============================================" -ForegroundColor Cyan

Write-Host ""

Write-Host "Usage:" -ForegroundColor White

Write-Host "  cargo build       -> auto-refresh mirror if stale" -ForegroundColor Gray

Write-Host "  cm                -> force re-test all mirrors now" -ForegroundColor Gray

Write-Host ""

Write-Host "Open a NEW PowerShell window for PATH to take effect globally." -ForegroundColor DarkGray

Write-Host ""



\### 3.4 运行安装



Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

E:\\code\\scripts\\install-cargo-auto.ps1



看到 INSTALLATION COMPLETE 即成功。



\---



\## 四、日常使用



\### 4.1 正常用 cargo（自动管理）



cargo build

cargo add serde

cargo install cargo-watch



自动逻辑：

\- 配置在 1 小时内 -> 直接执行 cargo

\- 配置超过 1 小时 -> 自动跑一次镜像测速 -> 切最快 -> 执行 cargo



首次有 2-5 秒延迟（测速），之后 1 小时内无感。



\### 4.2 手动强制重测



cm



用于：觉得下载慢、换了网络、想手动切换。



\### 4.3 查看当前镜像



Get-Content "$env:USERPROFILE\\.cargo\\config.toml"



\---



\## 五、命令一览



| 命令 | 作用 |

|------|------|

| cargo build | 编译（自动检查镜像） |

| cargo add xxx | 添加依赖（自动检查镜像） |

| cargo install xxx | 安装工具（自动检查镜像） |

| cm | 手动强制重测所有镜像 |

| cargo-mirror.ps1 | 同 cm（完整路径调用） |



\---



\## 六、支持的镜像



| Key | 镜像名 |

|-----|--------|

| tuna | 清华大学 TUNA |

| ustc | 中国科学技术大学 |

| aliyun | 阿里云 |

| rsproxy | rsproxy.cn（字节跳动） |

| sjtu | 上海交通大学 |

| nju | 南京大学 |

| official | 官方源 crates.io |



脚本每次运行时会测全部，自动选最快的。



\---



\## 七、文件布局



安装后产生以下文件：



| 文件 | 位置 | 说明 |

|------|------|------|

| cargo-mirror.ps1 | E:\\code\\scripts\\ | 镜像测速 + 切换 |

| install-cargo-auto.ps1 | E:\\code\\scripts\\ | 一键安装配置 |

| config.toml | %USERPROFILE%\\.cargo\\ | Cargo 镜像配置 |

| config.toml.bak | %USERPROFILE%\\.cargo\\ | 上一版本备份 |

| $PROFILE | %USERPROFILE%\\Documents\\WindowsPowerShell\\Microsoft.PowerShell\_profile.ps1 | cargo 包装函数 + cm 别名 |



\---



\## 八、常见问题 (FAQ)



\### Q1: 某个镜像显示 FAIL，正常吗？



正常。脚本会自动跳过，用其他可用的。例如清华在部分网络环境 443 被拦。



\### Q2: 怎么调整自动刷新频率？



修改 $PROFILE 里这一行：



if ($ageHours -lt 1) { ... }



\- 0.25 -> 15 分钟

\- 6 -> 6 小时

\- 24 -> 每天



\### Q3: 怎么卸载？



\# 1. 移除 $PROFILE 里的块（手动编辑）

notepad $PROFILE

\# 删除 "# ==== Cargo Mirror Automation" 到 "# ==== end" 之间



\# 2. 从 PATH 移除

$userPath = \[Environment]::GetEnvironmentVariable("Path", "User")

$newPath = ($userPath -split ';' | Where-Object { $\_ -ne 'E:\\code\\scripts' }) -join ';'

\[Environment]::SetEnvironmentVariable("Path", $newPath, "User")



\# 3. 删除脚本目录

Remove-Item "E:\\code\\scripts" -Recurse -Force



\### Q4: 怎么恢复官方源？



Remove-Item "$env:USERPROFILE\\.cargo\\config.toml" -Force



\### Q5: 脚本路径不是 E:\\code\\scripts 怎么改？



同步修改：



1\. install-cargo-auto.ps1 里 $scriptsDir = "E:\\code\\scripts"

2\. $PROFILE 里旧路径（删除 block 后重跑安装脚本）



\---



\## 九、验证安装



新开 PowerShell，依次运行：



$env:Path -like "\*E:\\code\\scripts\*"           # True

Get-Alias cm                                   # cm -> cargo-mirror.ps1

Get-Command cargo -CommandType Function        # Function cargo

cm                                             # 输出镜像测速结果



四项正常 = 安装成功。



\---



\## 十、注意事项



1\. 首次运行 cargo 会慢 2-5 秒（测速），后续 1 小时内无感

2\. 不要短时间反复跑 cm，每次会真实测速

3\. $PROFILE 只在交互式 PowerShell 生效；.ps1 脚本内调 cargo 不会触发自动刷新

4\. VS Code 内置终端生效（它会加载 $PROFILE）

5\. 换电脑：拷贝 E:\\code\\scripts\\ 目录，跑一次 install-cargo-auto.ps1



\---



\## 十一、AI 自动化指令（AI Agent 用）



以下内容供 AI 助手自动部署本脚本时使用。



\### 11.1 环境检测



\# 检查 Rust

cargo --version



\# 检查 PowerShell 版本

$PSVersionTable.PSVersion



\# 检查脚本目录是否存在

Test-Path "E:\\code\\scripts"



\### 11.2 全自动部署（AI 可直接执行）



\# 1. 创建目录

$scriptsDir = "E:\\code\\scripts"

New-Item -ItemType Directory -Path $scriptsDir -Force | Out-Null



\# 2. 写入 cargo-mirror.ps1（从本文档 3.2 节提取内容）

$mirrorContent = @'

<此处粘贴 3.2 节的完整内容>

'@

$utf8Bom = New-Object System.Text.UTF8Encoding $true

\[System.IO.File]::WriteAllText("$scriptsDir\\cargo-mirror.ps1", $mirrorContent, $utf8Bom)



\# 3. 写入 install-cargo-auto.ps1（从本文档 3.3 节提取内容）

$installerContent = @'

<此处粘贴 3.3 节的完整内容>

'@

\[System.IO.File]::WriteAllText("$scriptsDir\\install-cargo-auto.ps1", $installerContent, $utf8Bom)



\# 4. 运行安装

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

\& "$scriptsDir\\install-cargo-auto.ps1"



\### 11.3 AI 部署后校验



\# 应输出 True

$env:Path -like "\*E:\\code\\scripts\*"



\# 应输出 cargo-mirror.ps1

(Get-Alias cm).Definition



\# 应输出 Function

(Get-Command cargo -CommandType Function).CommandType



\# 应输出包含 "BEST:" 的测速结果

cm



\### 11.4 AI 修复常见问题



| 症状 | 原因 | 修复 |

|------|------|------|

| cm 未找到 | $PROFILE 未加载 | . $PROFILE 或新开终端 |

| cargo 不是 Function | 包装函数未定义 | 重跑 install-cargo-auto.ps1 |

| 中文乱码 | 文件非 UTF-8 with BOM | \[System.IO.File]::WriteAllText($path, $content, (New-Object System.Text.UTF8Encoding $true)) |

| Blocking waiting for file lock | rust-analyzer 后台占用 | 关闭 rust-analyzer 或 Get-Process cargo | Stop-Process -Force |

| 配置从不刷新 | LastWriteTime 未更新 | 确认脚本含 (Get-Item $ConfigPath).LastWriteTime = Get-Date |



\### 11.5 AI 判断脚本是否已安装



$installed = (Test-Path "E:\\code\\scripts\\cargo-mirror.ps1") `

&#x20;            -and (Test-Path "E:\\code\\scripts\\install-cargo-auto.ps1") `

&#x20;            -and ($env:Path -like "\*E:\\code\\scripts\*") `

&#x20;            -and ((Get-Content $PROFILE -Raw) -match "Cargo Mirror Automation")



$installed = True 表示已安装。



\---



\## 版本信息



| 项 | 值 |

|----|-----|

| 脚本版本 | v2 |

| 依赖 | PowerShell 5.1+ |

| 平台 | Windows 10 / 11 |

| 镜像数 | 7 |

| 自动刷新周期 | 1 小时（可调） |

| 编码 | UTF-8 with BOM |



\---



手册结束。

