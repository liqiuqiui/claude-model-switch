#!/bin/bash
# ============================================
# 统一测试运行脚本
# ============================================

set -e

echo "=========================================="
echo "  Claude Switcher 测试套件"
echo "=========================================="

echo ""
echo "🖥️  运行 Unix/Linux 测试..."
echo "----------------------------------------"
bats tests/unix/test_install.bats
bats tests/unix/test_switcher.bats
bats tests/unix/test_new_features.bats
echo "✅ Unix 测试全部通过"

echo ""
echo "🪟 运行 Windows 测试..."
echo "----------------------------------------"
echo "请在 PowerShell 中运行以下命令："
echo "  Install-Module -Name Pester -Force -Scope CurrentUser"
echo "  Invoke-Pester -Path tests/windows/"
echo ""

echo "=========================================="
echo "  所有测试完成！"
echo "=========================================="