# ============================================
# claude-switcher.ps1 测试用例
# ============================================
# 使用 Pester 测试框架
# 安装: Install-Module -Name Pester -Force -Scope CurrentUser
# 运行: Invoke-Pester -Path tests/
# ============================================

BeforeAll {
            $ScriptDir    = Join-Path $PSScriptRoot "../../windows"
            $SwitcherScript = Join-Path $ScriptDir "claude-switcher.ps1"

    # 创建隔离的测试 HOME 目录
    $TestDir  = Join-Path $env:TEMP "claude-switcher-test-$(Get-Random)"
    $MockHome = Join-Path $TestDir "home"
    New-Item -ItemType Directory -Path $MockHome -Force | Out-Null

    # 加载脚本（会定义所有 _CS- 函数和 claude-switcher）
    . $SwitcherScript
}

AfterAll {
    if (Test-Path $TestDir) { Remove-Item -Path $TestDir -Recurse -Force }
}

# 每个测试前重置测试目录
BeforeEach {
    $env:USERPROFILE = $MockHome
    $ConfigDir    = Join-Path $MockHome ".claude-switcher"
    $ProvidersDir = Join-Path $ConfigDir "providers"
    New-Item -ItemType Directory -Path $ProvidersDir -Force | Out-Null

    # 清理环境变量
    Remove-Item Env:\ANTHROPIC_BASE_URL            -ErrorAction SilentlyContinue
    Remove-Item Env:\ANTHROPIC_AUTH_TOKEN          -ErrorAction SilentlyContinue
    Remove-Item Env:\ANTHROPIC_DEFAULT_HAIKU_MODEL  -ErrorAction SilentlyContinue
    Remove-Item Env:\ANTHROPIC_DEFAULT_SONNET_MODEL -ErrorAction SilentlyContinue
    Remove-Item Env:\ANTHROPIC_DEFAULT_OPUS_MODEL   -ErrorAction SilentlyContinue
    Remove-Item Env:\CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS -ErrorAction SilentlyContinue
}

AfterEach {
    if (Test-Path (Join-Path $MockHome ".claude-switcher")) {
        Remove-Item -Path (Join-Path $MockHome ".claude-switcher") -Recurse -Force
    }
}

# ============================================
# 工具函数测试
# ============================================

Describe "工具函数" {
    It "_CS-ConfigDir 返回正确路径" {
        $result = _CS-ConfigDir
        $result | Should -Match "\.claude-switcher$"
    }

    It "_CS-ProvidersDir 返回正确路径" {
        $result = _CS-ProvidersDir
        $result | Should -Match "providers$"
    }

    It "_CS-WriteConf 写入文件" {
        $file = Join-Path (_CS-ConfigDir) "test.conf"
        _CS-WriteConf $file "MY_KEY" "my_value"
        $content = Get-Content $file -Raw
        $content | Should -Match "MY_KEY"
        $content | Should -Match "my_value"
    }

    It "_CS-ReadConf 读取正确值" {
        $file = Join-Path (_CS-ConfigDir) "test.conf"
        'MY_KEY="hello world"' | Set-Content $file
        $result = _CS-ReadConf $file "MY_KEY"
        $result | Should -Be "hello world"
    }

    It "_CS-ReadConf 对不存在的文件返回空" {
        $result = _CS-ReadConf "C:\nonexistent\path.conf" "KEY"
        $result | Should -BeNullOrEmpty
    }

    It "_CS-WriteConf 更新已有 KEY" {
        $file = Join-Path (_CS-ConfigDir) "test.conf"
        _CS-WriteConf $file "KEY" "first"
        _CS-WriteConf $file "KEY" "second"
        $result = _CS-ReadConf $file "KEY"
        $result | Should -Be "second"
    }

    It "_CS-MaskToken 对长 token 脱敏" {
        $result = _CS-MaskToken "sk-abcdefghijk"
        $result | Should -Match "\*\*\*\*"
        $result | Should -Not -Be "sk-abcdefghijk"
    }

    It "_CS-MaskToken 对空 token 返回未设置" {
        $result = _CS-MaskToken ""
        $result | Should -Be "(未设置)"
    }
}

# ============================================
# --help
# ============================================

Describe "--help" {
    It "显示用法信息" {
        $output = & { _CS-Help } 2>&1 | Out-String
        $output | Should -Match "用法"
        $output | Should -Match "claude-switcher"
    }

    It "包含所有主要选项" {
        $output = & { _CS-Help } 2>&1 | Out-String
        $output | Should -Match "\-\-list"
        $output | Should -Match "\-\-use"
        $output | Should -Match "\-\-add"
        $output | Should -Match "\-\-remove"
        $output | Should -Match "\-\-set-token"
        $output | Should -Match "\-\-set-model"
        $output | Should -Match "\-\-uninstall"
    }
}

# ============================================
# --list
# ============================================

Describe "--list" {
    It "无服务商时显示提示" {
        $output = & { _CS-List } 2>&1 | Out-String
        $output | Should -Match "尚未配置"
    }

    It "显示已配置的服务商" {
        $conf = Join-Path (_CS-ProvidersDir) "zhipu.conf"
        @(
            'PROVIDER_NAME="智谱 BigModel"',
            'BASE_URL="https://open.bigmodel.cn/api/anthropic"',
            'TOKEN_TYPE=""',
            'TOKEN=""',
            'HAIKU_MODEL="glm-4-flash"',
            'SONNET_MODEL="glm-4"',
            'OPUS_MODEL="glm-5"'
        ) | Set-Content $conf

        $output = & { _CS-List } 2>&1 | Out-String
        $output | Should -Match "zhipu"
        $output | Should -Match "智谱 BigModel"
    }
}

# ============================================
# --use
# ============================================

Describe "--use" {
    BeforeEach {
        $ProviderConf = Join-Path (_CS-ProvidersDir) "zhipu.conf"
        @(
            'PROVIDER_NAME="智谱 BigModel"',
            'BASE_URL="https://open.bigmodel.cn/api/anthropic"',
            'TOKEN_TYPE="plain"',
            'TOKEN="sk-test-token"',
            'HAIKU_MODEL="glm-4-flash"',
            'SONNET_MODEL="glm-4"',
            'OPUS_MODEL="glm-5"'
        ) | Set-Content $ProviderConf
    }

    It "不存在的服务商报错" {
        $output = & { _CS-Use "nonexistent" } 2>&1 | Out-String
        $output | Should -Match "不存在"
    }

    It "正确设置 ANTHROPIC_BASE_URL" {
        _CS-Use "zhipu"
        $env:ANTHROPIC_BASE_URL | Should -Be "https://open.bigmodel.cn/api/anthropic"
    }

    It "正确设置 ANTHROPIC_AUTH_TOKEN" {
        _CS-Use "zhipu"
        $env:ANTHROPIC_AUTH_TOKEN | Should -Be "sk-test-token"
    }

    It "正确设置三个模型层级" {
        _CS-Use "zhipu"
        $env:ANTHROPIC_DEFAULT_HAIKU_MODEL  | Should -Be "glm-4-flash"
        $env:ANTHROPIC_DEFAULT_SONNET_MODEL | Should -Be "glm-4"
        $env:ANTHROPIC_DEFAULT_OPUS_MODEL   | Should -Be "glm-5"
    }

    It "启用 Agent Teams 实验功能" {
        _CS-Use "zhipu"
        $env:CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS | Should -Be "true"
    }

    It "保存当前服务商到 config.conf" {
        _CS-Use "zhipu"
        $current = _CS-CurrentProvider
        $current | Should -Be "zhipu"
    }

    It "env 类型 token 从环境变量读取" {
        $conf = Join-Path (_CS-ProvidersDir) "envprov.conf"
        @(
            'PROVIDER_NAME="Env Prov"',
            'BASE_URL="https://example.com"',
            'TOKEN_TYPE="env"',
            'TOKEN="MY_SECRET_KEY"',
            'HAIKU_MODEL="m1"',
            'SONNET_MODEL="m1"',
            'OPUS_MODEL="m1"'
        ) | Set-Content $conf

        $env:MY_SECRET_KEY = "actual-secret"
        _CS-Use "envprov"
        $env:ANTHROPIC_AUTH_TOKEN | Should -Be "actual-secret"
        Remove-Item Env:\MY_SECRET_KEY -ErrorAction SilentlyContinue
    }
}

# ============================================
# --remove
# ============================================

Describe "--remove" {
    It "不存在的服务商报错" {
        $output = & { _CS-Remove "nonexistent" } 2>&1 | Out-String
        $output | Should -Match "不存在"
    }
}

# ============================================
# --set-model
# ============================================

Describe "--set-model" {
    BeforeEach {
        $conf = Join-Path (_CS-ProvidersDir) "prov.conf"
        @(
            'PROVIDER_NAME="Prov"',
            'BASE_URL="https://example.com"',
            'HAIKU_MODEL="old-h"',
            'SONNET_MODEL="old-s"',
            'OPUS_MODEL="old-o"'
        ) | Set-Content $conf
        _CS-WriteConf (Join-Path (_CS-ConfigDir) "config.conf") "CURRENT_PROVIDER" "prov"
    }

    It "没有模型参数时报错" {
        $output = & { _CS-SetModel @() } 2>&1 | Out-String
        $output | Should -Match "至少指定"
    }

    It "仅更新 haiku，不影响其他层级" {
        _CS-SetModel @("--haiku", "new-h")
        $conf = Join-Path (_CS-ProvidersDir) "prov.conf"
        (_CS-ReadConf $conf "HAIKU_MODEL")  | Should -Be "new-h"
        (_CS-ReadConf $conf "SONNET_MODEL") | Should -Be "old-s"
        (_CS-ReadConf $conf "OPUS_MODEL")   | Should -Be "old-o"
    }

    It "同时更新三个层级" {
        _CS-SetModel @("--haiku", "h", "--sonnet", "s", "--opus", "o")
        $conf = Join-Path (_CS-ProvidersDir) "prov.conf"
        (_CS-ReadConf $conf "HAIKU_MODEL")  | Should -Be "h"
        (_CS-ReadConf $conf "SONNET_MODEL") | Should -Be "s"
        (_CS-ReadConf $conf "OPUS_MODEL")   | Should -Be "o"
    }

    It "通过 --provider 指定非当前服务商" {
        $other = Join-Path (_CS-ProvidersDir) "other.conf"
        @(
            'PROVIDER_NAME="Other"',
            'BASE_URL="https://other.com"',
            'HAIKU_MODEL="old"'
        ) | Set-Content $other

        _CS-SetModel @("--haiku", "new-model", "--provider", "other")
        (_CS-ReadConf $other "HAIKU_MODEL") | Should -Be "new-model"
    }
}

# ============================================
# 脚本文件存在检查
# ============================================

Describe "脚本文件存在" {
    It "claude-switcher.ps1 文件存在" {
        Test-Path $SwitcherScript | Should -Be $true
    }

    It "install.ps1 文件存在" {
        $installScript = Join-Path $ScriptDir "install.ps1"
        Test-Path $installScript | Should -Be $true
    }
}
