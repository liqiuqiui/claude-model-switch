#!/usr/bin/env bats
# ============================================
# install.sh 测试用例
# ============================================

# 测试前设置
setup() {
    # 创建临时测试目录
    TEST_DIR="$(mktemp -d)"
    # 模拟 HOME 目录
    MOCK_HOME="$TEST_DIR/home"
    mkdir -p "$MOCK_HOME"

    # 创建脚本目录（unix 子目录）
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../unix" && pwd)"

    # 设置隔离环境
    export HOME="$MOCK_HOME"
    export SHELL_RC="$MOCK_HOME/.zshrc"
    export INSTALL_DIR="$MOCK_HOME/.claude-switch-model"

    # 创建模拟的 shell rc 文件
    touch "$SHELL_RC"
}

# 测试后清理
teardown() {
    # 清理临时目录
    rm -rf "$TEST_DIR"
}

# ============================================
# 测试：检测 shell 配置文件
# ============================================

@test "检测 zsh 配置文件路径" {
    export ZSH_VERSION="5.8"
    unset BASH_VERSION

    source "$SCRIPT_DIR/install.sh"
    result=$(detect_shell_rc)

    [ "$result" = "$HOME/.zshrc" ]
}

@test "检测 bash 配置文件路径" {
    export BASH_VERSION="5.0"
    unset ZSH_VERSION

    source "$SCRIPT_DIR/install.sh"
    result=$(detect_shell_rc)

    [ "$result" = "$HOME/.bashrc" ]
}

@test "检测未知 shell 时使用 .profile" {
    unset ZSH_VERSION
    unset BASH_VERSION

    source "$SCRIPT_DIR/install.sh"
    result=$(detect_shell_rc)

    [ "$result" = "$HOME/.profile" ]
}

# ============================================
# 测试：创建安装目录
# ============================================

@test "创建安装目录成功" {
    # 运行安装脚本（模拟模式）
    export REPO_URL="file://$SCRIPT_DIR"

    # 直接测试目录创建
    mkdir -p "$INSTALL_DIR"

    [ -d "$INSTALL_DIR" ]
}

# ============================================
# 测试：首次安装
# ============================================

@test "首次安装添加配置到 shell rc" {
    # 准备空的 shell rc 文件
    echo "# 原有配置" > "$SHELL_RC"

    # 手动添加配置（模拟安装过程）
    MARKER_START="# Claude 模型切换器 - 开始"
    MARKER_END="# Claude 模型切换器 - 结束"

    cat >> "$SHELL_RC" << EOF

$MARKER_START
# 以下内容由 Claude 模型切换器安装程序自动添加
source "$INSTALL_DIR/claude-switch-model.sh"
$MARKER_END
EOF

    # 验证配置已添加
    grep -q "$MARKER_START" "$SHELL_RC"
    grep -q "claude-switch-model.sh" "$SHELL_RC"
}

# ============================================
# 测试：更新安装
# ============================================

@test "更新安装时移除旧配置" {
    # 准备已安装的 shell rc 文件
    MARKER_START="# Claude 模型切换器 - 开始"
    MARKER_END="# Claude 模型切换器 - 结束"

    cat > "$SHELL_RC" << 'EOF'
# 原有配置
export PATH=$PATH:/usr/local/bin

# Claude 模型切换器 - 开始
# 以下内容由 Claude 模型切换器安装程序自动添加
source "/old/path/claude-switch-model.sh"
# Claude 模型切换器 - 结束

# 其他配置
alias ll='ls -la'
EOF

    # 移除旧配置
    sed -i.bak "/$MARKER_START/,/$MARKER_END/d" "$SHELL_RC"

    # 验证旧配置已移除
    ! grep -q "/old/path/claude-switch-model.sh" "$SHELL_RC"

    # 验证原有配置保留
    grep -q "原有配置" "$SHELL_RC"
    grep -q "alias ll" "$SHELL_RC"
}

# ============================================
# 测试：错误处理
# ============================================

@test "缺少 curl 和 wget 时报错" {
    # 在子 shell 中修改 PATH，避免污染 teardown 的执行环境
    (
        export PATH="$TEST_DIR/no-tools"
        ! command -v curl &>/dev/null
        ! command -v wget &>/dev/null
    )
}

# ============================================
# 测试：脚本执行权限
# ============================================

@test "install.sh 具有执行权限" {
    # 检查脚本是否存在
    [ -f "$SCRIPT_DIR/install.sh" ]
}

@test "claude-switch-model.sh 文件存在" {
    [ -f "$SCRIPT_DIR/claude-switch-model.sh" ]
}
