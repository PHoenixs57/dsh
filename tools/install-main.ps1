param(
  [switch]$NoKey,
  [switch]$NoLaunch,
  [switch]$NoDshInstall,
  [switch]$SkipPlugin
)
# 科研模式安装器（文字模式入口，由 install-console.bat 调用）。
# 图形界面入口见 install.bat（install-gui.ps1）。本文件由构建脚本统一加 UTF-8 BOM。
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$PathMarker = Join-Path $env:USERPROFILE '.bioresearch-paths'

function Fail([string]$Msg) {
  Write-Host ''
  Write-Host "[失败] $Msg" -ForegroundColor Red
  exit 1
}

# ---------- 0. 安装路径（环境变量 > 记忆 > 包所在盘符的 bioresearch） ----------
$pkgDrive = [string](Split-Path -Qualifier $ScriptDir)
$sysDrive = [string](Split-Path -Qualifier $env:SystemDrive)
$driveDefault = if ($pkgDrive.ToUpper() -ne $sysDrive.ToUpper()) { "$pkgDrive\bioresearch" } else { Join-Path $env:USERPROFILE 'bioresearch' }

if ($env:BIORESEARCH_HOME) { $BR_HOME = $env:BIORESEARCH_HOME } else { $BR_HOME = $driveDefault }
if ($env:DSH_HOME) { $DSH_DIR = $env:DSH_HOME } else { $DSH_DIR = Join-Path $env:USERPROFILE '.dsh' }
if (Test-Path -LiteralPath $PathMarker) {
  Get-Content -LiteralPath $PathMarker | ForEach-Object {
    $idx = $_.IndexOf('=')
    if ($idx -gt 0) {
      $k = $_.Substring(0, $idx).Trim()
      $v = $_.Substring($idx + 1).Trim()
      if ($k -eq 'BR_HOME' -and $v -and -not $env:BIORESEARCH_HOME) { $BR_HOME = $v }
      if ($k -eq 'DSH_DIR' -and $v -and -not $env:DSH_HOME) { $DSH_DIR = $v }
    }
  }
}

function Resolve-ChosenPath([string]$PathText, [string]$Fallback) {
  # 支持 ~ 与 %VAR% 展开，要求绝对路径；归一化常见输入错误（全角冒号、首尾空白与引号）
  # 注意：参数不能命名为 $Input（PowerShell 保留自动变量，永远绑定不到值）
  $p = $PathText.Trim().Trim('"').Trim("'")
  $p = $p -replace '：', ':' -replace '＋', '+'
  if ($p -eq '') { return $Fallback }
  if ($p.StartsWith('~\') -or $p -eq '~') { $p = $env:USERPROFILE + $p.Substring(1) }
  $p = [Environment]::ExpandEnvironmentVariables($p)
  if ($p -notmatch '^[A-Za-z]:[\\/]' -and $p -notmatch '^\\\\') { return $null }
  return $p
}

function Pick-Folder([string]$Title, [string]$Initial) {
  try {
    Add-Type -AssemblyName System.Windows.Forms
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = $Title
    $dlg.ShowNewFolderButton = $true
    if ($Initial -and (Test-Path -LiteralPath $Initial)) { $dlg.SelectedPath = $Initial }
    $null = $dlg.ShowDialog()
    return $dlg.SelectedPath
  } catch {
    return $Initial
  }
}

function Ask-Path([string]$Label, [string]$Current) {
  $ans = Read-Host "$Label（回车=默认：$Current；输入 y 弹窗选择；或直接输入路径）"
  $ans = "$ans".Trim()
  if ($ans -eq 'y' -or $ans -eq 'Y') {
    $picked = Pick-Folder $Label $Current
    if ($picked -and $picked -ne '') { return $picked }
    Write-Host '未选择文件夹，使用默认路径。'
    return $Current
  }
  $resolved = Resolve-ChosenPath $ans $Current
  if ($null -eq $resolved) { return $null }
  return $resolved
}

if (-not $env:BIORESEARCH_HOME) {
  $chosen = Ask-Path '选择「科研模式」安装目录' $BR_HOME
  if ($null -eq $chosen) { Fail "无效的安装目录（需要绝对路径，如 D:\bioresearch，或输入 y 弹窗选择）" }
  $BR_HOME = $chosen
  Write-Host "安装目录：$BR_HOME"
}
if (-not $env:DSH_HOME) {
  $chosen = Ask-Path '选择 DSH 数据目录（预设/API Key 存放处）' $DSH_DIR
  if ($null -eq $chosen) { Fail "无效的 DSH 数据目录（需要绝对路径，或输入 y 弹窗选择）" }
  $DSH_DIR = $chosen
  Write-Host "DSH 数据目录：$DSH_DIR"
}

& "$ScriptDir\install-core.ps1" -BR_HOME $BR_HOME -DSH_DIR $DSH_DIR `
  -NoKey:$NoKey -NoLaunch:$NoLaunch -NoDshInstall:$NoDshInstall -SkipPlugin:$SkipPlugin `
  -Log { param($m) Write-Host $m }
exit $LASTEXITCODE
