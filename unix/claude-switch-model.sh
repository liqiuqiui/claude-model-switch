# ============================================
# Claude 模型切换器
# 用于快速切换 Claude Code 使用的模型
# ============================================
# 使用方法：
#   source 此文件或添加到 shell 配置文件中
#   然后执行: claude-switch-model <模型名称>
# ============================================

# 切换 Claude 模型
# 参数: $1 - 模型名称 (如 glm-5, glm-4)
claude-switch-model() {
  local model="$1"

  # 参数检查
  if [ -z "$model" ]; then
    echo "用法: claude-switch-model <模型名称>"
    echo "示例: claude-switch-model glm-5"
    return 1
  fi

  # ============================================
  # 服务商配置
  # 根据模型前缀匹配对应的服务商
  # 添加新服务商时，在此处添加 case 分支
  # ============================================
  local base_url
  local provider

  case "$model" in
    # 智谱 AI BigModel 服务
    glm-*|GLM-*)
      provider="智谱 BigModel"
      base_url="https://open.bigmodel.cn/api/anthropic"
      ;;

    # 未来可扩展的服务商示例：
    # OpenAI 服务
    # openai-*)
    #   provider="OpenAI"
    #   base_url="https://api.openai.com/v1"
    #   ;;
    #
    # DeepSeek 服务
    # deepseek-*)
    #   provider="DeepSeek"
    #   base_url="https://api.deepseek.com"
    #   ;;

    # 未知前缀默认使用智谱 BigModel
    *)
      provider="智谱 BigModel (默认)"
      base_url="https://open.bigmodel.cn/api/anthropic"
      ;;
  esac

  # ============================================
  # 设置环境变量
  # 这些变量会被 Claude Code 读取使用
  # ============================================

  # API 基础地址
  export ANTHROPIC_BASE_URL="$base_url"

  # API 认证令牌（需要用户手动配置）
  export ANTHROPIC_AUTH_TOKEN=""

  # 模型配置 - 统一使用指定的模型
  export ANTHROPIC_DEFAULT_HAIKU_MODEL="$model"
  export ANTHROPIC_DEFAULT_SONNET_MODEL="$model"
  export ANTHROPIC_DEFAULT_OPUS_MODEL="$model"

  # 启用 Agent Teams 实验性功能
  export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=true

  # 输出切换结果
  echo "✓ 已切换 Claude 模型"
  echo "  模型: $model"
  echo "  服务商: $provider"
  echo "  Base URL: $base_url"
  echo ""
  echo "⚠ 请确保已设置 ANTHROPIC_AUTH_TOKEN 环境变量"
}

# 列出可用的模型
claude-list-models() {
  echo "可用的模型列表："
  echo "  glm-5    - GLM-5 (智谱 BigModel)"
  echo "  glm-4    - GLM-4 (智谱 BigModel)"
  echo ""
  echo "提示：可在 claude-switch-model.sh 中添加更多模型配置"
}

# 设置 API Token
# 参数: $1 - API Token 值
claude-set-token() {
  local token="$1"

  if [ -z "$token" ]; then
    echo "用法: claude-set-token <your-api-token>"
    echo "示例: claude-set-token sk-xxxxxxxx"
    return 1
  fi

  export ANTHROPIC_AUTH_TOKEN="$token"
  echo "✓ 已设置 ANTHROPIC_AUTH_TOKEN"
}

# ============================================
# 命令别名（简化命令输入）
# ============================================
alias csm='claude-switch-model'     # 切换模型
alias clm='claude-list-models'      # 列出模型
alias cst='claude-set-token'        # 设置 Token
