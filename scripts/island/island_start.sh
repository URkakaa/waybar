#!/usr/bin/env bash
set -euo pipefail

# ==================== 配置区 =====================
LISTEN_PORT="4090"
JSON_FILE="${HOME}/.config/waybar/scripts/island/data.txt"
LOCK_FILE="/tmp/island_start.lock"

DEFAULT_CLASS="stop"
DEFAULT_TEXT="        "

NOTIFY_DURATION=2      # 通知停留时间（秒）
IDLE_THRESHOLD=4       # 仅对stop状态生效，无需调大
REFRESH_INTERVAL="0.5" # Waybar 输出刷新率
CACHE_FILE="/tmp/island_lyric_cache"
# =================================================

# 1. 单实例锁
if [ -f "$LOCK_FILE" ] && ps -p $(cat "$LOCK_FILE") >/dev/null 2>&1; then
  exit 0
fi
echo "$$" >"$LOCK_FILE"

# 2. 清理函数
cleanup() {
  pkill -P $$ || true
  rm -f "${LOCK_FILE}" /tmp/island_last_update /tmp/island_expiry "${CACHE_FILE}"
  printf '{"class":"%s", "text":"%s"}\n' "${DEFAULT_CLASS}" "${DEFAULT_TEXT}" >"${JSON_FILE}"
  exit 0
}
trap cleanup SIGINT SIGTERM EXIT

# 3. 初始化状态
mkdir -p "$(dirname "${JSON_FILE}")"
echo 0 >/tmp/island_expiry
echo 0 >/tmp/island_last_update
>"${CACHE_FILE}"
printf '{"class":"%s", "text":"%s"}\n' "${DEFAULT_CLASS}" "${DEFAULT_TEXT}" >"${JSON_FILE}"

# 4. 监听与调度 (后台运行)
socat -u TCP-LISTEN:${LISTEN_PORT},reuseaddr,fork - | while IFS= read -r data || [[ -n "$data" ]]; do
  if [[ -n "${data}" && "${data}" == */* ]]; then
    state="${data%%/*}"
    text="${data#*/}"
    current_time=$(date +%s)

    expiry=$(cat /tmp/island_expiry 2>/dev/null || echo 0)
    write_allowed=false

    # 高优先级：通知类
    if [[ "$state" == "msg" || "$state" =~ ^notify- ]]; then
      # 仅缓存非通知/非默认状态
      current_content=$(cat "${JSON_FILE}" 2>/dev/null || "")
      if [[ ! "$current_content" =~ "\"class\":\"(stop|msg|notify-)\"" ]]; then
        echo "${current_content}" >"${CACHE_FILE}"
      fi
      echo $((current_time + NOTIFY_DURATION)) >/tmp/island_expiry
      write_allowed=true
    else
      # 低优先级：歌词类（play/paused/stop），通知过期后写入
      if [ "$expiry" -eq 0 ] || [ "$current_time" -ge "$expiry" ]; then
        write_allowed=true
      else
        continue
      fi
    fi

    if [ "$write_allowed" = true ]; then
      text_escaped=$(echo "$text" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\n/\\n/g')
      printf '{"class":"%s", "text":"%s"}\n' "$state" "$text_escaped" >"${JSON_FILE}"
      echo "$current_time" >/tmp/island_last_update
    fi
  fi
done &

# 5. 主循环：核心修改→按状态判断是否断流归位
while true; do
  current_time=$(date +%s)
  last_update=$(cat /tmp/island_last_update 2>/dev/null || echo 0)
  expiry=$(cat /tmp/island_expiry 2>/dev/null || echo 0)
  # 读取当前显示的class，用于判断状态类型
  current_class=$(cat "${JSON_FILE}" 2>/dev/null | grep -oE '"class":"[^"]+"' | cut -d'"' -f4 || echo "${DEFAULT_CLASS}")

  # 通知过期后恢复缓存的歌词状态（原有逻辑不变）
  if [ "$current_time" -gt "$expiry" ] && [ "$expiry" -ne 0 ]; then
    cached_lyric=$(cat "${CACHE_FILE}" 2>/dev/null || "")
    if [[ -n "${cached_lyric}" && "${cached_lyric}" != "{}" ]]; then
      echo "${cached_lyric}" >"${JSON_FILE}"
      echo "$current_time" >/tmp/island_last_update
    fi
    echo 0 >/tmp/island_expiry
    >"${CACHE_FILE}"
  fi

  # ========== 核心修改：仅当「当前是stop类状态」时，才执行断流归位 ==========
  # play/paused/notify-* 状态：永不归位到默认图标，彻底消除暂停闪烁
  if [ "$current_time" -gt "$expiry" ] && [[ "${current_class}" == "${DEFAULT_CLASS}" ]]; then
    idle_duration=$((current_time - last_update))
    if [ "${idle_duration}" -gt "${IDLE_THRESHOLD}" ]; then
      current_content=$(cat "${JSON_FILE}" 2>/dev/null || "")
      if [[ "$current_content" != *"${DEFAULT_TEXT}"* ]]; then
        printf '{"class":"%s", "text":"%s"}\n' "${DEFAULT_CLASS}" "${DEFAULT_TEXT}" >"${JSON_FILE}"
      fi
    fi
  fi

  # 输出给 Waybar
  if [[ -f "${JSON_FILE}" ]]; then
    cat "${JSON_FILE}"
  else
    printf '{"class":"%s", "text":"%s"}\n' "${DEFAULT_CLASS}" "${DEFAULT_TEXT}"
  fi

  sleep "${REFRESH_INTERVAL}"
done
