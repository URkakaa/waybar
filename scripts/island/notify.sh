#!/usr/bin/env bash
set -uo pipefail

HOST="localhost"
PORT="4090"

TEXT="$*"

# 核心逻辑：按「notify-xxx：文本」格式拆分
# 1. 提取「：」前的部分作为class（如 notify-warning）
CLASS=$(echo "$TEXT" | awk -F '：' '{print $1}')
# 2. 提取「：」后的部分作为显示文本（如 剩余电量15%）
CONTENT=$(echo "$TEXT" | awk -F '：' '{$1=""; print substr($0,2)}')

# 处理边界：如果没有「：」，class用默认 notify-normal，文本用原内容
if [[ -z "$CONTENT" ]]; then
  CLASS="notify-normal"
  CONTENT="$TEXT"
fi

# 转义特殊字符（避免JSON解析错误）
ESC_CONTENT=$(echo "$CONTENT" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\n/\\n/g')

# 发送 payload：class/文本
echo "${CLASS}/${ESC_CONTENT}" | socat - TCP:$HOST:$PORT 2>/dev/null || true
