# ============================================
# install.ps1 测试用例
# ============================================
# 使用 Pester 测试框架
# 安装: Install-Module -Name Pester -Force -Scope CurrentUser
# 运行: Invoke-Pester -Path tests/
# ============================================

BeforeAll {
    # 获取脚本目录（windows 子目录）
    $ScriptDir = Join-Path (Split-Path -Parent $PSScriptRoot) "windows"
    $InstallScript = Join-Path $ScriptDir "install.ps1"
    $SwitchModelScript = Join-Path $ScriptDir "claude-switch-model.ps1"

    # 创建临时测试目录
    $TestDir = Join-Path $env:TEMP "claude-switch-model-test-$(Get-Random)"
    New-Item -ItemType Directory -Path $TestDir -Force | Out-Null

    # 模拟 HOME 目录
    $MockHome = Join-Path $TestDir "home"
    New-Item -ItemType Directory -Path $MockHome -Force | Out-Null

    # 模拟安装目录
    $InstallDir = Join-Path $MockHome ".claude-switch-model"
}

AfterAll {
    # 清理临时目录
    if (Test-Path $TestDir) {
        Remove-Item -Path $TestDir -Recurse -Force
    }
}

# ============================================
# 测试：脚本文件存在
# ============================================

Describe "脚本文件检查" {
    It "install.ps1 文件存在" {
        Test-Path $InstallScript | Should -Be $true
    }

    It "claude-switch-model.ps1 文件存在" {
        Test-Path $SwitchModelScript | Should -Be $true
    }
}

# ============================================
# 测试：PowerShell 配置文件检测
# ============================================

Describe "PowerShell 配置文件检测" {
    BeforeEach {
        # 保存原始环境
        $OriginalProfile = $PROFILE
    }

    AfterEach {
        # 恢复原始环境
        $PROFILE = $OriginalProfile
    }

    It "能正确识别 PowerShell 配置文件路径" {
        # 默认配置文件路径应该存在或可创建
        $ProfilePath = $PROFILE.CurrentUserAllHosts
        $ProfileDir = Split-Path $ProfilePath -Parent

        # 验证路径格式正确
        $ProfilePath | Should -Match "profile\.ps1$"
    }
}

# ============================================
# 测试：安装目录创建
# ============================================

Describe "安装目录创建" {
    It "能创建安装目录" {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
        Test-Path $InstallDir | Should -Be $true
    }

    It "安装目录路径正确" {
        $InstallDir | Should -Match "\.claude-switch-model$"
    }
}

# ============================================
# 测试：首次安装
# ============================================

Describe "首次安装配置" {
    BeforeEach {
        # 创建测试用的 profile 文件
        $TestProfile = Join-Path $MockHome "profile.ps1"
        "# 原有配置" | Set-Content $TestProfile
    }

    It "能添加配置到 profile 文件" {
        $TestProfile = Join-Path $MockHome "profile.ps1"
        $MarkerStart = "# Claude 模型切换器 - 开始"
        $MarkerEnd = "# Claude 模型切换器 - 结束"

        # 模拟添加配置
        $Content = Get-Content $TestProfile
        $Content += @"

$MarkerStart
. "$InstallDir\claude-switch-model.ps1"
$MarkerEnd
"@
        $Content | Set-Content $TestProfile

        # 验证配置已添加
        $TestProfile | Should -FileContentMatch $MarkerStart
        $TestProfile | Should -FileContentMatch "claude-switch-model.ps1"
    }
}

# ============================================
# 测试：更新安装
# ============================================

Describe "更新安装配置" {
    BeforeEach {
        # 创建已安装状态的 profile 文件
        $TestProfile = Join-Path $MockHome "profile.ps1"
        $MarkerStart = "# Claude 模型切换器 - 开始"
        $MarkerEnd = "# Claude 模型切换器 - 结束"

        @(
            "# 原有配置",
            "export PATH=`$PATH:/usr/local/bin",
            "",
            $MarkerStart,
            ". '/old/path/claude-switch-model.ps1'",
            $MarkerEnd,
            "",
            "# 其他配置",
            "alias ll='ls -la'"
        ) | Set-Content $TestProfile
    }

    It "能移除旧配置并保留原有内容" {
        $TestProfile = Join-Path $MockHome "profile.ps1"
        $MarkerStart = "# Claude 模型切换器 - 开始"
        $MarkerEnd = "# Claude 模型切换器 - 结束"

        # 读取并移除旧配置
        $Content = Get-Content $TestProfile -Raw
        $Pattern = "(?s)$([regex]::Escape($MarkerStart))[\s\S]*?$([regex]::Escape($MarkerEnd))"
        $Content = $Content -replace $Pattern, ""
        $Content | Set-Content $TestProfile

        # 验证旧配置已移除
        $TestProfile | Should -Not -FileContentMatch "/old/path/"

        # 验证原有配置保留
        $TestProfile | Should -FileContentMatch "原有配置"
    }
}

# ============================================
# 测试：错误处理
# ============================================

Describe "错误处理" {
    It "无效 URL 下载失败" {
        $InvalidUrl = "https://invalid-url-that-does-not-exist.com/script.ps1"
        $DestPath = Join-Path $TestDir "test.ps1"

        # 尝试下载应该失败
        try {
            $WebClient = New-Object System.Net.WebClient
            $WebClient.DownloadFile($InvalidUrl, $DestPath)
            $Success = $true
        }
        catch {
            $Success = $false
        }

        $Success | Should -Be $false
    }
}
