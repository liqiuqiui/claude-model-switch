# ============================================
# Claude 模型切换器 - PowerShell 安装脚本
# ============================================
# 使用方法:
#   Invoke-Expression (Invoke-WebRequest -Uri "<安装地址>/install.ps1").Content
#
# 或者:
#   iwr -useb <安装地址>/install.ps1 | iex
#
# 安装流程:
#   1. 检测 PowerShell 配置文件路径
#   2. 下载脚本文件到本地
#   3. 添加 source 配置到 PowerShell 配置文件
# ============================================

# ============================================
# 配置项（发布前请修改）
# ============================================
# 脚本托管的仓库地址（GitHub Raw 或其他可访问的 URL）
# 发布到 GitHub 时，将 liqiuqiui 改为你的用户名
$RepoUrl = "https://raw.githubusercontent.com/liqiuqiui/claude-model-switch/main/windows"

# 脚本文件名
$ScriptName = "claude-switch-model.ps1"

# 本地安装目录
$InstallDir = Join-Path $env:USERPROFILE ".claude-switch-model"

# ============================================
# 颜色输出函数
# ============================================
function Write-Success {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Green
}

function Write-ColorWarning {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Yellow
}

function Write-ColorError {
    param([string]$Message)
    Write-Host "错误: $Message" -ForegroundColor Red
}

# ============================================
# 主安装流程
# ============================================

Write-Success "Claude 模型切换器 安装程序"
Write-Host ""

# 获取 PowerShell 配置文件路径
$ProfilePath = $PROFILE.CurrentUserAllHosts
if ([string]::IsNullOrEmpty($ProfilePath)) {
    $ProfilePath = Join-Path $env:USERPROFILE "Documents\PowerShell\profile.ps1"
}

Write-Host "检测到 PowerShell 配置文件: $ProfilePath"
Write-Host ""

# 创建安装目录
Write-Host "创建安装目录: $InstallDir"
if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

# 下载脚本文件
Write-Host "正在下载脚本文件..."
$ScriptPath = Join-Path $InstallDir $ScriptName

try {
    # 使用 .NET 的 WebClient 进行下载（更兼容）
    $WebClient = New-Object System.Net.WebClient
    $DownloadUrl = "$RepoUrl/$ScriptName"
    $WebClient.DownloadFile($DownloadUrl, $ScriptPath)
    Write-Host "脚本下载完成"
}
catch {
    Write-ColorError "脚本下载失败: $_"
    Write-Host "请检查网络连接或仓库地址"
    exit 1
}

# 验证下载是否成功
if (-not (Test-Path $ScriptPath)) {
    Write-ColorError "脚本下载失败，请检查网络连接或仓库地址"
    exit 1
}

# 安装标记（用于检测和卸载）
$MarkerStart = "# Claude 模型切换器 - 开始"
$MarkerEnd = "# Claude 模型切换器 - 结束"

# 确保 PowerShell 配置文件目录存在
$ProfileDir = Split-Path $ProfilePath -Parent
if (-not (Test-Path $ProfileDir)) {
    New-Item -ItemType Directory -Path $ProfileDir -Force | Out-Null
}

# 确保 PowerShell 配置文件存在
if (-not (Test-Path $ProfilePath)) {
    New-Item -ItemType File -Path $ProfilePath -Force | Out-Null
}

# 读取现有配置文件内容
$ProfileContent = Get-Content $ProfilePath -Raw -ErrorAction SilentlyContinue

# 检查是否已安装，如果已安装则先移除旧版本
if ($ProfileContent -match [regex]::Escape($MarkerStart)) {
    Write-ColorWarning "检测到已安装旧版本，正在更新..."
    # 删除旧的安装配置
    $Pattern = "(?s)$([regex]::Escape($MarkerStart))[\s\S]*?$([regex]::Escape($MarkerEnd))"
    $ProfileContent = $ProfileContent -replace $Pattern, ""
}

# 添加配置到 PowerShell 配置文件
Write-Host "正在配置 PowerShell..."
$NewContent = @"

$MarkerStart
# 以下内容由 Claude 模型切换器安装程序自动添加
. "$ScriptPath"
$MarkerEnd
"@

# 写入配置文件
$ProfileContent + $NewContent | Set-Content $ProfilePath -NoNewline

# ============================================
# 安装完成提示
# ============================================
Write-Host ""
Write-Success "✓ 安装完成！"
Write-Host ""
Write-Host "请执行以下命令使配置生效："
Write-Host "  . `$PROFILE" -ForegroundColor Yellow
Write-Host ""
Write-Host "或者重新打开 PowerShell 终端"
Write-Host ""
Write-Host "然后即可使用以下命令："
Write-Host "  Claude-SwitchModel glm-5    # 切换到 GLM-5 模型"
Write-Host "  Claude-SwitchModel glm-4    # 切换到 GLM-4 模型"
Write-Host "  Claude-ListModels           # 列出所有可用模型"
Write-Host "  Claude-SetToken <token>     # 设置 API Token"
Write-Host ""
Write-Host "简化命令别名："
Write-Host "  csm    - Claude-SwitchModel"
Write-Host "  clm    - Claude-ListModels"
Write-Host "  cst    - Claude-SetToken"
Write-Host ""
Write-ColorWarning "注意：首次使用前需要设置 ANTHROPIC_AUTH_TOKEN 环境变量"
Write-ColorWarning "可以通过 Claude-SetToken 命令或直接设置 `$env:ANTHROPIC_AUTH_TOKEN"
