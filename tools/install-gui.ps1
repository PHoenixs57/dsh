# 科研模式图形化安装向导（由 install.bat 调用）。
# 原生 WinForms，零第三方依赖；兼容 Windows PowerShell 5.1（STA）。
# 本文件由构建脚本统一加 UTF-8 BOM。
# 注意：函数参数不能命名为 $Input（PowerShell 保留自动变量，永远绑定不到值）。
param()

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$CorePath = Join-Path $ScriptDir 'install-core.ps1'
$PathMarker = Join-Path $env:USERPROFILE '.bioresearch-paths'
$DSH_VERSION = '0.1.0-rc.6'

# ---------- 默认路径（环境变量 > 记忆 > 包所在盘符的 bioresearch） ----------
$pkgDrive = [string](Split-Path -Qualifier $ScriptDir)
$sysDrive = [string](Split-Path -Qualifier $env:SystemDrive)
$driveDefault = if ($pkgDrive.ToUpper() -ne $sysDrive.ToUpper()) { "$pkgDrive\bioresearch" } else { Join-Path $env:USERPROFILE 'bioresearch' }

if ($env:BIORESEARCH_HOME) { $DefBr = $env:BIORESEARCH_HOME } else { $DefBr = $driveDefault }
if ($env:DSH_HOME) { $DefDs = $env:DSH_HOME } else { $DefDs = Join-Path $env:USERPROFILE '.dsh' }
if (Test-Path -LiteralPath $PathMarker) {
  Get-Content -LiteralPath $PathMarker | ForEach-Object {
    $idx = $_.IndexOf('=')
    if ($idx -gt 0) {
      $k = $_.Substring(0, $idx).Trim()
      $v = $_.Substring($idx + 1).Trim()
      if ($k -eq 'BR_HOME' -and $v -and -not $env:BIORESEARCH_HOME) { $DefBr = $v }
      if ($k -eq 'DSH_DIR' -and $v -and -not $env:DSH_HOME) { $DefDs = $v }
    }
  }
}

function Resolve-PathInput([string]$PathText) {
  $p = $PathText.Trim().Trim('"').Trim("'")
  $p = $p -replace '：', ':' -replace '＋', '+'
  if ($p -eq '') { return $null }
  if ($p.StartsWith('~\') -or $p -eq '~') { $p = $env:USERPROFILE + $p.Substring(1) }
  $p = [Environment]::ExpandEnvironmentVariables($p)
  if ($p -notmatch '^[A-Za-z]:[\\/]' -and $p -notmatch '^\\\\') { return $null }
  return $p
}

function Pick-Folder([string]$Title, [string]$Initial) {
  try {
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = $Title
    $dlg.ShowNewFolderButton = $true
    if ($Initial -and (Test-Path -LiteralPath $Initial)) { $dlg.SelectedPath = $Initial }
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $dlg.SelectedPath }
  } catch {
  }
  return $null
}

# 检查给定路径下的安装是否已就绪且为最新版本
function Test-Installed([string]$br, [string]$ds) {
  # 返回 'installed' | 'stale' | 'none'
  if ([string]::IsNullOrWhiteSpace($br) -or [string]::IsNullOrWhiteSpace($ds)) { return 'none' }
  $preset = Join-Path $ds '.agent-presets\bioresearch\agent.cordis.yml'
  if (-not (Test-Path -LiteralPath $preset)) { return 'none' }
  $raw = [IO.File]::ReadAllText($preset)
  if ($raw -match '\{\{(NODE_PATH|MCP_SERVER_PATH)\}\}') { return 'none' }
  if (-not (Test-Path -LiteralPath (Join-Path $br 'literature-search-mcp\dist\server.js'))) { return 'none' }
  $dshPath = $null
  $dshFound = Get-Command dsh -ErrorAction SilentlyContinue
  if ($dshFound) { $dshPath = $dshFound.Source }
  elseif (Test-Path -LiteralPath (Join-Path $br 'node\dsh.cmd')) { $dshPath = Join-Path $br 'node\dsh.cmd' }
  if (-not $dshPath) { return 'none' }
  $ver = (& $dshPath --version 2>$null | Out-String).Trim()
  if ($ver -ne $DSH_VERSION) { return 'stale' }
  $settings = Join-Path $ds 'settings.yaml'
  if (-not (Test-Path -LiteralPath $settings)) { return 'stale' }
  $settingsText = [IO.File]::ReadAllText($settings)
  if ($settingsText -notmatch '(?m)^\s*default\s*:\s*bioresearch\s*$') { return 'stale' }
  return 'installed'
}

# ---------- 主题 ----------
$Accent = [System.Drawing.Color]::FromArgb(37, 99, 235)
$AccentDark = [System.Drawing.Color]::FromArgb(29, 78, 216)
$GrayText = [System.Drawing.Color]::FromArgb(107, 114, 128)
$FontBody = New-Object System.Drawing.Font('Microsoft YaHei UI', 9.5)
$FontTitle = New-Object System.Drawing.Font('Microsoft YaHei UI', 15, [System.Drawing.FontStyle]::Bold)
$FontSub = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)

# ---------- 窗口 ----------
$form = New-Object System.Windows.Forms.Form
$form.Text = '科研模式 · 安装向导'
$form.ClientSize = New-Object System.Drawing.Size(680, 640)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.BackColor = [System.Drawing.Color]::White

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = '科研模式 · 安装向导'
$lblTitle.Font = $FontTitle
$lblTitle.ForeColor = [System.Drawing.Color]::FromArgb(17, 24, 39)
$lblTitle.Location = New-Object System.Drawing.Point(24, 18)
$lblTitle.AutoSize = $true

$lblSub = New-Object System.Windows.Forms.Label
$lblSub.Text = '生物医学文献检索助手 · 本地一键安装（所有组件已装则自动跳过）'
$lblSub.Font = $FontSub
$lblSub.ForeColor = $GrayText
$lblSub.Location = New-Object System.Drawing.Point(26, 52)
$lblSub.AutoSize = $true

# ---------- 分组：安装位置 ----------
$grpPath = New-Object System.Windows.Forms.GroupBox
$grpPath.Text = '安装位置'
$grpPath.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10, [System.Drawing.FontStyle]::Bold)
$grpPath.Location = New-Object System.Drawing.Point(24, 84)
$grpPath.Size = New-Object System.Drawing.Size(632, 148)
$grpPath.BackColor = [System.Drawing.Color]::White

$lblBr = New-Object System.Windows.Forms.Label
$lblBr.Text = '安装目录（程序本体、文献检索 MCP、启动快捷方式）'
$lblBr.Location = New-Object System.Drawing.Point(20, 34)
$lblBr.AutoSize = $true
$lblBr.Font = $FontBody

$txtBr = New-Object System.Windows.Forms.TextBox
$txtBr.Location = New-Object System.Drawing.Point(20, 58)
$txtBr.Size = New-Object System.Drawing.Size(498, 26)
$txtBr.Text = $DefBr
$txtBr.Font = $FontBody

$btnBr = New-Object System.Windows.Forms.Button
$btnBr.Text = '选择文件夹…'
$btnBr.Location = New-Object System.Drawing.Point(528, 56)
$btnBr.Size = New-Object System.Drawing.Size(88, 30)
$btnBr.Font = $FontBody
$btnBr.Add_Click({
  $picked = Pick-Folder '选择「科研模式」安装目录' $txtBr.Text
  if ($picked) { $txtBr.Text = $picked }
})

$lblDs = New-Object System.Windows.Forms.Label
$lblDs.Text = 'DSH 数据目录（科研模式预设、API Key 存放处）'
$lblDs.Location = New-Object System.Drawing.Point(20, 96)
$lblDs.AutoSize = $true
$lblDs.Font = $FontBody

$txtDs = New-Object System.Windows.Forms.TextBox
$txtDs.Location = New-Object System.Drawing.Point(20, 120)
$txtDs.Size = New-Object System.Drawing.Size(498, 26)
$txtDs.Text = $DefDs
$txtDs.Font = $FontBody

$btnDs = New-Object System.Windows.Forms.Button
$btnDs.Text = '选择文件夹…'
$btnDs.Location = New-Object System.Drawing.Point(528, 118)
$btnDs.Size = New-Object System.Drawing.Size(88, 30)
$btnDs.Font = $FontBody
$btnDs.Add_Click({
  $picked = Pick-Folder '选择 DSH 数据目录' $txtDs.Text
  if ($picked) { $txtDs.Text = $picked }
})

$grpPath.Controls.AddRange(@($lblBr, $txtBr, $btnBr, $lblDs, $txtDs, $btnDs))

# ---------- 分组：组件与密钥 ----------
$grpOpts = New-Object System.Windows.Forms.GroupBox
$grpOpts.Text = '组件与密钥'
$grpOpts.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10, [System.Drawing.FontStyle]::Bold)
$grpOpts.Location = New-Object System.Drawing.Point(24, 244)
$grpOpts.Size = New-Object System.Drawing.Size(632, 148)
$grpOpts.BackColor = [System.Drawing.Color]::White

$chkDsh = New-Object System.Windows.Forms.CheckBox
$chkDsh.Text = '安装 / 更新 DeepSeek Harness（本机已装同版本时自动跳过）'
$chkDsh.Location = New-Object System.Drawing.Point(20, 32)
$chkDsh.AutoSize = $true
$chkDsh.Checked = $true
$chkDsh.Font = $FontBody

$chkPlugin = New-Object System.Windows.Forms.CheckBox
$chkPlugin.Text = '安装「科研模式」插件（预设 + 文献检索 MCP + 设为默认模式）'
$chkPlugin.Location = New-Object System.Drawing.Point(20, 60)
$chkPlugin.AutoSize = $true
$chkPlugin.Checked = $true
$chkPlugin.Font = $FontBody

$lblKey = New-Object System.Windows.Forms.Label
$lblKey.Text = 'DeepSeek API Key（选填，之后也可在网页 设置→模型 中填写）'
$lblKey.Location = New-Object System.Drawing.Point(20, 92)
$lblKey.AutoSize = $true
$lblKey.Font = $FontBody

$txtKey = New-Object System.Windows.Forms.TextBox
$txtKey.Location = New-Object System.Drawing.Point(20, 116)
$txtKey.Size = New-Object System.Drawing.Size(596, 26)
$txtKey.UseSystemPasswordChar = $true
$txtKey.Font = $FontBody

$grpOpts.Controls.AddRange(@($chkDsh, $chkPlugin, $lblKey, $txtKey))

# ---------- 进度区 ----------
$btnInstall = New-Object System.Windows.Forms.Button
$btnInstall.Text = '开始安装'
$btnInstall.Location = New-Object System.Drawing.Point(24, 410)
$btnInstall.Size = New-Object System.Drawing.Size(190, 42)
$btnInstall.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 11, [System.Drawing.FontStyle]::Bold)
$btnInstall.FlatStyle = 'Flat'
$btnInstall.FlatAppearance.BorderSize = 0
$btnInstall.BackColor = $Accent
$btnInstall.ForeColor = [System.Drawing.Color]::White
$btnInstall.Cursor = 'Hand'
$btnInstall.Add_MouseEnter({ $btnInstall.BackColor = $AccentDark })
$btnInstall.Add_MouseLeave({ $btnInstall.BackColor = $Accent })

$btnLaunch = New-Object System.Windows.Forms.Button
$btnLaunch.Text = '启动 DSH'
$btnLaunch.Location = New-Object System.Drawing.Point(226, 410)
$btnLaunch.Size = New-Object System.Drawing.Size(220, 42)
$btnLaunch.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10)
$btnLaunch.FlatStyle = 'Flat'
$btnLaunch.Enabled = $false
$btnLaunch.Add_Click({
  $br = Resolve-PathInput $txtBr.Text
  if ($null -eq $br) { [void][System.Windows.Forms.MessageBox]::Show('安装目录无效，请重新选择。', '科研模式安装向导', 'OK', 'Warning'); return }
  $startBat = Join-Path $br 'start.bat'
  if (-not (Test-Path -LiteralPath $startBat)) {
    [void][System.Windows.Forms.MessageBox]::Show("未找到 $startBat，请先完成安装。", '科研模式安装向导', 'OK', 'Warning')
    return
  }
  $lblStatus.Text = '已启动 DSH，浏览器将打开 http://127.0.0.1:3081'
  Start-Process -FilePath $startBat
})

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = '退出'
$btnClose.Location = New-Object System.Drawing.Point(612, 410)
$btnClose.Size = New-Object System.Drawing.Size(64, 42)
$btnClose.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10)
$btnClose.FlatStyle = 'Flat'
$btnClose.Add_Click({ $form.Close() })

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = '检查安装状态…'
$lblStatus.ForeColor = $GrayText
$lblStatus.Location = New-Object System.Drawing.Point(26, 458)
$lblStatus.Size = New-Object System.Drawing.Size(648, 20)
$lblStatus.Font = $FontBody

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object System.Drawing.Point(24, 480)
$progress.Size = New-Object System.Drawing.Size(652, 8)
$progress.Style = 'Marquee'
$progress.MarqueeAnimationSpeed = 24
$progress.Visible = $false

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Location = New-Object System.Drawing.Point(24, 496)
$txtLog.Size = New-Object System.Drawing.Size(652, 126)
$txtLog.Multiline = $true
$txtLog.ReadOnly = $true
$txtLog.ScrollBars = 'Vertical'
$txtLog.BackColor = [System.Drawing.Color]::FromArgb(248, 250, 252)
$txtLog.Font = New-Object System.Drawing.Font('Consolas', 9)

$form.Controls.AddRange(@($lblTitle, $lblSub, $grpPath, $grpOpts,
  $btnInstall, $btnLaunch, $btnClose, $lblStatus, $progress, $txtLog))

# ---------- 安装执行 ----------
$script:installJob = $null
$script:jobExit = $null
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 200

function Append-Log([string]$text) {
  if (-not [string]::IsNullOrEmpty($text)) {
    $txtLog.AppendText($text.Replace("`r", '').TrimEnd() + "`r`n")
    $txtLog.SelectionStart = $txtLog.TextLength
    $txtLog.ScrollToCaret()
  }
}

function Set-Running([bool]$running) {
  $btnInstall.Enabled = -not $running
  $btnLaunch.Enabled = -not $running
  $btnClose.Enabled = -not $running
  $chkDsh.Enabled = -not $running
  $chkPlugin.Enabled = -not $running
  $txtBr.Enabled = -not $running
  $txtDs.Enabled = -not $running
  $btnBr.Enabled = -not $running
  $btnDs.Enabled = -not $running
  $txtKey.Enabled = -not $running
  $progress.Visible = $running
  if ($running) { $lblStatus.Text = '安装中，请稍候…' }
}

function Receive-InstallJobOutput {
  $receiveErrors = @()
  foreach ($line in @(Receive-Job -Job $script:installJob -ErrorAction SilentlyContinue -ErrorVariable receiveErrors)) {
    if ($line -match '^BIORESEARCH_EXIT=(\d+)$') { $script:jobExit = [int]$Matches[1]; continue }
    Append-Log ([string]$line)
  }
  foreach ($jobError in $receiveErrors) {
    Append-Log ("[错误] " + $jobError.Exception.Message)
  }
}

# 依据当前路径刷新「已安装 / 可更新 / 未安装」状态
function Update-InstallState {
  if ($null -ne $script:installJob -and $script:installJob.State -eq 'Running') { return }
  $br = Resolve-PathInput $txtBr.Text
  $ds = Resolve-PathInput $txtDs.Text
  if ($null -eq $br -or $null -eq $ds) {
    $lblStatus.Text = '请填写安装位置后开始安装'
    $btnInstall.Enabled = $true
    $btnInstall.Text = '开始安装'
    $btnLaunch.Enabled = $false
    return
  }
  $state = Test-Installed $br $ds
  switch ($state) {
    'installed' {
      $lblStatus.Text = "已安装（$DSH_VERSION），无需重复安装"
      $btnInstall.Enabled = $false
      $btnInstall.Text = '已安装 · 无需重复安装'
      $btnLaunch.Enabled = $true
    }
    'stale' {
      $lblStatus.Text = '检测到旧版本或配置不完整，可更新'
      $btnInstall.Enabled = $true
      $btnInstall.Text = '更新安装'
      $btnLaunch.Enabled = $true
    }
    default {
      $lblStatus.Text = '未安装，点击「开始安装」'
      $btnInstall.Enabled = $true
      $btnInstall.Text = '开始安装'
      $btnLaunch.Enabled = $false
    }
  }
}

$btnInstall.Add_Click({
  $br = Resolve-PathInput $txtBr.Text
  $ds = Resolve-PathInput $txtDs.Text
  if ($null -eq $br) { [void][System.Windows.Forms.MessageBox]::Show('安装目录无效：请填写绝对路径（如 D:\bioresearch），或点「选择文件夹…」', '科研模式安装向导', 'OK', 'Warning'); return }
  if ($null -eq $ds) { [void][System.Windows.Forms.MessageBox]::Show('DSH 数据目录无效：请填写绝对路径，或点「选择文件夹…」', '科研模式安装向导', 'OK', 'Warning'); return }

  $txtLog.Clear()
  Set-Running $true
  $noDsh = -not $chkDsh.Checked
  $skipPlugin = -not $chkPlugin.Checked
  $key = $txtKey.Text.Trim()
  $noKey = [string]::IsNullOrWhiteSpace($key)

  $script:jobExit = $null
  $script:installJob = Start-Job -Name 'bioresearch-install' -ScriptBlock {
    param($core, $br, $ds, $noDsh, $skipPlugin, $key, $noKey)
    & $core -BR_HOME $br -DSH_DIR $ds -NoDshInstall:$noDsh -SkipPlugin:$skipPlugin `
      -ApiKey $key -NoKey:$noKey -NoLaunch `
      -Log { param($m) Write-Output $m }
    Write-Output ("BIORESEARCH_EXIT=" + $LASTEXITCODE)
  } -ArgumentList $CorePath, $br, $ds, $noDsh, $skipPlugin, $key, $noKey

  $timer.Start()
})

$timer.Add_Tick({
  if ($null -eq $script:installJob) { return }
  Receive-InstallJobOutput
  if ($script:installJob.State -eq 'Running') { return }

  $timer.Stop()
  Receive-InstallJobOutput
  $exitCode = if ($null -ne $script:jobExit) { $script:jobExit } else { 1 }
  Remove-Job -Job $script:installJob -Force -ErrorAction SilentlyContinue
  $script:installJob = $null
  Set-Running $false

  if ($exitCode -eq 0) {
    Update-InstallState
    $answer = [System.Windows.Forms.MessageBox]::Show(
      '安装完成！已在桌面创建「deepseek-dsh」快捷方式（DeepSeek 图标）。是否立即启动 DSH 并打开网页（http://127.0.0.1:3081）？',
      '科研模式安装向导', 'YesNo', 'Question')
    if ($answer -eq 'Yes') {
      Start-Process -FilePath (Join-Path $txtBr.Text.Trim() 'start.bat')
    }
  } else {
    $lblStatus.Text = '安装失败（退出码 ' + $exitCode + '），请查看下方日志'
    [void][System.Windows.Forms.MessageBox]::Show(
      "安装未完成。请查看下方日志，重试请点「开始安装」。",
      '科研模式安装向导', 'OK', 'Error')
  }
})

$form.Add_FormClosing({
  param($sender, $e)
  if ($null -ne $script:installJob -and $script:installJob.State -eq 'Running') {
    [void][System.Windows.Forms.MessageBox]::Show('安装正在进行中，请等待完成后再退出。', '科研模式安装向导', 'OK', 'Information')
    $e.Cancel = $true
  }
})

$form.Add_Shown({ $form.Activate() })
$txtBr.Add_TextChanged({ Update-InstallState })
$txtDs.Add_TextChanged({ Update-InstallState })
Update-InstallState
[void]$form.ShowDialog()
