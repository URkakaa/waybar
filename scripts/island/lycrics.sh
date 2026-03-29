#!/usr/bin/env bash
# 去掉 -e，防止因为一个命令失败就导致整个脚本退出
set -uo pipefail

# ===================== 配置区 =====================
# 还原原有时间配置，无需调大
ISLAND_HOST="localhost"
ISLAND_PORT=4090
LYRIC_DIR="/home/kakaa/Music/win_music/lrc"
REFRESH_INTERVAL=1
PAUSED_INTERVAL=3
LYRIC_OFFSET=-1000

STOPPED_MESSAGE="    󰎆    "
PLAYING_ICON=" "
PAUSED_ICON=" "
NO_LYRIC_TIP=" (无歌词)"

PLAY_CLASS="play"
PAUSE_CLASS="paused"
STOP_CLASS="stop"

# MPD 相关配置
MPD_CONF="${HOME}/.mpd/mpd.conf" # MPD配置文件路径，按需调整

# ===================== 辅助函数 =====================
# 推送停止状态的payload（还原默认歌词）
send_stop_payload() {
  local stop_payload="${STOP_CLASS}/${STOPPED_MESSAGE}"
  echo "${stop_payload}" | socat - TCP:${ISLAND_HOST}:${ISLAND_PORT} 2>/dev/null || true
  echo "🔄 已推送停止状态，歌词恢复默认"
}

# 清理函数（退出时先清歌词，再关mpd）
cleanup() {
  echo "🛑 脚本退出，执行清理..."
  # 第一步：强制推送停止状态，恢复默认歌词
  send_stop_payload
  # 第二步：关闭mpd
  if pgrep -x "mpd" >/dev/null 2>&1; then
    echo "🔌 关闭MPD后台..."
    pkill -x "mpd" 2>/dev/null || sudo pkill -x "mpd" 2>/dev/null
  fi
  exit 0
}

# 注册清理函数（捕获所有退出信号）
trap cleanup SIGINT SIGTERM EXIT

# ===================== 启动脚本时自动启动MPD =====================
echo "🔍 检查MPD运行状态..."
if ! pgrep -x "mpd" >/dev/null 2>&1; then
  echo "🚀 MPD 未运行，正在启动..."
  # 启动mpd（先尝试默认配置，再尝试指定配置）
  if ! mpd 2>/dev/null; then
    if [ -f "${MPD_CONF}" ]; then
      mpd "${MPD_CONF}" 2>/dev/null || {
        echo "❌ MPD 启动失败！配置文件路径：${MPD_CONF}"
        echo "   请手动执行 mpd 命令检查错误，或确认配置文件是否正确"
      }
    else
      echo "❌ MPD 启动失败！未找到配置文件：${MPD_CONF}"
    fi
  fi
  # 等待mpd就绪
  sleep 1
  # 再次检查是否启动成功
  if pgrep -x "mpd" >/dev/null 2>&1; then
    echo "✅ MPD 启动成功"
  else
    echo "❌ MPD 最终启动失败，脚本将继续运行（仅歌词推送失效）"
  fi
else
  echo "✅ MPD 已在后台运行"
fi

mkdir -p "${LYRIC_DIR}"
last_song=""
last_lyric=""
lyrics=""
force_send_count=0
# 记录上一次的状态，用于判断状态变化
last_state=""

parse_time() {
  local time_str="$1"
  if [[ "${time_str}" =~ ^([0-9]{2}):([0-9]{2})\.([0-9]{2,3})$ ]]; then
    local min="${BASH_REMATCH[1]}" sec="${BASH_REMATCH[2]}" ms="${BASH_REMATCH[3]}"
    echo $((10#${min} * 60000 + 10#${sec} * 1000 + 10#${ms:0:3}))
  else echo 0; fi
}

load_lyrics() {
  local lyric_path="$1"
  if [[ ! -f "${lyric_path}" ]]; then
    echo ""
    return
  fi
  grep -E '\[[0-9]{2}:[0-9]{2}\.[0-9]{2,3}\]' "${lyric_path}" 2>/dev/null | while read -r line || [[ -n "$line" ]]; do
    time_str="$(echo "${line}" | grep -oE '[0-9]{2}:[0-9]{2}\.[0-9]{2,3}' | head -1)"
    text="$(echo "${line}" | sed -E 's/\[?[0-9]{2}:[0-9]{2}\.[0-9]{2,3}\]?\s*//')"
    echo "$(parse_time "${time_str}") ${text}"
  done || true
}

# ===================== 核心循环 =====================
while true; do
  status_info=$(mpc status -f "[[%artist% - %title%]]" 2>/dev/null || echo "stopped")

  # 判断当前状态
  if echo "$status_info" | grep -q "playing"; then
    state="playing"
    current_song=$(echo "${status_info}" | head -n 1)
  elif echo "$status_info" | grep -q "paused"; then
    state="paused"
    current_song=$(echo "${status_info}" | head -n 1)
  else
    state="stopped"
    current_song=""
  fi

  # 构造当前payload
  if [[ "${state}" == "stopped" ]]; then
    message="${STOPPED_MESSAGE}"
    send_class="${STOP_CLASS}"
    sleep_time="${PAUSED_INTERVAL}"
  else
    if [[ "${state}" == "playing" ]]; then
      # 播放状态：原有逻辑不变，正常刷新歌词
      time_pos=$(echo "${status_info}" | grep -oE '([0-9]{1,2}:[0-9]{2})/' | tr -d '/' | head -1 || echo "0:00")
      [[ "${time_pos}" =~ ^([0-9]{1}):([0-9]{2})$ ]] && time_pos="0${time_pos}"
      time_pos_ms=$(parse_time "${time_pos}.00")

      if [[ "${current_song}" != "${last_song}" ]]; then
        last_song="${current_song}"
        lyrics=$(load_lyrics "${LYRIC_DIR}/${current_song}.txt")
      fi

      if [[ -n "${lyrics}" ]]; then
        current_lyric=""
        while read -r ts text; do
          if [ -z "$ts" ]; then continue; fi
          if [ "${ts}" -le $((time_pos_ms - LYRIC_OFFSET)) ]; then
            current_lyric="${text}"
          else
            break
          fi
        done <<<"${lyrics}"
        message="${current_lyric:-${current_song}}"
      else
        message="${current_song}${NO_LYRIC_TIP}"
      fi
      message="${PLAYING_ICON}${message}"
      send_class="${PLAY_CLASS}"
      sleep_time="${REFRESH_INTERVAL}"
    else
      # 暂停状态：固定构造payload，无任何动态变化
      message="${PAUSED_ICON}${current_song}"
      send_class="${PAUSE_CLASS}"
      sleep_time="${PAUSED_INTERVAL}"
    fi
  fi
  full_payload="${send_class}/${message}"

  # ========== 核心修改：按状态区分推送规则 ==========
  if [[ "${state}" == "playing" ]]; then
    # 播放状态：原有心跳逻辑不变，正常刷新歌词
    if [[ "${full_payload}" != "${last_lyric}" ]] || [ "$force_send_count" -ge 2 ]; then
      echo "${full_payload}" | socat - TCP:${ISLAND_HOST}:${ISLAND_PORT} 2>/dev/null || true
      last_lyric="${full_payload}"
      force_send_count=0
    else
      ((force_send_count++))
    fi
  elif [[ "${state}" == "paused" ]]; then
    # 暂停状态：仅「状态变化（非暂停→暂停）」时推送一次，后续永不重复推
    if [[ "${last_state}" != "paused" ]]; then
      echo "${full_payload}" | socat - TCP:${ISLAND_HOST}:${ISLAND_PORT} 2>/dev/null || true
      last_lyric="${full_payload}"
      force_send_count=0
    fi
  else
    # 停止状态：原有心跳逻辑不变，保留断流归位
    if [[ "${full_payload}" != "${last_lyric}" ]] || [ "$force_send_count" -ge 2 ]; then
      echo "${full_payload}" | socat - TCP:${ISLAND_HOST}:${ISLAND_PORT} 2>/dev/null || true
      last_lyric="${full_payload}"
      force_send_count=0
    else
      ((force_send_count++))
    fi
  fi

  # 更新上一次状态
  last_state="${state}"
  sleep "${sleep_time}"
done
