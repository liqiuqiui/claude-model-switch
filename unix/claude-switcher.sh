#!/bin/bash
# ============================================
# claude-switcher - Claude Code 模型切换器
# ============================================
# 使用方法：
#   source 此文件或通过安装脚本自动配置
#   然后执行: claude-switcher --help
# ============================================

# ============================================
# 内部工具函数（以 _cs_ 前缀避免命名冲突）
# ============================================

_cs_config_dir()    { echo "${HOME}/.claude-switcher"; }
_cs_providers_dir() { echo "${HOME}/.claude-switcher/providers"; }
_cs_log_file()      { echo "${HOME}/.claude-switcher/switcher.log"; }

_cs_ensure_dirs() {
  local config_dir providers_dir
  config_dir=$(_cs_config_dir)
  providers_dir=$(_cs_providers_dir)
  mkdir -p "$providers_dir"
  chmod 700 "$config_dir"
  chmod 700 "$providers_dir"
}

# 日志记录函数
_cs_log() {
  local timestamp message
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  message="[$timestamp] $*"
  echo "$message" >> "$(_cs_log_file)"
  # 保留最近1000行日志
  tail -n 1000 "$(_cs_log_file)" > "$(_cs_log_file).tmp" 2>/dev/null && mv "$(_cs_log_file).tmp" "$(_cs_log_file)" 2>/dev/null || true
}

# 加密/解密函数（使用简单的 base64 编码）
_cs_encrypt() {
  echo -n "$1" | openssl enc -aes-256-cbc -a -salt -pass pass:"claude-switcher-secret" 2>/dev/null || echo "$1"
}

_cs_decrypt() {
  echo -n "$1" | openssl enc -aes-256-cbc -d -a -salt -pass pass:"claude-switcher-secret" 2>/dev/null || echo "$1"
}

# 从 KEY="VALUE" 格式的配置文件中安全读取值（不 source，避免代码注入）
_cs_read_conf() {
  local file="$1" key="$2"
  [[ ! -f "$file" ]] && echo "" && return
  local value
  value=$(grep "^${key}=" "$file" 2>/dev/null | head -1 \
    | sed "s/^${key}=//; s/^['\"]//; s/['\"]$//")

  # 如果是 TOKEN 字段且配置加密，则解密
  if [[ "$key" == "TOKEN" && -n "$value" ]]; then
    local encrypted=$(_cs_read_conf "$file" "TOKEN_ENCRYPTED")
    if [[ "$encrypted" == "true" ]]; then
      value=$(_cs_decrypt "$value")
    fi
  fi

  echo "$value"
}

# 写入或更新配置文件中的单个 KEY（支持版本管理）
_cs_write_conf() {
  local file="$1" key="$2" value="$3" enc_value="$4"
  local new_file=false

  # 如果文件不存在，创建并添加版本头
  if [[ ! -f "$file" ]]; then
    new_file=true
    echo "# Claude Switcher Config File" > "$file"
    echo "CONFIG_VERSION=2" >> "$file"
    echo "" >> "$file"
  else
    # 检查是否有版本信息，没有则添加
    if ! grep -q "^CONFIG_VERSION=" "$file" 2>/dev/null; then
      local tmp="${file}.tmp"
      echo "# Claude Switcher Config File" > "$tmp"
      echo "CONFIG_VERSION=2" >> "$tmp"
      echo "" >> "$tmp"
      cat "$file" >> "$tmp"
      mv "$tmp" "$file"
    fi
  fi

  touch "$file"
  chmod 600 "$file"

  # 如果是敏感字段（TOKEN），根据配置决定是否加密
  if [[ "$key" == "TOKEN" && -n "$enc_value" ]]; then
    value="$enc_value"
  fi

  if grep -q "^${key}=" "$file" 2>/dev/null; then
    local tmp="${file}.tmp"
    sed "s|^${key}=.*|${key}=\"${value}\"|" "$file" > "$tmp" && mv "$tmp" "$file"
  else
    echo "${key}=\"${value}\"" >> "$file"
  fi
}

_cs_current_provider() {
  _cs_read_conf "$(_cs_config_dir)/config.conf" "CURRENT_PROVIDER"
}

# 颜色输出
_cs_green()  { printf '\033[0;32m%s\033[0m\n' "$*"; }
_cs_yellow() { printf '\033[1;33m%s\033[0m\n' "$*"; }
_cs_red()    { printf '\033[0;31m%s\033[0m\n' "$*"; }
_cs_bold()   { printf '\033[1m%s\033[0m\n' "$*"; }

# 检查单个环境变量是否已设置，打印状态行
_cs_check_env_var() {
  local var="$1" val
  val="${!var}"
  if [[ -n "$val" ]]; then
    local display="${val:0:30}"
    [[ ${#val} -gt 30 ]] && display="${display}..."
    printf '  %-42s \033[0;32m✓\033[0m %s\n' "$var" "$display"
  else
    printf '  %-42s \033[0;31m✗ 未设置\033[0m\n' "$var"
  fi
}

# 将 token 脱敏显示
_cs_mask_token() {
  local token="$1"
  if [[ ${#token} -gt 8 ]]; then
    echo "${token:0:4}****${token: -4}"
  elif [[ -n "$token" ]]; then
    echo "****"
  else
    echo "(未设置)"
  fi
}

# ============================================
# --help / -h
# ============================================
_cs_help() {
  cat <<'EOF'
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
  claude-switcher --add zhipu
  claude-switcher --template openai
  claude-switcher --use zhipu
  claude-switcher --set-model --haiku glm-4-flash --sonnet glm-4 --opus glm-5
  claude-switcher --set-model --sonnet glm-4 --provider deepseek
  claude-switcher --set-token --provider zhipu
  claude-switcher --list
  claude-switcher --export config.json
  claude-switcher --import config.json
  claude-switcher --validate
  claude-switcher --remove zhipu
EOF
}

# ============================================
# --list / -l
# ============================================
_cs_list() {
  _cs_ensure_dirs
  local providers_dir current
  providers_dir=$(_cs_providers_dir)
  current=$(_cs_current_provider)

  local conf_files=("$providers_dir"/*.conf)
  if [[ ! -e "${conf_files[0]}" ]]; then
    echo "尚未配置任何服务商。"
    echo ""
    echo "运行: claude-switcher --add <id>"
    return
  fi

  echo "已配置的服务商:"
  for conf in "${conf_files[@]}"; do
    local id name base_url token_type token token_status
    id=$(basename "$conf" .conf)
    name=$(_cs_read_conf "$conf" "PROVIDER_NAME")
    base_url=$(_cs_read_conf "$conf" "BASE_URL")
    token_type=$(_cs_read_conf "$conf" "TOKEN_TYPE")
    token=$(_cs_read_conf "$conf" "TOKEN")

    if [[ "$token_type" == "env" ]]; then
      token_status="(env: \$$token)"
    elif [[ -n "$token" ]]; then
      token_status="(token 已设置)"
    else
      token_status="(token 未设置)"
    fi

    local marker="  " line
    line=$(printf '%-14s %-22s %-45s %s' "$id" "$name" "$base_url" "$token_status")
    if [[ "$id" == "$current" ]]; then
      marker="* "
      _cs_green "${marker}${line}  [当前]"
    else
      echo "${marker}${line}"
    fi
  done
}

# ============================================
# 无参数 → 显示当前状态
# ============================================
_cs_status() {
  _cs_ensure_dirs
  local current
  current=$(_cs_current_provider)

  if [[ -z "$current" ]]; then
    echo "尚未激活任何服务商。"
    echo ""
    echo "开始使用:"
    echo "  1. claude-switcher --add <id>   添加服务商"
    echo "  2. claude-switcher --use <id>   切换到该服务商"
    return
  fi

  local provider_file
  provider_file="$(_cs_providers_dir)/${current}.conf"
  if [[ ! -f "$provider_file" ]]; then
    _cs_red "错误: 当前服务商 '$current' 的配置文件丢失"
    return 1
  fi

  local name base_url token_type token haiku sonnet opus masked_token
  name=$(_cs_read_conf      "$provider_file" "PROVIDER_NAME")
  base_url=$(_cs_read_conf  "$provider_file" "BASE_URL")
  token_type=$(_cs_read_conf "$provider_file" "TOKEN_TYPE")
  token=$(_cs_read_conf     "$provider_file" "TOKEN")
  haiku=$(_cs_read_conf     "$provider_file" "HAIKU_MODEL")
  sonnet=$(_cs_read_conf    "$provider_file" "SONNET_MODEL")
  opus=$(_cs_read_conf      "$provider_file" "OPUS_MODEL")

  if [[ "$token_type" == "env" ]]; then
    masked_token="环境变量: \$$token"
  else
    masked_token=$(_cs_mask_token "$token")
  fi

  _cs_bold "当前配置:"
  printf '  %-10s %s\n' "服务商:"   "$current ($name)"
  printf '  %-10s %s\n' "Base URL:" "$base_url"
  printf '  %-10s %s\n' "Token:"    "$masked_token"
  printf '  %-10s %s\n' "Haiku:"    "${haiku:-(未设置)}"
  printf '  %-10s %s\n' "Sonnet:"   "${sonnet:-(未设置)}"
  printf '  %-10s %s\n' "Opus:"     "${opus:-(未设置)}"
  echo ""
  _cs_bold "环境变量状态:"
  _cs_check_env_var "ANTHROPIC_BASE_URL"
  _cs_check_env_var "ANTHROPIC_AUTH_TOKEN"
  _cs_check_env_var "ANTHROPIC_DEFAULT_HAIKU_MODEL"
  _cs_check_env_var "ANTHROPIC_DEFAULT_SONNET_MODEL"
  _cs_check_env_var "ANTHROPIC_DEFAULT_OPUS_MODEL"
  _cs_check_env_var "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"
}

# ============================================
# --use <id>
# ============================================
_cs_use() {
  local id="$1"
  if [[ -z "$id" ]]; then
    _cs_red "错误: 请指定服务商 ID"
    echo "用法: claude-switcher --use <id>"
    return 1
  fi

  _cs_ensure_dirs
  local provider_file
  provider_file="$(_cs_providers_dir)/${id}.conf"
  if [[ ! -f "$provider_file" ]]; then
    _cs_red "错误: 服务商 '$id' 不存在"
    echo "运行 claude-switcher --list 查看已配置的服务商"
    return 1
  fi

  local name base_url token_type token haiku sonnet opus actual_token
  name=$(_cs_read_conf      "$provider_file" "PROVIDER_NAME")
  base_url=$(_cs_read_conf  "$provider_file" "BASE_URL")
  token_type=$(_cs_read_conf "$provider_file" "TOKEN_TYPE")
  token=$(_cs_read_conf     "$provider_file" "TOKEN")
  haiku=$(_cs_read_conf     "$provider_file" "HAIKU_MODEL")
  sonnet=$(_cs_read_conf    "$provider_file" "SONNET_MODEL")
  opus=$(_cs_read_conf      "$provider_file" "OPUS_MODEL")

  if [[ "$token_type" == "env" ]]; then
    actual_token="${!token}"
    if [[ -z "$actual_token" ]]; then
      _cs_yellow "警告: 环境变量 \$$token 未设置，ANTHROPIC_AUTH_TOKEN 将为空"
    fi
  else
    actual_token="$token"
  fi

  export ANTHROPIC_BASE_URL="$base_url"
  export ANTHROPIC_AUTH_TOKEN="$actual_token"
  export ANTHROPIC_DEFAULT_HAIKU_MODEL="$haiku"
  export ANTHROPIC_DEFAULT_SONNET_MODEL="$sonnet"
  export ANTHROPIC_DEFAULT_OPUS_MODEL="$opus"
  export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS="true"

  _cs_write_conf "$(_cs_config_dir)/config.conf" "CURRENT_PROVIDER" "$id"

  _cs_green "✓ 已切换到 $id ($name)"
  printf '  %-10s %s\n' "Base URL:" "$base_url"
  printf '  %-10s %s\n' "Haiku:"    "${haiku:-(未设置)}"
  printf '  %-10s %s\n' "Sonnet:"   "${sonnet:-(未设置)}"
  printf '  %-10s %s\n' "Opus:"     "${opus:-(未设置)}"
}

# ============================================
# 服务商模板定义
# ============================================
_cs_get_template() {
  local template="$1"
  case "$template" in
    "openai")
      cat <<EOF
PROVIDER_NAME="OpenAI"
BASE_URL="https://api.openai.com/v1"
HAIKU_MODEL="gpt-4o-mini"
SONNET_MODEL="gpt-4o"
OPUS_MODEL="gpt-4o"
EOF
      ;;
    "zhipu")
      cat <<EOF
PROVIDER_NAME="智谱 BigModel"
BASE_URL="https://open.bigmodel.cn/api/anthropic"
HAIKU_MODEL="glm-4-flash"
SONNET_MODEL="glm-4"
OPUS_MODEL="glm-5"
EOF
      ;;
    "deepseek")
      cat <<EOF
PROVIDER_NAME="DeepSeek"
BASE_URL="https://api.deepseek.com/v1"
HAIKU_MODEL="deepseek-chat"
SONNET_MODEL="deepseek-chat"
OPUS_MODEL="deepseek-chat"
EOF
      ;;
    "anthropic")
      cat <<EOF
PROVIDER_NAME="Anthropic"
BASE_URL="https://api.anthropic.com"
HAIKU_MODEL="claude-3-haiku-20240307"
SONNET_MODEL="claude-3-5-sonnet-20241022"
OPUS_MODEL="claude-3-opus-20240229"
EOF
      ;;
    *)
      return 1
      ;;
  esac
}

# ============================================
# --template <id>
# ============================================
_cs_template() {
  local id="$1" skip_confirm="" skip_token="" skip_use=""

  # 支持测试参数：--no-confirm --no-token --no-use
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --no-confirm) skip_confirm="true"; shift ;;
      --no-token)   skip_token="true";   shift ;;
      --no-use)     skip_use="true";     shift ;;
      *) break ;;
    esac
  done

  id="$1"
  if [[ -z "$id" ]]; then
    _cs_red "错误: 请指定模板 ID"
    echo "可用模板: openai, zhipu, deepseek, anthropic"
    return 1
  fi

  _cs_ensure_dirs
  local provider_file
  provider_file="$(_cs_providers_dir)/${id}.conf"

  if [[ -f "$provider_file" ]]; then
    if [[ -z "$skip_confirm" ]]; then
      _cs_yellow "服务商 '$id' 已存在，继续将覆盖现有配置"
      local confirm
      read -r -p "是否继续? [y/N]: " confirm
      [[ "$confirm" =~ ^[Yy]$ ]] || return 0
    fi
  fi

  echo "使用模板添加服务商: $id"
  echo ""

  # 获取模板内容
  local template_content
  template_content=$(_cs_get_template "$id") || {
    _cs_red "错误: 未知模板 '$id'"
    echo "可用模板: openai, zhipu, deepseek, anthropic"
    return 1
  }

  # 创建配置文件
  : > "$provider_file"
  chmod 600 "$provider_file"

  # 写入模板配置
  echo "$template_content" >> "$provider_file"
  _cs_write_conf "$provider_file" "TOKEN_TYPE" ""
  _cs_write_conf "$provider_file" "TOKEN" ""

  local name
  name=$(_cs_read_conf "$provider_file" "PROVIDER_NAME")

  _cs_log "使用模板添加服务商: $id ($name)"
  echo ""
  _cs_green "✓ 服务商 $id ($name) 添加成功（使用预设模板）"
  echo ""
  if [[ -z "$skip_token" ]]; then
    local set_token_now use_now
    read -r -p "现在设置 API Token? [Y/n]: " set_token_now
    if [[ ! "$set_token_now" =~ ^[Nn]$ ]]; then
      _cs_set_token_for "$id"
    fi
    echo ""
    read -r -p "切换到此服务商? [Y/n]: " use_now
    if [[ ! "$use_now" =~ ^[Nn]$ ]]; then
      _cs_use "$id"
    fi
  fi
}

# ============================================
# --add <id>（交互式）
# ============================================
_cs_add() {
  local id="$1"
  if [[ -z "$id" ]]; then
    _cs_red "错误: 请指定服务商 ID"
    echo "用法: claude-switcher --add <id>"
    echo "示例: claude-switcher --add zhipu"
    return 1
  fi

  _cs_ensure_dirs
  local provider_file
  provider_file="$(_cs_providers_dir)/${id}.conf"

  if [[ -f "$provider_file" ]]; then
    _cs_yellow "服务商 '$id' 已存在，继续将覆盖现有配置"
    local confirm
    read -r -p "是否继续? [y/N]: " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || return 0
  fi

  echo "添加服务商: $id"
  echo ""

  local name base_url haiku sonnet opus
  read -r -p "服务商显示名称 [$id]: " name
  name="${name:-$id}"

  read -r -p "Base URL: " base_url
  if [[ -z "$base_url" ]]; then
    _cs_red "错误: Base URL 不能为空"
    return 1
  fi

  echo ""
  echo "配置各层级模型（留空则不设置，后续可用 --set-model 修改）:"
  read -r -p "Haiku  层级模型: " haiku
  read -r -p "Sonnet 层级模型: " sonnet
  read -r -p "Opus   层级模型: " opus

  # 写入配置文件
  : > "$provider_file"
  chmod 600 "$provider_file"
  _cs_write_conf "$provider_file" "PROVIDER_NAME" "$name"
  _cs_write_conf "$provider_file" "BASE_URL"       "$base_url"
  _cs_write_conf "$provider_file" "HAIKU_MODEL"    "$haiku"
  _cs_write_conf "$provider_file" "SONNET_MODEL"   "$sonnet"
  _cs_write_conf "$provider_file" "OPUS_MODEL"     "$opus"
  _cs_write_conf "$provider_file" "TOKEN_TYPE"     ""
  _cs_write_conf "$provider_file" "TOKEN"          ""

  echo ""
  local set_token_now
  read -r -p "现在设置 API Token? [Y/n]: " set_token_now
  if [[ ! "$set_token_now" =~ ^[Nn]$ ]]; then
    _cs_set_token_for "$id"
  fi

  echo ""
  _cs_green "✓ 服务商 $id ($name) 添加成功"
  echo ""
  local use_now
  read -r -p "切换到此服务商? [Y/n]: " use_now
  if [[ ! "$use_now" =~ ^[Nn]$ ]]; then
    _cs_use "$id"
  fi
}

# ============================================
# --remove <id>
# ============================================
_cs_remove() {
  local id="$1"
  if [[ -z "$id" ]]; then
    _cs_red "错误: 请指定服务商 ID"
    echo "用法: claude-switcher --remove <id>"
    return 1
  fi

  _cs_ensure_dirs
  local provider_file
  provider_file="$(_cs_providers_dir)/${id}.conf"
  if [[ ! -f "$provider_file" ]]; then
    _cs_red "错误: 服务商 '$id' 不存在"
    return 1
  fi

  local name confirm
  name=$(_cs_read_conf "$provider_file" "PROVIDER_NAME")
  read -r -p "确认删除服务商 '$id' ($name)? [y/N]: " confirm
  [[ "$confirm" =~ ^[Yy]$ ]] || return 0

  rm -f "$provider_file"

  local current
  current=$(_cs_current_provider)
  if [[ "$current" == "$id" ]]; then
    _cs_write_conf "$(_cs_config_dir)/config.conf" "CURRENT_PROVIDER" ""
    _cs_yellow "提示: 已清除当前激活的服务商，请运行 claude-switcher --use <id> 切换到其他服务商"
  fi

  _cs_green "✓ 服务商 '$id' 已删除"
}

# ============================================
# 内部：交互式为指定服务商设置 Token（支持加密）
# ============================================
_cs_set_token_for() {
  local id="$1" choice="$2" token_val="$3"
  local provider_file
  provider_file="$(_cs_providers_dir)/${id}.conf"

  # 如果没有提供参数，则使用交互模式
  if [[ -z "$choice" ]]; then
    echo ""
    echo "Token 存储方式:"
    echo "  1. 明文存储（文件权限 600，简单方便）"
    echo "  2. 引用环境变量（输入变量名，运行时动态读取，更安全）"
    echo "  3. 加密存储（文件权限 600，Token 内容加密）"
    read -r -p "请选择 [1]: " choice
    choice="${choice:-1}"
  fi

  if [[ "$choice" == "2" ]]; then
    if [[ -z "$token_val" ]]; then
      read -r -p "环境变量名 (例如 ZHIPU_API_KEY): " token_val
    fi
    if [[ -z "$token_val" ]]; then
      _cs_red "错误: 环境变量名不能为空"
      return 1
    fi
    # 检查环境变量是否存在
    if [[ -z "${!token_val}" ]]; then
      _cs_yellow "警告: 环境变量 \$$token_val 当前未设置"
      local confirm
      read -r -p "继续使用此变量名? [y/N]: " confirm
      [[ "$confirm" =~ ^[Yy]$ ]] || return 1
    fi
    _cs_write_conf "$provider_file" "TOKEN_TYPE" "env"
    _cs_write_conf "$provider_file" "TOKEN"      "$token_val"
    _cs_write_conf "$provider_file" "TOKEN_ENCRYPTED" "false"
    _cs_green "✓ 已配置为引用环境变量 \$$token_val"
  elif [[ "$choice" == "3" ]]; then
    if [[ -z "$token_val" ]]; then
      read -r -s -p "API Token: " token_val
      echo ""
    fi
    if [[ -z "$token_val" ]]; then
      _cs_red "错误: Token 不能为空"
      return 1
    fi
    # 加密 Token
    local encrypted_token
    encrypted_token=$(_cs_encrypt "$token_val")
    _cs_write_conf "$provider_file" "TOKEN_TYPE" "plain"
    _cs_write_conf "$provider_file" "TOKEN"      "$encrypted_token"
    _cs_write_conf "$provider_file" "TOKEN_ENCRYPTED" "true"
    _cs_green "✓ Token 已加密保存（文件权限 600）"
  else
    if [[ -z "$token_val" ]]; then
      read -r -s -p "API Token: " token_val
      echo ""
    fi
    if [[ -z "$token_val" ]]; then
      _cs_red "错误: Token 不能为空"
      return 1
    fi
    _cs_write_conf "$provider_file" "TOKEN_TYPE" "plain"
    _cs_write_conf "$provider_file" "TOKEN"      "$token_val"
    _cs_write_conf "$provider_file" "TOKEN_ENCRYPTED" "false"
    _cs_green "✓ Token 已保存（文件权限 600）"
  fi
}

# ============================================
# --set-token [--provider <id>]
# ============================================
_cs_set_token() {
  shift  # 移除 --set-token
  local provider_id=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --provider) provider_id="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  if [[ -z "$provider_id" ]]; then
    provider_id=$(_cs_current_provider)
    if [[ -z "$provider_id" ]]; then
      _cs_red "错误: 未激活任何服务商，请用 --provider <id> 指定目标服务商"
      return 1
    fi
  fi

  local provider_file
  provider_file="$(_cs_providers_dir)/${provider_id}.conf"
  if [[ ! -f "$provider_file" ]]; then
    _cs_red "错误: 服务商 '$provider_id' 不存在"
    return 1
  fi

  _cs_set_token_for "$provider_id"

  # 若修改的是当前激活的服务商，同步更新环境变量
  local current
  current=$(_cs_current_provider)
  if [[ "$current" == "$provider_id" ]]; then
    local token_type token actual_token
    token_type=$(_cs_read_conf "$provider_file" "TOKEN_TYPE")
    token=$(_cs_read_conf     "$provider_file" "TOKEN")
    if [[ "$token_type" == "env" ]]; then
      actual_token="${!token}"
    else
      actual_token="$token"
    fi
    export ANTHROPIC_AUTH_TOKEN="$actual_token"
    echo "  (当前会话环境变量已同步更新)"
  fi
}

# ============================================
# --export <file>
# ============================================
_cs_export() {
  local file="$1"
  if [[ -z "$file" ]]; then
    _cs_red "错误: 请指定导出文件路径"
    echo "用法: claude-switcher --export <file>"
    return 1
  fi

  _cs_ensure_dirs

  # 检查文件是否存在
  if [[ -f "$file" ]]; then
    _cs_red "错误: 文件 '$file' 已存在"
    return 1
  fi

  # 创建临时目录
  local temp_dir
  temp_dir=$(mktemp -d)
  trap "rm -rf '$temp_dir'" EXIT

  # 复制配置文件
  cp -r "$(_cs_config_dir)" "$temp_dir/config"

  # 创建导出信息
  cat <<EOF > "$temp_dir/info.json"
{
  "version": "1.0",
  "export_date": "$(date -Iseconds)",
  "current_provider": "$(_cs_current_provider)"
}
EOF

  # 打包成 tar.gz
  tar -czf "$file" -C "$temp_dir" . 2>/dev/null

  if [[ $? -eq 0 ]]; then
    _cs_green "✓ 配置已成功导出到: $file"
    _cs_log "配置导出: $file"
  else
    _cs_red "错误: 导出失败"
    return 1
  fi
}

# ============================================
# --import <file>
# ============================================
_cs_import() {
  local file="$1"
  if [[ -z "$file" ]]; then
    _cs_red "错误: 请指定导入文件路径"
    echo "用法: claude-switcher --import <file>"
    return 1
  fi

  if [[ ! -f "$file" ]]; then
    _cs_red "错误: 文件 '$file' 不存在"
    return 1
  fi

  # 创建临时目录
  local temp_dir
  temp_dir=$(mktemp -d)
  trap "rm -rf '$temp_dir'" EXIT

  # 解压文件
  if ! tar -xzf "$file" -C "$temp_dir" 2>/dev/null; then
    _cs_red "错误: 文件格式不正确或已损坏"
    return 1
  fi

  # 检查导入信息
  if [[ ! -f "$temp_dir/info.json" ]]; then
    _cs_red "错误: 导入文件格式不正确"
    return 1
  fi

  # 读取导入信息
  local import_date current_provider
  import_date=$(grep -o '"export_date":"[^"]*"' "$temp_dir/info.json" | cut -d'"' -f4)
  current_provider=$(grep -o '"current_provider":"[^"]*"' "$temp_dir/info.json" | cut -d'"' -f4)

  _cs_log "配置导入: $file (导出时间: $import_date)"

  echo "发现备份配置："
  echo "  导出时间: $import_date"
  if [[ -n "$current_provider" ]]; then
    echo "  当前服务商: $current_provider"
  fi
  echo ""

  local confirm
  read -r -p "确认导入此配置? [y/N]: " confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "导入已取消"
    return 0
  fi

  # 备份当前配置
  local backup_dir
  backup_dir="$(_cs_config_dir).backup.$(date +%Y%m%d_%H%M%S)"
  if [[ -d "$(_cs_config_dir)" ]]; then
    mv "$(_cs_config_dir)" "$backup_dir"
    _cs_yellow "已备份当前配置到: $backup_dir"
  fi

  # 导入新配置
  mkdir -p "$(_cs_config_dir)"
  cp -r "$temp_dir/config"/* "$(_cs_config_dir)/"

  # 设置权限
  chmod 700 "$(_cs_config_dir)"
  chmod 700 "$(_cs_providers_dir)"
  find "$(_cs_providers_dir)" -name "*.conf" -exec chmod 600 {} \;

  _cs_green "✓ 配置导入成功"

  # 如果有当前服务商，尝试激活
  if [[ -n "$current_provider" && -f "$(_cs_providers_dir)/${current_provider}.conf" ]]; then
    echo ""
    local activate_now
    read -r -p "激活导入的当前服务商 '$current_provider'? [Y/n]: " activate_now
    if [[ ! "$activate_now" =~ ^[Nn]$ ]]; then
      _cs_use "$current_provider"
    fi
  fi
}

# ============================================
# --validate
# ============================================
_cs_validate() {
  _cs_ensure_dirs
  local current error_count=0

  echo "验证配置..."
  echo ""

  current=$(_cs_current_provider)

  # 检查当前配置
  if [[ -z "$current" ]]; then
    _cs_yellow "警告: 当前未激活任何服务商"
    echo ""
  else
    local provider_file
    provider_file="$(_cs_providers_dir)/${current}.conf"
    if [[ ! -f "$provider_file" ]]; then
      _cs_red "错误: 当前服务商 '$current' 的配置文件丢失"
      ((error_count++))
    else
      local name base_url token_type token
      name=$(_cs_read_conf      "$provider_file" "PROVIDER_NAME")
      base_url=$(_cs_read_conf  "$provider_file" "BASE_URL")
      token_type=$(_cs_read_conf "$provider_file" "TOKEN_TYPE")
      token=$(_cs_read_conf     "$provider_file" "TOKEN")

      echo "当前服务商: $current ($name)"
      echo "  Base URL: $base_url"

      if [[ "$token_type" == "env" ]]; then
        if [[ -z "${!token}" ]]; then
          _cs_red "错误: 环境变量 \$$token 未设置"
          ((error_count++))
        else
          _cs_green "✓ 环境变量 \$$token 已设置"
        fi
      elif [[ -n "$token" ]]; then
        local encrypted=$(_cs_read_conf "$provider_file" "TOKEN_ENCRYPTED")
        if [[ "$encrypted" == "true" ]]; then
          _cs_green "✓ Token 已加密存储"
        else
          _cs_green "✓ Token 已存储"
        fi
      else
        _cs_yellow "警告: Token 未设置"
      fi
      echo ""
    fi
  fi

  # 检查所有服务商
  echo "检查所有服务商配置:"
  local conf_files=("$(_cs_providers_dir)"/*.conf)
  for conf in "${conf_files[@]}"; do
    [[ ! -f "$conf" ]] && continue
    local id name
    id=$(basename "$conf" .conf)
    name=$(_cs_read_conf "$conf" "PROVIDER_NAME")
    if [[ -n "$name" ]]; then
      if [[ "$id" == "$current" ]]; then
        echo "  * $id ($name) [当前]"
      else
        echo "    $id ($name)"
      fi
    else
      echo "    $id (配置不完整)"
    fi
  done

  echo ""
  if [[ $error_count -eq 0 ]]; then
    _cs_green "✓ 配置验证通过"
  else
    _cs_red "发现 $error_count 个问题"
  fi
}

# ============================================
# --set-model [--haiku <m>] [--sonnet <m>] [--opus <m>] [--provider <id>]
# ============================================
_cs_set_model() {
  shift  # 移除 --set-model
  local provider_id="" haiku="" sonnet="" opus=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --provider) provider_id="$2"; shift 2 ;;
      --haiku)    haiku="$2";       shift 2 ;;
      --sonnet)   sonnet="$2";      shift 2 ;;
      --opus)     opus="$2";        shift 2 ;;
      *) shift ;;
    esac
  done

  if [[ -z "$provider_id" ]]; then
    provider_id=$(_cs_current_provider)
    if [[ -z "$provider_id" ]]; then
      _cs_red "错误: 未激活任何服务商，请用 --provider <id> 指定目标服务商"
      return 1
    fi
  fi

  if [[ -z "$haiku" && -z "$sonnet" && -z "$opus" ]]; then
    _cs_red "错误: 请至少指定一个模型参数 (--haiku / --sonnet / --opus)"
    return 1
  fi

  local provider_file
  provider_file="$(_cs_providers_dir)/${provider_id}.conf"
  if [[ ! -f "$provider_file" ]]; then
    _cs_red "错误: 服务商 '$provider_id' 不存在"
    return 1
  fi

  [[ -n "$haiku" ]]  && _cs_write_conf "$provider_file" "HAIKU_MODEL"  "$haiku"
  [[ -n "$sonnet" ]] && _cs_write_conf "$provider_file" "SONNET_MODEL" "$sonnet"
  [[ -n "$opus" ]]   && _cs_write_conf "$provider_file" "OPUS_MODEL"   "$opus"

  _cs_green "✓ 服务商 '$provider_id' 模型配置已更新"
  [[ -n "$haiku" ]]  && printf '  %-10s %s\n' "Haiku:"  "$haiku"
  [[ -n "$sonnet" ]] && printf '  %-10s %s\n' "Sonnet:" "$sonnet"
  [[ -n "$opus" ]]   && printf '  %-10s %s\n' "Opus:"   "$opus"

  # 若修改的是当前激活的服务商，同步更新环境变量
  local current
  current=$(_cs_current_provider)
  if [[ "$current" == "$provider_id" ]]; then
    [[ -n "$haiku" ]]  && export ANTHROPIC_DEFAULT_HAIKU_MODEL="$haiku"
    [[ -n "$sonnet" ]] && export ANTHROPIC_DEFAULT_SONNET_MODEL="$sonnet"
    [[ -n "$opus" ]]   && export ANTHROPIC_DEFAULT_OPUS_MODEL="$opus"
    echo "  (当前会话环境变量已同步更新)"
  fi
}

# ============================================
# --uninstall
# ============================================
_cs_uninstall() {
  echo "即将卸载 Claude Switcher..."
  echo ""

  local shell_rc
  if [[ -n "$ZSH_VERSION" ]]; then
    shell_rc="$HOME/.zshrc"
  elif [[ -n "$BASH_VERSION" ]]; then
    shell_rc="$HOME/.bashrc"
  else
    shell_rc="$HOME/.profile"
  fi

  local config_dir del_config
  config_dir=$(_cs_config_dir)
  read -r -p "是否同时删除配置目录 ($config_dir/)? [Y/n]: " del_config

  local marker_start="# Claude Switcher - 开始"
  local marker_end="# Claude Switcher - 结束"

  if grep -q "$marker_start" "$shell_rc" 2>/dev/null; then
    local tmp="${shell_rc}.tmp"
    sed "/$marker_start/,/$marker_end/d" "$shell_rc" > "$tmp" && mv "$tmp" "$shell_rc"
    _cs_green "✓ 已从 $shell_rc 移除配置"
  else
    echo "未在 $shell_rc 中找到安装标记，跳过"
  fi

  if [[ ! "$del_config" =~ ^[Nn]$ ]]; then
    rm -rf "$config_dir"
    _cs_green "✓ 已删除配置目录 $config_dir"
  fi

  echo ""
  _cs_green "✓ 卸载完成。重新打开终端后 claude-switcher 命令将不再可用。"
}

# ============================================
# 主入口
# ============================================
claude-switcher() {
  case "${1:-}" in
    --help|-h)    _cs_help ;;
    --list|-l)    _cs_list ;;
    --use)        _cs_use "${2:-}" ;;
    --add)        _cs_add "${2:-}" ;;
    --template)   _cs_template "${2:-}" ;;
    --remove)     _cs_remove "${2:-}" ;;
    --set-token)  _cs_set_token "$@" ;;
    --set-model)  _cs_set_model "$@" ;;
    --export)     _cs_export "${2:-}" ;;
    --import)     _cs_import "${2:-}" ;;
    --validate)   _cs_validate ;;
    --uninstall)  _cs_uninstall ;;
    "")           _cs_status ;;
    *)
      _cs_red "错误: 未知参数 '${1}'"
      echo ""
      _cs_help
      return 1
      ;;
  esac
}
