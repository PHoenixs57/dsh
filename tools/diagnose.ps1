# 科研模式诊断脚本：逐项检查安装组件并给出中文结论。
# 由 diagnose.bat 调用；兼容 Windows PowerShell 5.1（构建时加 UTF-8 BOM）。
Write-Host '================ 科研模式诊断 ================'
Write-Host ''

# ---------- 1. 路径记忆 ----------
$PathMarker = Join-Path $env:USERPROFILE '.bioresearch-paths'
$BR_HOME = $null
$DSH_DIR = $null
if ($env:BIORESEARCH_HOME) { $BR_HOME = $env:BIORESEARCH_HOME }
if ($env:DSH_HOME) { $DSH_DIR = $env:DSH_HOME }
if (Test-Path -LiteralPath $PathMarker) {
  Get-Content -LiteralPath $PathMarker | ForEach-Object {
    $idx = $_.IndexOf('=')
    if ($idx -gt 0) {
      $k = $_.Substring(0, $idx).Trim()
      $v = $_.Substring($idx + 1).Trim()
      if ($k -eq 'BR_HOME' -and $v -and -not $BR_HOME) { $BR_HOME = $v }
      if ($k -eq 'DSH_DIR' -and $v -and -not $DSH_DIR) { $DSH_DIR = $v }
    }
  }
}
if (-not $BR_HOME) { $BR_HOME = Join-Path $env:USERPROFILE 'bioresearch' }
if (-not $DSH_DIR) { $DSH_DIR = Join-Path $env:USERPROFILE '.dsh' }
Write-Host "[1] 安装目录   : $BR_HOME"
Write-Host "[1] DSH 数据目录: $DSH_DIR"
Write-Host ''

# ---------- 2. Node 与 dsh ----------
Write-Host '[2] Node.js / dsh：'
$node = Get-Command node -ErrorAction SilentlyContinue
if ($node) { Write-Host "    node: $($node.Source) $( (& $node.Source -v) )" } else { Write-Host '    node: 未找到（PATH 中无 node）' }
$dsh = Get-Command dsh -ErrorAction SilentlyContinue
$dshPath = $null
if ($dsh) { $dshPath = $dsh.Source } elseif (Test-Path (Join-Path $BR_HOME 'node\dsh.cmd')) { $dshPath = Join-Path $BR_HOME 'node\dsh.cmd' }
if ($dshPath) {
  $ver = (& $dshPath --version 2>$null | Out-String).Trim()
  Write-Host "    dsh : $dshPath ($ver)"
} else {
  Write-Host '    dsh : 未找到 —— 请重新运行 install.bat 安装'
}
Write-Host ''

# ---------- 3. 预设 ----------
Write-Host '[3] 科研模式预设：'
$presetFile = Join-Path $DSH_DIR '.agent-presets\bioresearch\agent.cordis.yml'
if (-not (Test-Path -LiteralPath $presetFile)) {
  Write-Host "    缺失: $presetFile"
  Write-Host '    → 请重新运行 install.bat（预设未安装或装到了别的目录）'
} else {
  $raw = [IO.File]::ReadAllText($presetFile)
  if ($raw -match '\{\{(NODE_PATH|MCP_SERVER_PATH)\}\}') {
    Write-Host '    存在但含未替换占位符（安装未完整执行）→ 请重新运行 install.bat'
  } else {
    Write-Host '    存在且路径已写入。关键行：'
    foreach ($line in $raw -split "`r?`n") {
      if ($line -match "^\s*(command|args):") { Write-Host "      $line".Trim() }
    }
  }
}
Write-Host ''

# ---------- 4. MCP ----------
Write-Host '[4] 文献检索 MCP：'
$mcpServer = Join-Path $BR_HOME 'literature-search-mcp\dist\server.js'
if (-not (Test-Path -LiteralPath $mcpServer)) {
  Write-Host "    缺失: $mcpServer → 请重新运行 install.bat"
} else {
  Write-Host "    存在: $mcpServer"
  $mcpNodeModules = Join-Path $BR_HOME 'literature-search-mcp\node_modules'
  if (-not (Test-Path -LiteralPath $mcpNodeModules)) {
    Write-Host '    依赖未安装（node_modules 缺失）→ 请重新运行 install.bat'
  } else {
    Write-Host '    依赖已安装。冒烟测试（启动 3 秒看是否存活）...'
    $errFile = Join-Path $env:TEMP 'bioresearch-mcp-smoke.log'
    Remove-Item -LiteralPath $errFile -Force -ErrorAction SilentlyContinue
    $proc = Start-Process -FilePath $node.Source -ArgumentList $mcpServer -NoNewWindow -PassThru -RedirectStandardError $errFile
    Start-Sleep -Seconds 3
    if ($proc.HasExited) {
      Write-Host '    MCP 启动即退出（异常）。stderr：'
      if (Test-Path -LiteralPath $errFile) { Get-Content -LiteralPath $errFile | ForEach-Object { Write-Host "      $_" } }
    } else {
      Write-Host '    MCP 进程存活，服务正常等待连接。'
      Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    }
  }
}
Write-Host ''

# ---------- 5. API Key 与端口 ----------
Write-Host '[5] 配置与端口：'
$credFile = Join-Path $DSH_DIR '.credentials.yaml'
if (Test-Path -LiteralPath $credFile) {
  Write-Host '    API Key 文件存在' + $(if ([IO.File]::ReadAllText($credFile) -match '(?m)^\s*DEEPSEEK_API_KEY\s*:') { '，且含 DEEPSEEK_API_KEY' } else { '，但无 DEEPSEEK_API_KEY 条目' })
} else {
  Write-Host '    API Key 文件缺失 → 打开网页后在 设置→模型 中填写'
}
$portInUse = Get-NetTCPConnection -LocalPort 3081 -State Listen -ErrorAction SilentlyContinue
if ($portInUse) {
  Write-Host "    端口 3081 已被占用（PID $($portInUse.OwningProcess)）→ 用 start.bat 3090 换端口"
} else {
  Write-Host '    端口 3081 空闲'
}
Write-Host ''
Write-Host '================ 诊断完成 ================'
Write-Host '若某项提示“请重新运行 install.bat”，解压最新安装包后双击 install.bat 即可修复。'
exit 0
