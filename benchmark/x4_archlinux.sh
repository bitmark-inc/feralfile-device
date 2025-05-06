#!/usr/bin/env bash
################################################################################
# Usage:  ./x4.sh [URL] [SECONDS] [DELAY]
################################################################################
set -uo pipefail # -e off because intel_gpu_top → 124 on timeout

URL=${1:-https://example.com}
DUR=${2:-60}
DELAY=${3:-5}

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
FPS_LIST=()
MAX_POWER=30

# ─── CPU helpers ─────────────────────────────────────────────────────────────
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

ws_url() { # first "page" target's WS URL
  curl -s http://127.0.0.1:$DEBUG_PORT/json |
    jq -r '[ .[] | select(.type=="page") ][0].webSocketDebuggerUrl'
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

#─── Energy helpers ────────────────────────────────────────────
find_zone() {
  local want=$1 base=/sys/class/powercap/intel-rapl:0
  for n in "$base"/*/name; do
    [[ $(<"$n") == "$want" ]] && {
      echo "${n%/*}"
      return 0
    }
  done
  return 1 # not found
}

PKG=/sys/class/powercap/intel-rapl:0 # package zone
CORE=$(find_zone core)               # PP0
GPU=$(find_zone uncore || find_zone gpu) || {
  echo "✗  This firmware does not expose a PP1/uncore domain." >&2
  exit 1
}

# ─── read PL1 & PL2 (µW → W) ───────────────────────────────────────────────
read -r PL1_uW < <(sudo cat "$PKG/constraint_0_power_limit_uw") # long-term cap
read -r PL2_uW < <(sudo cat "$PKG/constraint_1_power_limit_uw") # short-term cap
PL1=$(awk "BEGIN{printf \"%.2f\", $PL1_uW/1e6}")   # :contentReference[oaicite:0]{index=0}
PL2=$(awk "BEGIN{printf \"%.2f\", $PL2_uW/1e6}")
[[ $PL1_uW -gt 0 && $PL2_uW -gt 0 ]] || {
  echo "PL1 or PL2 is zero—check your package limits" >&2
}

# Read the per-domain rollover limit from max_energy_range_uj (32-bit by spec)
MAX_CORE=$(<"$CORE/max_energy_range_uj")
MAX_GPU=$(<"$GPU/max_energy_range_uj")

# Initial samples
read -r c_prev < <(sudo cat "$CORE/energy_uj")
read -r g_prev < <(sudo cat "$GPU/energy_uj")
prev_watts_ts=$(date +%s.%N)
get_watts() {
  curr_ts=$(date +%s.%N)
  read -r c_curr < <(sudo cat "$CORE/energy_uj")
  read -r g_curr < <(sudo cat "$GPU/energy_uj")

  # ----------- handle 32-bit wrap-around per domain -----------
  ((c_curr < c_prev)) && c_curr=$((c_curr + MAX_CORE))
  ((g_curr < g_prev)) && g_curr=$((g_curr + MAX_GPU))

  # actual elapsed time in seconds (float)
  dt=$(awk "BEGIN{print $curr_ts - $prev_watts_ts}")

  # ----------- µJ → W (µJ / 1 000 000) ------------------------
  w_core=$(awk "BEGIN{printf \"%.2f\", ($c_curr-$c_prev)/1e6/$dt}")
  w_gpu=$(awk "BEGIN{printf \"%.2f\", ($g_curr-$g_prev)/1e6/$dt}")

  # percentages of PL1 & PL2
  pc1=$(awk "BEGIN{printf \"%.1f\", $w_core/$PL1*100}")
  pc2=$(awk "BEGIN{printf \"%.1f\", $w_core/$PL2*100}")
  pg1=$(awk "BEGIN{printf \"%.1f\", $w_gpu/$PL1*100}")
  pg2=$(awk "BEGIN{printf \"%.1f\", $w_gpu/$PL2*100}")

  # slide window
  c_prev=$((c_curr % MAX_CORE))
  g_prev=$((g_curr % MAX_GPU))
  prev_watts_ts=$curr_ts

  printf "%6s %6s %6s %6s %6s %6s\n" \
    "$w_core" "$pc1" "$pc2" "$w_gpu" "$pg1" "$pg2"
}

#─── Chromium helpers ──────────────────────────────────────────
get_fps() {
  local fps
  fps=$(fps_from_rAF 2>/dev/null)
  if [[ $fps =~ ^[0-9]+$ && $fps -gt 0 ]]; then
    echo "$fps"
    return
  fi

  echo 0 # couldn't measure
}

calc_1pct_low_fps() {
  local n=${#FPS_LIST[@]}
  if (( n == 0 )); then
    echo "0.0"
    return
  fi
  local sorted=($(printf "%s\n" "${FPS_LIST[@]}" | sort -n))

  local n_low=$(( (n + 99) / 100 ))
  (( n_low < 1 )) && n_low=1

  local sum=0
  for (( i=0; i<n_low; i++ )); do
    sum=$(( sum + sorted[i] ))
  done

  awk -v s="$sum" -v k="$n_low" 'BEGIN {
    if (k > 0) printf "%.1f", s / k;
    else           print "0.0";
  }'
}

get_drop_pct() {
  local ws js payload drop_pct
  command -v websocat &>/dev/null || return
  ws=$(ws_url)
  [[ -z $ws || $ws == null ]] && { echo "0"; return; }

  js='(async()=>{let count=0,expected=0;const start=performance.now(),ts0=start;function f(ts){count++;expected+=Math.floor((ts-ts0)/16.666);ts0=ts;if(performance.now()-start<1000)requestAnimationFrame(f);}requestAnimationFrame(f);await new Promise(r=>setTimeout(r,1100));const dropped=expected-count;return dropped>0?Math.round(dropped*100/(expected||1)):0;})()'

  payload=$(printf '{"id":10,"method":"Runtime.evaluate","params":{"expression":"%s","awaitPromise":true,"returnByValue":true}}' "$js")

  drop_pct=$(printf '%s' "$payload" \
             | websocat -n1 "$ws" 2>/dev/null \
             | jq -r '.result.result.value // 0')

  echo "$drop_pct"
}

js_heap() {
  # Check for required tools
  command -v websocat &>/dev/null || return 1

  # Get WebSocket URL for DevTools Protocol
  local ws
  ws=$(ws_url)
  [[ -z "$ws" || "$ws" == "null" ]] && return 1

  # Helper function to query JavaScript values
  get_js_value() {
    local expr="$1"
    printf '{"id":4,"method":"Runtime.evaluate","params":{"expression":"%s","returnByValue":true}}\n' "$expr" |
      websocat -n1 "$ws" 2>/dev/null |
      jq -r '.result.result.value // 0'
  }

  # Get heap metrics - performance.memory is Chrome-specific
  local t_heap
  t_heap=$(get_js_value "performance.memory ? performance.memory.totalJSHeapSize : 0")
  local u_heap
  u_heap=$(get_js_value "performance.memory ? performance.memory.usedJSHeapSize : 0")

  # Verify we got valid data
  [[ "$t_heap" == "0" || -z "$t_heap" ]] && return 1

  # Convert to MB and calculate percentage
  local t_mb
  t_mb=$(echo "scale=2; $t_heap/1024/1024" | bc)
  local u_mb
  u_mb=$(echo "scale=2; $u_heap/1024/1024" | bc)
  local pct
  pct=$(echo "scale=1; $u_heap*100/$t_heap" | bc)

  # Output as "total_mb used_mb percentage"
  printf "%.2f %.2f %.1f" "$t_mb" "$u_mb" "$pct"
}

# ─── Power meter helpers ────────────────────────────────────────────
get_power_meter_readings() {
  local output
  output=$(sigrok-cli -d rdtech-tc:conn=/dev/ttyACM0 --frames 1 2>/dev/null)
  
  # Extract voltage and current using grep and awk
  local voltage current_ma
  voltage=$(echo "$output" | grep -o "V: [0-9.]* V" | awk '{print $2}')
  current_ma=$(echo "$output" | grep -o "I: [0-9.]* mA" | awk '{print $2}')
  
  # If values were not found, return zeros
  [[ -z "$voltage" ]] && voltage=0
  [[ -z "$current_ma" ]] && current_ma=0
  
  # Convert current from mA to A
  local current
  current=$(awk "BEGIN {printf \"%.3f\", $current_ma/1000}")
  
  # Calculate power in watts (voltage * current)
  local power
  power=$(awk "BEGIN {printf \"%.2f\", $voltage * $current}")
  
  # Calculate power usage percentage (30W max)
  local power_pct
  power_pct=$(awk "BEGIN {printf \"%.1f\", $power * 100 / $MAX_POWER}")
  
  # Return space-separated voltage, current, power, and power percentage
  echo "$voltage $current $power $power_pct"
}

# ─── launch Chromium ────────────────────────────────────────────────────────
chromium "$URL" \
  --remote-debugging-port=$DEBUG_PORT \
  --kiosk \
  --ozone-platform=wayland \
  --no-first-run \
  --disable-sync \
  --disable-translate \
  --disable-infobars \
  --disable-features=TranslateUI \
  --disable-popup-blocking \
  --autoplay-policy=no-user-gesture-required \
  --allow-file-access-from-files \
  --enable-features=AcceleratedVideoDecodeLinuxGL \
  2>/dev/null &
ROOT=$!
sleep "$DELAY" # allow renderer + CDP

C_PIDS=$(get_tree_pids "$ROOT")
MEM_TOTAL=$(awk '/MemTotal/ {print $2}' /proc/meminfo)

# ─── accumulators ───────────────────────────────────────────────────────────
declare -A sum
for k in cu su cf ct gu gf gt cm cmp sm smp fps ju jt jpct cw gw cwpct1 cwpct2 gwpct1 gwpct2 df v i w wpct; do sum[$k]=0; done
cnt=0 start=$(date +%s)

# ─── main loop ──────────────────────────────────────────────────────────────
while kill -0 "$ROOT" 2>/dev/null; do
  ((DUR > 0 && $(date +%s) - start >= DUR)) && break
  C_PIDS=$(get_tree_pids "$ROOT")

  read sys_cpu ch_cpu <<<"$(get_cpu_usages)"
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
  FPS_LIST+=("$fps")
  drop_pct=$(get_drop_pct)
  # JS heap stats
  if ! read -r t_heap u_heap heap_pct <<<"$(js_heap 2>/dev/null)"; then
    t_heap=0
    u_heap=0
    heap_pct=0
  fi
  read cw cwpct1 cwpct2 gw gwpct1 gwpct2 <<<"$(get_watts)"
  
  # Power meter readings
  read -r voltage current power power_pct <<<"$(get_power_meter_readings)"

  # ─── live output ─────────────────────────────────────────────────────────
  printf "\n%(%F %T)T | PIDs: %s\n" -1 "$C_PIDS"
  printf "CPU : Chromium:%7s | System:%7s @%4d MHz | Temp:%s | Watts(%%PL1 %%PL2): %.2f W(%7s %7s)\n" \
    "$(pct "$ch_cpu")" "$(pct "$sys_cpu")" "$cpu_freq" "$(tmp "$cpu_temp")" "$cw" "$(pct "$cwpct1")" "$(pct "$cwpct2")"
  printf "MEM : Chromium:%4d MB (%7s) | System:%4d/%4d MB (%7s)\n" \
    "$ch_mem" "$(pct "$ch_pct")" "$sys_used" "$sys_tot" "$(pct "$sys_pct")"
  printf "GPU : %7s @%4d MHz | Temp: %s | Watts(%%PL1 %%PL2): %.2f W(%7s %7s) | FPS:%s | Drop Frame: %s\n" "$(pct "$gpu_busy")" "$gpu_freq" "$(tmp "$cpu_temp")" "$gw" "$(pct "$gwpct1")" "$(pct "$gwpct2")" "$fps" "$(pct "$drop_pct")"
  printf "JS Heap : %.2f/%.2f MB (%7s)\n" "$u_heap" "$t_heap" "$(pct $heap_pct)"
  printf "Power Meter: %.2f V | %.3f A | %.2f W (%7s)\n" "$voltage" "$current" "$power" "$(pct "$power_pct")"

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
  sum[ju]=$(bc -l <<<"${sum[ju]}+$u_heap")
  sum[jt]=$(bc -l <<<"${sum[jt]}+$t_heap")
  sum[jpct]=$(bc -l <<<"${sum[jpct]}+$heap_pct")
  sum[cw]=$(bc -l <<<"${sum[cw]}+$cw")
  sum[cwpct1]=$(bc -l <<<"${sum[cwpct1]}+$cwpct1")
  sum[cwpct2]=$(bc -l <<<"${sum[cwpct2]}+$cwpct2")
  sum[gw]=$(bc -l <<<"${sum[gw]}+$gw")
  sum[gwpct1]=$(bc -l <<<"${sum[gwpct1]}+$gwpct1")
  sum[gwpct2]=$(bc -l <<<"${sum[gwpct2]}+$gwpct2")
  sum[df]=$(bc -l <<<"${sum[df]}+$drop_pct")
  sum[v]=$(bc -l <<<"${sum[v]}+$voltage")
  sum[i]=$(bc -l <<<"${sum[i]}+$current")
  sum[w]=$(bc -l <<<"${sum[w]}+$power")
  sum[wpct]=$(bc -l <<<"${sum[wpct]}+$power_pct")

  ((cnt++))
done

kill "$ROOT" 2>/dev/null || true
[[ $cnt -eq 0 ]] && {
  echo "No samples"
  exit 1
}

avg() { printf "%.1f" "$(bc -l <<<"${sum[$1]}/$cnt")"; }
avg_i() { echo "$(bc -l <<<"scale=2; ${sum[$1]}/$cnt")"; }

one_pct_low_fps=$(calc_1pct_low_fps)

echo -e "\nAverage over $cnt samples"
printf "CPU : Chromium:%7s | System:%7s @%.0f MHz | Temp:%s | Watts(%%PL1 %%PL2): %.2f W(%7s %7s)\n" \
  "$(pct "$(avg cu)")" "$(pct "$(avg su)")" "$(avg_i cf)" "$(tmp "$(avg ct)")" "$(avg cw)" "$(pct "$(avg cwpct1)")" "$(pct "$(avg cwpct2)")"
printf "MEM : Chromium:%.2f MB (%7s) | System:%.2f/%.2f MB (%7s)\n" \
  "$(avg_i cm)" "$(pct "$(avg cmp)")" "$(avg_i sm)" "$((MEM_TOTAL / 1024))" "$(pct "$(avg smp)")"
printf "GPU : %7s @%.0f MHz | Watts(%%PL1 %%PL2): %.2f W(%7s %7s) | FPS:%s | 1%% Low FPS: %s | Drop Frame: %s \n" \
  "$(pct "$(avg gu)")" "$(avg_i gf)" "$(avg gw)" "$(pct "$(avg gwpct1)")" "$(pct "$(avg gwpct2)")" "$(avg fps)" "$one_pct_low_fps" "$(pct "$(avg df)")"
printf "JS Heap : %.2f/%.2f MB (%7s)\n" "$(avg_i ju)" "$(avg_i jt)" "$(pct "$(avg jpct)")"
printf "Power Meter: %.2f V | %.3f A | %.2f W (%7s)\n" "$(avg_i v)" "$(avg_i i)" "$(avg_i w)" "$(pct "$(avg wpct)")"
