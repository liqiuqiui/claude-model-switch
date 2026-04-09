#!/bin/bash

# ============================================
# Claude Switcher - 安装脚本
# ============================================
# 使用方法:
#   curl -fsSL <安装地址>/install.sh | bash
#
# 安装流程:
#   1. 检测当前 shell 类型
#   2. 下载主脚本到本地
#   3. 添加 source 配置到 shell 配置文件
#   4. 提示用户下一步操作
# ============================================

set -e

# ============================================
# 配置项（发布前请修改）
# ============================================
REPO_URL="https://raw.githubusercontent.com/liqiuqiui/claude-model-switch/main/unix"
SCRIPT_NAME="claude-switcher.sh"
INSTALL_DIR="$HOME/.claude-switcher"

# ============================================
# 颜色定义
# ============================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

# ============================================
# 工具函数
# ============================================

detect_shell_rc() {
  case "$SHELL" in
    */zsh)  echo "$HOME/.zshrc" ;;
    */bash) echo "$HOME/.bashrc" ;;
    *)      echo "$HOME/.profile" ;;
  esac
}

error_exit() {
  echo -e "${RED}错误: $1${NC}" >&2
  exit 1
}

# ============================================
# 主安装流程
# ============================================
main() {
  echo -e "${BOLD}Claude Switcher 安装程序${NC}"
  echo ""

  local shell_rc
  shell_rc=$(detect_shell_rc)
  echo "检测到 shell 配置文件: $shell_rc"

  # 创建安装目录（主脚本与配置目录共用同一根目录）
  echo "创建安装目录: $INSTALL_DIR"
  mkdir -p "$INSTALL_DIR/providers"
  chmod 700 "$INSTALL_DIR"
  chmod 700 "$INSTALL_DIR/providers"

  # 下载主脚本
  echo "正在下载脚本文件..."
  local script_path="$INSTALL_DIR/$SCRIPT_NAME"
  if command -v curl &>/dev/null; then
    curl -fsSL "$REPO_URL/$SCRIPT_NAME" -o "$script_path"
  elif command -v wget &>/dev/null; then
    wget -q "$REPO_URL/$SCRIPT_NAME" -O "$script_path"
  else
    error_exit "需要 curl 或 wget 才能继续安装"
  fi

  if [[ ! -f "$script_path" ]]; then
    error_exit "脚本下载失败，请检查网络连接或仓库地址"
  fi
  echo "脚本下载完成"

  # 安装标记（用于后续更新和卸载定位）
  local marker_start="# Claude Switcher - 开始"
  local marker_end="# Claude Switcher - 结束"

  # 若已安装旧版本，先移除
  if grep -q "$marker_start" "$shell_rc" 2>/dev/null; then
    echo -e "${YELLOW}检测到已安装旧版本，正在更新...${NC}"
    local tmp="${shell_rc}.bak"
    sed "/$marker_start/,/$marker_end/d" "$shell_rc" > "$tmp" && mv "$tmp" "$shell_rc"
  fi

  # 注入 source 配置
  echo "正在配置 shell..."
  {
    echo ""
    echo "$marker_start"
    echo "# 以下内容由 Claude Switcher 安装程序自动添加，请勿手动修改"
    echo "source \"$script_path\""
    echo "$marker_end"
  } >> "$shell_rc"

  # ============================================
  # 安装完成 + 下一步引导
  # ============================================
  echo ""
  echo -e "${GREEN}✓ 安装完成！${NC}"
  echo ""
  echo -e "${BOLD}请按以下步骤开始使用:${NC}"
  echo ""
  echo -e "  ${BOLD}第 1 步${NC}: 重新加载 shell 配置"
  echo -e "    ${YELLOW}source $shell_rc${NC}"
  echo ""
  echo -e "  ${BOLD}第 2 步${NC}: 添加你的第一个服务商（交互式引导）"
  echo -e "    ${YELLOW}claude-switcher --add <id>${NC}"
  echo -e "    例如: claude-switcher --add zhipu"
  echo ""
  echo -e "  ${BOLD}第 3 步${NC}: 切换到该服务商"
  echo -e "    ${YELLOW}claude-switcher --use <id>${NC}"
  echo ""
  echo -e "  完成后 Claude Code 将自动使用你配置的模型。"
  echo ""
  echo -e "  运行 ${YELLOW}claude-switcher --help${NC} 查看所有可用命令。"
}

# 若被 source 则不执行主流程（兼容 curl | bash 管道执行）
(return 0 2>/dev/null) || main
