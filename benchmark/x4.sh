#!/usr/bin/env bash
################################################################################
# Usage:  ./monitor_chromium.sh [URL] [SECONDS]
################################################################################
set -uo pipefail # -e off because intel_gpu_top → 124 on timeout

URL=${1:-https://example.com}
DUR=${2:-60}

# ─── colour helpers ──────────────────────────────────────────────────────────
RED=$'\e[0;31m'
YEL=$'\e[1;33m'
GRN=$'\e[0;32m'
NC=$'\e[0m'
pct() {
  { (($(bc -l <<<"$1>80"))) && printf "${RED}%.1f%%%s" "$1" "$NC"; } ||
    { (($(bc -l <<<"$1>50"))) && printf "${YEL}%.1f%%%s" "$1" "$NC"; } ||
    printf "${GRN}%.1f%%%s" "$1" "$NC"
}
tmp() {
  { (($(bc -l <<<"$1 > 75"))) && printf "${RED}%.1f°C%s" "$1" "$NC"; } ||
    { (($(bc -l <<<"$1 > 60"))) && printf "${YEL}%.1f°C%s" "$1" "$NC"; } ||
    printf "${GRN}%.1f°C%s" "$1" "$NC"
}

NUM_CORES=$(nproc)

# ─── CPU helpers ─────────────────────────────────────────────────────────────
get_total_cpu() {
  read -r _ u n s i io irq sirq st _ _ </proc/stat
  echo $((u + n + s + i + io + irq + sirq + st))
}
get_sys_cpu() {
  local idle_pct
  idle_pct=$(top -bn2 -d 0.5 | grep "Cpu(s)" | tail -n1 |
    awk -F',' '{ for(i=1;i<NF;i++) if($i~"id") print $i }' |
    awk '{print $1}')
  awk "BEGIN{printf \"%d\", 100 - $idle_pct}"
}
get_cpu_freq() {
  sum=0 cnt=0
  for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq; do
    [[ -r $f ]] && sum=$((sum + $(<"$f"))) && ((cnt++))
  done
  ((cnt)) && echo $((sum / cnt / 1000)) || echo 0
}
get_cpu_temp() {
  sensors -u 2>/dev/null | awk '
                                              /^Package id 0:/    { in_pkg=1; next }  
                                              /^$/                { in_pkg=0 }
                                              in_pkg && /temp1_input:/ {printf "%.1f",$2; exit}'
}

# ─── process-tree helpers ────────────────────────────────────────────────────
get_tree_pids() {
  local q=("$1") a=("$1") kids
  while ((${#q[@]})); do
    kids=($(pgrep -P "${q[0]}")) && a+=("${kids[@]}")
    q=("${q[@]:1}" "${kids[@]}")
  done
  printf '%s ' "${a[@]}"
}
get_chromium_cpu_pct() {
  read -a pids_arr <<<"$C_PIDS"
  local top_cmd="top -bn2 -d 0.5"
  for pid in "${pids_arr[@]}"; do
    top_cmd+=" -p $pid"
  done

  local cpu_sum=$(
    eval "$top_cmd" |
      awk -v NUM_CORES=$NUM_CORES '
      /^top/ { iter++; next }
      $1 ~ /^[0-9]+$/ && iter==2 { sum += $9 }
      END { printf "%.1f", sum / NUM_CORES }
    '
  )

  echo $cpu_sum
}
chrome_time() {
  t=0
  for p in $C_PIDS; do
    read -ra st </proc/$p/stat 2>/dev/null || continue
    t=$((t + st[13] + st[14]))
  done
  echo $t
}
chrome_mem() {
  kb=0
  for p in $C_PIDS; do
    if [[ -r /proc/$p/smaps ]]; then
      kb=$((kb + $(awk '/^Pss:/ {s+=$2} END{print s}' /proc/$p/smaps)))
    else kb=$((kb + $(awk '/VmRSS:/ {print $2}' /proc/$p/status))); fi
  done
  echo $((kb / 1024))
}

# ─── GPU helpers ─────────────────────────────────────────────────────────────
gpu_stats() {
  ###########################################################################
  # 1. Grab 1-second JSON sample
  ###########################################################################
  raw=$(timeout 1s sudo intel_gpu_top -J -s 1000 -o - 2>/dev/null)

  # intel_gpu_top never writes the closing ']' – just cut the opening '['
  json=$(sed '1s/^[[:space:]]*\[//' <<<"$raw")
  [[ -z $json ]] && {
    echo "0 0"
    return
  }

  ###########################################################################
  # 2. Build a jq-friendly list of Chromium PIDs (as strings)
  ###########################################################################
  pids_j=$(printf '%s\n' $C_PIDS | jq -R . | jq -cs .)

  ###########################################################################
  # 3. Sum Render/3D busy % for those PIDs (strings in JSON, so no tonumber)
  ###########################################################################
  busy=$(jq -r --argjson p "$pids_j" '
      reduce .clients?[]? as $c (0;
        if $p|index($c.pid) then
          . + ($c["engine-classes"]["Render/3D"].busy|tonumber)
        else . end )
    ' <<<"$json")

  # fallback to whole-GPU busy if no chromium client found
  [[ -z $busy ]] || awk 'BEGIN{exit !('"$busy"' == 0)}' && busy=$(jq -r '.engines."Render/3D".busy' <<<"$json")

  ###########################################################################
  # 4. GPU MHz (actual) → integer
  ###########################################################################
  freq=$(jq -r '.frequency.actual // empty' <<<"$json" |
    awk '{printf "%d",$1}')

  ###########################################################################
  # 5. Final fallbacks & echo
  ###########################################################################
  echo "${busy:-0} ${freq:-0}"
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

# ─── launch Chromium ────────────────────────────────────────────────────────
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
sleep 5 # allow renderer + CDP

C_PIDS=$(get_tree_pids "$ROOT")
MEM_TOTAL=$(awk '/MemTotal/ {print $2}' /proc/meminfo)

# ─── accumulators ───────────────────────────────────────────────────────────
declare -A sum
for k in cu su cf ct gu gf gt cm cmp sm smp fps; do sum[$k]=0; done
cnt=0 start=$(date +%s)

# ─── main loop ──────────────────────────────────────────────────────────────
while kill -0 "$ROOT" 2>/dev/null; do
  ((DUR > 0 && $(date +%s) - start >= DUR)) && break
  C_PIDS=$(get_tree_pids "$ROOT")

  sys_cpu=$(get_sys_cpu)
  ch_cpu=$(get_chromium_cpu_pct)

  cpu_freq=$(get_cpu_freq)
  cpu_temp=$(get_cpu_temp)
  read -r gpu_busy gpu_freq <<<"$(gpu_stats)"
  ch_mem=$(chrome_mem)
  mem_free=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
  sys_used=$(((MEM_TOTAL - mem_free) / 1024))
  sys_tot=$((MEM_TOTAL / 1024))
  ch_pct=$(printf "%.1f" "$(bc -l <<<"$ch_mem*100/$sys_tot")")
  sys_pct=$(printf "%.1f" "$(bc -l <<<"$sys_used*100/$sys_tot")")
  fps=$(get_fps)
  [[ -z $fps ]] && fps=0

  # ─── live output ─────────────────────────────────────────────────────────
  printf "\n%(%F %T)T | PIDs: %s\n" -1 "$C_PIDS"
  printf "CPU : Chromium:%7s | System:%7s @%4d MHz | Temp:%s\n" \
    "$(pct "$ch_cpu")" "$(pct "$sys_cpu")" "$cpu_freq" "$(tmp "$cpu_temp")"
  printf "MEM : Chromium:%4d MB (%7s) | System:%4d/%4d MB (%7s)\n" \
    "$ch_mem" "$(pct "$ch_pct")" "$sys_used" "$sys_tot" "$(pct "$sys_pct")"
  printf "GPU : %7s @%4d MHz | FPS:%s\n" "$(pct "$gpu_busy")" "$gpu_freq" "$fps"

  # accum
  sum[cu]=$(bc -l <<<"${sum[cu]}+$ch_cpu")
  sum[su]=$(bc -l <<<"${sum[su]}+$sys_cpu")
  sum[cf]=$((sum[cf] + cpu_freq))
  sum[ct]=$(bc -l <<<"${sum[ct]}+$cpu_temp")
  sum[gu]=$(bc -l <<<"${sum[gu]}+$gpu_busy")
  sum[gf]=$((sum[gf] + gpu_freq))
  sum[gt]=$(bc -l <<<"${sum[gt]}+$cpu_temp")
  sum[cm]=$((sum[cm] + ch_mem))
  sum[cmp]=$(bc -l <<<"${sum[cmp]}+$ch_pct")
  sum[sm]=$((sum[sm] + sys_used))
  sum[smp]=$(bc -l <<<"${sum[smp]}+$sys_pct")
  sum[fps]=$(bc -l <<<"${sum[fps]}+$fps")
  ((cnt++))
  sleep 1
done

kill "$ROOT" 2>/dev/null || true
[[ $cnt -eq 0 ]] && {
  echo "No samples"
  exit 1
}

avg() { printf "%.1f" "$(bc -l <<<"${sum[$1]}/$cnt")"; }
avg_i() { echo $((sum[$1] / cnt)); }

echo -e "\nAverage over $cnt samples"
printf "CPU : Chromium:%7s | System:%7s @%4d MHz | Temp:%s\n" \
  "$(pct "$(avg cu)")" "$(pct "$(avg su)")" "$(avg_i cf)" "$(tmp "$(avg ct)")"
printf "MEM : Chromium:%4d MB (%7s) | System:%4d/%4d MB (%7s)\n" \
  "$(avg_i cm)" "$(pct "$(avg cmp)")" "$(avg_i sm)" "$((MEM_TOTAL / 1024))" "$(pct "$(avg smp)")"
printf "GPU : %7s @%4d MHz | FPS:%s\n" \
  "$(pct "$(avg gu)")" "$(avg_i gf)" "$(avg fps)"
