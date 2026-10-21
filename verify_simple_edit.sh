#!/bin/bash

echo "==================================="
echo "✅ 简化版歌词编辑功能验证"
echo "==================================="
echo ""

echo "检查修改："
echo ""

# 检查是否添加了新状态变量
if grep -q "isEditingTime" LyricMist/LyricView.swift && grep -q "timeOffset: Double" LyricMist/LyricView.swift; then
    echo "✅ 状态变量已添加 (isEditingTime, timeOffset)"
else
    echo "❌ 状态变量缺失"
fi

# 检查是否有时间调整按钮
if grep -q "chevron.left" LyricMist/LyricView.swift && grep -q "arrow.counterclockwise" LyricMist/LyricView.swift; then
    echo "✅ 时间调整按钮已添加 (← 0.5秒, 重置, 0.5秒 →)"
else
    echo "❌ 时间调整按钮缺失"
fi

# 检查是否有调整时间函数
if grep -q "func adjustTime" LyricMist/LyricView.swift && grep -q "func resetTimeOffset" LyricMist/LyricView.swift; then
    echo "✅ 时间调整函数已实现"
else
    echo "❌ 时间调整函数缺失"
fi

# 检查是否在鼠标移开时退出编辑模式
if grep -q "if !hovering && isEditingTime" LyricMist/LyricView.swift; then
    echo "✅ 鼠标移开退出编辑模式逻辑已实现"
else
    echo "❌ 鼠标移开逻辑缺失"
fi

# 检查 LyricStorage 和 LyricEditorView 是否在项目中
storage_in_project=$(grep -c "LyricStorage.swift" LyricMist.xcodeproj/project.pbxproj)
if [ "$storage_in_project" -eq 4 ]; then
    echo "✅ LyricStorage.swift 已在项目中"
else
    echo "⚠️  LyricStorage.swift 在项目中的引用: $storage_in_project (应为 4)"
fi

echo ""
echo "==================================="
echo "功能说明："
echo "==================================="
echo ""
echo "1. 悬停显示 5 个按钮："
echo "   上一首 | 播放/暂停 | 下一首 | 编辑时间 | 锁定"
echo ""
echo "2. 点击编辑按钮 (🕐) → 显示 3 个时间调整按钮："
echo "   ← 0.5秒 | 重置 | 0.5秒 →"
echo ""
echo "3. 鼠标移开 → 自动保存并退出编辑模式"
echo ""
echo "4. 再次悬停 → 恢复显示原始 5 个按钮"
echo ""

