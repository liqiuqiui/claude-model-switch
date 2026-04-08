#!/bin/bash

# ============================================
# Claude 模型切换器 - 安装脚本
# ============================================
# 使用方法:
#   curl -fsSL <安装地址>/install.sh | bash
#
# 安装流程:
#   1. 检测当前 shell 类型
#   2. 下载脚本文件到本地
#   3. 添加 source 配置到 shell 配置文件
# ============================================

set -e

# ============================================
# 配置项（发布前请修改）
# ============================================
# 脚本托管的仓库地址（GitHub Raw 或其他可访问的 URL）
# 发布到 GitHub 时，将 liqiuqiui 改为你的用户名
REPO_URL="https://raw.githubusercontent.com/liqiuqiui/claude-model-switch/main/unix"

# 脚本文件名
SCRIPT_NAME="claude-switch-model.sh"

# 本地安装目录
INSTALL_DIR="$HOME/.claude-switch-model"

# ============================================
# 颜色定义
# ============================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # 重置颜色

# ============================================
# 函数定义
# ============================================

# 检测 shell 配置文件路径
# 返回: 当前 shell 对应的 rc 文件路径
detect_shell_rc() {
  if [ -n "$ZSH_VERSION" ]; then
    echo "$HOME/.zshrc"
  elif [ -n "$BASH_VERSION" ]; then
    echo "$HOME/.bashrc"
  else
    echo "$HOME/.profile"
  fi
}

# 打印错误信息并退出
# 参数: $1 - 错误信息
error_exit() {
  echo -e "${RED}错误: $1${NC}"
  exit 1
}

# ============================================
# 主安装流程
# ============================================
main() {
  echo -e "${GREEN}Claude 模型切换器 安装程序${NC}"
  echo ""

  # 检测 shell 配置文件
  SHELL_RC=$(detect_shell_rc)
  echo "检测到 shell 配置文件: $SHELL_RC"

  # 创建安装目录
  echo "创建安装目录: $INSTALL_DIR"
  mkdir -p "$INSTALL_DIR"

  # 下载脚本文件
  echo "正在下载脚本文件..."
  if command -v curl &> /dev/null; then
    curl -fsSL "$REPO_URL/$SCRIPT_NAME" -o "$INSTALL_DIR/$SCRIPT_NAME"
  elif command -v wget &> /dev/null; then
    wget -q "$REPO_URL/$SCRIPT_NAME" -O "$INSTALL_DIR/$SCRIPT_NAME"
  else
    error_exit "需要 curl 或 wget 才能继续安装"
  fi

  # 验证下载是否成功
  if [ ! -f "$INSTALL_DIR/$SCRIPT_NAME" ]; then
    error_exit "脚本下载失败，请检查网络连接或仓库地址"
  fi

  echo "脚本下载完成"

  # 安装标记（用于检测和卸载）
  MARKER_START="# Claude 模型切换器 - 开始"
  MARKER_END="# Claude 模型切换器 - 结束"

  # 检查是否已安装，如果已安装则先移除旧版本
  if grep -q "$MARKER_START" "$SHELL_RC" 2>/dev/null; then
    echo -e "${YELLOW}检测到已安装旧版本，正在更新...${NC}"
    # 删除旧的安装配置
    sed -i.bak "/$MARKER_START/,/$MARKER_END/d" "$SHELL_RC" 2>/dev/null || true
    # 删除备份文件
    rm -f "${SHELL_RC}.bak" 2>/dev/null || true
  fi

  # 添加配置到 shell 配置文件
  echo "正在配置 shell..."
  {
    echo ""
    echo "$MARKER_START"
    echo "# 以下内容由 Claude 模型切换器安装程序自动添加"
    echo "source \"$INSTALL_DIR/$SCRIPT_NAME\""
    echo "$MARKER_END"
  } >> "$SHELL_RC"

  # ============================================
  # 安装完成提示
  # ============================================
  echo ""
  echo -e "${GREEN}✓ 安装完成！${NC}"
  echo ""
  echo "请执行以下命令使配置生效："
  echo -e "  ${YELLOW}source $SHELL_RC${NC}"
  echo ""
  echo "然后即可使用以下命令："
  echo "  claude-switch-model glm-5    # 切换到 GLM-5 模型"
  echo "  claude-switch-model glm-4    # 切换到 GLM-4 模型"
  echo "  claude-list-models           # 列出所有可用模型"
  echo "  claude-set-token <token>     # 设置 API Token"
  echo ""
  echo -e "${YELLOW}注意：首次使用前需要设置 ANTHROPIC_AUTH_TOKEN 环境变量${NC}"
  echo -e "${YELLOW}可以通过 claude-set-token 命令或直接 export 设置${NC}"
}

# 仅在直接执行时运行主流程，source 时只加载函数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main
fi
