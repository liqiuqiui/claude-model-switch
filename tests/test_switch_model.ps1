# ============================================
# claude-switch-model.ps1 测试用例
# ============================================
# 使用 Pester 测试框架
# 安装: Install-Module -Name Pester -Force -Scope CurrentUser
# 运行: Invoke-Pester -Path tests/
# ============================================

BeforeAll {
    # 获取脚本目录（windows 子目录）并加载函数
    $ScriptDir = Join-Path (Split-Path -Parent $PSScriptRoot) "windows"
    . (Join-Path $ScriptDir "claude-switch-model.ps1")
}

AfterAll {
    # 清理环境变量
    Remove-Item Env:ANTHROPIC_BASE_URL -ErrorAction SilentlyContinue
    Remove-Item Env:ANTHROPIC_AUTH_TOKEN -ErrorAction SilentlyContinue
    Remove-Item Env:ANTHROPIC_DEFAULT_HAIKU_MODEL -ErrorAction SilentlyContinue
    Remove-Item Env:ANTHROPIC_DEFAULT_SONNET_MODEL -ErrorAction SilentlyContinue
    Remove-Item Env:ANTHROPIC_DEFAULT_OPUS_MODEL -ErrorAction SilentlyContinue
    Remove-Item Env:CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS -ErrorAction SilentlyContinue
}

# ============================================
# 测试：无参数时显示用法
# ============================================

Describe "Claude-SwitchModel 无参数测试" {
    It "无参数时显示用法提示" {
        $Output = Claude-SwitchModel 2>&1
        $Output | Should -Match "用法"
        $Output | Should -Match "Claude-SwitchModel"
    }
}

# ============================================
# 测试：切换 glm-5 模型
# ============================================

Describe "Claude-SwitchModel glm-5 测试" {
    BeforeEach {
        # 清理环境变量
        Remove-Item Env:ANTHROPIC_BASE_URL -ErrorAction SilentlyContinue
        Remove-Item Env:ANTHROPIC_AUTH_TOKEN -ErrorAction SilentlyContinue
        Remove-Item Env:ANTHROPIC_DEFAULT_HAIKU_MODEL -ErrorAction SilentlyContinue
        Remove-Item Env:ANTHROPIC_DEFAULT_SONNET_MODEL -ErrorAction SilentlyContinue
        Remove-Item Env:ANTHROPIC_DEFAULT_OPUS_MODEL -ErrorAction SilentlyContinue
        Remove-Item Env:CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS -ErrorAction SilentlyContinue
    }

    It "切换到 glm-5 模型成功" {
        $Output = Claude-SwitchModel "glm-5"
        $Output | Should -Match "已切换"
        $Output | Should -Match "glm-5"
        $Output | Should -Match "智谱 BigModel"
    }

    It "切换 glm-5 后环境变量正确设置" {
        Claude-SwitchModel "glm-5" | Out-Null

        $env:ANTHROPIC_BASE_URL | Should -Be "https://open.bigmodel.cn/api/anthropic"
        $env:ANTHROPIC_DEFAULT_HAIKU_MODEL | Should -Be "glm-5"
        $env:ANTHROPIC_DEFAULT_SONNET_MODEL | Should -Be "glm-5"
        $env:ANTHROPIC_DEFAULT_OPUS_MODEL | Should -Be "glm-5"
        $env:CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS | Should -Be "true"
    }
}

# ============================================
# 测试：切换 glm-4 模型
# ============================================

Describe "Claude-SwitchModel glm-4 测试" {
    BeforeEach {
        Remove-Item Env:ANTHROPIC_DEFAULT_HAIKU_MODEL -ErrorAction SilentlyContinue
        Remove-Item Env:ANTHROPIC_DEFAULT_SONNET_MODEL -ErrorAction SilentlyContinue
        Remove-Item Env:ANTHROPIC_DEFAULT_OPUS_MODEL -ErrorAction SilentlyContinue
    }

    It "切换到 glm-4 模型成功" {
        $Output = Claude-SwitchModel "glm-4"
        $Output | Should -Match "已切换"
        $Output | Should -Match "glm-4"
    }

    It "切换 glm-4 后环境变量正确设置" {
        Claude-SwitchModel "glm-4" | Out-Null

        $env:ANTHROPIC_DEFAULT_HAIKU_MODEL | Should -Be "glm-4"
        $env:ANTHROPIC_DEFAULT_SONNET_MODEL | Should -Be "glm-4"
        $env:ANTHROPIC_DEFAULT_OPUS_MODEL | Should -Be "glm-4"
    }
}

# ============================================
# 测试：切换大写模型名
# ============================================

Describe "Claude-SwitchModel 大写模型名测试" {
    It "GLM-5 大写模型名也能识别" {
        $Output = Claude-SwitchModel "GLM-5"
        $Output | Should -Match "智谱 BigModel"
    }

    It "GLM-5 大写模型名环境变量正确设置" {
        Claude-SwitchModel "GLM-5" | Out-Null
        $env:ANTHROPIC_DEFAULT_HAIKU_MODEL | Should -Be "GLM-5"
    }
}

# ============================================
# 测试：未知前缀模型
# ============================================

Describe "Claude-SwitchModel 未知前缀测试" {
    It "未知前缀模型使用默认服务商" {
        $Output = Claude-SwitchModel "unknown-model"
        $Output | Should -Match "智谱 BigModel (默认)"
    }

    It "未知模型环境变量正确设置" {
        Claude-SwitchModel "unknown-model" | Out-Null

        $env:ANTHROPIC_BASE_URL | Should -Be "https://open.bigmodel.cn/api/anthropic"
        $env:ANTHROPIC_DEFAULT_HAIKU_MODEL | Should -Be "unknown-model"
    }
}

# ============================================
# 测试：ANTHROPIC_AUTH_TOKEN 初始为空
# ============================================

Describe "ANTHROPIC_AUTH_TOKEN 测试" {
    It "ANTHROPIC_AUTH_TOKEN 初始为空" {
        Claude-SwitchModel "glm-5" | Out-Null
        $env:ANTHROPIC_AUTH_TOKEN | Should -Be ""
    }
}

# ============================================
# 测试：Claude-ListModels 命令
# ============================================

Describe "Claude-ListModels 测试" {
    It "显示可用模型列表" {
        $Output = Claude-ListModels
        $Output | Should -Match "可用的模型列表"
        $Output | Should -Match "glm-5"
        $Output | Should -Match "glm-4"
    }
}

# ============================================
# 测试：Claude-SetToken 命令
# ============================================

Describe "Claude-SetToken 测试" {
    It "无参数时显示用法" {
        $Output = Claude-SetToken 2>&1
        $Output | Should -Match "用法"
    }

    It "设置 token 成功" {
        $Output = Claude-SetToken "sk-test-token-123"
        $Output | Should -Match "已设置"
    }

    It "设置 token 后环境变量正确" {
        Claude-SetToken "sk-test-token-456" | Out-Null
        $env:ANTHROPIC_AUTH_TOKEN | Should -Be "sk-test-token-456"
    }
}

# ============================================
# 测试：多次切换模型
# ============================================

Describe "多次切换模型测试" {
    It "多次切换模型环境变量更新正确" {
        Claude-SwitchModel "glm-5" | Out-Null
        $env:ANTHROPIC_DEFAULT_HAIKU_MODEL | Should -Be "glm-5"

        Claude-SwitchModel "glm-4" | Out-Null
        $env:ANTHROPIC_DEFAULT_HAIKU_MODEL | Should -Be "glm-4"

        Claude-SwitchModel "glm-5-plus" | Out-Null
        $env:ANTHROPIC_DEFAULT_HAIKU_MODEL | Should -Be "glm-5-plus"
    }
}

# ============================================
# 测试：输出格式
# ============================================

Describe "输出格式测试" {
    It "输出包含警告提示" {
        $Output = Claude-SwitchModel "glm-5"
        $Output | Should -Match "ANTHROPIC_AUTH_TOKEN"
    }

    It "输出包含 Base URL" {
        $Output = Claude-SwitchModel "glm-5"
        $Output | Should -Match "Base URL"
        $Output | Should -Match "open.bigmodel.cn"
    }
}

# ============================================
# 测试：命令别名
# ============================================

Describe "命令别名测试" {
    It "csm 别名可用" {
        Get-Alias -Name "csm" | Should -Not -BeNullOrEmpty
    }

    It "clm 别名可用" {
        Get-Alias -Name "clm" | Should -Not -BeNullOrEmpty
    }

    It "cst 别名可用" {
        Get-Alias -Name "cst" | Should -Not -BeNullOrEmpty
    }

    It "csm 别名功能正确" {
        csm "glm-5" | Out-Null
        $env:ANTHROPIC_DEFAULT_HAIKU_MODEL | Should -Be "glm-5"
    }

    It "cst 别名功能正确" {
        cst "test-token" | Out-Null
        $env:ANTHROPIC_AUTH_TOKEN | Should -Be "test-token"
    }
}
