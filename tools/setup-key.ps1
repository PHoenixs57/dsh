param(
  [Parameter(Mandatory = $true)][string]$DshDir,
  [string]$Key = ''
)
$ErrorActionPreference = 'Stop'

$credFile = Join-Path $DshDir '.credentials.yaml'

if (Test-Path -LiteralPath $credFile) {
  $existing = [IO.File]::ReadAllText($credFile)
  if ($existing -match '(?m)^\s*DEEPSEEK_API_KEY\s*:') {
    Write-Host "检测到已配置 DeepSeek API Key（$credFile），跳过。"
    exit 2
  }
}

if ($Key -ne '') {
  # 非交互模式（GUI 传入）：直接用给定 Key
  $key = $Key
} else {
  $choice = Read-Host "是否现在输入 DeepSeek API Key？[y/N]"
  if ($choice -notmatch '^[yY]') {
    Write-Host "跳过。之后可在网页 设置→模型 中填写。"
    exit 2
  }

  $sec = Read-Host "请输入 DeepSeek API Key（输入不回显）" -AsSecureString
  $key = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
  if ([string]::IsNullOrWhiteSpace($key)) {
    Write-Host "输入为空，跳过。之后可在网页 设置→模型 中填写。"
    exit 2
  }
}

# 校验 Key：调用 DeepSeek 的 /models 端点（401/403 = Key 无效）
try {
  $null = Invoke-WebRequest -UseBasicParsing -Uri 'https://api.deepseek.com/models' -Headers @{ Authorization = "Bearer $key" } -TimeoutSec 20
} catch {
  $resp = $_.Exception.Response
  if ($resp -ne $null -and $resp.StatusCode -eq [System.Net.HttpStatusCode]::Unauthorized) {
    Write-Host "Key 校验失败（HTTP 401）。请确认 Key 正确后重跑本脚本，或在网页 设置→模型 中填写。"
    exit 3
  }
  Write-Host "无法连接 api.deepseek.com（网络受限或请求失败）。Key 未写入；之后可在网页 设置→模型 中填写。"
  exit 4
}

$line = "DEEPSEEK_API_KEY: $key"
if (Test-Path -LiteralPath $credFile) {
  $content = [IO.File]::ReadAllText($credFile)
  if (-not $content.EndsWith("`n")) { $line = "`n" + $line }
  [IO.File]::AppendAllText($credFile, $line, (New-Object System.Text.UTF8Encoding($false)))
} else {
  New-Item -ItemType Directory -Force -Path $DshDir | Out-Null
  [IO.File]::WriteAllText($credFile, $line + "`n", (New-Object System.Text.UTF8Encoding($false)))
}
Write-Host "API Key 已保存到 $credFile"
exit 0
