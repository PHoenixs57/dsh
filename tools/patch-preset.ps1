param(
  [Parameter(Mandatory = $true)][string]$PresetDir,
  [Parameter(Mandatory = $true)][string]$NodePath,
  [Parameter(Mandatory = $true)][string]$McpServerPath
)
$ErrorActionPreference = 'Stop'

$file = Join-Path $PresetDir 'agent.cordis.yml'
if (-not (Test-Path -LiteralPath $file)) {
  Write-Error "预设缺少 agent.cordis.yml: $file"
  exit 1
}

$raw = [IO.File]::ReadAllText($file)
$node = $NodePath.Replace("'", "''")
$mcp = $McpServerPath.Replace("'", "''")
$raw = $raw.Replace('{{NODE_PATH}}', $node).Replace('{{MCP_SERVER_PATH}}', $mcp)

# 只认大写占位符（我们自己的 NODE_PATH / MCP_SERVER_PATH）；DSH 人设里
# 合法的运行时模板 {{model}} / {{cwd}} 是小写，必须原样保留。
# -match 不区分大小写，必须用 -cmatch。
if ($raw -cmatch '\{\{[A-Z0-9_]+\}\}') {
  Write-Error "替换后仍存在未处理的占位符"
  exit 1
}

[IO.File]::WriteAllText($file, $raw, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "已写入预设路径: node=$NodePath mcp=$McpServerPath"
exit 0
