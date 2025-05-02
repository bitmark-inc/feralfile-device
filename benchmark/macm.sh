#!/usr/bin/env bash
###############################################################################
# macm.sh  — Apple-Silicon edition
# Usage:  ./macm.sh [URL] [SECONDS]
###############################################################################
set -uo pipefail # Removed -e to prevent unwanted exits

# Error handling function
handle_error() {
    echo "Warning: Command failed: $1" >&2
    return 0
}

URL=${1:-https://example.com}
DUR=${2:-60}
DELAY=${3:-5}
DEBUG_PORT=9222

cleanup() {
    # Try to kill the root process and its children
    if [[ -n "${ROOT:-}" ]]; then
        kill "$ROOT" 2>/dev/null || true
    fi
    # Also try to kill any remaining Chromium processes
    pkill -f "[C]hromium" 2>/dev/null || true
    exit 0
}

# Set up trap to ensure cleanup happens even if the script is interrupted
trap cleanup INT

RED=$'\e[0;31m'
YEL=$'\e[1;33m'
GRN=$'\e[0;32m'
NC=$'\e[0m'
pct() {
    if (($(bc -l <<<"$1>80"))); then
        printf "${RED}%.1f%%%s" "$1" "$NC"
    elif (($(bc -l <<<"$1>50"))); then
        printf "${YEL}%.1f%%%s" "$1" "$NC"
    else
        printf "${GRN}%.1f%%%s" "$1" "$NC"
    fi
}
tmp() {
    if (($(bc -l <<<"$1>75"))); then
        printf "${RED}%.1f°C%s" "$1" "$NC"
    elif (($(bc -l <<<"$1>60"))); then
        printf "${YEL}%.1f°C%s" "$1" "$NC"
    else
        printf "${GRN}%.1f°C%s" "$1" "$NC"
    fi
}

NUM_CORES=$(sysctl -n hw.logicalcpu)
FPS_LIST=()

macmon_sample() {
    # Use set +e locally to prevent exit on failure
    {
        set +e
        macmon pipe -s1 -i1000 | tail -1 || echo "{}"
        set -e
    }
}

get_sys_cpu() {
    local sample="$1"
    local pcpu=0
    local ecpu=0
    pcpu=$(echo "$sample" | jq -r '."pcpu_usage"[1]*100' 2>/dev/null || echo "0")
    ecpu=$(echo "$sample" | jq -r '."ecpu_usage"[1]*100' 2>/dev/null || echo "0")

    echo "scale=1; $pcpu + $ecpu" | bc
}

get_cpu_freq() {
    local sample="$1"
    local pcpu_raw=0
    local ecpu_raw=0
    pcpu_raw=$(echo "$sample" | jq -r '."pcpu_usage"[0]' 2>/dev/null || echo "0")
    ecpu_raw=$(echo "$sample" | jq -r '."ecpu_usage"[0]' 2>/dev/null || echo "0")

    # Get the total raw frequency
    local total
    total=$(echo "scale=1; $pcpu_raw + $ecpu_raw" | bc)
    
    # Simple threshold-based detection
    # If the value is large (>10000), it's likely in KHz and needs conversion to MHz
    if (( $(echo "$total > 10000" | bc -l) )); then
        echo "scale=0; $total / 1000" | bc
    # Otherwise it's already in MHz
    else
        echo "scale=0; $total" | bc
    fi
}

get_cpu_temp() {
    local sample="$1"
    echo "scale=0; $(echo "$sample" | jq '.temp.cpu_temp_avg' 2>/dev/null || echo "0")" | bc
}

get_gpu_freq() {
    local sample="$1"
    local gpu_raw=0
    gpu_raw=$(echo "$sample" | jq -r '."gpu_usage"[0]' 2>/dev/null || echo "0")
    
    # Simple threshold-based detection
    # If the value is large (>10000), it's likely in KHz and needs conversion to MHz
    if (( $(echo "$gpu_raw > 10000" | bc -l) )); then
        echo "scale=0; $gpu_raw / 1000" | bc
    # Otherwise it's already in MHz
    else
        echo "scale=0; $gpu_raw" | bc
    fi
}

get_gpu_busy() {
    local sample="$1"
    echo "scale=1; $(echo "$sample" | jq -r '."gpu_usage"[1]*100' 2>/dev/null || echo "0")" | bc
}

get_gpu_temp() {
    local sample="$1"
    echo "scale=0; $(echo "$sample" | jq '.temp.gpu_temp_avg' 2>/dev/null || echo "0")" | bc
}

get_mem_stats() {
    local sample="$1"
    local used=0
    local total=1
    local pct=0
    used=$(echo "$sample" | jq -r '.memory.ram_usage/1024/1024' 2>/dev/null || echo "0")
    total=$(echo "$sample" | jq -r '.memory.ram_total/1024/1024' 2>/dev/null || echo "1")
    pct=$(echo "scale=1; $used*100/$total" | bc)
    printf "%.0f %.0f %.1f" "$used" "$total" "$pct"
}

# macOS compatible helper to get process tree (main process + children)
get_tree_pids() {
    local parent_pid="$1"
    echo -n "$parent_pid "

    # Find all child processes where parent_pid is the PPID
    ps -ax -o ppid,pid | grep "^[[:space:]]*$parent_pid " | awk '{print $2}' | while read child_pid; do
        echo -n "$child_pid "
    done
}

# Main loop that collects data for each iteration
collect_data() {
    C_PIDS=$(get_tree_pids "$ROOT" 2>/dev/null || echo "$ROOT")

    # Get a single sample per iteration to ensure consistency
    sample=$(macmon_sample 2>/dev/null || echo "{}")

    # Skip this iteration if the sample is empty
    if [[ -z "$sample" || "$sample" == "{}" ]]; then
        echo "Warning: Failed to get macmon sample, retrying..."
        return 1
    fi

    # Try to extract all metrics from the sample
    sys_cpu=$(get_sys_cpu "$sample" 2>/dev/null || echo "0")
    cpu_freq=$(get_cpu_freq "$sample" 2>/dev/null || echo "0")
    cpu_temp=$(get_cpu_temp "$sample" 2>/dev/null || echo "0")
    gpu_freq=$(get_gpu_freq "$sample" 2>/dev/null || echo "0")
    gpu_busy=$(get_gpu_busy "$sample" 2>/dev/null || echo "0")
    gpu_temp=$(get_gpu_temp "$sample" 2>/dev/null || echo "0")

    # Handle memory stats
    if ! read -r sys_used sys_tot sys_pct <<<"$(get_mem_stats "$sample" 2>/dev/null)"; then
        sys_used=0
        sys_tot=1
        sys_pct=0
    fi

    # JS heap stats
    if ! read -r t_heap u_heap heap_pct <<<"$(js_heap 2>/dev/null)"; then
        t_heap=0
        u_heap=0
        heap_pct=0
    fi

    # Process-specific metrics
    ch_cpu=$(get_chromium_cpu_pct 2>/dev/null || echo "0")
    ch_mem=$(chrome_mem 2>/dev/null || echo "0")

    # Avoid division by zero
    if [[ "$sys_tot" -gt 0 ]]; then
        ch_pct=$(bc -l <<<"scale=1; $ch_mem*100/$sys_tot" 2>/dev/null || echo "0")
    else
        ch_pct="0.0"
    fi

    fps=$(get_fps 2>/dev/null || echo "0.0")
    FPS_LIST+=("$fps")

    drop_pct=$(get_drop_pct)

    # Display the metrics
    printf "\n%(%F %T)T | PIDs: %s\n" -1 "$C_PIDS"
    printf "CPU : Chromium:%7s | System:%7s @%4d MHz | Temp:%s\n" \
        "$(pct $ch_cpu)" "$(pct $sys_cpu)" "$cpu_freq" "$(tmp $cpu_temp)"
    printf "MEM : Chromium:%4d MB (%7s) | System:%4d/%4d MB (%7s)\n" \
        "$ch_mem" "$(pct $ch_pct)" "$sys_used" "$sys_tot" "$(pct $sys_pct)"
    printf "GPU : %7s @%4d MHz | Temp:%s | FPS:%s | Drop Frame: %s\n" \
        "$(pct $gpu_busy)" "$gpu_freq" "$(tmp $gpu_temp)" "$fps" "$(pct $drop_pct)"
    printf "JS Heap : %.2f/%.2f MB (%7s)\n" "$u_heap" "$t_heap" "$(pct $heap_pct)"

    # Accumulate the metrics for later averaging
    sum[cu]=$(bc -l <<<"${sum[cu]}+$ch_cpu" 2>/dev/null || echo "${sum[cu]}")
    sum[su]=$(bc -l <<<"${sum[su]}+$sys_cpu" 2>/dev/null || echo "${sum[su]}")
    sum[cf]=$((sum[cf] + cpu_freq))
    sum[ct]=$(bc -l <<<"${sum[ct]}+$cpu_temp" 2>/dev/null || echo "${sum[ct]}")
    sum[gu]=$(bc -l <<<"${sum[gu]}+$gpu_busy" 2>/dev/null || echo "${sum[gu]}")
    sum[gf]=$((sum[gf] + gpu_freq))
    sum[gt]=$(bc -l <<<"${sum[gt]}+$gpu_temp" 2>/dev/null || echo "${sum[gt]}")
    sum[cm]=$((sum[cm] + ch_mem))
    sum[cmp]=$(bc -l <<<"${sum[cmp]}+$ch_pct" 2>/dev/null || echo "${sum[cmp]}")
    sum[sm]=$((sum[sm] + sys_used))
    sum[smp]=$(bc -l <<<"${sum[smp]}+$sys_pct" 2>/dev/null || echo "${sum[smp]}")
    sum[fps]=$(bc -l <<<"${sum[fps]}+$fps" 2>/dev/null || echo "${sum[fps]}")
    sum[ju]=$(bc -l <<<"${sum[ju]}+$u_heap" 2>/dev/null || echo "${sum[ju]}")
    sum[jt]=$(bc -l <<<"${sum[jt]}+$t_heap" 2>/dev/null || echo "${sum[jt]}")
    sum[jpct]=$(bc -l <<<"${sum[jpct]}+$heap_pct" 2>/dev/null || echo "${sum[jpct]}")
    sum[df]=$(bc -l <<<"${sum[df]}+$drop_pct")

    return 0
}

get_chromium_cpu_pct() {
    ps -o %cpu= -p "${C_PIDS// /,}" 2>/dev/null | awk -v c=$NUM_CORES '{s+=$1} END{printf "%.1f", s/c}' || echo "0.0"
}
chrome_mem() {
    ps -o rss= -p "${C_PIDS// /,}" 2>/dev/null | awk '{k+=$1} END{print int(k/1024)}' || echo "0"
}

ws_url() {
    curl -s http://127.0.0.1:$DEBUG_PORT/json 2>/dev/null | jq -r '[.[]|select(.type=="page")][0].webSocketDebuggerUrl' || echo ""
}
fps_from_metrics() {
    command -v websocat &>/dev/null || return 1
    local ws
    ws=$(ws_url)
    [[ -z $ws || $ws == null ]] && return 1
    websocat -n1 "$ws" <<<'{"id":1,"method":"Performance.enable"}' >/dev/null
    local result
    result=$(websocat -n1 "$ws" <<<'{"id":2,"method":"Performance.getMetrics"}' | jq -r '.result.metrics[]|select(.name=="FramesPerSecond").value' 2>/dev/null || echo "")
    if [ -n "$result" ] && [ "$result" != "null" ]; then
        awk 'BEGIN{printf "%.1f", '"$result"'}'
        return 0
    fi
    return 1
}
fps_from_rAF() {
    command -v websocat &>/dev/null || return 1
    local ws
    ws=$(ws_url)
    [[ -z $ws || $ws == null ]] && return 1
    local js='(async()=>{let c=0,s=performance.now();function f(ts){c++;if(ts-s<1000)requestAnimationFrame(f);}requestAnimationFrame(f);await new Promise(r=>setTimeout(r,1050));return (c*1000/(performance.now()-s)).toFixed(1);})();'
    local result
    result=$(printf '{"id":3,"method":"Runtime.evaluate","params":{"expression":"%s","awaitPromise":true,"returnByValue":true}}\n' "$js" | websocat -n1 "$ws" | jq -r '.result.result.value // empty' 2>/dev/null)
    if [ -n "$result" ] && [ "$result" != "null" ]; then
        echo "$result"
        return 0
    fi
    return 1
}
get_fps() {
    local fps_val
    if fps_val=$(fps_from_metrics 2>/dev/null) && [ -n "$fps_val" ]; then
        echo "$fps_val"
    elif fps_val=$(fps_from_rAF 2>/dev/null) && [ -n "$fps_val" ]; then
        echo "$fps_val"
    else
        echo "0.0"
    fi
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

  local sum=0.0
  for (( i=0; i<n_low; i++ )); do
    sum=$(awk -v s="$sum" -v v="${sorted[i]}" 'BEGIN { printf "%.10f", s + v }')
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
        printf '{"id":4,"method":"Runtime.evaluate","params":{"expression":"%s","returnByValue":true}}\n' "$expr" | \
        websocat -n1 "$ws" 2>/dev/null | \
        jq -r '.result.result.value // 0'
    }
    
    # Get heap metrics - performance.memory is Chrome-specific
    local t_heap; t_heap=$(get_js_value "performance.memory ? performance.memory.totalJSHeapSize : 0")
    local u_heap; u_heap=$(get_js_value "performance.memory ? performance.memory.usedJSHeapSize : 0")
    
    # Verify we got valid data
    [[ "$t_heap" == "0" || -z "$t_heap" ]] && return 1
    
    # Convert to MB and calculate percentage
    local t_mb; t_mb=$(echo "scale=2; $t_heap/1024/1024" | bc)
    local u_mb; u_mb=$(echo "scale=2; $u_heap/1024/1024" | bc)
    local pct; pct=$(echo "scale=1; $u_heap*100/$t_heap" | bc)
    
    # Output as "total_mb used_mb percentage"
    printf "%.2f %.2f %.1f" "$t_mb" "$u_mb" "$pct"
}

if [[ -n "${CHROMIUM_BIN:-}" && -x "$CHROMIUM_BIN" ]]; then
    : # use the caller-supplied path verbatim
else
    if command -v chromium-browser &>/dev/null; then
        CHROMIUM_BIN="$(command -v chromium-browser)" # Ubuntu / Debian
    elif command -v chromium &>/dev/null; then
        CHROMIUM_BIN="$(command -v chromium)" # Arch / Homebrew
    elif [[ -x "/Applications/Chromium.app/Contents/MacOS/Chromium" ]]; then
        CHROMIUM_BIN="/Applications/Chromium.app/Contents/MacOS/Chromium" # macOS bundle
    else
        echo "❌ Chromium executable not found. Install it or set \$CHROMIUM_BIN." >&2
        exit 1
    fi
fi

"$CHROMIUM_BIN" "$URL" \
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
echo "Root PID: $ROOT"
sleep "$DELAY"
C_PIDS=$(get_tree_pids "$ROOT" 2>/dev/null || echo "$ROOT")

declare -A sum
for k in cu su cf ct gu gf gt cm cmp sm smp fps ju jt jpct df; do sum[$k]=0; done
cnt=0
start=$(date +%s)

end_time=$((start + DUR))
while kill -0 "$ROOT" 2>/dev/null; do
    # Check if duration has been reached
    current_time=$(date +%s)
    if ((DUR > 0 && current_time >= end_time)); then
        echo "Duration reached, exiting loop"
        break
    fi

    # Collect and process data
    if collect_data; then
        ((cnt++))
    fi
done

# Clean up
kill "$ROOT" 2>/dev/null || true

# If no samples were collected, exit
if ((cnt == 0)); then
    echo "No samples collected"
    exit 1
fi

avg() { printf "%.1f" "$(bc -l <<<"${sum[$1]}/$cnt")"; }
avg_i() { echo "$(bc -l <<<"scale=2; ${sum[$1]}/$cnt")"; }

avg_cpu_freq=$(echo "scale=0; ${sum[cf]}/$cnt" | bc)
avg_gpu_freq=$(echo "scale=0; ${sum[gf]}/$cnt" | bc)
one_pct_low_fps=$(calc_1pct_low_fps)

echo -e "\nAverage over $cnt samples"
printf "CPU : Chromium:%7s | System:%7s @%4d MHz | Temp:%s\n" \
    "$(pct "$(avg cu)")" "$(pct "$(avg su)")" "$avg_cpu_freq" "$(tmp "$(avg ct)")"
printf "MEM : Chromium:%.2f MB (%7s) | System:%.2f/%.2f MB (%7s)\n" \
    "$(avg_i cm)" "$(pct "$(avg cmp)")" "$(avg_i sm)" "$sys_tot" "$(pct "$(avg smp)")"
printf "GPU : %7s @%4d MHz | Temp:%s | FPS:%s | 1%% Low FPS: %s | Drop Frame: %s\n" \
    "$(pct "$(avg gu)")" "$avg_gpu_freq" "$(tmp "$(avg gt)")" "$(avg fps)" "$one_pct_low_fps" "$(pct "$(avg df)")"
printf "JS Heap : %.2f/%.2f MB (%7s)\n" "$(avg_i ju)" "$(avg_i jt)" "$(pct "$(avg jpct)")"

trap - EXIT
cleanup
