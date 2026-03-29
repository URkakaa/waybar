#!/usr/bin/env bash
set -euo pipefail

# ===================== 配置区（可自定义） =====================
# kitty窗口类名（对应你的waybar样式/窗口规则）
KITTY_CLASS="ncmpcpp_island"
# mpd配置文件路径（默认路径，无需修改）
MPD_CONF="${HOME}/.mpd/mpd.conf"
# 错误通知标题
NOTIFY_TITLE="音乐启动脚本"

# ===================== 工具函数 =====================
# 发送通知（兼容之前的notify.sh，也兼容系统notify-send）
send_notify() {
  local icon="$1"
  local msg="$2"
  # 优先用你的waybar通知脚本，不存在则用系统通知
  if [ -f "${HOME}/.config/waybar/scripts/island/notify.sh" ]; then
    bash "${HOME}/.config/waybar/scripts/island/notify.sh" "notify-normal：${icon} ${msg}"
  else
    notify-send -u normal "${NOTIFY_TITLE}" "${icon} ${msg}"
  fi
}

# ===================== 核心逻辑 =====================
# 1. 检查mpd是否已启动，未启动则启动
if ! pgrep -x "mpd" >/dev/null 2>&1; then
  echo "🔍 MPD 未运行，正在启动..."
  # 启动mpd（指定配置文件，避免默认配置问题）
  mpd "${MPD_CONF}" 2>/dev/null || {
    send_notify "" "MPD 启动失败！"
    exit 1
  }
  # 短暂等待mpd完全启动（避免ncmpcpp连接不上）
  sleep 0.5
  send_notify "󰎆" "MPD 启动成功" # 音乐启动图标
else
  echo "✅ MPD 已在后台运行"
  send_notify "󰎈" "MPD 已运行，启动播放列表" # 音乐已运行图标
fi

# 2. 启动kitty并运行ncmpcpp（指定窗口类名）
echo "🚀 打开 ncmpcpp 窗口..."
kitty --class "${KITTY_CLASS}" ncmpcpp 2>/dev/null || {
  send_notify "" "ncmpcpp 启动失败！"
  exit 1
}

# 3. 可选：ncmpcpp退出后，是否自动关闭mpd（取消注释启用）
echo "🛑"

echo "✅ 操作完成"
exit 0
