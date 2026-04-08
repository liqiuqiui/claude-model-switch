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

function _CS-EnsureDirs {
    $configDir    = _CS-ConfigDir
    $providersDir = _CS-ProvidersDir
    if (-not (Test-Path $configDir))    { New-Item -ItemType Directory -Path $configDir    -Force | Out-Null }
    if (-not (Test-Path $providersDir)) { New-Item -ItemType Directory -Path $providersDir -Force | Out-Null }
}

# 从 KEY="VALUE" 格式的配置文件中安全读取值（不 source）
function _CS-ReadConf {
    param([string]$File, [string]$Key)
    if (-not (Test-Path $File)) { return "" }
    $line = Get-Content $File -ErrorAction SilentlyContinue |
            Where-Object { $_ -match "^${Key}=" } |
            Select-Object -First 1
    if ($line) {
        return ($line -replace "^${Key}=", "") -replace '^[''"]', '' -replace '[''"]$', ''
    }
    return ""
}

# 写入或更新配置文件中的单个 KEY
function _CS-WriteConf {
    param([string]$File, [string]$Key, [string]$Value)
    if (-not (Test-Path $File)) { New-Item -ItemType File -Path $File -Force | Out-Null }
    $raw = Get-Content $File -Raw -ErrorAction SilentlyContinue
    if (-not $raw) { $raw = "" }
    if ($raw -match "(?m)^${Key}=") {
        $raw = $raw -replace "(?m)^${Key}=.*", "${Key}=`"${Value}`""
    } else {
        $raw = $raw.TrimEnd() + "`n${Key}=`"${Value}`""
    }
    [System.IO.File]::WriteAllText($File, $raw)
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
function _CS-Help {
    Write-Host @"
用法: claude-switcher [选项]

选项:
  (无参数)                               显示当前激活的配置状态
  --help,  -h                            显示此帮助
  --list,  -l                            列出所有已配置的服务商
  --use    <id>                          切换到指定服务商并更新环境变量
  --add    <id>                          交互式添加新服务商
  --remove <id>                          删除指定服务商
  --set-token [--provider <id>]          为服务商设置 API Token
  --set-model  --haiku  <model>          配置服务商各层级模型（可组合使用）
               --sonnet <model>
               --opus   <model>
              [--provider <id>]
  --uninstall                            卸载 claude-switcher

示例:
  claude-switcher --add zhipu
  claude-switcher --use zhipu
  claude-switcher --set-model --haiku glm-4-flash --sonnet glm-4 --opus glm-5
  claude-switcher --set-model --sonnet glm-4 --provider deepseek
  claude-switcher --set-token --provider zhipu
  claude-switcher --list
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
    $choice = Read-Host "请选择 [1]"
    if (-not $choice) { $choice = "1" }

    if ($choice -eq "2") {
        $envVar = Read-Host "环境变量名 (例如 ZHIPU_API_KEY)"
        if (-not $envVar) { _CS-WriteError "环境变量名不能为空"; return }
        _CS-WriteConf $providerFile "TOKEN_TYPE" "env"
        _CS-WriteConf $providerFile "TOKEN"      $envVar
        _CS-WriteSuccess "✓ 已配置为引用环境变量 `$$envVar"
    } else {
        $secureToken = Read-Host "API Token" -AsSecureString
        $tokenVal    = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                           [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureToken))
        if (-not $tokenVal) { _CS-WriteError "Token 不能为空"; return }
        _CS-WriteConf $providerFile "TOKEN_TYPE" "plain"
        _CS-WriteConf $providerFile "TOKEN"      $tokenVal
        _CS-WriteSuccess "✓ Token 已保存"
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
        "--remove"    { _CS-Remove $args[1];                             break }
        "--set-token" { _CS-SetToken  ($args | Select-Object -Skip 1);  break }
        "--set-model" { _CS-SetModel  ($args | Select-Object -Skip 1);  break }
        "--uninstall" { _CS-Uninstall;                                   break }
        ""            { _CS-Status;                                      break }
        default {
            _CS-WriteError "未知参数 '$cmd'"
            Write-Host ""
            _CS-Help
        }
    }
}
