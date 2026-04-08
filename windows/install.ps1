# ============================================
# Claude Switcher - PowerShell 安装脚本
# ============================================
# 使用方法:
#   Invoke-Expression (Invoke-WebRequest -Uri "<安装地址>/install.ps1").Content
#
# 或者:
#   iwr -useb <安装地址>/install.ps1 | iex
#
# 安装流程:
#   1. 检测 PowerShell 配置文件路径
#   2. 下载主脚本到本地
#   3. 添加 source 配置到 PowerShell profile
#   4. 提示用户下一步操作
# ============================================

# ============================================
# 配置项（发布前请修改）
# ============================================
$RepoUrl    = "https://raw.githubusercontent.com/liqiuqiui/claude-model-switch/main/windows"
$ScriptName = "claude-switcher.ps1"
$InstallDir = Join-Path $env:USERPROFILE ".claude-switcher"

# ============================================
# 颜色输出函数
# ============================================
function Write-Success { param([string]$Msg) Write-Host $Msg -ForegroundColor Green }
function Write-Warn    { param([string]$Msg) Write-Host $Msg -ForegroundColor Yellow }
function Write-Err     { param([string]$Msg) Write-Host "错误: $Msg" -ForegroundColor Red }

# ============================================
# 主安装流程
# ============================================

Write-Host "Claude Switcher 安装程序" -ForegroundColor White
Write-Host ""

# 获取 PowerShell profile 路径
$ProfilePath = $PROFILE.CurrentUserAllHosts
if ([string]::IsNullOrEmpty($ProfilePath)) {
    $ProfilePath = Join-Path $env:USERPROFILE "Documents\PowerShell\profile.ps1"
}
Write-Host "检测到 PowerShell profile: $ProfilePath"

# 创建安装目录（同时初始化 providers 子目录）
Write-Host "创建安装目录: $InstallDir"
@($InstallDir, (Join-Path $InstallDir "providers")) | ForEach-Object {
    if (-not (Test-Path $_)) { New-Item -ItemType Directory -Path $_ -Force | Out-Null }
}

# 下载主脚本
Write-Host "正在下载脚本文件..."
$ScriptPath  = Join-Path $InstallDir $ScriptName
$DownloadUrl = "$RepoUrl/$ScriptName"

try {
    $WebClient = New-Object System.Net.WebClient
    $WebClient.DownloadFile($DownloadUrl, $ScriptPath)
    Write-Host "脚本下载完成"
} catch {
    Write-Err "脚本下载失败: $_"
    Write-Host "请检查网络连接或仓库地址"
    exit 1
}

if (-not (Test-Path $ScriptPath)) {
    Write-Err "脚本下载失败，请检查网络连接或仓库地址"
    exit 1
}

# 安装标记（用于后续更新和卸载定位）
$MarkerStart = "# Claude Switcher - 开始"
$MarkerEnd   = "# Claude Switcher - 结束"

# 确保 profile 目录和文件存在
$ProfileDir = Split-Path $ProfilePath -Parent
if (-not (Test-Path $ProfileDir)) { New-Item -ItemType Directory -Path $ProfileDir -Force | Out-Null }
if (-not (Test-Path $ProfilePath)) { New-Item -ItemType File -Path $ProfilePath -Force | Out-Null }

# 若已安装旧版本，先移除
$ProfileContent = Get-Content $ProfilePath -Raw -ErrorAction SilentlyContinue
if ($ProfileContent -and $ProfileContent -match [regex]::Escape($MarkerStart)) {
    Write-Warn "检测到已安装旧版本，正在更新..."
    $Pattern        = "(?s)$([regex]::Escape($MarkerStart))[\s\S]*?$([regex]::Escape($MarkerEnd))"
    $ProfileContent = $ProfileContent -replace $Pattern, ""
} else {
    $ProfileContent = if ($ProfileContent) { $ProfileContent } else { "" }
}

# 注入 source 配置
Write-Host "正在配置 PowerShell..."
$NewBlock = @"

$MarkerStart
# 以下内容由 Claude Switcher 安装程序自动添加，请勿手动修改
. "$ScriptPath"
$MarkerEnd
"@

[System.IO.File]::WriteAllText($ProfilePath, $ProfileContent + $NewBlock)

# ============================================
# 安装完成 + 下一步引导
# ============================================
Write-Host ""
Write-Success "✓ 安装完成！"
Write-Host ""
Write-Host "请按以下步骤开始使用:" -ForegroundColor White
Write-Host ""
Write-Host "  第 1 步: 重新加载 PowerShell profile" -ForegroundColor White
Write-Host "    . `$PROFILE" -ForegroundColor Yellow
Write-Host "    或者重新打开 PowerShell 终端"
Write-Host ""
Write-Host "  第 2 步: 添加你的第一个服务商（交互式引导）" -ForegroundColor White
Write-Host "    claude-switcher --add <id>" -ForegroundColor Yellow
Write-Host "    例如: claude-switcher --add zhipu"
Write-Host ""
Write-Host "  第 3 步: 切换到该服务商" -ForegroundColor White
Write-Host "    claude-switcher --use <id>" -ForegroundColor Yellow
Write-Host ""
Write-Host "  完成后 Claude Code 将自动使用你配置的模型。"
Write-Host ""
Write-Host "  运行 claude-switcher --help 查看所有可用命令。" -ForegroundColor Yellow
