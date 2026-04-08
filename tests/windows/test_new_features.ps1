# ============================================
# PowerShell 新功能测试用例
# ============================================

Describe "Claude Switcher 新功能测试" {
    BeforeAll {
        # 隔离配置目录
        $script:TestHome = [System.IO.Path]::GetTempPath() + "claude-switcher-test-" + [System.Guid]::NewGuid().ToString()
        New-Item -ItemType Directory -Path $script:TestHome -Force | Out-Null

        # 设置环境变量
        $env:USERPROFILE = $script:TestHome
        $env:OPENAI_API_KEY = "test-openai-key"
        $env:ZHIPU_API_KEY = "test-zhipu-key"

        # 加载脚本
        $script:ScriptDir = Split-Path -Parent $PSScriptRoot
        . "$script:ScriptDir/../../windows/claude-switcher.ps1"
    }

    AfterAll {
        # 清理测试目录
        Remove-Item -Path $script:TestHome -Recurse -Force -ErrorAction SilentlyContinue
    }

    Context "模板功能测试" {
        It "使用模板添加智谱提供商" {
            # 模拟用户输入：直接确认
            { & { _CS-Template "zhipu" } } | Should -Not -Throw
            $providerFile = Join-Path (_CS-ConfigDir) "providers\zhipu.conf"
            Test-Path $providerFile | Should -Be $true

            $name = _CS-ReadConf $providerFile "PROVIDER_NAME"
            $name | Should -BeExactly "智谱 BigModel"
        }

        It "未知模板返回错误" {
            { & { _CS-Template "unknown" } } | Should -Throw
        }

        It "模板列表显示可用选项" {
            $output = & { _CS-Help } 2>&1
            $output | Should -Match "可用模板"
            $output | Should -Match "openai"
            $output | Should -Match "zhipu"
        }
    }

    Context "Token 存储测试" {
        It "环境变量模式设置" {
            $providerFile = Join-Path (_CS-ProvidersDir) "envtest.conf"
            @"
PROVIDER_NAME="Env Test"
BASE_URL="https://example.com"
HAIKU_MODEL="test"
SONNET_MODEL="test"
OPUS_MODEL="test"
"@ | Set-Content $providerFile

            # 模拟用户输入：选择2，输入变量名
            $script:input = "2`nTEST_VAR"
            { & { _CS-SetTokenFor "envtest" } } | Should -Not -Throw

            $tokenType = _CS-ReadConf $providerFile "TOKEN_TYPE"
            $tokenVar = _CS-ReadConf $providerFile "TOKEN"

            $tokenType | Should -BeExactly "env"
            $tokenVar | Should -BeExactly "TEST_VAR"
        }

        It "加密模式设置" {
            # 模拟用户输入：选择3，输入token
            $script:input = "3`nsk-test-encrypted"
            { & { _CS-SetTokenFor "encrypttest" } } | Should -Not -Throw

            $providerFile = Join-Path (_CS-ProvidersDir) "encrypttest.conf"
            $tokenType = _CS-ReadConf $providerFile "TOKEN_TYPE"
            $encrypted = _CS-ReadConf $providerFile "TOKEN_ENCRYPTED"

            $tokenType | Should -BeExactly "plain"
            $encrypted | Should -BeExactly "true"
        }
    }

    Context "导入/导出功能测试" {
        It "导出配置文件" {
            # 先添加一个测试提供商
            $providerFile = Join-Path (_CS-ProvidersDir) "exporttest.conf"
            @"
PROVIDER_NAME="Export Test"
BASE_URL="https://example.com"
TOKEN_TYPE="plain"
TOKEN="sk-export-test"
HAIKU_MODEL="test-haiku"
"@ | Set-Content $providerFile
            _CS-WriteConf (Join-Path (_CS-ConfigDir) "config.conf") "CURRENT_PROVIDER" "exporttest"

            $exportFile = Join-Path $script:TestHome "test-export.zip"
            { & { _CS-Export $exportFile } } | Should -Not -Throw
            Test-Path $exportFile | Should -Be $true

            # 验证 ZIP 内容（如果有 Compress-Archive 命令）
            if (Get-Command Compress-Archive -ErrorAction SilentlyContinue) {
                $content = [System.IO.Compression.ZipFile]::OpenRead($exportFile).Entries.Name
                $content | Should -Contain "providers/exporttest.conf"
                $content | Should -Contain "info.json"
            }
        }

        It "导出失败当文件已存在" {
            $existingFile = Join-Path $script:TestHome "existing.zip"
            New-Item -ItemType File -Path $existingFile -Force | Out-Null

            { & { _CS-Export $existingFile } } | Should -Throw
        }

        It "导出失败当没有指定路径" {
            { & { _CS-Export } } | Should -Throw
        }
    }

    Context "验证功能测试" {
        It "验证报告缺少 Token" {
            $providerFile = Join-Path (_CS-ProvidersDir) "valtest.conf"
            @"
PROVIDER_NAME="Validation Test"
BASE_URL="https://example.com"
"@ | Set-Content $providerFile
            _CS-WriteConf (Join-Path (_CS-ConfigDir) "config.conf") "CURRENT_PROVIDER" "valtest"

            $output = & { _CS-Validate } 2>&1
            $output | Should -Match "Token 未设置"
        }

        It "验证报告环境变量缺失" {
            $providerFile = Join-Path (_CS-ProvidersDir) "valenv.conf"
            @"
PROVIDER_NAME="Env Validation Test"
BASE_URL="https://example.com"
TOKEN_TYPE="env"
TOKEN="MISSING_ENV_VAR"
"@ | Set-Content $providerFile
            _CS-WriteConf (Join-Path (_CS-ConfigDir) "config.conf") "CURRENT_PROVIDER" "valenv"

            $output = & { _CS-Validate } 2>&1
            $output | Should -Match "环境变量"
            $output | Should -Match "未设置"
        }

        It "验证成功显示通过" {
            $providerFile = Join-Path (_CS-ProvidersDir) "valgood.conf"
            @"
PROVIDER_NAME="Good Validation Test"
BASE_URL="https://example.com"
TOKEN_TYPE="plain"
TOKEN="sk-good-token"
"@ | Set-Content $providerFile
            _CS-WriteConf (Join-Path (_CS-ConfigDir) "config.conf") "CURRENT_PROVIDER" "valgood"

            $output = & { _CS-Validate } 2>&1
            $output | Should -Match "验证通过"
        }
    }

    Context "版本管理测试" {
        It "配置文件包含版本头" {
            $providerFile = Join-Path (_CS-ProvidersDir) "versiontest.conf"
            $configFile = Join-Path (_CS-ConfigDir) "config.conf"

            @"
PROVIDER_NAME="Version Test"
BASE_URL="https://example.com"
TOKEN_TYPE="plain"
TOKEN="sk-version-test"
"@ | Set-Content $providerFile
            _CS-WriteConf $configFile "CURRENT_PROVIDER" "versiontest"

            Test-Path $providerFile | Should -Be $true
            $content = Get-Content $providerFile -Raw
            $content | Should -Match "^CONFIG_VERSION=2"
        }
    }

    Context "错误处理测试" {
        It "未知命令显示帮助" {
            $output = & { claude-switcher --unknown-new-command } 2>&1
            $output | Should -Match "未知参数"
            $output | Should -Match "用法"
        }
    }
}