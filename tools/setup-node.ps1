param(
  [Parameter(Mandatory = $true)][string]$DestDir
)
$ErrorActionPreference = 'Stop'

# 已装且版本 ≥22 则直接复用；版本过低则删除重装
if (Test-Path -LiteralPath (Join-Path $DestDir 'node.exe')) {
  $existing = Join-Path $DestDir 'node.exe'
  $v = (& $existing -v 2>$null | Out-String).Trim()
  if ($v -match '^v(\d+)\.' -and [int]$Matches[1] -ge 22) {
    Write-Host "便携 Node 已就绪（$v），跳过下载。"
    exit 0
  }
  Write-Host "便携 Node 版本过低（$v），重新下载..."
  Remove-Item -LiteralPath $DestDir -Recurse -Force -ErrorAction SilentlyContinue
}

$mirrors = @('https://registry.npmmirror.com/-/binary/node/', 'https://nodejs.org/dist/')
$idx = $null
foreach ($m in $mirrors) {
  try {
    $idx = Invoke-RestMethod -Uri ($m + 'index.json') -TimeoutSec 30
    break
  } catch {
    Write-Host "无法获取版本列表（$m），尝试下一源..."
  }
}
if (-not $idx) {
  Write-Error "无法获取 Node.js 版本列表（网络受限）"
  exit 1
}

$v = ($idx | Where-Object { $_.version -match '^v22\.\d+\.\d+$' } | Select-Object -First 1).version
if (-not $v) {
  Write-Error "未找到 Node.js v22 版本"
  exit 1
}
Write-Host "最新 Node.js v22: $v"

$zip = Join-Path $env:TEMP ("node-" + $v + "-win-x64.zip")
$ok = $false
foreach ($m in $mirrors) {
  $url = $m + $v + '/node-' + $v + '-win-x64.zip'
  try {
    Write-Host "下载: $url"
    Invoke-WebRequest -Uri $url -OutFile $zip -TimeoutSec 600
    $ok = $true
    break
  } catch {
    Write-Host "下载失败，尝试下一源..."
  }
}
if (-not $ok) {
  Write-Error "Node.js 下载失败，请手动安装 Node.js 22+（https://nodejs.org）后重跑安装脚本"
  exit 1
}

$tmp = Join-Path $env:TEMP ("node-extract-" + $v)
if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force }
Expand-Archive -Path $zip -DestinationPath $tmp -Force
$inner = Join-Path $tmp ("node-" + $v + '-win-x64')
New-Item -ItemType Directory -Force -Path (Split-Path $DestDir -Parent) | Out-Null
if (Test-Path -LiteralPath $DestDir) { Remove-Item -LiteralPath $DestDir -Recurse -Force }
Move-Item -LiteralPath $inner -Destination $DestDir
Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
Write-Host "Node.js 便携版已安装: $DestDir"
exit 2
