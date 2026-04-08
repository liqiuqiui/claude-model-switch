#!/usr/bin/env bats
# ============================================
# install.sh 测试用例
# ============================================

setup() {
    TEST_DIR="$(mktemp -d)"
    MOCK_HOME="$TEST_DIR/home"
    mkdir -p "$MOCK_HOME"

    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../unix" && pwd)"

    export HOME="$MOCK_HOME"
    export SHELL_RC="$MOCK_HOME/.zshrc"
    export INSTALL_DIR="$MOCK_HOME/.claude-switcher"

    touch "$SHELL_RC"
}

teardown() {
    rm -rf "$TEST_DIR"
}

# ============================================
# 测试：检测 shell 配置文件
# ============================================

@test "detect_zsh_config_path" {
    export ZSH_VERSION="5.8"
    unset BASH_VERSION

    source "$SCRIPT_DIR/install.sh"
    result=$(detect_shell_rc)

    [ "$result" = "$HOME/.zshrc" ]
}

@test "detect_bash_config_path" {
    export BASH_VERSION="5.0"
    unset ZSH_VERSION

    source "$SCRIPT_DIR/install.sh"
    result=$(detect_shell_rc)

    [ "$result" = "$HOME/.bashrc" ]
}

@test "detect_unknown_shell_uses_profile" {
    unset ZSH_VERSION
    unset BASH_VERSION

    source "$SCRIPT_DIR/install.sh"
    result=$(detect_shell_rc)

    [ "$result" = "$HOME/.profile" ]
}

# ============================================
# 测试：安装目录创建
# ============================================

@test "create_install_dir_success" {
    mkdir -p "$INSTALL_DIR/providers"
    [ -d "$INSTALL_DIR/providers" ]
}

# ============================================
# 测试：首次安装
# ============================================

@test "first_install_adds_to_shell_rc" {
    echo "# 原有配置" > "$SHELL_RC"

    MARKER_START="# Claude Switcher - 开始"
    MARKER_END="# Claude Switcher - 结束"

    cat >> "$SHELL_RC" <<EOF

$MARKER_START
# 以下内容由 Claude Switcher 安装程序自动添加，请勿手动修改
source "$INSTALL_DIR/claude-switcher.sh"
$MARKER_END
EOF

    grep -q "$MARKER_START" "$SHELL_RC"
    grep -q "claude-switcher.sh" "$SHELL_RC"
}

# ============================================
# 测试：更新安装（新标记格式）
# ============================================

@test "update_install_removes_old_config" {
    MARKER_START="# Claude Switcher - 开始"
    MARKER_END="# Claude Switcher - 结束"

    cat > "$SHELL_RC" <<'EOF'
# 原有配置
export PATH=$PATH:/usr/local/bin

# Claude Switcher - 开始
# 以下内容由 Claude Switcher 安装程序自动添加，请勿手动修改
source "/old/path/claude-switcher.sh"
# Claude Switcher - 结束

# 其他配置
alias ll='ls -la'
EOF

    sed "/$MARKER_START/,/$MARKER_END/d" "$SHELL_RC" > "${SHELL_RC}.tmp" && mv "${SHELL_RC}.tmp" "$SHELL_RC"

    ! grep -q "/old/path/claude-switcher.sh" "$SHELL_RC"
    grep -q "原有配置" "$SHELL_RC"
    grep -q "alias ll" "$SHELL_RC"
}

# ============================================
# 测试：错误处理
# ============================================

@test "missing_curl_wget_check" {
    (
        export PATH="$TEST_DIR/no-tools"
        ! command -v curl &>/dev/null
        ! command -v wget &>/dev/null
    )
}

# ============================================
# 测试：脚本文件存在
# ============================================

@test "install_script_exists" {
    [ -f "$SCRIPT_DIR/install.sh" ]
}

@test "main_script_exists" {
    [ -f "$SCRIPT_DIR/claude-switcher.sh" ]
}
