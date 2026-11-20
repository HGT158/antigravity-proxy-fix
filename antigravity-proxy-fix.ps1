<#
.SYNOPSIS
  修复 Antigravity 启动黑屏：自动定位 Antigravity、自动探测本地代理端口，
  在修复脚本所在目录生成可双击的代理启动脚本。

.DESCRIPTION
  黑屏根因：Antigravity 的语言服务器（Go 后端）不读 Windows 系统代理，
  只认 HTTP_PROXY / HTTPS_PROXY 环境变量。连不上 Google 就黑屏。
  本脚本以普通用户身份生成 launch-antigravity.cmd。

.PARAMETER ProxyPort
  指定代理端口。不传则自动探测：
    1) 读取系统代理设置（ProxyServer）
    2) 依次测试常见端口(7890/7897/7899/7891/10809/10808/10811/1080/8888/2080)，
       用 curl 经该代理访问 oauth2.googleapis.com，curl 退出码为 0 且返回真实
       HTTP 状态码(非 000)才视为可用。

.PARAMETER ProbeOnly
  只探测并打印结果，不修改任何东西（用于先看看再决定）。

.PARAMETER SkipRelaunch
  只生成启动脚本，不关闭或重启 Antigravity。

.EXAMPLE
  .\antigravity-proxy-fix.ps1                      # 自动探测并修复 + 重启
  .\antigravity-proxy-fix.ps1 -ProxyPort 7890      # 明确指定端口
  .\antigravity-proxy-fix.ps1 -ProbeOnly           # 先探测看一下
#>
param(
  [ValidateRange(1, 65535)]
  [int]$ProxyPort,
  [switch]$ProbeOnly,
  [switch]$SkipRelaunch
)
$ScriptVersion = '1.2.1'
$ErrorActionPreference = 'Stop'

function Step($m){ Write-Host "[*] $m" -ForegroundColor Cyan }
function OK($m){ Write-Host "[+] $m" -ForegroundColor Green }
function Warn($m){ Write-Host "[!] $m" -ForegroundColor Yellow }
function Err($m){ Write-Host "[x] $m" -ForegroundColor Red }

function Assert-StandardUser {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  try {
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
      throw '当前进程已获得管理员权限。请从资源管理器双击 fix-antigravity.cmd，或在普通 PowerShell 中重新运行。'
    }
  } finally {
    $identity.Dispose()
  }
}

# ---------- 1) 定位 Antigravity.exe ----------
function Find-Antigravity {
  $cands = New-Object System.Collections.Generic.List[string]
  if ($env:LOCALAPPDATA) {
    $cands.Add((Join-Path $env:LOCALAPPDATA 'Programs\antigravity\Antigravity.exe'))
  }

  foreach ($root in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
                      'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
                      'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
    Get-ItemProperty $root -ErrorAction SilentlyContinue |
      Where-Object { $_.DisplayName -match 'antigravity' } |
      ForEach-Object {
        if ($_.DisplayIcon) {
          # Expand REG_SZ variables too; remove only the trailing icon index.
          # Matching the first .exe truncates paths with .exe in a parent folder.
          $ico = [Environment]::ExpandEnvironmentVariables([string]$_.DisplayIcon).Trim()
          $ico = ($ico -replace ',\s*-?\d+\s*$', '').Trim().Trim('"')
          if ([IO.Path]::IsPathRooted($ico) -and [IO.Path]::GetFileName($ico) -ieq 'Antigravity.exe') {
            $cands.Add($ico)
          }
        }
        if ($_.InstallLocation) {
          $location = [Environment]::ExpandEnvironmentVariables([string]$_.InstallLocation).Trim().Trim('"')
          if ($location -and [IO.Path]::IsPathRooted($location)) {
            $cands.Add([IO.Path]::Combine($location, 'Antigravity.exe'))
          }
        }
      }
  }
  foreach ($p in $cands) { if ($p -and (Test-Path -LiteralPath $p -PathType Leaf)) { return (Resolve-Path -LiteralPath $p).Path } }

  $localPrograms = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'Programs' } else { $null }
  foreach ($base in @($localPrograms, $env:ProgramFiles, ${env:ProgramFiles(x86)})) {
    if ($base) {
      $hit = Get-ChildItem -LiteralPath $base -Directory -Filter 'antigravity*' -ErrorAction SilentlyContinue |
             ForEach-Object { Join-Path $_.FullName 'Antigravity.exe' } |
             Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
      if ($hit) { return $hit }
    }
  }
  return $null
}

# ---------- 2) 探测代理端口 ----------
function Test-ProxyPort($port) {
  if (-not $port) { return $false }
  # 用 curl 经代理访问 Google，能返回真实 HTTP 状态码 => 代理可用（能穿透到 Google）。
  # 必须同时检查 curl 退出码：连接失败时 -w 也会输出 000，若只看状态码，
  # 死端口会被误判可用，导致端口扫描永远停在第一个端口(7890)上。
  $u = 'https://oauth2.googleapis.com/'
  try {
    $out = & curl.exe --disable --noproxy 'localhost,127.0.0.1' -x "http://127.0.0.1:$port" -s -o NUL --connect-timeout 4 -m 12 -w '%{http_code}' $u 2>$null
  } catch { return $false }   # $ErrorActionPreference=Stop 下 native 命令写 stderr 会变成终止错误
  $code = [string]($out -join '')
  if ($LASTEXITCODE -eq 0 -and $code -match '^[1-9]\d{2}$') { return $true }   # 200/301/302/404... 都算通，000=没连上
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

  foreach ($p in @(7890,7897,7899,7891,10809,10808,10811,1080,8888,2080)) {
    if (Test-ProxyPort $p) { Step "发现可用代理端口 $p"; return $p }
  }
  return $null
}

# ---------- 3) 在修复脚本旁生成启动器 ----------
function Start-Antigravity {
  param([string]$exe, [int]$port)
  Assert-StandardUser
  if (-not [IO.File]::Exists($exe)) {
    throw "找不到 Antigravity：$exe。请重新运行 fix-antigravity.cmd。"
  }

  $sessionId = (Get-Process -Id $PID).SessionId
  $unreadable = Get-RunningAntigravity $exe $sessionId | Where-Object { -not $_.Path } | Select-Object -First 1
  if ($unreadable) {
    throw '无法读取当前会话中的 Antigravity 进程（可能以管理员身份运行）。请保存工作并完全退出该实例，再运行 launch-antigravity.cmd。'
  }

  $startInfo = [Diagnostics.ProcessStartInfo]::new()
  $startInfo.FileName = $exe
  $startInfo.WorkingDirectory = [IO.Path]::GetDirectoryName($exe)
  # 直接创建进程，保留当前权限，只在子进程的环境中注入代理。
  $startInfo.UseShellExecute = $false
  foreach ($name in 'HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY') {
    $startInfo.EnvironmentVariables[$name] = "http://127.0.0.1:$port"
  }
  try {
    return [Diagnostics.Process]::Start($startInfo)
  } catch {
    $cause = $_.Exception.GetBaseException()
    if ($cause -is [ComponentModel.Win32Exception] -and $cause.NativeErrorCode -eq 740) {
      throw "Windows 要求以管理员身份启动 $exe。请检查该文件的属性 → 兼容性（包括「更改所有用户的设置」）中的「以管理员身份运行此程序」。如果管理员权限由安装版本或组织策略要求，请联系管理员。"
    }
    throw
  }
}

function Install-File($source, $destination) {
  # 先完整写好临时文件，再发布，避免运行中的启动入口读到半截文件。
  if (-not [IO.File]::Exists($destination)) {
    try { [IO.File]::Move($source, $destination); return }
    catch {
      if (-not [IO.File]::Exists($destination)) { throw }
    }
  }
  [IO.File]::Replace($source, $destination, [NullString]::Value)
}

function New-Launcher($dir, $exe, $port) {
  $launcher = Join-Path $dir 'start-antigravity.ps1'
  $entry = Join-Path $dir 'launch-antigravity.cmd'
  $temp = Join-Path $dir ([guid]::NewGuid().ToString() + '.tmp')
  $exeLiteral = [System.Management.Automation.Language.CodeGeneration]::EscapeSingleQuotedStringContent($exe)
  # 启动器与安装脚本共享同一套权限检查和进程启动逻辑，并保留 Unicode 路径。
  $body = @"
`$ErrorActionPreference = 'Stop'
function Assert-StandardUser {${function:Assert-StandardUser}}
function Get-RunningAntigravity {${function:Get-RunningAntigravity}}
function Start-Antigravity {${function:Start-Antigravity}}
try {
  `$app = Start-Antigravity '$exeLiteral' $port
  `$app.Dispose()
} catch {
  Write-Host "[x] `$(`$_.Exception.GetBaseException().Message)" -ForegroundColor Red
  exit 1
}
"@
  $command = @(
    '@echo off'
    'setlocal DisableDelayedExpansion'
    '"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -File "%~dp0start-antigravity.ps1"'
    'set "RC=%ERRORLEVEL%"'
    'if not "%RC%"=="0" pause'
    'endlocal & exit /b %RC%'
  )
  try {
    [IO.File]::WriteAllText($temp, $body, [Text.UTF8Encoding]::new($true))
    Install-File $temp $launcher
    [IO.File]::WriteAllLines($temp, $command, [Text.Encoding]::ASCII)
    Install-File $temp $entry
  } finally {
    [IO.File]::Delete($temp)
  }
  return $entry
}

# ---------- 4) 检查和关闭旧实例 ----------
function Get-RunningAntigravity($exe, $sessionId) {
  Get-Process -Name Antigravity -ErrorAction SilentlyContinue | Where-Object {
    # 读不到路径的进程可能已提权，同会话内有这类进程时不能确认旧实例已退出。
    $_.SessionId -eq $sessionId -and (-not $_.Path -or $_.Path -ieq $exe)
  }
}

function Close-RunningAntigravity($exe) {
  $sessionId = (Get-Process -Id $PID).SessionId
  $running = @(Get-RunningAntigravity $exe $sessionId)
  if (-not $running.Count) { return }

  Step '正在请求当前 Antigravity 窗口退出……'
  foreach ($app in $running) {
    try {
      if ($app.Path -ieq $exe -and $app.MainWindowHandle -ne 0) { [void]$app.CloseMainWindow() }
    } catch {
      # 进程可能在查询后退出。下方重新检查实际状态。
    }
  }
  $deadline = [Diagnostics.Stopwatch]::StartNew()
  do {
    Start-Sleep -Milliseconds 250
    $running = @(Get-RunningAntigravity $exe $sessionId)
  } while ($running.Count -and $deadline.Elapsed.TotalSeconds -lt 10)

  if ($running.Count) {
    throw '当前 Antigravity 仍在运行。请保存工作并从应用菜单完全退出（包括以管理员身份运行的窗口），再运行 launch-antigravity.cmd。'
  }
}

# ================= 主流程 =================
Write-Host "============================================" -ForegroundColor DarkCyan
Write-Host " Antigravity 黑屏修复 (自动走代理) v$ScriptVersion" -ForegroundColor DarkCyan
Write-Host "============================================" -ForegroundColor DarkCyan

try { Assert-StandardUser }
catch { Err $_.Exception.Message; exit 1 }

$exe = Find-Antigravity
if (-not $exe) { Err "未找到 Antigravity.exe，请先安装 Antigravity 再运行本脚本。"; exit 1 }
Step "已定位 Antigravity: $exe"

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

try {
  $launcher = New-Launcher $PSScriptRoot $exe $port
  OK "已生成代理启动入口：$launcher"
} catch {
  Err "无法在 $PSScriptRoot 生成代理启动入口。请把修复脚本放在当前用户可写的文件夹中。$($_.Exception.GetBaseException().Message)"
  exit 1
}

if (-not $SkipRelaunch) {
  try {
    Close-RunningAntigravity $exe
    $app = Start-Antigravity $exe $port
    try {
      if ($app.WaitForExit(3000)) { throw 'Antigravity 启动后随即退出，请确认旧实例已完全退出，再运行 launch-antigravity.cmd。' }
    } finally {
      $app.Dispose()
    }
    OK '已使用代理环境变量启动 Antigravity。'
  } catch {
    Err "代理入口已配置，自动重启未完成。$($_.Exception.Message)"
    exit 1
  }
}

OK '完成。日常使用时保持代理客户端运行，双击上面显示的启动脚本。'
