param(
  [Parameter(Mandatory = $true)][string]$DshDir
)
# 把「科研模式」写为 DSH 的默认会话模式（settings.yaml 的 agent-presets.default）。
# 文本级 upsert：保留其他设置内容与已有 default 之外的结构；DSH 会热加载外部修改。
$ErrorActionPreference = 'Stop'
$file = Join-Path $DshDir 'settings.yaml'

$content = if (Test-Path -LiteralPath $file) { [IO.File]::ReadAllText($file) } else { '' }
$lines = @($content -split "`r?`n")
if ($lines.Count -eq 1 -and $lines[0] -eq '') { $lines = @() }

$found = -1
$done = $false
$out = New-Object System.Collections.Generic.List[string]
for ($i = 0; $i -lt $lines.Count; $i++) {
  $line = $lines[$i]
  if ($line -match '^\s*agent-presets\s*:') {
    $found = $i
    $out.Add('agent-presets:')
    continue
  }
  if ($found -ge 0 -and -not $done -and $line -match '^\s*default\s*:') {
    $out.Add('  default: bioresearch')
    $done = $true
    continue
  }
  if ($found -ge 0 -and -not $done -and $line -match '^[^\s]') {
    $out.Add('  default: bioresearch')
    $done = $true
  }
  $out.Add($line)
}
if ($found -lt 0) {
  $out.Add('agent-presets:')
  $out.Add('  default: bioresearch')
  $done = $true
} elseif (-not $done) {
  $out.Add('  default: bioresearch')
}

$text = ($out -join "`r`n") + "`r`n"
[IO.File]::WriteAllText($file, $text, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "已将「科研模式」设为默认会话模式（$file，可在网页 设置 中更改）"
exit 0
