#!/usr/bin/env bats
# ============================================
# 新功能测试用例
# ============================================

setup() {
  SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../unix" && pwd)"

  # 隔离配置目录，避免污染真实环境
  export HOME="$(mktemp -d)"
  export TEST_HOME="$HOME"
  export OPENAI_API_KEY="test-openai-key"  # 用于测试环境变量模式
  export ZHIPU_API_KEY="test-zhipu-key"   # 用于测试环境变量模式

  # 加载脚本
  source "$SCRIPT_DIR/claude-switcher.sh"

  # 清理环境变量
  unset ANTHROPIC_BASE_URL
  unset ANTHROPIC_AUTH_TOKEN
  unset ANTHROPIC_DEFAULT_HAIKU_MODEL
  unset ANTHROPIC_DEFAULT_SONNET_MODEL
  unset ANTHROPIC_DEFAULT_OPUS_MODEL
  unset CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS
}

teardown() {
  rm -rf "$TEST_HOME"
}

# ============================================
# 模板功能测试
# ============================================

@test "template_adds_zhipu_provider" {
  # 模拟模板函数的逻辑
  _cs_ensure_dirs
  local provider_file="$HOME/.claude-switcher/providers/zhipu.conf"

  # 获取模板内容
  local template_content
  template_content=$(_cs_get_template "zhipu") || {
    _cs_red "错误: 未知模板 'zhipu'"
    return 1
  }

  # 创建配置文件
  : > "$provider_file"
  chmod 600 "$provider_file"

  # 写入模板配置，避免覆盖
  echo "$template_content" | while IFS= read -r line; do
    [[ "$line" =~ ^TOKEN_TYPE= ]] && continue
    [[ "$line" =~ ^TOKEN= ]] && continue
    echo "$line"
  done > "$provider_file.tmp"
  echo 'TOKEN_TYPE=""' >> "$provider_file.tmp"
  echo 'TOKEN=""' >> "$provider_file.tmp"
  mv "$provider_file.tmp" "$provider_file"
  chmod 600 "$provider_file"

  [ -f "$provider_file" ]

  local name
  name=$(_cs_read_conf "$provider_file" "PROVIDER_NAME")

  [ "$name" = "智谱 BigModel" ]
}

@test "template_fails_for_unknown_template" {
  run claude-switcher --template unknown
  [ "$status" -ne 0 ]
  [[ "$output" == *"未知模板"* ]]
}

@test "template_shows_available_templates" {
  run claude-switcher --template
  [ "$status" -ne 0 ]
  [[ "$output" == *"可用模板"* ]]
  [[ "$output" == *"openai"* ]]
  [[ "$output" == *"zhipu"* ]]
}

# ============================================
# Token 存储测试
# ============================================

@test "set_token_env_var_mode" {
  _cs_ensure_dirs
  local conf="$HOME/.claude-switcher/providers/envtest.conf"
  {
    echo 'PROVIDER_NAME="Env Test"'
    echo 'BASE_URL="https://example.com"'
    echo 'HAIKU_MODEL="test"'
    echo 'SONNET_MODEL="test"'
    echo 'OPUS_MODEL="test"'
  } > "$conf"

  # 直接调用内部函数，避免交互
  export TEST_VAR="test-value"  # 设置环境变量
  _cs_set_token_for envtest 2 "TEST_VAR"

  # 验证配置
  local token_type
  token_type=$(_cs_read_conf "$conf" "TOKEN_TYPE")
  [ "$token_type" = "env" ]

  local token_var
  token_var=$(_cs_read_conf "$conf" "TOKEN")
  [ "$token_var" = "TEST_VAR" ]
}

@test "set_token_encryption_mode" {
  _cs_ensure_dirs
  # 先创建配置文件
  local conf="$HOME/.claude-switcher/providers/encrypttest.conf"
  {
    echo 'PROVIDER_NAME="Encrypt Test"'
    echo 'BASE_URL="https://example.com"'
    echo 'HAIKU_MODEL="test"'
    echo 'SONNET_MODEL="test"'
    echo 'OPUS_MODEL="test"'
  } > "$conf"

  # 直接调用内部函数，避免交互
  _cs_set_token_for encrypttest 3 "sk-test-encrypted-token"

  # 验证配置
  local token_type token encrypted
  token_type=$(_cs_read_conf "$conf" "TOKEN_TYPE")
  token=$(_cs_read_conf "$conf" "TOKEN")
  encrypted=$(_cs_read_conf "$conf" "TOKEN_ENCRYPTED")

  [ "$token_type" = "plain" ]
  [ "$encrypted" = "true" ]
  # 注意：加密/解密测试需要openssl，这里只验证设置了加密标记
}

# ============================================
# 导入/导出功能测试
# ============================================

@test "export_creates_tar_file" {
  # 先添加一个测试提供商
  _cs_ensure_dirs
  local conf="$HOME/.claude-switcher/providers/exporttest.conf"
  {
    echo 'PROVIDER_NAME="Export Test"'
    echo 'BASE_URL="https://example.com"'
    echo 'TOKEN_TYPE="plain"'
    echo 'TOKEN="sk-export-test"'
    echo 'HAIKU_MODEL="test-haiku"'
  } > "$conf"
  _cs_write_conf "$HOME/.claude-switcher/config.conf" "CURRENT_PROVIDER" "exporttest"

  # 导出配置
  local export_file="$TEST_HOME/test-export.tar.gz"
  run _cs_export "$export_file"
  [ "$status" -eq 0 ]
  [ -f "$export_file" ]

  # 验证tar文件内容
  run tar -tzf "$export_file"
  [ "$status" -eq 0 ]
  [[ "$output" == *"providers/exporttest.conf"* ]]
  [[ "$output" == *"info.json"* ]]
}

@test "export_fails_for_existing_file" {
  local existing_file="$TEST_HOME/existing.tar.gz"
  touch "$existing_file"

  run _cs_export "$existing_file"
  [ "$status" -ne 0 ]
  [[ "$output" == *"已存在"* ]]
}

@test "export_fails_without_path" {
  run _cs_export
  [ "$status" -ne 0 ]
  [[ "$output" == *"请指定"* ]]
}

# ============================================
# 验证功能测试
# ============================================

@test "validate_reports_missing_token" {
  _cs_ensure_dirs
  local conf="$HOME/.claude-switcher/providers/valtest.conf"
  {
    echo 'PROVIDER_NAME="Validation Test"'
    echo 'BASE_URL="https://example.com"'
    # 故意不设置TOKEN
  } > "$conf"
  _cs_write_conf "$HOME/.claude-switcher/config.conf" "CURRENT_PROVIDER" "valtest"

  run claude-switcher --validate
  [ "$status" -eq 0 ]
  [[ "$output" == *"Token 未设置"* ]]
}

@test "validate_reports_env_var_missing" {
  _cs_ensure_dirs
  local conf="$HOME/.claude-switcher/providers/valenv.conf"
  {
    echo 'PROVIDER_NAME="Env Validation Test"'
    echo 'BASE_URL="https://example.com"'
    echo 'TOKEN_TYPE="env"'
    echo 'TOKEN="MISSING_ENV_VAR"'
  } > "$conf"
  _cs_write_conf "$HOME/.claude-switcher/config.conf" "CURRENT_PROVIDER" "valenv"

  run claude-switcher --validate
  [ "$status" -eq 0 ]
  [[ "$output" == *"环境变量"* ]]
  [[ "$output" == *"未设置"* ]]
}

@test "validate_shows_success_with_good_config" {
  _cs_ensure_dirs
  local conf="$HOME/.claude-switcher/providers/valgood.conf"
  {
    echo 'PROVIDER_NAME="Good Validation Test"'
    echo 'BASE_URL="https://example.com"'
    echo 'TOKEN_TYPE="plain"'
    echo 'TOKEN="sk-good-token"'
  } > "$conf"
  _cs_write_conf "$HOME/.claude-switcher/config.conf" "CURRENT_PROVIDER" "valgood"

  run claude-switcher --validate
  [ "$status" -eq 0 ]
  [[ "$output" == *"验证通过"* ]]
}

# ============================================
# 版本管理测试
# ============================================

@test "config_files_have_version_header" {
  # 使用 _cs_write_conf 创建配置文件，确保有版本头
  _cs_ensure_dirs
  local conf="$HOME/.claude-switcher/providers/versiontest.conf"
  _cs_write_conf "$conf" "PROVIDER_NAME" "Version Test"
  _cs_write_conf "$conf" "BASE_URL" "https://example.com"
  _cs_write_conf "$conf" "HAIKU_MODEL" "test"
  _cs_write_conf "$HOME/.claude-switcher/config.conf" "CURRENT_PROVIDER" "versiontest"

  [ -f "$conf" ]

  grep -q "^CONFIG_VERSION=" "$conf"
}

# ============================================
# 错误处理测试
# ============================================

@test "unknown_command_shows_help_with_new_options" {
  run claude-switcher --unknown-new-command
  [ "$status" -ne 0 ]
  [[ "$output" == *"未知参数"* ]]
  [[ "$output" == *"用法"* ]]
}