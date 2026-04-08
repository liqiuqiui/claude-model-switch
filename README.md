# Claude Switcher

一个跨平台命令行工具，用于快速管理并切换 Claude Code 所使用的底层模型和服务商。

支持 **macOS / Linux（Bash/Zsh）** 和 **Windows（PowerShell）**。

---

## 功能特性

- **统一入口**：所有操作通过 `claude-switcher` 单命令 + 参数完成
- **本地配置文件**：服务商信息持久化存储在 `~/.claude-switcher/`
- **多服务商管理**：添加、切换、删除任意服务商
- **灵活 Token 存储**：支持明文存储（权限 600）和引用环境变量两种方式
- **分层模型配置**：为每个服务商单独配置 Haiku / Sonnet / Opus 三个层级的模型
- **安全卸载**：提供卸载命令，可选是否同时清除配置文件

---

## 安装

### macOS / Linux

```bash
curl -fsSL https://raw.githubusercontent.com/liqiuqiui/claude-model-switch/main/unix/install.sh | bash
```

安装完成后按提示执行：

```bash
# 第 1 步：重新加载 shell 配置
source ~/.zshrc   # 或 ~/.bashrc

# 第 2 步：添加服务商（交互式）
claude-switcher --add zhipu

# 第 3 步：切换到该服务商
claude-switcher --use zhipu
```

### Windows（PowerShell）

```powershell
iwr -useb https://raw.githubusercontent.com/liqiuqiui/claude-model-switch/main/windows/install.ps1 | iex
```

安装完成后：

```powershell
# 第 1 步：重新加载 profile
. $PROFILE

# 第 2 步：添加服务商（交互式）
claude-switcher --add zhipu

# 第 3 步：切换到该服务商
claude-switcher --use zhipu
```

---

## 命令参考

```
用法: claude-switcher [选项]

选项:
  (无参数)                               显示当前激活的配置状态
  --help,  -h                            显示帮助
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
```

### 示例

```bash
# 添加智谱 BigModel 服务商（交互式引导）
claude-switcher --add zhipu

# 切换到指定服务商
claude-switcher --use zhipu

# 查看当前状态和环境变量
claude-switcher

# 列出所有服务商
claude-switcher --list

# 为当前服务商设置 Token
claude-switcher --set-token

# 为指定服务商设置 Token
claude-switcher --set-token --provider zhipu

# 配置三个层级的模型（当前服务商）
claude-switcher --set-model --haiku glm-4-flash --sonnet glm-4 --opus glm-5

# 仅修改 sonnet 层级（其他层级不变）
claude-switcher --set-model --sonnet glm-4

# 为指定服务商配置模型
claude-switcher --set-model --haiku glm-4-flash --provider zhipu

# 删除服务商
claude-switcher --remove zhipu

# 卸载（提示是否同时删除配置文件）
claude-switcher --uninstall
```

---

## 配置文件结构

安装后，配置文件存储在：

```
~/.claude-switcher/
  config.conf           # 当前激活的服务商
  providers/
    zhipu.conf          # 每个服务商一个文件（权限 600）
    deepseek.conf
    ...
```

每个服务商配置文件格式：

```bash
PROVIDER_NAME="智谱 BigModel"
BASE_URL="https://open.bigmodel.cn/api/anthropic"
TOKEN_TYPE="plain"         # plain = 明文 | env = 读取环境变量
TOKEN="sk-xxxxxx"          # plain 时为 token 值，env 时为变量名
HAIKU_MODEL="glm-4-flash"
SONNET_MODEL="glm-4"
OPUS_MODEL="glm-5"
```

---

## Token 存储方式

添加或更新 Token 时，可选择两种存储方式：

| 方式 | 说明 | 适合场景 |
|------|------|----------|
| **明文存储** | Token 写入配置文件，文件权限自动设为 600 | 个人机器，追求简便 |
| **引用环境变量** | 配置文件只存变量名，运行时从环境变量读取 | 团队机器，追求安全 |

---

## 卸载

```bash
claude-switcher --uninstall
```

执行后会提示：
- 从 shell rc 文件中移除 source 配置
- 是否同时删除 `~/.claude-switcher/` 配置目录（默认：是）

---

## 开发与测试

```bash
# 运行 Unix 测试（需要 bats-core）
bats tests/test_install.bats
bats tests/test_switcher.bats
```

```powershell
# 运行 Windows 测试（需要 Pester）
Install-Module -Name Pester -Force -Scope CurrentUser
Invoke-Pester -Path tests/
```

CI 在 push / PR 时自动运行：macOS、Ubuntu 的 bats 测试，Windows 的 Pester 测试，以及所有脚本的语法检查。
