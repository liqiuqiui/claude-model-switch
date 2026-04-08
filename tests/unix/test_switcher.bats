#!/usr/bin/env bats
# ============================================
# claude-switcher.sh 测试用例
# ============================================

setup() {
  SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../unix" && pwd)"

  # 隔离配置目录，避免污染真实环境
  export HOME="$(mktemp -d)"
  export TEST_HOME="$HOME"

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
# 工具函数测试
# ============================================

@test "config_dir_returns_correct_path" {
  local result
  result=$(_cs_config_dir)
  [[ "$result" == "$HOME/.claude-switcher" ]]
}

@test "providers_dir_returns_correct_path" {
  local result
  result=$(_cs_providers_dir)
  [[ "$result" == "$HOME/.claude-switcher/providers" ]]
}

@test "ensure_dirs_creates_directories" {
  _cs_ensure_dirs
  [ -d "$HOME/.claude-switcher/providers" ]
}

@test "write_conf_creates_file_with_correct_content" {
  _cs_ensure_dirs
  local file="$HOME/.claude-switcher/test.conf"
  _cs_write_conf "$file" "KEY" "value123"
  run grep "^KEY=" "$file"
  [[ "$output" == *"value123"* ]]
}

@test "read_conf_reads_correct_value" {
  _cs_ensure_dirs
  local file="$HOME/.claude-switcher/test.conf"
  echo 'KEY="hello world"' > "$file"
  local result
  result=$(_cs_read_conf "$file" "KEY")
  [[ "$result" == "hello world" ]]
}

@test "read_conf_returns_empty_for_missing_file" {
  local result
  result=$(_cs_read_conf "/nonexistent/path.conf" "KEY")
  [[ -z "$result" ]]
}

@test "write_conf_updates_existing_key" {
  _cs_ensure_dirs
  local file="$HOME/.claude-switcher/test.conf"
  _cs_write_conf "$file" "KEY" "first"
  _cs_write_conf "$file" "KEY" "second"
  local result
  result=$(_cs_read_conf "$file" "KEY")
  [[ "$result" == "second" ]]
}

# ============================================
# --help
# ============================================

@test "help_shows_usage" {
  run claude-switcher --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"用法"* ]]
  [[ "$output" == *"claude-switcher"* ]]
}

@test "help_short_flag_works" {
  run claude-switcher -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"用法"* ]]
}

@test "help_shows_all_options" {
  run claude-switcher --help
  [[ "$output" == *"--list"* ]]
  [[ "$output" == *"--use"* ]]
  [[ "$output" == *"--add"* ]]
  [[ "$output" == *"--remove"* ]]
  [[ "$output" == *"--set-token"* ]]
  [[ "$output" == *"--set-model"* ]]
  [[ "$output" == *"--uninstall"* ]]
}

# ============================================
# 无参数 → 状态显示
# ============================================

@test "no_args_shows_no_provider_message" {
  run claude-switcher
  [ "$status" -eq 0 ]
  [[ "$output" == *"尚未激活"* ]]
}

# ============================================
# --list
# ============================================

@test "list_shows_no_providers_message_when_empty" {
  run claude-switcher --list
  [ "$status" -eq 0 ]
  [[ "$output" == *"尚未配置"* ]]
}

@test "list_short_flag_works" {
  run claude-switcher -l
  [ "$status" -eq 0 ]
}

@test "list_shows_configured_providers" {
  _cs_ensure_dirs
  local conf="$HOME/.claude-switcher/providers/zhipu.conf"
  {
    echo 'PROVIDER_NAME="智谱 BigModel"'
    echo 'BASE_URL="https://open.bigmodel.cn/api/anthropic"'
    echo 'TOKEN_TYPE=""'
    echo 'TOKEN=""'
    echo 'HAIKU_MODEL="glm-4-flash"'
    echo 'SONNET_MODEL="glm-4"'
    echo 'OPUS_MODEL="glm-5"'
  } > "$conf"

  run claude-switcher --list
  [ "$status" -eq 0 ]
  [[ "$output" == *"zhipu"* ]]
  [[ "$output" == *"智谱 BigModel"* ]]
}

# ============================================
# --use
# ============================================

@test "use_fails_without_id" {
  run claude-switcher --use
  [ "$status" -ne 0 ]
  [[ "$output" == *"请指定"* ]]
}

@test "use_fails_for_nonexistent_provider" {
  run claude-switcher --use nonexistent
  [ "$status" -ne 0 ]
  [[ "$output" == *"不存在"* ]]
}

@test "use_sets_env_vars_correctly" {
  _cs_ensure_dirs
  local conf="$HOME/.claude-switcher/providers/zhipu.conf"
  {
    echo 'PROVIDER_NAME="智谱 BigModel"'
    echo 'BASE_URL="https://open.bigmodel.cn/api/anthropic"'
    echo 'TOKEN_TYPE="plain"'
    echo 'TOKEN="sk-test-token"'
    echo 'HAIKU_MODEL="glm-4-flash"'
    echo 'SONNET_MODEL="glm-4"'
    echo 'OPUS_MODEL="glm-5"'
  } > "$conf"
  chmod 600 "$conf"

  _cs_use zhipu

  [ "$ANTHROPIC_BASE_URL" = "https://open.bigmodel.cn/api/anthropic" ]
  [ "$ANTHROPIC_AUTH_TOKEN" = "sk-test-token" ]
  [ "$ANTHROPIC_DEFAULT_HAIKU_MODEL" = "glm-4-flash" ]
  [ "$ANTHROPIC_DEFAULT_SONNET_MODEL" = "glm-4" ]
  [ "$ANTHROPIC_DEFAULT_OPUS_MODEL" = "glm-5" ]
  [ "$CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS" = "true" ]
}

@test "use_saves_current_provider" {
  _cs_ensure_dirs
  local conf="$HOME/.claude-switcher/providers/testprov.conf"
  {
    echo 'PROVIDER_NAME="Test"'
    echo 'BASE_URL="https://example.com"'
    echo 'TOKEN_TYPE="plain"'
    echo 'TOKEN="sk-test"'
    echo 'HAIKU_MODEL="model1"'
    echo 'SONNET_MODEL="model1"'
    echo 'OPUS_MODEL="model1"'
  } > "$conf"
  chmod 600 "$conf"

  _cs_use testprov

  local current
  current=$(_cs_current_provider)
  [ "$current" = "testprov" ]
}

@test "use_outputs_success_message" {
  _cs_ensure_dirs
  local conf="$HOME/.claude-switcher/providers/zhipu.conf"
  {
    echo 'PROVIDER_NAME="智谱 BigModel"'
    echo 'BASE_URL="https://open.bigmodel.cn/api/anthropic"'
    echo 'TOKEN_TYPE="plain"'
    echo 'TOKEN="sk-test"'
    echo 'HAIKU_MODEL="glm-4-flash"'
    echo 'SONNET_MODEL="glm-4"'
    echo 'OPUS_MODEL="glm-5"'
  } > "$conf"
  chmod 600 "$conf"

  run claude-switcher --use zhipu
  [ "$status" -eq 0 ]
  [[ "$output" == *"已切换"* ]]
  [[ "$output" == *"zhipu"* ]]
}

@test "use_resolves_env_token_type" {
  _cs_ensure_dirs
  local conf="$HOME/.claude-switcher/providers/envprov.conf"
  {
    echo 'PROVIDER_NAME="Env Provider"'
    echo 'BASE_URL="https://example.com"'
    echo 'TOKEN_TYPE="env"'
    echo 'TOKEN="MY_API_KEY"'
    echo 'HAIKU_MODEL="model1"'
    echo 'SONNET_MODEL="model1"'
    echo 'OPUS_MODEL="model1"'
  } > "$conf"
  chmod 600 "$conf"

  export MY_API_KEY="actual-secret-token"
  _cs_use envprov
  [ "$ANTHROPIC_AUTH_TOKEN" = "actual-secret-token" ]
}

# ============================================
# --remove
# ============================================

@test "remove_fails_without_id" {
  run claude-switcher --remove
  [ "$status" -ne 0 ]
}

@test "remove_fails_for_nonexistent_provider" {
  run claude-switcher --remove nonexistent
  [ "$status" -ne 0 ]
  [[ "$output" == *"不存在"* ]]
}

@test "remove_deletes_provider_file" {
  _cs_ensure_dirs
  local conf="$HOME/.claude-switcher/providers/todel.conf"
  {
    echo 'PROVIDER_NAME="ToDelete"'
    echo 'BASE_URL="https://example.com"'
  } > "$conf"

  echo "y" | _cs_remove todel
  [ ! -f "$conf" ]
}

# ============================================
# --set-model
# ============================================

@test "set_model_fails_without_model_args" {
  _cs_ensure_dirs
  local conf="$HOME/.claude-switcher/providers/prov.conf"
  {
    echo 'PROVIDER_NAME="Prov"'
    echo 'BASE_URL="https://example.com"'
  } > "$conf"
  _cs_write_conf "$HOME/.claude-switcher/config.conf" "CURRENT_PROVIDER" "prov"

  run claude-switcher --set-model
  [ "$status" -ne 0 ]
  [[ "$output" == *"至少指定"* ]]
}

@test "set_model_updates_haiku_only" {
  _cs_ensure_dirs
  local conf="$HOME/.claude-switcher/providers/prov.conf"
  {
    echo 'PROVIDER_NAME="Prov"'
    echo 'BASE_URL="https://example.com"'
    echo 'HAIKU_MODEL="old-haiku"'
    echo 'SONNET_MODEL="old-sonnet"'
    echo 'OPUS_MODEL="old-opus"'
  } > "$conf"
  _cs_write_conf "$HOME/.claude-switcher/config.conf" "CURRENT_PROVIDER" "prov"

  _cs_set_model --set-model --haiku new-haiku

  local result
  result=$(_cs_read_conf "$conf" "HAIKU_MODEL")
  [ "$result" = "new-haiku" ]
  result=$(_cs_read_conf "$conf" "SONNET_MODEL")
  [ "$result" = "old-sonnet" ]
}

@test "set_model_updates_all_tiers" {
  _cs_ensure_dirs
  local conf="$HOME/.claude-switcher/providers/prov.conf"
  {
    echo 'PROVIDER_NAME="Prov"'
    echo 'BASE_URL="https://example.com"'
  } > "$conf"
  _cs_write_conf "$HOME/.claude-switcher/config.conf" "CURRENT_PROVIDER" "prov"

  _cs_set_model --set-model --haiku h-model --sonnet s-model --opus o-model

  [ "$(_cs_read_conf "$conf" "HAIKU_MODEL")"  = "h-model" ]
  [ "$(_cs_read_conf "$conf" "SONNET_MODEL")" = "s-model" ]
  [ "$(_cs_read_conf "$conf" "OPUS_MODEL")"   = "o-model" ]
}

@test "set_model_with_explicit_provider" {
  _cs_ensure_dirs
  local conf="$HOME/.claude-switcher/providers/other.conf"
  {
    echo 'PROVIDER_NAME="Other"'
    echo 'BASE_URL="https://example.com"'
    echo 'HAIKU_MODEL="old"'
  } > "$conf"

  _cs_set_model --set-model --haiku new-model --provider other

  [ "$(_cs_read_conf "$conf" "HAIKU_MODEL")" = "new-model" ]
}

@test "set_model_syncs_env_vars_for_active_provider" {
  _cs_ensure_dirs
  local conf="$HOME/.claude-switcher/providers/active.conf"
  {
    echo 'PROVIDER_NAME="Active"'
    echo 'BASE_URL="https://example.com"'
    echo 'TOKEN_TYPE="plain"'
    echo 'TOKEN="sk-x"'
    echo 'HAIKU_MODEL="old-h"'
    echo 'SONNET_MODEL="old-s"'
    echo 'OPUS_MODEL="old-o"'
  } > "$conf"
  chmod 600 "$conf"
  _cs_use active

  _cs_set_model --set-model --haiku new-h --sonnet new-s

  [ "$ANTHROPIC_DEFAULT_HAIKU_MODEL" = "new-h" ]
  [ "$ANTHROPIC_DEFAULT_SONNET_MODEL" = "new-s" ]
  [ "$ANTHROPIC_DEFAULT_OPUS_MODEL" = "old-o" ]
}

# ============================================
# 无效参数
# ============================================

@test "unknown_arg_returns_error" {
  run claude-switcher --invalid-flag
  [ "$status" -ne 0 ]
  [[ "$output" == *"未知参数"* ]]
}

@test "unknown_arg_shows_help" {
  run claude-switcher --invalid-flag
  [[ "$output" == *"用法"* ]]
}
