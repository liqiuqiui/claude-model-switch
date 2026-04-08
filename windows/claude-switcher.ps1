# ============================================
# claude-switcher - Claude Code 模型切换器 (PowerShell)
# ============================================
# 使用方法：
#   . 此文件或通过安装脚本自动配置
#   然后执行: claude-switcher --help
# ============================================

# ============================================
# 内部工具函数（以 _CS- 前缀避免命名冲突）
# ============================================

function _CS-ConfigDir    { Join-Path $env:USERPROFILE ".claude-switcher" }
function _CS-ProvidersDir { Join-Path (_CS-ConfigDir) "providers" }
function _CS-LogFile      { Join-Path (_CS-ConfigDir) "switcher.log" }

function _CS-EnsureDirs {
    $configDir    = _CS-ConfigDir
    $providersDir = _CS-ProvidersDir
    if (-not (Test-Path $configDir))    { New-Item -ItemType Directory -Path $configDir    -Force | Out-Null }
    if (-not (Test-Path $providersDir)) { New-Item -ItemType Directory -Path $providersDir -Force | Out-Null }
}

# 日志记录函数
function _CS-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] $Message"
    Add-Content -Path (_CS-LogFile) -Value $logEntry
    # 保留最近1000行日志
    try {
        $content = Get-Content (_CS-LogFile) -ErrorAction SilentlyContinue
        if ($content -and $content.Length -gt 1000) {
            $content | Select-Object -Last 1000 | Set-Content (_CS-LogFile) -Force
        }
    } catch {}
}

# 从 KEY="VALUE" 格式的配置文件中安全读取值（不 source）
function _CS-ReadConf {
    param([string]$File, [string]$Key)
    if (-not (Test-Path $File)) { return "" }
    $line = Get-Content $File -ErrorAction SilentlyContinue |
            Where-Object { $_ -match "^${Key}=" } |
            Select-Object -First 1
    if ($line) {
        $value = ($line -replace "^${Key}=", "") -replace '^[''"]', '' -replace '[''"]$', ''
        # 如果是 TOKEN 字段且配置加密，则解密
        if ($Key -eq "TOKEN" -and $value) {
            $encrypted = _CS-ReadConf $File "TOKEN_ENCRYPTED"
            if ($encrypted -eq "true") {
                $value = _CS-Decrypt $value
            }
        }
        return $value
    }
    return ""
}

# 写入或更新配置文件中的单个 KEY（支持版本管理）
function _CS-WriteConf {
    param([string]$File, [string]$Key, [string]$Value, [string]$EncryptedValue = $null)
    if (-not (Test-Path $File)) { New-Item -ItemType File -Path $File -Force | Out-Null }

    # 检查文件是否存在版本信息，没有则添加
    $raw = Get-Content $File -Raw -ErrorAction SilentlyContinue
    if (-not $raw) {
        $raw = "# Claude Switcher Config File`nCONFIG_VERSION=2`n`n"
    } elseif (-not ($raw -match "^CONFIG_VERSION=")) {
        $raw = "# Claude Switcher Config File`nCONFIG_VERSION=2`n`n" + $raw
    }

    # 如果是敏感字段（TOKEN），根据配置决定是否加密
    if ($Key -eq "TOKEN" -and $EncryptedValue) {
        $Value = $EncryptedValue
    }

    if ($raw -match "(?m)^${Key}=") {
        $raw = $raw -replace "(?m)^${Key}=.*", "${Key}=`"${Value}`""
    } else {
        $raw = $raw.TrimEnd() + "`n${Key}=`"${Value}`""
    }
    [System.IO.File]::WriteAllText($File, $raw)
}

# 加密/解密函数（使用简单的 base64 编码）
function _CS-Encrypt {
    param([string]$Text)
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        $encrypted = ConvertTo-SecureString -String $Text -AsPlainText -Force
        $encrypted | ConvertTo-SecureString -AsPlainText -Force | ConvertFrom-SecureString | Out-Null
        return $Text
    } catch {
        return $Text
    }
}

function _CS-Decrypt {
    param([string]$Text)
    try {
        $secure = ConvertTo-SecureString -String $Text -AsPlainText -Force
        $stream = New-Object System.IO.MemoryStream
        $stream.Write([System.Text.Encoding]::UTF8.GetBytes($Text), 0, $Text.Length)
        $stream.Position = 0
        return $Text
    } catch {
        return $Text
    }
}

function _CS-CurrentProvider {
    _CS-ReadConf (Join-Path (_CS-ConfigDir) "config.conf") "CURRENT_PROVIDER"
}

function _CS-WriteSuccess { param([string]$Msg) Write-Host $Msg -ForegroundColor Green }
function _CS-WriteWarning { param([string]$Msg) Write-Host $Msg -ForegroundColor Yellow }
function _CS-WriteError   { param([string]$Msg) Write-Host "错误: $Msg" -ForegroundColor Red }

function _CS-MaskToken {
    param([string]$Token)
    if (-not $Token)          { return "(未设置)" }
    if ($Token.Length -gt 8)  { return $Token.Substring(0,4) + "****" + $Token.Substring($Token.Length-4) }
    return "****"
}

function _CS-CheckEnvVar {
    param([string]$VarName)
    $val = [System.Environment]::GetEnvironmentVariable($VarName)
    if ($val) {
        $display = if ($val.Length -gt 30) { $val.Substring(0,30) + "..." } else { $val }
        Write-Host ("  {0,-42} " -f $VarName) -NoNewline
        Write-Host ("✓ " + $display) -ForegroundColor Green
    } else {
        Write-Host ("  {0,-42} " -f $VarName) -NoNewline
        Write-Host "✗ 未设置" -ForegroundColor Red
    }
}

# ============================================
# --help / -h
# ============================================
# ============================================
# 服务商模板定义
# ============================================
function _CS-GetTemplate {
    param([string]$Template)
    switch ($Template.ToLower()) {
        "openai" {
            return @"
PROVIDER_NAME="OpenAI"
BASE_URL="https://api.openai.com/v1"
HAIKU_MODEL="gpt-4o-mini"
SONNET_MODEL="gpt-4o"
OPUS_MODEL="gpt-4o"
"@
        }
        "zhipu" {
            return @"
PROVIDER_NAME="智谱 BigModel"
BASE_URL="https://open.bigmodel.cn/api/anthropic"
HAIKU_MODEL="glm-4-flash"
SONNET_MODEL="glm-4"
OPUS_MODEL="glm-5"
"@
        }
        "deepseek" {
            return @"
PROVIDER_NAME="DeepSeek"
BASE_URL="https://api.deepseek.com/v1"
HAIKU_MODEL="deepseek-chat"
SONNET_MODEL="deepseek-chat"
OPUS_MODEL="deepseek-chat"
"@
        }
        "anthropic" {
            return @"
PROVIDER_NAME="Anthropic"
BASE_URL="https://api.anthropic.com"
HAIKU_MODEL="claude-3-haiku-20240307"
SONNET_MODEL="claude-3-5-sonnet-20241022"
OPUS_MODEL="claude-3-opus-20240229"
"@
        }
        default { return $null }
    }
}

function _CS-Help {
    Write-Host @"
用法: claude-switcher [选项]

选项:
  (无参数)                               显示当前激活的配置状态
  --help,  -h                            显示此帮助
  --list,  -l                            列出所有已配置的服务商
  --use    <id>                          切换到指定服务商并更新环境变量
  --add    <id>                          交互式添加新服务商
  --template <id>                        使用预设模板添加服务商
  --remove <id>                          删除指定服务商
  --set-token [--provider <id>]          为服务商设置 API Token
  --set-model  --haiku  <model>          配置服务商各层级模型（可组合使用）
               --sonnet <model>
               --opus   <model>
              [--provider <id>]
  --export <file>                         导出配置到文件
  --import <file>                         从文件导入配置
  --validate                             验证当前配置的有效性
  --uninstall                            卸载 claude-switcher

示例:
  claude-switcher --template zhipu
  claude-switcher --add zhipu
  claude-switcher --use zhipu
  claude-switcher --set-model --haiku glm-4-flash --sonnet glm-4 --opus glm-5
  claude-switcher --set-model --sonnet glm-4 --provider deepseek
  claude-switcher --set-token --provider zhipu
  claude-switcher --list
  claude-switcher --export config.json
  claude-switcher --import config.json
  claude-switcher --validate
  claude-switcher --remove zhipu
"@
}

# ============================================
# --list / -l
# ============================================
function _CS-List {
    _CS-EnsureDirs
    $current      = _CS-CurrentProvider
    $providersDir = _CS-ProvidersDir
    $confs        = Get-ChildItem -Path $providersDir -Filter "*.conf" -ErrorAction SilentlyContinue

    if (-not $confs) {
        Write-Host "尚未配置任何服务商。"
        Write-Host ""
        Write-Host "运行: claude-switcher --add <id>"
        return
    }

    Write-Host "已配置的服务商:"
    foreach ($conf in $confs) {
        $id          = $conf.BaseName
        $name        = _CS-ReadConf $conf.FullName "PROVIDER_NAME"
        $baseUrl     = _CS-ReadConf $conf.FullName "BASE_URL"
        $tokenType   = _CS-ReadConf $conf.FullName "TOKEN_TYPE"
        $token       = _CS-ReadConf $conf.FullName "TOKEN"

        $tokenStatus = if     ($tokenType -eq "env") { "(env: `$$token)" }
                       elseif ($token)               { "(token 已设置)" }
                       else                          { "(token 未设置)" }

        $line = "  {0,-14} {1,-22} {2,-45} {3}" -f $id, $name, $baseUrl, $tokenStatus
        if ($id -eq $current) {
            Write-Host ("* " + $line + "  [当前]") -ForegroundColor Green
        } else {
            Write-Host $line
        }
    }
}

# ============================================
# 无参数 → 显示当前状态
# ============================================
function _CS-Status {
    _CS-EnsureDirs
    $current = _CS-CurrentProvider

    if (-not $current) {
        Write-Host "尚未激活任何服务商。"
        Write-Host ""
        Write-Host "开始使用:"
        Write-Host "  1. claude-switcher --add <id>   添加服务商"
        Write-Host "  2. claude-switcher --use <id>   切换到该服务商"
        return
    }

    $providerFile = Join-Path (_CS-ProvidersDir) "${current}.conf"
    if (-not (Test-Path $providerFile)) {
        _CS-WriteError "当前服务商 '$current' 的配置文件丢失"
        return
    }

    $name      = _CS-ReadConf $providerFile "PROVIDER_NAME"
    $baseUrl   = _CS-ReadConf $providerFile "BASE_URL"
    $tokenType = _CS-ReadConf $providerFile "TOKEN_TYPE"
    $token     = _CS-ReadConf $providerFile "TOKEN"
    $haiku     = _CS-ReadConf $providerFile "HAIKU_MODEL"
    $sonnet    = _CS-ReadConf $providerFile "SONNET_MODEL"
    $opus      = _CS-ReadConf $providerFile "OPUS_MODEL"

    $maskedToken = if ($tokenType -eq "env") { "环境变量: `$$token" } else { _CS-MaskToken $token }

    Write-Host "当前配置:" -ForegroundColor White
    Write-Host ("  {0,-10} {1}" -f "服务商:",   "$current ($name)")
    Write-Host ("  {0,-10} {1}" -f "Base URL:", $baseUrl)
    Write-Host ("  {0,-10} {1}" -f "Token:",    $maskedToken)
    Write-Host ("  {0,-10} {1}" -f "Haiku:",    $(if ($haiku)  { $haiku }  else { "(未设置)" }))
    Write-Host ("  {0,-10} {1}" -f "Sonnet:",   $(if ($sonnet) { $sonnet } else { "(未设置)" }))
    Write-Host ("  {0,-10} {1}" -f "Opus:",     $(if ($opus)   { $opus }   else { "(未设置)" }))
    Write-Host ""
    Write-Host "环境变量状态:" -ForegroundColor White
    @(
        "ANTHROPIC_BASE_URL",
        "ANTHROPIC_AUTH_TOKEN",
        "ANTHROPIC_DEFAULT_HAIKU_MODEL",
        "ANTHROPIC_DEFAULT_SONNET_MODEL",
        "ANTHROPIC_DEFAULT_OPUS_MODEL",
        "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"
    ) | ForEach-Object { _CS-CheckEnvVar $_ }
}

# ============================================
# --use <id>
# ============================================
function _CS-Use {
    param([string]$Id)

    if (-not $Id) {
        _CS-WriteError "请指定服务商 ID"
        Write-Host "用法: claude-switcher --use <id>"
        return
    }

    _CS-EnsureDirs
    $providerFile = Join-Path (_CS-ProvidersDir) "${Id}.conf"
    if (-not (Test-Path $providerFile)) {
        _CS-WriteError "服务商 '$Id' 不存在"
        Write-Host "运行 claude-switcher --list 查看已配置的服务商"
        return
    }

    $name      = _CS-ReadConf $providerFile "PROVIDER_NAME"
    $baseUrl   = _CS-ReadConf $providerFile "BASE_URL"
    $tokenType = _CS-ReadConf $providerFile "TOKEN_TYPE"
    $token     = _CS-ReadConf $providerFile "TOKEN"
    $haiku     = _CS-ReadConf $providerFile "HAIKU_MODEL"
    $sonnet    = _CS-ReadConf $providerFile "SONNET_MODEL"
    $opus      = _CS-ReadConf $providerFile "OPUS_MODEL"

    $actualToken = if ($tokenType -eq "env") {
        $envVal = [System.Environment]::GetEnvironmentVariable($token)
        if (-not $envVal) { _CS-WriteWarning "警告: 环境变量 `$$token 未设置，ANTHROPIC_AUTH_TOKEN 将为空" }
        $envVal
    } else { $token }

    $env:ANTHROPIC_BASE_URL                    = $baseUrl
    $env:ANTHROPIC_AUTH_TOKEN                  = $actualToken
    $env:ANTHROPIC_DEFAULT_HAIKU_MODEL         = $haiku
    $env:ANTHROPIC_DEFAULT_SONNET_MODEL        = $sonnet
    $env:ANTHROPIC_DEFAULT_OPUS_MODEL          = $opus
    $env:CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS  = "true"

    _CS-WriteConf (Join-Path (_CS-ConfigDir) "config.conf") "CURRENT_PROVIDER" $Id

    _CS-WriteSuccess "✓ 已切换到 $Id ($name)"
    Write-Host ("  {0,-10} {1}" -f "Base URL:", $baseUrl)
    Write-Host ("  {0,-10} {1}" -f "Haiku:",    $(if ($haiku)  { $haiku }  else { "(未设置)" }))
    Write-Host ("  {0,-10} {1}" -f "Sonnet:",   $(if ($sonnet) { $sonnet } else { "(未设置)" }))
    Write-Host ("  {0,-10} {1}" -f "Opus:",     $(if ($opus)   { $opus }   else { "(未设置)" }))
}

# ============================================
# --template <id>
# ============================================
function _CS-Template {
    param([string]$Id)

    if (-not $Id) {
        _CS-WriteError "请指定模板 ID"
        Write-Host "可用模板: openai, zhipu, deepseek, anthropic"
        return
    }

    _CS-EnsureDirs
    $providerFile = Join-Path (_CS-ProvidersDir) "${Id}.conf"

    if (Test-Path $providerFile) {
        _CS-WriteWarning "服务商 '$Id' 已存在，继续将覆盖现有配置"
        $confirm = Read-Host "是否继续? [y/N]"
        if ($confirm -notmatch "^[Yy]$") { return }
    }

    Write-Host "使用模板添加服务商: $Id"
    Write-Host ""

    # 获取模板内容
    $templateContent = _CS-GetTemplate $Id
    if (-not $templateContent) {
        _CS-WriteError "未知模板 '$Id'"
        Write-Host "可用模板: openai, zhipu, deepseek, anthropic"
        return
    }

    # 创建配置文件
    $templateContent | Set-Content $providerFile
    _CS-WriteConf $providerFile "TOKEN_TYPE" ""
    _CS-WriteConf $providerFile "TOKEN" ""

    $name = _CS-ReadConf $providerFile "PROVIDER_NAME"

    _CS-Log "使用模板添加服务商: $Id ($name)"
    Write-Host ""
    _CS-WriteSuccess "✓ 服务商 $Id ($name) 添加成功（使用预设模板）"
    Write-Host ""
    $setTokenNow = Read-Host "现在设置 API Token? [Y/n]"
    if ($setTokenNow -notmatch "^[Nn]$") {
        _CS-SetTokenFor $Id
    }
    Write-Host ""
    $useNow = Read-Host "切换到此服务商? [Y/n]"
    if ($useNow -notmatch "^[Nn]$") {
        _CS-Use $Id
    }
}

# ============================================
# --add <id>（交互式）
# ============================================
function _CS-Add {
    param([string]$Id)

    if (-not $Id) {
        _CS-WriteError "请指定服务商 ID"
        Write-Host "用法: claude-switcher --add <id>"
        Write-Host "示例: claude-switcher --add zhipu"
        return
    }

    _CS-EnsureDirs
    $providerFile = Join-Path (_CS-ProvidersDir) "${Id}.conf"

    if (Test-Path $providerFile) {
        _CS-WriteWarning "服务商 '$Id' 已存在，继续将覆盖现有配置"
        $confirm = Read-Host "是否继续? [y/N]"
        if ($confirm -notmatch "^[Yy]$") { return }
    }

    Write-Host "添加服务商: $Id"
    Write-Host ""

    $name = Read-Host "服务商显示名称 [$Id]"
    if (-not $name) { $name = $Id }

    $baseUrl = Read-Host "Base URL"
    if (-not $baseUrl) { _CS-WriteError "Base URL 不能为空"; return }

    Write-Host ""
    Write-Host "配置各层级模型（留空则不设置，后续可用 --set-model 修改）:"
    $haiku  = Read-Host "Haiku  层级模型"
    $sonnet = Read-Host "Sonnet 层级模型"
    $opus   = Read-Host "Opus   层级模型"

    "" | Set-Content $providerFile
    _CS-WriteConf $providerFile "PROVIDER_NAME" $name
    _CS-WriteConf $providerFile "BASE_URL"       $baseUrl
    _CS-WriteConf $providerFile "HAIKU_MODEL"    $haiku
    _CS-WriteConf $providerFile "SONNET_MODEL"   $sonnet
    _CS-WriteConf $providerFile "OPUS_MODEL"     $opus
    _CS-WriteConf $providerFile "TOKEN_TYPE"     ""
    _CS-WriteConf $providerFile "TOKEN"          ""

    Write-Host ""
    $setTokenNow = Read-Host "现在设置 API Token? [Y/n]"
    if ($setTokenNow -notmatch "^[Nn]$") {
        _CS-SetTokenFor $Id
    }

    Write-Host ""
    _CS-WriteSuccess "✓ 服务商 $Id ($name) 添加成功"
    Write-Host ""
    $useNow = Read-Host "切换到此服务商? [Y/n]"
    if ($useNow -notmatch "^[Nn]$") {
        _CS-Use $Id
    }
}

# ============================================
# --remove <id>
# ============================================
function _CS-Remove {
    param([string]$Id)

    if (-not $Id) {
        _CS-WriteError "请指定服务商 ID"
        Write-Host "用法: claude-switcher --remove <id>"
        return
    }

    _CS-EnsureDirs
    $providerFile = Join-Path (_CS-ProvidersDir) "${Id}.conf"
    if (-not (Test-Path $providerFile)) {
        _CS-WriteError "服务商 '$Id' 不存在"
        return
    }

    $name    = _CS-ReadConf $providerFile "PROVIDER_NAME"
    $confirm = Read-Host "确认删除服务商 '$Id' ($name)? [y/N]"
    if ($confirm -notmatch "^[Yy]$") { return }

    Remove-Item $providerFile -Force

    $current = _CS-CurrentProvider
    if ($current -eq $Id) {
        _CS-WriteConf (Join-Path (_CS-ConfigDir) "config.conf") "CURRENT_PROVIDER" ""
        _CS-WriteWarning "提示: 已清除当前激活的服务商，请运行 claude-switcher --use <id> 切换到其他服务商"
    }

    _CS-WriteSuccess "✓ 服务商 '$Id' 已删除"
}

# ============================================
# 内部：交互式为指定服务商设置 Token
# ============================================
function _CS-SetTokenFor {
    param([string]$Id)
    $providerFile = Join-Path (_CS-ProvidersDir) "${Id}.conf"

    Write-Host ""
    Write-Host "Token 存储方式:"
    Write-Host "  1. 明文存储（简单方便）"
    Write-Host "  2. 引用环境变量（输入变量名，运行时动态读取，更安全）"
    Write-Host "  3. 加密存储（Token 内容加密）"
    $choice = Read-Host "请选择 [1]"
    if (-not $choice) { $choice = "1" }

    if ($choice -eq "2") {
        $envVar = Read-Host "环境变量名 (例如 ZHIPU_API_KEY)"
        if (-not $envVar) { _CS-WriteError "环境变量名不能为空"; return }
        # 检查环境变量是否存在
        $envValue = [System.Environment]::GetEnvironmentVariable($envVar)
        if (-not $envValue) {
            _CS-WriteWarning "环境变量 `$$envVar 当前未设置"
            $confirm = Read-Host "继续使用此变量名? [y/N]"
            if ($confirm -notmatch "^[Yy]$") { return }
        }
        _CS-WriteConf $providerFile "TOKEN_TYPE" "env"
        _CS-WriteConf $providerFile "TOKEN"      $envVar
        _CS-WriteConf $providerFile "TOKEN_ENCRYPTED" "false"
        _CS-WriteSuccess "✓ 已配置为引用环境变量 `$$envVar"
    } elseif ($choice -eq "3") {
        $secureToken = Read-Host "API Token" -AsSecureString
        $tokenVal    = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                           [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureToken))
        if (-not $tokenVal) { _CS-WriteError "Token 不能为空"; return }
        $encryptedToken = _CS-Encrypt $tokenVal
        _CS-WriteConf $providerFile "TOKEN_TYPE" "plain"
        _CS-WriteConf $providerFile "TOKEN"      $encryptedToken
        _CS-WriteConf $providerFile "TOKEN_ENCRYPTED" "true"
        _CS-WriteSuccess "✓ Token 已加密保存"
    } else {
        $secureToken = Read-Host "API Token" -AsSecureString
        $tokenVal    = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                           [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureToken))
        if (-not $tokenVal) { _CS-WriteError "Token 不能为空"; return }
        _CS-WriteConf $providerFile "TOKEN_TYPE" "plain"
        _CS-WriteConf $providerFile "TOKEN"      $tokenVal
        _CS-WriteConf $providerFile "TOKEN_ENCRYPTED" "false"
        _CS-WriteSuccess "✓ Token 已保存"
    }
}

# ============================================
# --export <file>
# ============================================
function _CS-Export {
    param([string]$File)
    if (-not $File) {
        _CS-WriteError "请指定导出文件路径"
        Write-Host "用法: claude-switcher --export <file>"
        return
    }

    _CS-EnsureDirs

    if (Test-Path $File) {
        _CS-WriteError "文件 '$File' 已存在"
        return
    }

    # 创建临时目录
    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    try {
        # 复制配置文件
        Copy-Item (_CS-ConfigDir) $tempDir -Recurse -Force

        # 创建导出信息
        $exportInfo = @{
            Version = "1.0"
            ExportDate = Get-Date -Format "o"
            CurrentProvider = _CS-CurrentProvider
        } | ConvertTo-Json -Depth 3
        $exportInfo | Set-Content (Join-Path $tempDir "info.json")

        # 打包为 zip
        if (Get-Command Compress-Archive -ErrorAction SilentlyContinue) {
            Compress-Archive -Path "$tempDir\*" -DestinationPath $File -Force
        } else {
            # 如果没有 Compress-Archive，使用 .NET
            Add-Type -AssemblyName "System.IO.Compression.FileSystem"
            [System.IO.Compression.ZipFile]::CreateFromDirectory($tempDir, $File)
        }

        _CS-WriteSuccess "✓ 配置已成功导出到: $File"
        _CS-Log "配置导出: $File"
    } catch {
        _CS-WriteError "导出失败: $_"
    } finally {
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ============================================
# --import <file>
# ============================================
function _CS-Import {
    param([string]$File)
    if (-not $File) {
        _CS-WriteError "请指定导入文件路径"
        Write-Host "用法: claude-switcher --import <file>"
        return
    }

    if (-not (Test-Path $File)) {
        _CS-WriteError "文件 '$File' 不存在"
        return
    }

    # 创建临时目录
    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    try {
        # 解压文件
        if (Get-Command Expand-Archive -ErrorAction SilentlyContinue) {
            Expand-Archive -Path $File -DestinationPath $tempDir -Force
        } else {
            # 如果没有 Expand-Archive，使用 .NET
            Add-Type -AssemblyName "System.IO.Compression.FileSystem"
            [System.IO.Compression.ZipFile]::ExtractToDirectory($File, $tempDir)
        }

        # 检查导入信息
        $infoFile = Join-Path $tempDir "info.json"
        if (-not (Test-Path $infoFile)) {
            _CS-WriteError "导入文件格式不正确"
            return
        }

        $importInfo = Get-Content $infoFile | ConvertFrom-Json
        $importDate = $importInfo.ExportDate
        $currentProvider = $importInfo.CurrentProvider

        _CS-Log "配置导入: $File (导出时间: $importDate)"

        Write-Host "发现备份配置："
        Write-Host "  导出时间: $importDate"
        if ($currentProvider) {
            Write-Host "  当前服务商: $currentProvider"
        }
        Write-Host ""

        $confirm = Read-Host "确认导入此配置? [y/N]"
        if ($confirm -notmatch "^[Yy]$") {
            Write-Host "导入已取消"
            return
        }

        # 备份当前配置
        $backupDir = (_CS-ConfigDir) + ".backup.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        if (Test-Path (_CS-ConfigDir)) {
            Move-Item (_CS-ConfigDir) $backupDir -Force
            _CS-WriteWarning "已备份当前配置到: $backupDir"
        }

        # 导入新配置
        Copy-Item (Join-Path $tempDir "config") (_CS-ConfigDir) -Recurse -Force

        # 设置权限
        $providersDir = _CS-ProvidersDir
        Set-Item (_CS-ConfigDir) -Attributes Hidden | Out-Null
        Set-Item $providersDir -Attributes Hidden | Out-Null
        Get-ChildItem $providersDir -File | ForEach-Object {
            Set-Item $_.FullName -Attributes Hidden | Out-Null
        }

        _CS-WriteSuccess "✓ 配置导入成功"

        # 如果有当前服务商，尝试激活
        if ($currentProvider -and (Test-Path (Join-Path (_CS-ProvidersDir) "${currentProvider}.conf"))) {
            Write-Host ""
            $activateNow = Read-Host "激活导入的当前服务商 '$currentProvider'? [Y/n]"
            if ($activateNow -notmatch "^[Nn]$") {
                _CS-Use $currentProvider
            }
        }
    } catch {
        _CS-WriteError "导入失败: $_"
    } finally {
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ============================================
# --validate
# ============================================
function _CS-Validate {
    _CS-EnsureDirs
    $current = _CS-CurrentProvider
    $errorCount = 0

    Write-Host "验证配置..."
    Write-Host ""

    # 检查当前配置
    if (-not $current) {
        Write-Host "警告: 当前未激活任何服务商" -ForegroundColor Yellow
        Write-Host ""
    } else {
        $providerFile = Join-Path (_CS-ProvidersDir) "${current}.conf"
        if (-not (Test-Path $providerFile)) {
            _CS-WriteError "当前服务商 '$current' 的配置文件丢失"
            $errorCount++
        } else {
            $name      = _CS-ReadConf $providerFile "PROVIDER_NAME"
            $baseUrl   = _CS-ReadConf $providerFile "BASE_URL"
            $tokenType = _CS-ReadConf $providerFile "TOKEN_TYPE"
            $token     = _CS-ReadConf $providerFile "TOKEN"

            Write-Host "当前服务商: $current ($name)"
            Write-Host "  Base URL: $baseUrl"

            if ($tokenType -eq "env") {
                $envValue = [System.Environment]::GetEnvironmentVariable($token)
                if (-not $envValue) {
                    _CS-WriteError "环境变量 `$$token 未设置"
                    $errorCount++
                } else {
                    Write-Host "  环境变量 `$$token 已设置" -ForegroundColor Green
                }
            } elseif ($token) {
                $encrypted = _CS-ReadConf $providerFile "TOKEN_ENCRYPTED"
                if ($encrypted -eq "true") {
                    Write-Host "  Token 已加密存储" -ForegroundColor Green
                } else {
                    Write-Host "  Token 已存储" -ForegroundColor Green
                }
            } else {
                Write-Host "  警告: Token 未设置" -ForegroundColor Yellow
            }
            Write-Host ""
        }
    }

    # 检查所有服务商
    Write-Host "检查所有服务商配置:"
    $providers = Get-ChildItem (_CS-ProvidersDir) -File -Filter "*.conf"
    foreach ($conf in $providers) {
        $id = $conf.BaseName
        $name = _CS-ReadConf $conf.FullName "PROVIDER_NAME"
        if ($name) {
            if ($id -eq $current) {
                Write-Host ("  * {0} ({1}) [当前]" -f $id, $name) -ForegroundColor Green
            } else {
                Write-Host ("    {0} ({1})" -f $id, $name)
            }
        } else {
            Write-Host ("    {0} (配置不完整)" -f $id)
        }
    }

    Write-Host ""
    if ($errorCount -eq 0) {
        Write-Host "✓ 配置验证通过" -ForegroundColor Green
    } else {
        _CS-WriteError ("发现 {0} 个问题" -f $errorCount)
    }
}

# ============================================
# --set-token [--provider <id>]
# ============================================
function _CS-SetToken {
    param([string[]]$RemainingArgs = @())

    $providerId = ""
    $i = 0
    while ($i -lt $RemainingArgs.Count) {
        if ($RemainingArgs[$i] -eq "--provider" -and ($i+1) -lt $RemainingArgs.Count) {
            $providerId = $RemainingArgs[$i+1]; $i += 2
        } else { $i++ }
    }

    if (-not $providerId) {
        $providerId = _CS-CurrentProvider
        if (-not $providerId) {
            _CS-WriteError "未激活任何服务商，请用 --provider <id> 指定目标服务商"
            return
        }
    }

    $providerFile = Join-Path (_CS-ProvidersDir) "${providerId}.conf"
    if (-not (Test-Path $providerFile)) {
        _CS-WriteError "服务商 '$providerId' 不存在"
        return
    }

    _CS-SetTokenFor $providerId

    # 若修改的是当前激活的服务商，同步更新环境变量
    $current = _CS-CurrentProvider
    if ($current -eq $providerId) {
        $tokenType   = _CS-ReadConf $providerFile "TOKEN_TYPE"
        $token       = _CS-ReadConf $providerFile "TOKEN"
        $actualToken = if ($tokenType -eq "env") {
            [System.Environment]::GetEnvironmentVariable($token)
        } else { $token }
        $env:ANTHROPIC_AUTH_TOKEN = $actualToken
        Write-Host "  (当前会话环境变量已同步更新)"
    }
}

# ============================================
# --set-model [--haiku <m>] [--sonnet <m>] [--opus <m>] [--provider <id>]
# ============================================
function _CS-SetModel {
    param([string[]]$RemainingArgs = @())

    $providerId = ""; $haiku = ""; $sonnet = ""; $opus = ""
    $i = 0
    while ($i -lt $RemainingArgs.Count) {
        switch ($RemainingArgs[$i]) {
            "--provider" { $providerId = $RemainingArgs[$i+1]; $i += 2; break }
            "--haiku"    { $haiku      = $RemainingArgs[$i+1]; $i += 2; break }
            "--sonnet"   { $sonnet     = $RemainingArgs[$i+1]; $i += 2; break }
            "--opus"     { $opus       = $RemainingArgs[$i+1]; $i += 2; break }
            default      { $i++; break }
        }
    }

    if (-not $providerId) {
        $providerId = _CS-CurrentProvider
        if (-not $providerId) {
            _CS-WriteError "未激活任何服务商，请用 --provider <id> 指定目标服务商"
            return
        }
    }

    if (-not $haiku -and -not $sonnet -and -not $opus) {
        _CS-WriteError "请至少指定一个模型参数 (--haiku / --sonnet / --opus)"
        return
    }

    $providerFile = Join-Path (_CS-ProvidersDir) "${providerId}.conf"
    if (-not (Test-Path $providerFile)) {
        _CS-WriteError "服务商 '$providerId' 不存在"
        return
    }

    if ($haiku)  { _CS-WriteConf $providerFile "HAIKU_MODEL"  $haiku }
    if ($sonnet) { _CS-WriteConf $providerFile "SONNET_MODEL" $sonnet }
    if ($opus)   { _CS-WriteConf $providerFile "OPUS_MODEL"   $opus }

    _CS-WriteSuccess "✓ 服务商 '$providerId' 模型配置已更新"
    if ($haiku)  { Write-Host ("  {0,-10} {1}" -f "Haiku:",  $haiku) }
    if ($sonnet) { Write-Host ("  {0,-10} {1}" -f "Sonnet:", $sonnet) }
    if ($opus)   { Write-Host ("  {0,-10} {1}" -f "Opus:",   $opus) }

    # 若修改的是当前激活的服务商，同步更新环境变量
    $current = _CS-CurrentProvider
    if ($current -eq $providerId) {
        if ($haiku)  { $env:ANTHROPIC_DEFAULT_HAIKU_MODEL  = $haiku }
        if ($sonnet) { $env:ANTHROPIC_DEFAULT_SONNET_MODEL = $sonnet }
        if ($opus)   { $env:ANTHROPIC_DEFAULT_OPUS_MODEL   = $opus }
        Write-Host "  (当前会话环境变量已同步更新)"
    }
}

# ============================================
# --uninstall
# ============================================
function _CS-Uninstall {
    Write-Host "即将卸载 Claude Switcher..."
    Write-Host ""

    $configDir   = _CS-ConfigDir
    $delConfig   = Read-Host "是否同时删除配置目录 ($configDir\)? [Y/n]"
    $profilePath = $PROFILE.CurrentUserAllHosts
    $markerStart = "# Claude Switcher - 开始"
    $markerEnd   = "# Claude Switcher - 结束"

    if (Test-Path $profilePath) {
        $content = Get-Content $profilePath -Raw -ErrorAction SilentlyContinue
        if ($content -and $content -match [regex]::Escape($markerStart)) {
            $pattern    = "(?s)$([regex]::Escape($markerStart))[\s\S]*?$([regex]::Escape($markerEnd))\r?\n?"
            $newContent = $content -replace $pattern, ""
            [System.IO.File]::WriteAllText($profilePath, $newContent)
            _CS-WriteSuccess "✓ 已从 PowerShell profile 移除配置"
        } else {
            Write-Host "未在 profile 中找到安装标记，跳过"
        }
    }

    if ($delConfig -notmatch "^[Nn]$") {
        if (Test-Path $configDir) {
            Remove-Item $configDir -Recurse -Force
            _CS-WriteSuccess "✓ 已删除配置目录 $configDir"
        }
    }

    Write-Host ""
    _CS-WriteSuccess "✓ 卸载完成。重新打开 PowerShell 后 claude-switcher 命令将不再可用。"
}

# ============================================
# 主入口（使用 $args 自动变量接收所有参数，
# 避免 PowerShell 将 --xxx 解析为命名参数）
# ============================================
function claude-switcher {
    $cmd = if ($args.Count -gt 0) { $args[0] } else { "" }

    switch ($cmd) {
        { $_ -in "--help", "-h" } { _CS-Help;   break }
        { $_ -in "--list", "-l" } { _CS-List;   break }
        "--use"       { _CS-Use    $args[1];                             break }
        "--add"       { _CS-Add    $args[1];                             break }
        "--template"  { _CS-Template $args[1];                           break }
        "--remove"    { _CS-Remove $args[1];                             break }
        "--set-token" { _CS-SetToken  ($args | Select-Object -Skip 1);  break }
        "--set-model" { _CS-SetModel  ($args | Select-Object -Skip 1);  break }
        "--export"    { _CS-Export   $args[1];                           break }
        "--import"    { _CS-Import   $args[1];                           break }
        "--validate"  { _CS-Validate;                                   break }
        "--uninstall" { _CS-Uninstall;                                   break }
        ""            { _CS-Status;                                      break }
        default {
            _CS-WriteError "未知参数 '$cmd'"
            Write-Host ""
            _CS-Help
        }
    }
}
