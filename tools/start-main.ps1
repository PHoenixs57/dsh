param([string]$Port = '3081')
# 科研模式启动脚本主逻辑（由 start.bat 调用）
# 兼容 Windows PowerShell 5.1；本文件由构建脚本统一加 UTF-8 BOM。

$Here = Split-Path -Parent $MyInvocation.MyCommand.Path

# 恢复安装时选择的 DSH 数据目录（预设与 API Key 所在），保证 dsh 能找到预设
$PathMarker = Join-Path $env:USERPROFILE '.bioresearch-paths'
if (Test-Path -LiteralPath $PathMarker) {
  Get-Content -LiteralPath $PathMarker | ForEach-Object {
    $idx = $_.IndexOf('=')
    if ($idx -gt 0) {
      $k = $_.Substring(0, $idx).Trim()
      $v = $_.Substring($idx + 1).Trim()
      if ($k -eq 'DSH_DIR' -and $v -and -not $env:DSH_HOME) { $env:DSH_HOME = $v }
    }
  }
}

if (Test-Path -LiteralPath (Join-Path $Here 'node\node.exe')) {
  $env:PATH = (Join-Path $Here 'node') + ';' + $env:PATH
}
$dshCmd = Join-Path $Here 'node\dsh.cmd'
if (-not (Test-Path -LiteralPath $dshCmd)) {
  $found = Get-Command dsh -ErrorAction SilentlyContinue
  if ($found) { $dshCmd = $found.Source }
}
if (-not $dshCmd -or -not (Test-Path -LiteralPath $dshCmd)) {
  Write-Host '未找到 dsh 命令，请重新运行安装脚本 install.bat'
  exit 1
}

Write-Host "正在启动科研模式（http://127.0.0.1:$Port）..."

# 后台探测服务就绪后自动打开浏览器（与 dsh web 并行，互不阻塞）
$probe = Start-Job -ArgumentList $Port -ScriptBlock {
  param($p)
  $up = $false
  for ($i = 0; $i -lt 30; $i++) {
    try {
      $null = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$p/" -TimeoutSec 2
      $up = $true
      break
    } catch {
      Start-Sleep -Seconds 2
    }
  }
  Start-Process "http://127.0.0.1:$p"
  if (-not $up) {
    Write-Host '服务似乎未在 60 秒内就绪，请查看下方窗口的报错信息。'
  }
}

Write-Host '保持本窗口开启即可使用；关闭它（或按 Ctrl+C）即停止服务。'
& $dshCmd web --port $Port
$code = $LASTEXITCODE
Stop-Job $probe -ErrorAction SilentlyContinue
Remove-Job $probe -Force -ErrorAction SilentlyContinue
exit $code
