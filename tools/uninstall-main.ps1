# 科研模式卸载脚本主逻辑（由 uninstall.bat 调用）
# 兼容 Windows PowerShell 5.1；本文件由构建脚本统一加 UTF-8 BOM。

if ($env:DSH_HOME) { $DSH_DIR = $env:DSH_HOME } else { $DSH_DIR = Join-Path $env:USERPROFILE '.dsh' }
if ($env:BIORESEARCH_HOME) { $BR_HOME = $env:BIORESEARCH_HOME } else { $BR_HOME = Join-Path $env:USERPROFILE 'bioresearch' }

# 读取安装时记忆的路径（与安装脚本一致）
$PathMarker = Join-Path $env:USERPROFILE '.bioresearch-paths'
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

Write-Host '将删除：'
Write-Host "  1) 预设目录   $DSH_DIR\.agent-presets\bioresearch"
Write-Host "  2) 安装目录   $BR_HOME（含文献检索 MCP 与便携 Node）"
Write-Host '  3) 桌面「deepseek-dsh」快捷方式'
Write-Host ''
Write-Host "不受影响：工作区里的 research-log 研究日志、API Key（$DSH_DIR\.credentials.yaml）。"
$ok = Read-Host '确认卸载？[y/N]'
if ($ok -notmatch '^[yY]') { exit 0 }

Remove-Item -LiteralPath (Join-Path $DSH_DIR '.agent-presets\bioresearch') -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $BR_HOME -Recurse -Force -ErrorAction SilentlyContinue
$desktop = [Environment]::GetFolderPath('Desktop')
Remove-Item -LiteralPath (Join-Path $desktop 'deepseek-dsh.lnk') -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $desktop '科研模式.lnk') -Force -ErrorAction SilentlyContinue
if (Test-Path -LiteralPath (Join-Path $env:USERPROFILE 'OneDrive\Desktop')) {
  Remove-Item -LiteralPath (Join-Path $env:USERPROFILE 'OneDrive\Desktop\deepseek-dsh.lnk') -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath (Join-Path $env:USERPROFILE 'OneDrive\Desktop\科研模式.lnk') -Force -ErrorAction SilentlyContinue
}
Remove-Item -LiteralPath $PathMarker -Force -ErrorAction SilentlyContinue
Write-Host '已卸载。'
Write-Host '如需移除 DeepSeek Harness 本体，请在命令行运行：npm rm -g @deepseek-ai/dsh'
exit 0
