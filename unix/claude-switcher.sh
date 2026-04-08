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

_cs_ensure_dirs() {
  local config_dir providers_dir
  config_dir=$(_cs_config_dir)
  providers_dir=$(_cs_providers_dir)
  mkdir -p "$providers_dir"
  chmod 700 "$config_dir"
  chmod 700 "$providers_dir"
}

# 从 KEY="VALUE" 格式的配置文件中安全读取值（不 source，避免代码注入）
_cs_read_conf() {
  local file="$1" key="$2"
  [[ ! -f "$file" ]] && echo "" && return
  grep "^${key}=" "$file" 2>/dev/null | head -1 \
    | sed "s/^${key}=//; s/^['\"]//; s/['\"]$//"
}

# 写入或更新配置文件中的单个 KEY
_cs_write_conf() {
  local file="$1" key="$2" value="$3"
  touch "$file"
  chmod 600 "$file"
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
# 内部：交互式为指定服务商设置 Token
# ============================================
_cs_set_token_for() {
  local id="$1"
  local provider_file
  provider_file="$(_cs_providers_dir)/${id}.conf"

  echo ""
  echo "Token 存储方式:"
  echo "  1. 明文存储（文件权限 600，简单方便）"
  echo "  2. 引用环境变量（输入变量名，运行时动态读取，更安全）"
  local choice
  read -r -p "请选择 [1]: " choice
  choice="${choice:-1}"

  if [[ "$choice" == "2" ]]; then
    local env_var
    read -r -p "环境变量名 (例如 ZHIPU_API_KEY): " env_var
    if [[ -z "$env_var" ]]; then
      _cs_red "错误: 环境变量名不能为空"
      return 1
    fi
    _cs_write_conf "$provider_file" "TOKEN_TYPE" "env"
    _cs_write_conf "$provider_file" "TOKEN"      "$env_var"
    _cs_green "✓ 已配置为引用环境变量 \$$env_var"
  else
    local token_val
    read -r -s -p "API Token: " token_val
    echo ""
    if [[ -z "$token_val" ]]; then
      _cs_red "错误: Token 不能为空"
      return 1
    fi
    _cs_write_conf "$provider_file" "TOKEN_TYPE" "plain"
    _cs_write_conf "$provider_file" "TOKEN"      "$token_val"
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
    --remove)     _cs_remove "${2:-}" ;;
    --set-token)  _cs_set_token "$@" ;;
    --set-model)  _cs_set_model "$@" ;;
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
