param(
  [Parameter(Mandatory = $true)][string]$Name,
  [Parameter(Mandatory = $true)][string]$TargetPath,
  [Parameter(Mandatory = $true)][string]$WorkingDirectory,
  [string]$IconPath = ''
)
$ErrorActionPreference = 'Stop'

$desktop = [Environment]::GetFolderPath('Desktop')
$lnkPath = Join-Path $desktop ($Name + '.lnk')
$ws = New-Object -ComObject WScript.Shell
$lnk = $ws.CreateShortcut($lnkPath)
$lnk.TargetPath = $TargetPath
$lnk.WorkingDirectory = $WorkingDirectory
$lnk.Description = 'DeepSeek Harness 科研模式（生物医学文献检索助手）'
if ($IconPath -ne '' -and (Test-Path -LiteralPath $IconPath)) {
  $lnk.IconLocation = "$IconPath,0"
}
$lnk.Save()
Write-Host "已创建桌面快捷方式: $lnkPath"
exit 0
