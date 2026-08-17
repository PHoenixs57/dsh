param(
  [Parameter(Mandatory = $true)][string]$BR_HOME,
  [Parameter(Mandatory = $true)][string]$DSH_DIR,
  [switch]$NoKey,
  [switch]$NoLaunch,
  [switch]$NoDshInstall,
  [switch]$SkipPlugin,
  [string]$ApiKey = '',
  [scriptblock]$Log = { param($m) Write-Host $m }
)
# 科研模式安装核心引擎：控制台（install-main.ps1）与图形界面（install-gui.ps1）共用。
# 所有步骤先探测、已满足则跳过（幂等）；进度消息通过 -Log 回调输出。
# 兼容 Windows PowerShell 5.1；本文件由构建脚本统一加 UTF-8 BOM。
$ErrorActionPreference = 'Stop'

$PACK_VERSION = '0.3.5'
$DSH_VERSION = '0.1.0-rc.6'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$PkgRoot = Split-Path -Parent $ScriptDir
$PathMarker = Join-Path $env:USERPROFILE '.bioresearch-paths'

function Log { param([string]$m) & $Log $m }
function Fail([string]$Msg) {
  Log ''
  Log "[失败] $Msg"
  exit 1
}

# Windows PowerShell 5.1 的后台任务会把原生命令写入 stderr 的普通警告
# 当作 PowerShell 错误；在全局 ErrorActionPreference=Stop 下会直接终止任务。
# npm 经常输出 deprecated 等非致命警告，因此仅在执行 npm 时暂时允许
# 非终止错误，并始终以 npm 的真实进程退出码判断成功或失败。
$script:NpmExitCode = 0
function Invoke-Npm([string[]]$NpmArgs) {
  $previousErrorAction = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    & $npmCmd @NpmArgs 2>&1 | ForEach-Object { Log ("      " + [string]$_) }
    $script:NpmExitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previousErrorAction
  }
}

New-Item -ItemType Directory -Force -Path $BR_HOME | Out-Null
New-Item -ItemType Directory -Force -Path $DSH_DIR | Out-Null
[IO.File]::WriteAllText($PathMarker, "BR_HOME=$BR_HOME`r`nDSH_DIR=$DSH_DIR`r`n", (New-Object System.Text.UTF8Encoding($false)))

Log '=============================================================='
Log "  科研模式（生物医学文献检索助手）一键安装  v$PACK_VERSION"
Log "  安装目录 : $BR_HOME"
Log "  DSH 数据 : $DSH_DIR"
Log '=============================================================='
Log ''

# ---------- 1. Node.js ----------
$nodeCmd = $null
$npmCmd = $null
$found = Get-Command node -ErrorAction SilentlyContinue
if ($found) {
  $candidate = $found.Source
  $verOut = & $candidate -v 2>$null
  $major = -1
  if ($verOut -match '^v(\d+)\.') { $major = [int]$Matches[1] }
  if ($major -ge 22) {
    $nodeCmd = $candidate
    $npm = Get-Command npm -ErrorAction SilentlyContinue
    if ($npm) { $npmCmd = $npm.Source }
    Log "[1/7] 检测到 Node $verOut"
  } else {
    Log "[1/7] 检测到 Node $verOut，版本低于 22，将使用便携版。"
  }
}
if (-not $nodeCmd) {
  Log '[1/7] 检查/下载便携版 Node.js 22（npmmirror，失败自动回退 nodejs.org）...'
  & "$ScriptDir\setup-node.ps1" -DestDir (Join-Path $BR_HOME 'node')
  if (-not (Test-Path -LiteralPath (Join-Path $BR_HOME 'node\node.exe'))) {
    Fail 'Node.js 下载失败。请手动安装 Node.js 22 或更高版本（https://nodejs.org）后重试。'
  }
  $nodeCmd = Join-Path $BR_HOME 'node\node.exe'
  $npmCmd = Join-Path $BR_HOME 'node\npm.cmd'
  $env:PATH = (Join-Path $BR_HOME 'node') + ';' + $env:PATH
  Log '[1/7] 便携 Node 就绪。'
}
if (-not $npmCmd) { Fail '未找到 npm，请检查 Node.js 安装后重试。' }

# ---------- 2. npm 镜像（已是镜像则不动） ----------
$curRegistry = (& $npmCmd config get registry 2>$null | Out-String).Trim().TrimEnd('/')
if ($curRegistry -ne 'https://registry.npmmirror.com') {
  Log '[2/7] 配置 npm 镜像（npmmirror，加速国内下载）...'
  & $npmCmd config set registry https://registry.npmmirror.com 2>$null | Out-Null
} else {
  Log '[2/7] npm 已使用 npmmirror 镜像，跳过。'
}

# ---------- 3. DSH ----------
if ($NoDshInstall) {
  $dshExisting = $null
  $dshFound = Get-Command dsh -ErrorAction SilentlyContinue
  if ($dshFound) { $dshExisting = $dshFound.Source }
  if (-not $dshExisting) { Fail '未勾选安装 DSH，但本机也未找到 dsh 命令。请勾选「安装/更新 DeepSeek Harness」后重试。' }
  Log "[3/7] 跳过 DSH 安装（使用已装 dsh: $dshExisting）"
} else {
  # 已装且版本一致 → 跳过；版本不符 → 升级/修复；没装 → 安装
  $dshExisting = $null
  $dshFound = Get-Command dsh -ErrorAction SilentlyContinue
  if ($dshFound) { $dshExisting = $dshFound.Source }
  if (-not $dshExisting -and (Test-Path -LiteralPath (Join-Path $BR_HOME 'node\dsh.cmd'))) {
    $dshExisting = Join-Path $BR_HOME 'node\dsh.cmd'
  }
  $needInstall = $true
  if ($dshExisting) {
    $vOut = (& $dshExisting --version 2>$null | Out-String).Trim()
    if ($vOut -eq $DSH_VERSION) {
      Log "[3/7] 已安装 DeepSeek Harness $DSH_VERSION，跳过安装。"
      $needInstall = $false
    } else {
      Log "[3/7] 检测到 DeepSeek Harness $vOut，将更新到 $DSH_VERSION ..."
    }
  }
  if ($needInstall) {
    Log "[3/7] 安装 DeepSeek Harness @deepseek-ai/dsh@$DSH_VERSION（首次约 1-3 分钟）..."
    Invoke-Npm -NpmArgs @('install', '-g', "@deepseek-ai/dsh@$DSH_VERSION")
    if ($script:NpmExitCode -ne 0) { Fail 'DSH 安装失败。请检查网络后重试；公司网络请确认 npm 可访问。' }
  }
}

$presetDst = $null
$mcpDst = $null
if (-not $SkipPlugin) {
  # ---------- 4. 预设（覆盖同步，幂等） ----------
  Log "[4/7] 同步「科研模式」预设 → $DSH_DIR\.agent-presets\bioresearch"
  $presetDst = Join-Path $DSH_DIR '.agent-presets\bioresearch'
  New-Item -ItemType Directory -Force -Path $presetDst | Out-Null
  Copy-Item -Path (Join-Path $PkgRoot 'preset\*') -Destination $presetDst -Recurse -Force

  # ---------- 5. MCP（按 lockfile 哈希判断依赖是否已就绪） ----------
  Log "[5/7] 同步文献检索 MCP → $BR_HOME\literature-search-mcp"
  $mcpDst = Join-Path $BR_HOME 'literature-search-mcp'
  New-Item -ItemType Directory -Force -Path $mcpDst | Out-Null
  Copy-Item -Path (Join-Path $PkgRoot 'mcp\*') -Destination $mcpDst -Recurse -Force
  $lockHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $mcpDst 'package-lock.json')).Hash
  $depsMarker = Join-Path $mcpDst 'node_modules\.bioresearch-lockhash'
  $depsOk = (Test-Path -LiteralPath $depsMarker) -and ((Get-Content -LiteralPath $depsMarker -Raw).Trim() -eq $lockHash)
  if ($depsOk) {
    Log '      MCP 依赖已就绪（哈希匹配），跳过安装。'
  } else {
    Log '      安装 MCP 运行依赖（npm ci --omit=dev）...'
    Push-Location $mcpDst
    try {
      Invoke-Npm -NpmArgs @('ci', '--omit=dev')
      if ($script:NpmExitCode -ne 0) { Fail 'MCP 依赖安装失败，请检查网络后重试。' }
    } finally {
      Pop-Location
    }
    [IO.File]::WriteAllText($depsMarker, $lockHash, (New-Object System.Text.UTF8Encoding($false)))
  }

  # ---------- 6. 写入绝对路径（每次重跑都重写，路径变更后自动纠正） ----------
  $mcpServerFs = ((Join-Path $mcpDst 'dist\server.js') -replace '\\', '/')
  $nodeFs = ($nodeCmd -replace '\\', '/')
  & "$ScriptDir\patch-preset.ps1" -PresetDir $presetDst -NodePath $nodeFs -McpServerPath $mcpServerFs
  if ($LASTEXITCODE -ne 0) { Fail '预设路径写入失败。' }

  # ---------- 6.5 默认会话模式 ----------
  Log '[6.5/7] 设置「科研模式」为默认会话模式...'
  try {
    & "$ScriptDir\set-default-preset.ps1" -DshDir $DSH_DIR
  } catch {
    Log '    写入 settings.yaml 失败；可稍后在网页 设置 中手动把默认模式选为「科研模式」。'
  }
} else {
  Log '[4-6/7] 按选择跳过「科研模式」插件安装。'
}

# ---------- 7. API Key ----------
if ($NoKey) {
  Log '[7/7] 跳过 API Key 配置'
} elseif ($ApiKey -ne '') {
  Log '[7/7] 校验并写入 DeepSeek API Key...'
  & "$ScriptDir\setup-key.ps1" -DshDir $DSH_DIR -Key $ApiKey
  $keyErr = $LASTEXITCODE
  if ($keyErr -eq 3) { Log 'Key 校验失败（401）：Key 未写入，请确认后重试，或在网页 设置→模型 中填写。' }
  if ($keyErr -eq 4) { Log '网络受限，Key 未写入：之后可在网页 设置→模型 中填写。' }
} else {
  Log '[7/7] 配置 DeepSeek API Key...'
  & "$ScriptDir\setup-key.ps1" -DshDir $DSH_DIR
  $keyErr = $LASTEXITCODE
  if ($keyErr -eq 3) { Log 'Key 校验失败：可重新运行安装程序，或在网页 设置→模型 中填写。' }
  if ($keyErr -eq 4) { Log '网络受限，Key 未写入：之后可在网页 设置→模型 中填写。' }
}

# ---------- 启动脚本与快捷方式 ----------
Log '生成启动脚本与桌面快捷方式...'
Copy-Item -LiteralPath (Join-Path $ScriptDir 'start-template.bat') -Destination (Join-Path $BR_HOME 'start.bat') -Force
Copy-Item -LiteralPath (Join-Path $ScriptDir 'start-main.ps1') -Destination (Join-Path $BR_HOME 'start-main.ps1') -Force
$iconSrc = Join-Path $PkgRoot 'assets\deepseek.ico'
$iconDst = Join-Path $BR_HOME 'deepseek.ico'
if (Test-Path -LiteralPath $iconSrc) {
  Copy-Item -LiteralPath $iconSrc -Destination $iconDst -Force
} else {
  $iconDst = ''
}
& "$ScriptDir\make-shortcut.ps1" -Name 'deepseek-dsh' -TargetPath (Join-Path $BR_HOME 'start.bat') -WorkingDirectory $BR_HOME -IconPath $iconDst

Log ''
Log '=============================================================='
Log '  安装完成！已在桌面创建「deepseek-dsh」快捷方式'
Log "  以后启动：双击桌面「deepseek-dsh」快捷方式，或运行 $BR_HOME\start.bat"
Log '  网页地址：http://127.0.0.1:3081'
Log '=============================================================='
if (-not $NoLaunch) {
  Start-Process -FilePath (Join-Path $BR_HOME 'start.bat')
}
exit 0
