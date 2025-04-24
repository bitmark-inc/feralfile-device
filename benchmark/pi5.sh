#!/bin/bash

# Usage: ./monitor_chromium.sh <URL> <DURATION_SEC> <STARTUP_DELAY_SEC>
# Example: ./monitor_chromium.sh https://example.com 60 5

URL=${1:-"https://example.com"}
DURATION=${2:-60}
DELAY=${3:-5}

NUM_CORES=$(nproc)

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

get_cpu_usages() {
  # ----- Function: get total system time -----
  get_total_idle() {
    awk '/^cpu / { print $5 }' /proc/stat
  }

  get_total_sum() {
    awk '/^cpu / {
      sum=0; for (i=2; i<=5; i++) sum+=$i;
      print sum
    }' /proc/stat
  }

  # ----- Function: sum pid times (utime + stime) -----
  get_pids_time() {
    local sum=0
    for pid in $C_PIDS; do
      if [ -r "/proc/$pid/stat" ]; then
        t=$(awk '{print $14 + $15}' "/proc/$pid/stat")
        sum=$((sum + t))
      fi
    done
    echo "$sum"
  }

  # First snapshot
  total1=$(get_total_sum)
  idle1=$(get_total_idle)
  pids1=$(get_pids_time)

  sleep 1

  # Second snapshot
  total2=$(get_total_sum)
  idle2=$(get_total_idle)
  pids2=$(get_pids_time)

  # Delta
  total2=$(get_total_sum)
  idle2=$(get_total_idle)
  pids2=$(get_pids_time)

  # Calculate usage %
  total_delta=$((total2 - total1))
  idle_delta=$((idle2 - idle1))
  pids_delta=$((pids2 - pids1))

  if [ "$total_delta" -gt 0 ]; then
    sys_pct=$(awk "BEGIN { printf \"%.1f\", ($total_delta - $idle_delta) / $total_delta * 100 }")
    pid_pct=$(awk "BEGIN { printf \"%.1f\", $pids_delta / $total_delta * 100 }")
  else
    sys_pct="0.0"
    pid_pct="0.0"
  fi

  echo "$sys_pct $pid_pct"
}

get_cpu_avg_freq() {
  vcgencmd measure_clock arm | awk -F= '{print int($2/1000000)}'
}

get_soc_temp() {
  vcgencmd measure_temp | grep -oP '[0-9.]+'
}

get_tree_pids() {
  local q=("$1") a=("$1") kids
  while ((${#q[@]})); do
    kids=($(pgrep -P "${q[0]}")) && a+=("${kids[@]}")
    q=("${q[@]:1}" "${kids[@]}")
  done
  printf '%s ' "${a[@]}"
}

get_chromium_mem_stats() {
  local sum_kb=0
  for pid in $C_PIDS; do
    if [ -r "/proc/$pid/smaps" ]; then
      sum_kb=$((sum_kb + $(awk '/^Pss:/ {sum+=$2} END{print sum}' /proc/$pid/smaps)))
    elif [ -r "/proc/$pid/status" ]; then
      sum_kb=$((sum_kb + $(grep VmRSS /proc/$pid/status | awk '{print $2}')))
    fi
  done

  local mem_mb=$((sum_kb / 1024))
  local total_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
  local mem_pct=$(awk -v kb="$sum_kb" -v total="$total_kb" 'BEGIN{printf "%.1f", (kb / total) * 100}')
  echo "$mem_mb $mem_pct"
}

color_temp() {
  local t=$1
  if (($(echo "$t > 75" | bc -l))); then
    echo -e "${RED}${t}°C${NC}"
  elif (($(echo "$t > 60" | bc -l))); then
    echo -e "${YELLOW}${t}°C${NC}"
  else
    echo -e "${GREEN}${t}°C${NC}"
  fi
}

color_usage() {
  local u=$1
  if (($(echo "$u > 80" | bc -l))); then
    echo -e "${RED}${u}%${NC}"
  elif (($(echo "$u > 50" | bc -l))); then
    echo -e "${YELLOW}${u}%${NC}"
  else
    echo -e "${GREEN}${u}%${NC}"
  fi
}

get_gpu_usage() {
  local stat_file
  if [[ -r /sys/kernel/debug/dri/0/gpu_usage ]]; then
    stat_file="/sys/kernel/debug/dri/0/gpu_usage"
  elif [[ -r /sys/kernel/debug/dri/1/gpu_usage ]]; then
    stat_file="/sys/kernel/debug/dri/1/gpu_usage"
  else
    echo "0.0"
    return
  fi

  local tmp1=$(mktemp)
  local tmp2=$(mktemp)
  cat "$stat_file" > "$tmp1"
  sleep 1
  cat "$stat_file" > "$tmp2"

  local timestamp1 timestamp2 runtime1 runtime2 elapsed runtime_delta max=0
  local queues=("v3d_bin" "v3d_ren" "v3d_tfu" "v3d_csd" "v3d_cac")

  timestamp1=$(grep '^timestamp;' "$tmp1" | cut -d';' -f2)
  timestamp2=$(grep '^timestamp;' "$tmp2" | cut -d';' -f2)
  elapsed=$((timestamp2 - timestamp1))

  for q in "${queues[@]}"; do
    runtime1=$(grep "^$q" "$tmp1" | awk -F';' '{print $3}')
    runtime2=$(grep "^$q" "$tmp2" | awk -F';' '{print $3}')
    if [[ -n "$runtime1" && -n "$runtime2" && "$elapsed" -gt 0 ]]; then
      runtime_delta=$((runtime2 - runtime1))
      usage=$(echo "scale=3; ($runtime_delta / $elapsed)" | bc)
      max=$(awk -v u=$usage -v m=$max 'BEGIN{ print (u > m) ? u : m }')
    fi
  done

  rm -f "$tmp1" "$tmp2"
  awk -v u=$max 'BEGIN{ printf "%.1f", u * 100 }'
}

get_dev_info() {
  local freq usage

  if [[ -r /sys/kernel/debug/dri/0/measure_clock ]]; then
    freq=$(awk '/^cycles:/ { print int($2 / 1000000) }' /sys/kernel/debug/dri/0/measure_clock)
  else
    freq=$(vcgencmd measure_clock v3d | awk -F= '{print int($2/1000000)}')
  fi

  usage=$(get_gpu_usage)
  echo "$usage $freq"
}

# ─── FPS helper  (CDP → fallback 0) ──────────────────────────────────────────
DEBUG_PORT=9222

ws_url() { # first “page” target’s WS URL
  curl -s http://127.0.0.1:$DEBUG_PORT/json |
    jq -r '[ .[] | select(.type=="page") ][0].webSocketDebuggerUrl'
}

fps_from_metrics() { # tier-1 (fast, native)
  command -v websocat &>/dev/null || return
  local ws
  ws=$(ws_url)
  [[ -z $ws || $ws == null ]] && return
  websocat -n1 "$ws" <<<'{"id":1,"method":"Performance.enable"}' >/dev/null 2>&1
  websocat -n1 "$ws" <<<'{"id":2,"method":"Performance.getMetrics"}' |
    jq -r '.result.metrics[]? | select(.name=="FramesPerSecond") | .value' |
    awk '{printf "%.0f",$1}'
}

fps_from_rAF() { # Tier-2, always works
  command -v websocat &>/dev/null || return
  local ws
  ws=$(ws_url)
  [[ -z $ws || $ws == null ]] && return

  # JavaScript snippet: count rAF for 1s, return FPS
  local js='(async()=>{let c=0,s=performance.now();function f(ts){c++; if(ts-s<1000) requestAnimationFrame(f);}requestAnimationFrame(f);await new Promise(r=>setTimeout(r,1050));return Math.round(c*1000/(performance.now()-s));})();'

  printf '{"id":3,"method":"Runtime.evaluate","params":{"expression":"%s","awaitPromise":true,"returnByValue":true}}\n' \
    "$js" |
    websocat -n1 "$ws" |
    jq -r '.result.result.value // empty'
}

get_fps() {
  local fps

  # Tier-1: Performance.getMetrics
  fps=$(fps_from_metrics 2>/dev/null)
  if [[ $fps =~ ^[0-9]+$ && $fps -gt 0 ]]; then
    echo "$fps"
    return
  fi

  # Tier-2: one-second rAF counter
  fps=$(fps_from_rAF 2>/dev/null)
  if [[ $fps =~ ^[0-9]+$ && $fps -gt 0 ]]; then
    echo "$fps"
    return
  fi

  echo 0 # couldn’t measure
}

sum_CU=0 sum_SU=0 sum_CF=0 sum_ST=0 \
  sum_GU=0 sum_GF=0 sum_FPS=0 sum_GT=0 \
  sum_CM=0 sum_CMP=0 sum_SU_M=0 sum_SP=0
count=0

START_TS=$(date +%s)

chromium-browser "$URL" \
  --remote-debugging-port=$DEBUG_PORT \
  --kiosk \
  --no-first-run \
  --disable-sync \
  --disable-translate \
  --disable-infobars \
  --disable-features=TranslateUI \
  --disable-popup-blocking \
  --autoplay-policy=no-user-gesture-required \
  2>/dev/null &
ROOT=$!
C_PIDS=$(get_tree_pids "$ROOT")
echo "Launched Chromium (PID: $ROOT)"
sleep "$DELAY"

while kill -0 $ROOT 2>/dev/null; do
  NOW_TS=$(date +%s)
  ELAPSED=$((NOW_TS - START_TS))
  if ((DURATION > 0 && ELAPSED >= DURATION)); then
    echo "Exiting..."
    break
  fi
  C_PIDS=$(get_tree_pids "$ROOT")

  NOW=$(date "+%F %T")
  read SYS_CPU CHR_CPU <<<$(get_cpu_usages)
  read CHR_MEM CHR_MEM_PCT <<<$(get_chromium_mem_stats)
  CPU_FREQ=$(get_cpu_avg_freq)
  SOC_TEMP=$(get_soc_temp)
  read G_USAGE G_FREQ <<<$(get_dev_info)
  GPU_TEMP="$SOC_TEMP"
  read SYS_MEM_USED SYS_MEM_TOTAL <<<$(grep -E 'MemTotal|MemAvailable' /proc/meminfo | awk 'NR==1{t=$2} NR==2{a=$2} END{printf "%d %d",(t-a)/1024,t/1024}')
  SYS_MEM_PCT=$(awk "BEGIN{printf \"%.1f\", ($SYS_MEM_USED/$SYS_MEM_TOTAL)*100}")
  FPS=$(get_fps)

  echo "$NOW"
  echo "============================================================="
  printf "\n%(%F %T)T | PIDs: %s\n" -1 "$C_PIDS"
  printf "CPU : Chromium: %5s | System: %5s @%4s MHz | Temp: %s\n" \
    "$(color_usage $CHR_CPU)" "$(color_usage $SYS_CPU)" "$CPU_FREQ" "$(color_temp $SOC_TEMP)"
  printf "MEM : Chromium: %5s MB (%5s) | Sys: %5s/%5s MB (%5s)\n" \
    "$CHR_MEM" "$(color_usage $CHR_MEM_PCT)" "$SYS_MEM_USED" "$SYS_MEM_TOTAL" "$(color_usage $SYS_MEM_PCT)"
  printf "GPU : %5s @%4s MHz | FPS:%4s | Temp: %s\n" \
    "$(color_usage $G_USAGE)" "$G_FREQ" "$FPS" "$(color_temp $GPU_TEMP)"
  echo "============================================================="

  sum_CU=$(awk "BEGIN{print $sum_CU+$CHR_CPU}")
  sum_SU=$(awk "BEGIN{print $sum_SU+$SYS_CPU}")
  sum_CF=$(awk "BEGIN{print $sum_CF+$CPU_FREQ}")
  sum_ST=$(awk "BEGIN{print $sum_ST+$SOC_TEMP}")
  sum_GU=$(awk "BEGIN{print $sum_GU+$G_USAGE}")
  sum_GF=$(awk "BEGIN{print $sum_GF+$G_FREQ}")
  sum_FPS=$(awk "BEGIN{print $sum_FPS+$FPS}")
  sum_GT=$(awk "BEGIN{print $sum_GT+$GPU_TEMP}")
  sum_CM=$(awk "BEGIN{print $sum_CM+$CHR_MEM}")
  sum_CMP=$(awk "BEGIN{print $sum_CMP+$CHR_MEM_PCT}")
  sum_SU_M=$(awk "BEGIN{print $sum_SU_M+$SYS_MEM_USED}")
  sum_SP=$(awk "BEGIN{print $sum_SP+$SYS_MEM_PCT}")
  ((count++))
done

kill $ROOT 2>/dev/null || true
echo "Chromium closed."

if ((count > 0)); then
  AVG_CU=$(awk "BEGIN{printf \"%.1f\", $sum_CU/$count}")
  AVG_SU=$(awk "BEGIN{printf \"%.1f\", $sum_SU/$count}")
  AVG_CF=$(awk "BEGIN{printf \"%d\",   $sum_CF/$count}")
  AVG_ST=$(awk "BEGIN{printf \"%.1f\", $sum_ST/$count}")
  AVG_GU=$(awk "BEGIN{printf \"%.1f\", $sum_GU/$count}")
  AVG_GF=$(awk "BEGIN{printf \"%d\",   $sum_GF/$count}")
  AVG_FPS=$(awk "BEGIN{printf \"%d\",   $sum_FPS/$count}")
  AVG_GT=$(awk "BEGIN{printf \"%.1f\", $sum_GT/$count}")
  AVG_CM=$(awk "BEGIN{printf \"%d\",   $sum_CM/$count}")
  AVG_CMP=$(awk "BEGIN{printf \"%.1f\", $sum_CMP/$count}")
  AVG_SU_M=$(awk "BEGIN{printf \"%d\",   $sum_SU_M/$count}")
  AVG_SP=$(awk "BEGIN{printf \"%.1f\", $sum_SP/$count}")
else
  echo "No average data."
  exit 1
fi

read SYS_MEM_USED SYS_MEM_TOTAL <<<$(grep -E 'MemTotal|MemAvailable' /proc/meminfo | awk 'NR==1{t=$2} NR==2{a=$2} END{printf "%d %d",(t-a)/1024,t/1024}')

echo "# Average Report"
echo "============================================================="
printf "CPU : Chromium: %5s | System: %5s @%4s MHz | Temp: %s\n" \
  "$(color_usage $AVG_CU)" "$(color_usage $AVG_SU)" "$AVG_CF" "$(color_temp $AVG_ST)"
printf "MEM : Chromium: %5s MB (%5s) | Sys: %5s/%5s MB (%5s)\n" \
  "$AVG_CM" "$(color_usage $AVG_CMP)" "$AVG_SU_M" "$SYS_MEM_TOTAL" "$(color_usage $AVG_SP)"
printf "GPU : %5s @%4s MHz | FPS:%4s | Temp: %s\n" \
  "$(color_usage $AVG_GU)" "$AVG_GF" "$AVG_FPS" "$(color_temp $AVG_GT)"
echo "============================================================="