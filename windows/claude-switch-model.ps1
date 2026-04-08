# ============================================
# Claude 模型切换器 - PowerShell 版本
# 用于快速切换 Claude Code 使用的模型
# ============================================
# 使用方法：
#   . 此文件或添加到 PowerShell 配置文件中
#   然后执行: Claude-SwitchModel <模型名称>
# ============================================

# 切换 Claude 模型
# 参数: $ModelName - 模型名称 (如 glm-5, glm-4)
function Claude-SwitchModel {
    param(
        [Parameter(Mandatory=$false, Position=0)]
        [string]$ModelName
    )

    # 参数检查
    if ([string]::IsNullOrEmpty($ModelName)) {
        Write-Host "用法: Claude-SwitchModel <模型名称>"
        Write-Host "示例: Claude-SwitchModel glm-5"
        return
    }

    # ============================================
    # 服务商配置
    # 根据模型前缀匹配对应的服务商
    # 添加新服务商时，在此处添加 switch 分支
    # ============================================
    $BaseUrl = ""
    $Provider = ""

    switch -Regex ($ModelName) {
        # 智谱 AI BigModel 服务
        "^glm-" {
            $Provider = "智谱 BigModel"
            $BaseUrl = "https://open.bigmodel.cn/api/anthropic"
            break
        }

        # 未来可扩展的服务商示例：
        # OpenAI 服务
        # "^openai-" {
        #     $Provider = "OpenAI"
        #     $BaseUrl = "https://api.openai.com/v1"
        #     break
        # }
        #
        # DeepSeek 服务
        # "^deepseek-" {
        #     $Provider = "DeepSeek"
        #     $BaseUrl = "https://api.deepseek.com"
        #     break
        # }

        # 未知前缀默认使用智谱 BigModel
        default {
            $Provider = "智谱 BigModel (默认)"
            $BaseUrl = "https://open.bigmodel.cn/api/anthropic"
        }
    }

    # ============================================
    # 设置环境变量
    # 这些变量会被 Claude Code 读取使用
    # ============================================

    # API 基础地址
    $env:ANTHROPIC_BASE_URL = $BaseUrl

    # API 认证令牌（需要用户手动配置）
    $env:ANTHROPIC_AUTH_TOKEN = ""

    # 模型配置 - 统一使用指定的模型
    $env:ANTHROPIC_DEFAULT_HAIKU_MODEL = $ModelName
    $env:ANTHROPIC_DEFAULT_SONNET_MODEL = $ModelName
    $env:ANTHROPIC_DEFAULT_OPUS_MODEL = $ModelName

    # 启用 Agent Teams 实验性功能
    $env:CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "true"

    # 输出切换结果
    Write-Host "✓ 已切换 Claude 模型"
    Write-Host "  模型: $ModelName"
    Write-Host "  服务商: $Provider"
    Write-Host "  Base URL: $BaseUrl"
    Write-Host ""
    Write-Host "⚠ 请确保已设置 ANTHROPIC_AUTH_TOKEN 环境变量"
}

# 列出可用的模型
function Claude-ListModels {
    Write-Host "可用的模型列表："
    Write-Host "  glm-5    - GLM-5 (智谱 BigModel)"
    Write-Host "  glm-4    - GLM-4 (智谱 BigModel)"
    Write-Host ""
    Write-Host "提示：可在 claude-switch-model.ps1 中添加更多模型配置"
}

# 设置 API Token
# 参数: $Token - API Token 值
function Claude-SetToken {
    param(
        [Parameter(Mandatory=$false, Position=0)]
        [string]$Token
    )

    if ([string]::IsNullOrEmpty($Token)) {
        Write-Host "用法: Claude-SetToken <your-api-token>"
        Write-Host "示例: Claude-SetToken sk-xxxxxxxx"
        return
    }

    $env:ANTHROPIC_AUTH_TOKEN = $Token
    Write-Host "✓ 已设置 ANTHROPIC_AUTH_TOKEN"
}

# 别名（简化命令）
Set-Alias -Name csm -Value Claude-SwitchModel
Set-Alias -Name clm -Value Claude-ListModels
Set-Alias -Name cst -Value Claude-SetToken
