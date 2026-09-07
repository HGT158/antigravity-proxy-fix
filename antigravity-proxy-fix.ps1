<#
.SYNOPSIS
  修复 Antigravity 启动黑屏：自动定位 Antigravity、自动探测本地代理端口，
  生成走代理的启动器，并把桌面 / 开始菜单快捷方式指向它。
  之后双击图标即自动走代理，不再黑屏。

.DESCRIPTION
  黑屏根因：Antigravity 的语言服务器（Go 后端）不读 Windows 系统代理，
  只认 HTTP_PROXY / HTTPS_PROXY 环境变量。连不上 Google 就黑屏。
  本脚本把代理环境变量固化进一个启动器，并替换所有启动入口。

.PARAMETER ProxyPort
  指定代理端口。不传则自动探测：
    1) 读取系统代理设置（ProxyServer）
    2) 依次测试常见端口(7890/7897/7891/10809/10808/1080/8888/2080)，
       用 curl 经该代理访问 oauth2.googleapis.com，能返回 HTTP 状态码即视为可用。

.PARAMETER ProbeOnly
  只探测并打印结果，不修改任何东西（用于先看看再决定）。

.PARAMETER SkipRelaunch
  不结束进程、不重新启动，只生成启动器和改快捷方式。

.EXAMPLE
  .\antigravity-proxy-fix.ps1                      # 自动探测并修复 + 重启
  .\antigravity-proxy-fix.ps1 -ProxyPort 7890      # 明确指定端口
  .\antigravity-proxy-fix.ps1 -ProbeOnly           # 先探测看一下
#>
param(
  [string]$ProxyPort,
  [switch]$ProbeOnly,
  [switch]$SkipRelaunch
)
$ErrorActionPreference = 'Stop'

function Step($m){ Write-Host "[*] $m" -ForegroundColor Cyan }
function OK($m){ Write-Host "[+] $m" -ForegroundColor Green }
function Warn($m){ Write-Host "[!] $m" -ForegroundColor Yellow }
function Err($m){ Write-Host "[x] $m" -ForegroundColor Red }

# ---------- 1) 定位 Antigravity.exe ----------
function Find-Antigravity {
  $cands = New-Object System.Collections.Generic.List[string]
  $cands.Add((Join-Path $env:LOCALAPPDATA 'Programs\antigravity\Antigravity.exe'))

  foreach ($root in @('HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
                      'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
    Get-ItemProperty $root -ErrorAction SilentlyContinue |
      Where-Object { $_.DisplayName -match 'antigravity' } |
      ForEach-Object {
        if ($_.DisplayIcon -and $_.DisplayIcon -match '^(.+?\.exe)') {
          $cands.Add($Matches[1])
        }
        if ($_.InstallLocation) { $cands.Add((Join-Path $_.InstallLocation 'Antigravity.exe')) }
      }
  }
  foreach ($p in $cands) { if ($p -and (Test-Path -LiteralPath $p)) { return (Resolve-Path -LiteralPath $p).Path } }

  foreach ($base in @("$env:LOCALAPPDATA\Programs", "$env:ProgramFiles", "${env:ProgramFiles(x86)}")) {
    if ($base) {
      $hit = Get-ChildItem -Path $base -Directory -Filter 'antigravity*' -ErrorAction SilentlyContinue |
             ForEach-Object { Join-Path $_.FullName 'Antigravity.exe' } |
             Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
      if ($hit) { return $hit }
    }
  }
  return $null
}

# ---------- 2) 探测代理端口 ----------
function Test-ProxyPort($port) {
  if (-not $port) { return $false }
  # 用 curl 经代理访问 Google，能返回任意 HTTP 状态码 => 代理可用（能穿透到 Google）
  $u = 'https://oauth2.googleapis.com/'
  $code = ((& curl.exe -x "http://127.0.0.1:$port" -s -o NUL -m 12 -w '%{http_code}' $u) 2>$null)
  if ($code -match '^\d{3}$') { return $true }   # 200/301/302/404... 都算通
  return $false
}

function Find-ProxyPort {
  if ($ProxyPort) { return [int]$ProxyPort }

  # 先看系统代理设置
  try {
    $ps = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
    if ($ps.ProxyEnable -eq 1 -and $ps.ProxyServer -match '(\d{4,5})$') {
      $sysPort = [int]$Matches[1]
      if (Test-ProxyPort $sysPort) { Step "读取到系统代理端口 $sysPort，测试可用"; return $sysPort }
      else { Warn "系统代理端口 $sysPort 存在但测试不通，继续扫描" }
    }
  } catch {}

  foreach ($p in @(7890,7897,7891,10809,10808,1080,8888,2080)) {
    if (Test-ProxyPort $p) { Step "发现可用代理端口 $p"; return $p }
  }
  return $null
}

# ---------- 3) 生成启动器 ----------
function New-Launcher($exeDir, $port) {
  $launcher = Join-Path $exeDir 'launch-antigravity.bat'
  $bat = @"
@echo off
rem Antigravity launcher - forces the LS (Go) backend through the local proxy.
set HTTP_PROXY=http://127.0.0.1:$port
set HTTPS_PROXY=http://127.0.0.1:$port
set ALL_PROXY=http://127.0.0.1:$port
start "" "$exeDir\Antigravity.exe"
"@
  Set-Content -LiteralPath $launcher -Value $bat -Encoding ASCII
  return $launcher
}

# ---------- 4) 替换/创建快捷方式 ----------
function Update-Shortcut($lnkPath, $target, $icon) {
  if (-not (Test-Path -LiteralPath $lnkPath)) { return }
  try {
    $ws = New-Object -ComObject WScript.Shell
    $lnk = $ws.CreateShortcut($lnkPath)
    $lnk.TargetPath = $target
    if ($icon) { $lnk.IconLocation = $icon }
    $lnk.WorkingDirectory = (Split-Path $target)
    $lnk.Save()
    OK "已更新快捷方式: $lnkPath"
  } catch { Warn "无法更新快捷方式 $lnkPath : $_" }
}
function Create-Shortcut($lnkPath, $target, $icon) {
  try {
    $ws = New-Object -ComObject WScript.Shell
    $lnk = $ws.CreateShortcut($lnkPath)
    $lnk.TargetPath = $target
    if ($icon) { $lnk.IconLocation = $icon }
    $lnk.WorkingDirectory = (Split-Path $target)
    $lnk.Save()
    OK "已创建快捷方式: $lnkPath"
  } catch { Warn "无法创建快捷方式 $lnkPath : $_" }
}

# ================= 主流程 =================
Write-Host "============================================" -ForegroundColor DarkCyan
Write-Host " Antigravity 黑屏修复 (自动走代理)" -ForegroundColor DarkCyan
Write-Host "============================================" -ForegroundColor DarkCyan

$exe = Find-Antigravity
if (-not $exe) { Err "未找到 Antigravity.exe，请先安装 Antigravity 再运行本脚本。"; exit 1 }
Step "已定位 Antigravity: $exe"

$exeDir = Split-Path $exe
$icon   = "$exe,0"

$port = Find-ProxyPort
if (-not $port) { Err "未找到可用的本地代理端口。请先开启代理客户端(如 Clash Verge)，或加 -ProxyPort 指定端口后重试。"; exit 1 }
OK "使用代理端口: $port"

if ($ProbeOnly) {
  Write-Host "`n[探测模式] 只检测，不修改。结果为:" -ForegroundColor Yellow
  Write-Host "  Antigravity : $exe"
  Write-Host "  代理端口    : $port"
  Write-Host "  系统代理    : $( (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue).ProxyServer )"
  exit 0
}

$launcher = New-Launcher $exeDir $port
OK "已生成启动器: $launcher"

# 快捷方式：桌面 + 开始菜单 + 任务栏(若存在)
$desktop = [Environment]::GetFolderPath('Desktop')
$startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
$taskBar = Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'

if (Test-Path (Join-Path $desktop 'Antigravity.lnk')) { Update-Shortcut (Join-Path $desktop 'Antigravity.lnk') $launcher $icon }
else { Create-Shortcut (Join-Path $desktop 'Antigravity.lnk') $launcher $icon }

if (Test-Path (Join-Path $startMenu 'Antigravity.lnk')) { Update-Shortcut (Join-Path $startMenu 'Antigravity.lnk') $launcher $icon }
else { Create-Shortcut (Join-Path $startMenu 'Antigravity.lnk') $launcher $icon }

Get-ChildItem -Path $taskBar -Filter '*ntigravity*.lnk' -ErrorAction SilentlyContinue | ForEach-Object { Update-Shortcut $_.FullName $launcher $icon }

# 重新启动（走代理）
if (-not $SkipRelaunch) {
  Step "结束当前 Antigravity / language_server... "
  Get-Process Antigravity, language_server -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 2
  Step "通过启动器重新启动 Antigravity (走代理 $port)..."
  Start-Process -FilePath $launcher -WorkingDirectory $exeDir
  Start-Sleep -Seconds 8
  if (Get-Process Antigravity -ErrorAction SilentlyContinue) { OK "Antigravity 已重新启动。窗口应正常显示，不再黑屏。" }
  else { Warn "未检测到 Antigravity 进程，可能启动失败，请查看是否开启了代理客户端。" }
}

Write-Host "`n完成。以后打开 Antigravity 只需：代理客户端(如 Clash Verge)保持运行，直接双击图标即可。" -ForegroundColor Green
