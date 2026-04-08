#!/usr/bin/env bats
# ============================================
# claude-switch-model.sh 测试用例
# ============================================

# 测试前设置
setup() {
    # 创建临时测试目录
    TEST_DIR="$(mktemp -d)"

    # 获取脚本目录（unix 子目录）
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../unix" && pwd)"

    # 非交互式 bash 默认不展开 alias，需手动开启才能测试别名
    shopt -s expand_aliases

    # Source 脚本以加载函数
    source "$SCRIPT_DIR/claude-switch-model.sh"
}

# 测试后清理
teardown() {
    # 清理环境变量
    unset ANTHROPIC_BASE_URL
    unset ANTHROPIC_AUTH_TOKEN
    unset ANTHROPIC_DEFAULT_HAIKU_MODEL
    unset ANTHROPIC_DEFAULT_SONNET_MODEL
    unset ANTHROPIC_DEFAULT_OPUS_MODEL
    unset CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS

    # 清理临时目录
    rm -rf "$TEST_DIR"
}

# ============================================
# 测试：无参数时显示用法
# ============================================

@test "show_usage_without_args" { # 无参数时显示用法提示
    run claude-switch-model

    [ "$status" -eq 1 ]
    [[ "$output" == *"用法"* ]]
    [[ "$output" == *"claude-switch-model"* ]]
}

# ============================================
# 测试：切换 glm-5 模型
# ============================================

@test "switch_to_glm5_model" { # 切换到 glm-5 模型
    run claude-switch-model glm-5

    [ "$status" -eq 0 ]
    [[ "$output" == *"已切换"* ]]
    [[ "$output" == *"glm-5"* ]]
    [[ "$output" == *"智谱 BigModel"* ]]
}

@test "glm5_env_vars_set_correctly" { # 切换 glm-5 后环境变量正确设置
    claude-switch-model glm-5 >/dev/null

    [ "$ANTHROPIC_BASE_URL" = "https://open.bigmodel.cn/api/anthropic" ]
    [ "$ANTHROPIC_DEFAULT_HAIKU_MODEL" = "glm-5" ]
    [ "$ANTHROPIC_DEFAULT_SONNET_MODEL" = "glm-5" ]
    [ "$ANTHROPIC_DEFAULT_OPUS_MODEL" = "glm-5" ]
    [ "$CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS" = "true" ]
}

# ============================================
# 测试：切换 glm-4 模型
# ============================================

@test "switch_to_glm4_model" { # 切换到 glm-4 模型
    run claude-switch-model glm-4

    [ "$status" -eq 0 ]
    [[ "$output" == *"已切换"* ]]
    [[ "$output" == *"glm-4"* ]]
}

@test "glm4_env_vars_set_correctly" { # 切换 glm-4 后环境变量正确设置
    claude-switch-model glm-4 >/dev/null

    [ "$ANTHROPIC_DEFAULT_HAIKU_MODEL" = "glm-4" ]
    [ "$ANTHROPIC_DEFAULT_SONNET_MODEL" = "glm-4" ]
    [ "$ANTHROPIC_DEFAULT_OPUS_MODEL" = "glm-4" ]
}

# ============================================
# 测试：切换大写模型名
# ============================================

@test "recognize_uppercase_glm5" { # 切换 GLM-5 大写模型名也能识别
    run claude-switch-model GLM-5

    [ "$status" -eq 0 ]
    [[ "$output" == *"智谱 BigModel"* ]]
}

@test "uppercase_glm5_env_vars" { # GLM-5 大写模型名环境变量正确设置
    claude-switch-model GLM-5 >/dev/null

    [ "$ANTHROPIC_DEFAULT_HAIKU_MODEL" = "GLM-5" ]
}

# ============================================
# 测试：未知前缀模型
# ============================================

@test "unknown_prefix_uses_default_provider" { # 未知前缀模型使用默认服务商
    run claude-switch-model unknown-model

    [ "$status" -eq 0 ]
    [[ "$output" == *"智谱 BigModel (默认)"* ]]
}

@test "unknown_model_env_vars" { # 未知模型环境变量正确设置
    claude-switch-model unknown-model >/dev/null

    [ "$ANTHROPIC_BASE_URL" = "https://open.bigmodel.cn/api/anthropic" ]
    [ "$ANTHROPIC_DEFAULT_HAIKU_MODEL" = "unknown-model" ]
}

# ============================================
# 测试：ANTHROPIC_AUTH_TOKEN 初始为空
# ============================================

@test "anthropic_auth_token_empty_initially" { # ANTHROPIC_AUTH_TOKEN 初始为空
    claude-switch-model glm-5 >/dev/null

    [ -z "$ANTHROPIC_AUTH_TOKEN" ]
}

# ============================================
# 测试：claude-list-models 命令
# ============================================

@test "claude_list_models_shows_available" { # claude-list-models 显示可用模型
    run claude-list-models

    [ "$status" -eq 0 ]
    [[ "$output" == *"可用的模型列表"* ]]
    [[ "$output" == *"glm-5"* ]]
    [[ "$output" == *"glm-4"* ]]
}

# ============================================
# 测试：claude-set-token 命令
# ============================================

@test "claude_set_token_usage_without_args" { # claude-set-token 无参数时显示用法
    run claude-set-token

    [ "$status" -eq 1 ]
    [[ "$output" == *"用法"* ]]
}

@test "claude_set_token_success" { # claude-set-token 设置 token 成功
    run claude-set-token "sk-test-token-123"

    [ "$status" -eq 0 ]
    [[ "$output" == *"已设置"* ]]
}

@test "claude_set_token_env_vars" { # claude-set-token 后环境变量正确设置
    claude-set-token "sk-test-token-456" >/dev/null

    [ "$ANTHROPIC_AUTH_TOKEN" = "sk-test-token-456" ]
}

# ============================================
# 测试：多次切换模型
# ============================================

@test "multiple_switch_env_vars_update" { # 多次切换模型环境变量更新正确
    claude-switch-model glm-5 >/dev/null
    [ "$ANTHROPIC_DEFAULT_HAIKU_MODEL" = "glm-5" ]

    claude-switch-model glm-4 >/dev/null
    [ "$ANTHROPIC_DEFAULT_HAIKU_MODEL" = "glm-4" ]

    claude-switch-model glm-5-plus >/dev/null
    [ "$ANTHROPIC_DEFAULT_HAIKU_MODEL" = "glm-5-plus" ]
}

# ============================================
# 测试：输出格式
# ============================================

@test "output_contains_warning" { # 输出包含警告提示
    run claude-switch-model glm-5

    [[ "$output" == *"ANTHROPIC_AUTH_TOKEN"* ]]
}

@test "output_contains_base_url" { # 输出包含 Base URL
    run claude-switch-model glm-5

    [[ "$output" == *"Base URL"* ]]
    [[ "$output" == *"open.bigmodel.cn"* ]]
}

# ============================================
# 测试：命令别名
# ============================================

@test "csm_alias_available" { # csm 别名可用
    # 检查别名是否定义
    type csm | grep -q "claude-switch-model"
}

@test "clm_alias_available" { # clm 别名可用
    type clm | grep -q "claude-list-models"
}

@test "cst_alias_available" { # cst 别名可用
    type cst | grep -q "claude-set-token"
}

@test "csm_alias_points_to_main" { # csm 别名指向 claude-switch-model
    alias csm | grep -q "claude-switch-model"
}

@test "cst_alias_points_to_set_token" { # cst 别名指向 claude-set-token
    alias cst | grep -q "claude-set-token"
}

@test "clm_alias_points_to_list_models" { # clm 别名指向 claude-list-models
    alias clm | grep -q "claude-list-models"
}
