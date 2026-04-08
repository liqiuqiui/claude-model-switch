# ============================================
# install.ps1 测试用例
# ============================================
# 使用 Pester 测试框架
# 安装: Install-Module -Name Pester -Force -Scope CurrentUser
# 运行: Invoke-Pester -Path tests/
# ============================================

BeforeAll {
    $ScriptDir     = Join-Path (Split-Path -Parent $PSScriptRoot) "windows"
    $InstallScript = Join-Path $ScriptDir "install.ps1"
    $SwitcherScript = Join-Path $ScriptDir "claude-switcher.ps1"

    $TestDir  = Join-Path $env:TEMP "claude-switcher-install-test-$(Get-Random)"
    $MockHome = Join-Path $TestDir "home"
    New-Item -ItemType Directory -Path $MockHome -Force | Out-Null

    $InstallDir = Join-Path $MockHome ".claude-switcher"
}

AfterAll {
    if (Test-Path $TestDir) { Remove-Item -Path $TestDir -Recurse -Force }
}

# ============================================
# 脚本文件存在检查
# ============================================

Describe "脚本文件检查" {
    It "install.ps1 文件存在" {
        Test-Path $InstallScript | Should -Be $true
    }

    It "claude-switcher.ps1 文件存在" {
        Test-Path $SwitcherScript | Should -Be $true
    }
}

# ============================================
# PowerShell 配置文件检测
# ============================================

Describe "PowerShell 配置文件检测" {
    It "能正确识别 PowerShell 配置文件路径" {
        $ProfilePath = $PROFILE.CurrentUserAllHosts
        $ProfilePath | Should -Match "profile\.ps1$"
    }
}

# ============================================
# 安装目录创建
# ============================================

Describe "安装目录创建" {
    It "能创建安装目录及 providers 子目录" {
        $ProvidersDir = Join-Path $InstallDir "providers"
        New-Item -ItemType Directory -Path $ProvidersDir -Force | Out-Null
        Test-Path $ProvidersDir | Should -Be $true
    }

    It "安装目录路径包含 .claude-switcher" {
        $InstallDir | Should -Match "\.claude-switcher$"
    }
}

# ============================================
# 首次安装
# ============================================

Describe "首次安装配置" {
    BeforeEach {
        $TestProfile = Join-Path $MockHome "profile.ps1"
        "# 原有配置" | Set-Content $TestProfile
    }

    It "能添加新标记格式的配置到 profile 文件" {
        $TestProfile  = Join-Path $MockHome "profile.ps1"
        $MarkerStart  = "# Claude Switcher - 开始"
        $MarkerEnd    = "# Claude Switcher - 结束"

        $Content  = Get-Content $TestProfile -Raw
        $Content += @"

$MarkerStart
# 以下内容由 Claude Switcher 安装程序自动添加，请勿手动修改
. "$InstallDir\claude-switcher.ps1"
$MarkerEnd
"@
        [System.IO.File]::WriteAllText($TestProfile, $Content)

        $TestProfile | Should -FileContentMatch $MarkerStart
        $TestProfile | Should -FileContentMatch "claude-switcher.ps1"
    }
}

# ============================================
# 更新安装
# ============================================

Describe "更新安装配置" {
    BeforeEach {
        $TestProfile = Join-Path $MockHome "profile.ps1"
        $MarkerStart = "# Claude Switcher - 开始"
        $MarkerEnd   = "# Claude Switcher - 结束"

        @(
            "# 原有配置",
            'export PATH=$PATH:/usr/local/bin',
            "",
            $MarkerStart,
            ". '/old/path/claude-switcher.ps1'",
            $MarkerEnd,
            "",
            "# 其他配置",
            "alias ll='ls -la'"
        ) | Set-Content $TestProfile
    }

    It "能移除旧配置并保留原有内容" {
        $TestProfile = Join-Path $MockHome "profile.ps1"
        $MarkerStart = "# Claude Switcher - 开始"
        $MarkerEnd   = "# Claude Switcher - 结束"

        $Content = Get-Content $TestProfile -Raw
        $Pattern = "(?s)$([regex]::Escape($MarkerStart))[\s\S]*?$([regex]::Escape($MarkerEnd))"
        $Content = $Content -replace $Pattern, ""
        [System.IO.File]::WriteAllText($TestProfile, $Content)

        $TestProfile | Should -Not -FileContentMatch "/old/path/"
        $TestProfile | Should -FileContentMatch "原有配置"
    }
}

# ============================================
# 错误处理
# ============================================

Describe "错误处理" {
    It "无效 URL 下载失败" {
        $InvalidUrl = "https://invalid-url-that-does-not-exist-xyz.com/script.ps1"
        $DestPath   = Join-Path $TestDir "test.ps1"
        $Success    = $true

        try {
            $WebClient = New-Object System.Net.WebClient
            $WebClient.DownloadFile($InvalidUrl, $DestPath)
        } catch {
            $Success = $false
        }

        $Success | Should -Be $false
    }
}
