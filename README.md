# Claude 模型切换器

快速切换 Claude Code 使用的模型，支持 macOS、Linux 和 Windows。

## 功能特性

- 🔄 快速切换 Claude Code 使用的模型
- 🖥️ 跨平台支持（macOS、Linux、Windows）
- 🔧 易于扩展新的服务商
- 📦 简单的一键安装

## 安装

### macOS / Linux (Bash/Zsh)

```bash
curl -fsSL https://raw.githubusercontent.com/liqiuqiui/claude-model-switch/main/unix/install.sh | bash
```

安装后执行：

```bash
source ~/.zshrc  # 如果使用 zsh
# 或
source ~/.bashrc # 如果使用 bash
```

### Windows (PowerShell)

```powershell
iwr -useb https://raw.githubusercontent.com/liqiuqiui/claude-model-switch/main/windows/install.ps1 | iex
```

安装后重新打开 PowerShell 或执行：

```powershell
. $PROFILE
```

## 使用方法

### 切换模型

```bash
# 完整命令
claude-switch-model glm-5

# 简化命令
csm glm-5
```

### 列出可用模型

```bash
# 完整命令
claude-list-models

# 简化命令
clm
```

### 设置 API Token

```bash
# 完整命令
claude-set-token your-api-token

# 简化命令
cst your-api-token
```

### Windows PowerShell 命令

```powershell
# 切换模型
Claude-SwitchModel glm-5
csm glm-5  # 别名

# 列出模型
Claude-ListModels
clm  # 别名

# 设置 Token
Claude-SetToken your-api-token
cst your-api-token  # 别名
```

## 支持的模型

| 模型 | 服务商 |
|------|--------|
| glm-5 | 智谱 BigModel |
| glm-4 | 智谱 BigModel |

## 添加新服务商

编辑 `unix/claude-switch-model.sh`（或 `windows/claude-switch-model.ps1`），在 `case` 语句中添加新的服务商配置：

```bash
# Bash 示例
case "$model" in
  glm-*)
    provider="智谱 BigModel"
    base_url="https://open.bigmodel.cn/api/anthropic"
    ;;

  # 添加新服务商
  deepseek-*)
    provider="DeepSeek"
    base_url="https://api.deepseek.com"
    ;;
esac
```

## 命令别名

| 别名 | 完整命令 | 说明 |
|------|----------|------|
| `csm` | `claude-switch-model` | 切换模型 |
| `clm` | `claude-list-models` | 列出模型 |
| `cst` | `claude-set-token` | 设置 Token |

## 卸载

### macOS / Linux

1. 编辑 `~/.zshrc` 或 `~/.bashrc`
2. 删除以下标记之间的内容：
   ```bash
   # Claude 模型切换器 - 开始
   ... 删除这部分 ...
   # Claude 模型切换器 - 结束
   ```
3. 删除安装目录：
   ```bash
   rm -rf ~/.claude-switch-model
   ```

### Windows

1. 编辑 PowerShell 配置文件：
   ```powershell
   notepad $PROFILE
   ```
2. 删除 `# Claude 模型切换器 - 开始` 和 `# Claude 模型切换器 - 结束` 之间的内容
3. 删除安装目录：
   ```powershell
   Remove-Item -Recurse -Force "$env:USERPROFILE\.claude-switch-model"
   ```

## 开发

### 运行测试

**Bash 测试 (macOS/Linux):**

```bash
# 安装 bats
brew install bats-core  # macOS
# 或
sudo apt-get install bats  # Ubuntu

# 运行测试
bats tests/test_install.bats
bats tests/test_switch_model.bats
```

**PowerShell 测试 (Windows):**

```powershell
# 安装 Pester
Install-Module -Name Pester -Force -Scope CurrentUser

# 运行测试
Invoke-Pester -Path tests/
```

### 项目结构

```
claude-model-switch/
├── unix/                        # macOS / Linux 脚本
│   ├── install.sh               # 安装脚本
│   └── claude-switch-model.sh   # 函数定义
├── windows/                     # Windows 脚本
│   ├── install.ps1              # 安装脚本
│   └── claude-switch-model.ps1  # 函数定义
├── tests/                       # 测试文件
│   ├── test_install.bats        # Bash 安装测试
│   ├── test_switch_model.bats   # Bash 功能测试
│   ├── test_install.ps1         # PowerShell 安装测试
│   └── test_switch_model.ps1    # PowerShell 功能测试
├── .github/
│   └── workflows/
│       └── test.yml             # GitHub Actions 测试工作流
└── README.md
```

## 许可证

MIT License
