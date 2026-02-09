#!/bin/bash
# =============================================================================
# WiFi Dead Spot Survey Tool
# Walk around with the laptop, press 'm' to mark locations with signal data
# Continuously logs signal, latency, retries, and roaming in the background
# =============================================================================

set -uo pipefail

SURVEY_DIR="$(dirname "$0")/surveys"
SITE_NAME="${1:-}"
WIFI_IFACE=""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Signal quality thresholds (dBm)
EXCELLENT=-30
GOOD=-50
FAIR=-60
WEAK=-70

# Background PIDs
MONITOR_PID=""
SIGNAL_LOG_PID=""
PING_LOG_PID=""

# =============================================================================
# Setup
# =============================================================================

if [ -z "$SITE_NAME" ]; then
    echo -e "${BOLD}WiFi Dead Spot Survey${NC}"
    echo ""
    read -rp "Site/location name: " SITE_NAME
    if [ -z "$SITE_NAME" ]; then
        echo "Site name required."
        exit 1
    fi
fi

mkdir -p "$SURVEY_DIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
CSV_FILE="$SURVEY_DIR/${SITE_NAME}_survey_${TIMESTAMP}.csv"
SSID_CSV="$SURVEY_DIR/${SITE_NAME}_ssids_${TIMESTAMP}.csv"
TIMESERIES_CSV="$SURVEY_DIR/${SITE_NAME}_timeseries_${TIMESTAMP}.csv"
PING_CSV="$SURVEY_DIR/${SITE_NAME}_ping_${TIMESTAMP}.csv"
LOG_FILE="$SURVEY_DIR/${SITE_NAME}_survey_${TIMESTAMP}.log"

# Detect WiFi interface
WIFI_IFACE=$(iw dev 2>/dev/null | awk '/Interface/{print $2}' | head -1)
if [ -z "$WIFI_IFACE" ]; then
    echo "No WiFi interface found."
    exit 1
fi

# Get connected SSID and BSSID
SSID=$(iw dev "$WIFI_IFACE" info 2>/dev/null | awk '/ssid/{print $2}')
BSSID=$(iw dev "$WIFI_IFACE" link 2>/dev/null | head -1 | awk '{print $3}')
FREQ=$(iw dev "$WIFI_IFACE" info 2>/dev/null | awk '/channel/{gsub(/[(),]/,"",$3); printf "%s MHz (Ch %s)", $3, $2}')
GATEWAY=$(ip route show default | awk '{print $3}' | head -1)

# =============================================================================
# Helper functions
# =============================================================================

get_signal() {
    iw dev "$WIFI_IFACE" link 2>/dev/null | awk '/signal/{print $2}'
}

get_bitrate() {
    local rx tx
    rx=$(iw dev "$WIFI_IFACE" link 2>/dev/null | awk '/rx bitrate/{print $3, $4}')
    tx=$(iw dev "$WIFI_IFACE" link 2>/dev/null | awk '/tx bitrate/{print $3, $4}')
    echo "RX:${rx} TX:${tx}"
}

get_bssid() {
    iw dev "$WIFI_IFACE" link 2>/dev/null | head -1 | awk '{print $3}'
}

get_station_stats() {
    iw dev "$WIFI_IFACE" station dump 2>/dev/null
}

get_tx_retries() {
    get_station_stats | awk '/tx retries:/{print $3}'
}

get_tx_failed() {
    get_station_stats | awk '/tx failed:/{print $3}'
}

get_rx_packets() {
    get_station_stats | awk '/rx packets:/{print $3}'
}

get_tx_packets() {
    get_station_stats | awk '/tx packets:/{print $3}'
}

get_beacon_loss() {
    get_station_stats | awk '/beacon loss:/{print $3}'
}

get_noise() {
    # Try to get noise floor from survey dump
    iw dev "$WIFI_IFACE" survey dump 2>/dev/null | awk '/noise:/{print $2; exit}'
}

signal_label() {
    local sig=$1
    if [ "$sig" -ge "$EXCELLENT" ]; then echo -e "${GREEN}EXCELLENT${NC}"
    elif [ "$sig" -ge "$GOOD" ]; then echo -e "${GREEN}GOOD${NC}"
    elif [ "$sig" -ge "$FAIR" ]; then echo -e "${YELLOW}FAIR${NC}"
    elif [ "$sig" -ge "$WEAK" ]; then echo -e "${YELLOW}WEAK${NC}"
    else echo -e "${RED}DEAD SPOT${NC}"
    fi
}

signal_quality() {
    local sig=$1
    if [ "$sig" -ge "$EXCELLENT" ]; then echo "excellent"
    elif [ "$sig" -ge "$GOOD" ]; then echo "good"
    elif [ "$sig" -ge "$FAIR" ]; then echo "fair"
    elif [ "$sig" -ge "$WEAK" ]; then echo "weak"
    else echo "dead_spot"
    fi
}

signal_bar() {
    local sig=$1
    local bar_len=$(( (sig + 100) * 40 / 70 ))
    [ "$bar_len" -lt 0 ] && bar_len=0
    [ "$bar_len" -gt 40 ] && bar_len=40
    local color
    if [ "$sig" -ge "$GOOD" ]; then color="$GREEN"
    elif [ "$sig" -ge "$FAIR" ]; then color="$YELLOW"
    else color="$RED"
    fi
    local bar="" empty=""
    for ((i=0; i<bar_len; i++)); do bar+="█"; done
    for ((i=bar_len; i<40; i++)); do empty+="░"; done
    echo -e "${color}${bar}${DIM}${empty}${NC}"
}

# Get all visible SSIDs from cached scan dump
get_all_ssids() {
    iw dev "$WIFI_IFACE" scan dump 2>/dev/null | awk '
    /^BSS / {
        if (bssid != "") {
            printf "%s|%s|%s|%s|%s\n", ssid, bssid, signal, freq, channel
        }
        bssid = $2; sub(/\(.*/, "", bssid)
        ssid=""; signal=""; freq=""; channel=""
    }
    /SSID:/ { ssid=$2; for(i=3;i<=NF;i++) ssid=ssid" "$i }
    /signal:/ { signal=$2 }
    /freq:/ { freq=$2 }
    /DS Parameter set: channel/ { channel=$NF }
    /primary channel:/ { channel=$NF }
    END {
        if (bssid != "") {
            printf "%s|%s|%s|%s|%s\n", ssid, bssid, signal, freq, channel
        }
    }' | sort -t'|' -k3 -n -r
}

# Signal stability: sample N times and return min|max|avg
get_signal_stability() {
    local samples=${1:-10}
    local signals=()
    for ((i=0; i<samples; i++)); do
        local s=$(get_signal)
        [ -n "$s" ] && signals+=("$s")
        sleep 0.3
    done
    if [ ${#signals[@]} -eq 0 ]; then
        echo "n/a|n/a|n/a|0"
        return
    fi
    local min=0 max=-200 sum=0 count=${#signals[@]}
    for s in "${signals[@]}"; do
        sum=$((sum + s))
        [ "$s" -lt "$min" ] && min=$s
        [ "$s" -gt "$max" ] && max=$s
    done
    # Initialise min properly
    min=${signals[0]}
    for s in "${signals[@]}"; do
        [ "$s" -lt "$min" ] && min=$s
    done
    local avg=$((sum / count))
    echo "${min}|${max}|${avg}|${count}"
}

# Quick latency test: 5 pings, return min/avg/max/loss
quick_ping() {
    local target=$1
    local output
    output=$(ping -c 5 -W 2 -i 0.3 "$target" 2>/dev/null)
    local loss
    loss=$(echo "$output" | grep -oP '\d+(?=% packet loss)')
    local rtt_line
    rtt_line=$(echo "$output" | grep 'rtt\|round-trip')
    local min avg max
    if [ -n "$rtt_line" ]; then
        # Format: rtt min/avg/max/mdev = 5.136/5.844/6.905/0.657 ms
        local stats
        stats=$(echo "$rtt_line" | grep -oP '[\d.]+/[\d.]+/[\d.]+/[\d.]+')
        min=$(echo "$stats" | cut -d/ -f1)
        avg=$(echo "$stats" | cut -d/ -f2)
        max=$(echo "$stats" | cut -d/ -f3)
        echo "${loss:-100}% loss, ${min}/${avg}/${max} ms (min/avg/max)"
    else
        echo "${loss:-100}% loss, n/a ms"
    fi
}

# Quick DNS test
quick_dns() {
    local time
    time=$(dig google.com +stats 2>/dev/null | awk '/Query time/{print $4}')
    echo "${time:-n/a} ms"
}

# HTTP TTFB test
quick_http() {
    local ttfb
    ttfb=$(curl -o /dev/null -s -w '%{time_starttransfer}' --max-time 5 http://google.com 2>/dev/null)
    if [ -n "$ttfb" ]; then
        # Convert to ms
        local ms
        ms=$(awk "BEGIN{printf \"%.0f\", $ttfb * 1000}")
        echo "${ms} ms"
    else
        echo "n/a"
    fi
}

# =============================================================================
# CSV headers
# =============================================================================

echo "timestamp,location,floor,room_type,indoor_outdoor,distance_m,walls,wall_material,glass_doors,interference_sources,signal_dBm,signal_min,signal_max,signal_avg,signal_samples,quality,noise_floor,tx_retries,tx_failed,beacon_loss,ssid,bssid,frequency,rx_bitrate,tx_bitrate,nearby_ssid_count,gateway_latency,dns_latency_ms,http_ttfb_ms,ping_8888,notes" > "$CSV_FILE"
echo "timestamp,location,ssid,bssid,signal_dBm,frequency_MHz,channel" > "$SSID_CSV"
echo "timestamp,signal_dBm,noise_floor,bssid,rx_bitrate,tx_bitrate,tx_retries,tx_failed,beacon_loss,rx_packets,tx_packets" > "$TIMESERIES_CSV"
echo "timestamp,target,rtt_ms,status" > "$PING_CSV"

# =============================================================================
# Background loggers
# =============================================================================

# Continuous signal/stats logger (every 2 seconds)
start_signal_logger() {
    local prev_bssid="$BSSID"
    while true; do
        local ts=$(date '+%Y-%m-%d %H:%M:%S')
        local sig=$(get_signal)
        local noise=$(get_noise)
        local current_bssid=$(get_bssid)
        local bitrate=$(get_bitrate)
        local rx_br=$(echo "$bitrate" | sed 's/.*RX:\(.*\) TX:.*/\1/')
        local tx_br=$(echo "$bitrate" | sed 's/.*TX://')
        local retries=$(get_tx_retries)
        local failed=$(get_tx_failed)
        local bloss=$(get_beacon_loss)
        local rxp=$(get_rx_packets)
        local txp=$(get_tx_packets)

        echo "${ts},${sig},${noise},${current_bssid},${rx_br},${tx_br},${retries},${failed},${bloss},${rxp},${txp}" >> "$TIMESERIES_CSV"

        # Roaming detection
        if [ -n "$current_bssid" ] && [ "$current_bssid" != "$prev_bssid" ]; then
            echo "${ts},ROAM,Switched from ${prev_bssid} to ${current_bssid},${sig}" >> "$TIMESERIES_CSV"
            echo "[${ts}] ROAMING EVENT: ${prev_bssid} -> ${current_bssid} (signal: ${sig} dBm)" >> "$LOG_FILE"
            prev_bssid="$current_bssid"
        fi

        sleep 2
    done
}

# Continuous ping logger (gateway)
start_ping_logger() {
    while true; do
        local ts=$(date '+%Y-%m-%d %H:%M:%S')
        local rtt
        rtt=$(ping -c 1 -W 2 "$GATEWAY" 2>/dev/null | awk -F'=' '/time=/{print $NF}' | sed 's/ ms//')
        if [ -n "$rtt" ]; then
            echo "${ts},${GATEWAY},${rtt},ok" >> "$PING_CSV"
        else
            echo "${ts},${GATEWAY},,timeout" >> "$PING_CSV"
        fi
        sleep 1
    done
}

# =============================================================================
# Display monitor (foreground signal bar)
# =============================================================================

start_monitor() {
    while true; do
        local sig=$(get_signal)
        if [ -n "$sig" ]; then
            local label=$(signal_label "$sig")
            local bar=$(signal_bar "$sig")
            echo -ne "\033[s\033[2K  Signal: ${BOLD}${sig} dBm${NC} ${label}  ${bar}\033[u"
        fi
        sleep 1
    done
}

# =============================================================================
# Cleanup
# =============================================================================

cleanup() {
    [ -n "$MONITOR_PID" ] && kill "$MONITOR_PID" 2>/dev/null
    [ -n "$SIGNAL_LOG_PID" ] && kill "$SIGNAL_LOG_PID" 2>/dev/null
    [ -n "$PING_LOG_PID" ] && kill "$PING_LOG_PID" 2>/dev/null
    stty sane 2>/dev/null
    echo ""
}
trap cleanup EXIT

# =============================================================================
# Main display
# =============================================================================

MARK_COUNT=0

clear
echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║            WiFi Dead Spot Survey Tool                   ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${CYAN}Site:${NC}      $SITE_NAME"
echo -e "  ${CYAN}SSID:${NC}      $SSID"
echo -e "  ${CYAN}BSSID:${NC}     $BSSID"
echo -e "  ${CYAN}Frequency:${NC} $FREQ"
echo -e "  ${CYAN}Gateway:${NC}   $GATEWAY"
echo -e "  ${CYAN}Interface:${NC} $WIFI_IFACE"
echo ""
echo -e "${BOLD}  Controls:${NC}"
echo -e "    ${GREEN}m${NC} = Mark location (full survey with prompts)"
echo -e "    ${GREEN}n${NC} = Quick note"
echo -e "    ${GREEN}s${NC} = Show current stats snapshot"
echo -e "    ${GREEN}q${NC} = Quit and show summary + analysis"
echo ""
echo -e "  ${DIM}Background: signal logging (2s), gateway ping (1s), roaming detection${NC}"
echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"

# Reserve signal display line
echo ""
echo ""

# Start all background processes
start_monitor &
MONITOR_PID=$!

start_signal_logger &
SIGNAL_LOG_PID=$!

start_ping_logger &
PING_LOG_PID=$!

# =============================================================================
# Menu helpers
# =============================================================================

# All menu functions use /dev/tty for display and input so they work inside $() subshells.
# Only the final return value goes to stdout (captured by the caller).

# Instant single-keypress menu (no Enter needed)
quick_select() {
    local prompt="$1"
    shift
    local items=("$@")

    # Display options to terminal
    echo -ne "  ${BOLD}${prompt}${NC} " > /dev/tty
    for item in "${items[@]}"; do
        local key="${item%%:*}"
        local label="${item#*:}"
        echo -ne " ${GREEN}${key}${NC})${label}" > /dev/tty
    done
    echo -ne "  ${DIM}0)other${NC} " > /dev/tty

    while true; do
        read -rsn1 key < /dev/tty
        if [ "$key" = "b" ] || [ "$key" = "B" ]; then
            echo "" > /dev/tty
            echo "b"
            return
        fi
        if [ "$key" = "0" ]; then
            echo "" > /dev/tty
            local custom
            read -rp "    Custom: " custom < /dev/tty > /dev/tty
            echo "$custom"
            return
        fi
        for item in "${items[@]}"; do
            local ikey="${item%%:*}"
            local ilabel="${item#*:}"
            if [ "$key" = "$ikey" ]; then
                echo -e " ${GREEN}✓ ${ilabel}${NC}" > /dev/tty
                echo "$ilabel"
                return
            fi
        done
    done
}

# Toggle multi-select — press numbers to toggle on/off, Enter to confirm
toggle_select() {
    local prompt="$1"
    shift
    local options=("$@")
    local count=${#options[@]}
    local -a selected=()
    for ((i=0; i<count; i++)); do selected[$i]=0; done

    while true; do
        echo -ne "\r\033[2K  ${BOLD}${prompt}${NC} " > /dev/tty
        for ((i=0; i<count; i++)); do
            if [ "${selected[$i]}" -eq 1 ]; then
                echo -ne " ${GREEN}[$((i+1)):${options[$i]}]${NC}" > /dev/tty
            else
                echo -ne " ${DIM}$((i+1)):${options[$i]}${NC}" > /dev/tty
            fi
        done
        echo -ne "  ${DIM}Enter=done${NC} " > /dev/tty

        read -rsn1 key < /dev/tty
        if [ "$key" = "" ]; then
            echo "" > /dev/tty
            local result=""
            for ((i=0; i<count; i++)); do
                if [ "${selected[$i]}" -eq 1 ]; then
                    [ -n "$result" ] && result+="; "
                    result+="${options[$i]}"
                fi
            done
            [ -z "$result" ] && result="none"
            echo "$result"
            return
        fi
        if [ "$key" = "b" ] || [ "$key" = "B" ]; then
            echo "" > /dev/tty
            echo "b"
            return
        fi
        if [[ "$key" =~ ^[0-9]$ ]] && [ "$key" -ge 1 ] && [ "$key" -le "$count" ]; then
            local idx=$((key - 1))
            if [ "${selected[$idx]}" -eq 0 ]; then
                selected[$idx]=1
                if [ "$idx" -eq 0 ] && [ "${options[0]}" = "none" ]; then
                    for ((i=1; i<count; i++)); do selected[$i]=0; done
                else
                    [ "${options[0]}" = "none" ] && selected[0]=0
                fi
            else
                selected[$idx]=0
            fi
        fi
    done
}

# Display current selections as compact summary bar
show_mark_summary() {
    local -n _labels=$1
    local -n _values=$2
    local current_step=$3
    local tgt="${4:-/dev/tty}"

    echo -e "  ${DIM}────────────────────────────────────────────────────────────${NC}" > "$tgt"
    local line1=""
    for ((i=0; i<${#_labels[@]}; i++)); do
        local val="${_values[$i]}"
        if [ -n "$val" ] && [ "$val" != "-" ]; then
            if [ "$i" -eq "$current_step" ]; then
                line1+="  ${YELLOW}${_labels[$i]}:${NC}${BOLD}${val}${NC}"
            else
                line1+="  ${GREEN}${_labels[$i]}:${NC}${val}"
            fi
        elif [ "$i" -eq "$current_step" ]; then
            line1+="  ${YELLOW}→${_labels[$i]}${NC}"
        fi
    done
    echo -e "$line1" > "$tgt"
    echo -e "  ${DIM}b=back                                                      ${NC}" > "$tgt"
}

# =============================================================================
# Mark location function
# =============================================================================

mark_location() {
    kill "$MONITOR_PID" 2>/dev/null
    wait "$MONITOR_PID" 2>/dev/null

    echo ""
    echo -e "\n${BOLD}${CYAN}── MARK LOCATION ──────────────────────────────────────────${NC}"

    # Auto-capture: signal stability (sample 10 times over ~3s)
    echo -e "  ${DIM}Sampling signal stability (10 readings)...${NC}"
    local stability
    stability=$(get_signal_stability 10)
    local sig_min sig_max sig_avg sig_samples
    IFS='|' read -r sig_min sig_max sig_avg sig_samples <<< "$stability"

    local sig=$(get_signal)
    local sig_int=${sig:--100}
    local quality=$(signal_quality "$sig_int")
    local noise=$(get_noise)
    local bitrate=$(get_bitrate)
    local rx_br=$(echo "$bitrate" | sed 's/.*RX:\(.*\) TX:.*/\1/')
    local tx_br=$(echo "$bitrate" | sed 's/.*TX://')
    local retries=$(get_tx_retries)
    local failed=$(get_tx_failed)
    local bloss=$(get_beacon_loss)
    local current_bssid=$(get_bssid)

    echo -e "  Signal: ${BOLD}${sig} dBm${NC} ($(signal_label "$sig_int"))  stability: ${sig_min}/${sig_avg}/${sig_max} dBm"
    [ -n "$noise" ] && echo -e "  Noise floor: ${noise} dBm  SNR: $(( sig_int - noise )) dB"
    echo -e "  Bitrate: ${rx_br} RX / ${tx_br} TX"
    echo -e "  TX retries: ${retries:-0}  failed: ${failed:-0}  beacon loss: ${bloss:-0}"
    echo ""

    # Scan all visible SSIDs
    local all_ssids
    all_ssids=$(get_all_ssids)
    local ssid_count
    ssid_count=$(echo "$all_ssids" | grep -c '.' || echo 0)

    echo -e "  ${CYAN}Nearby networks (${ssid_count} found):${NC}"
    printf "    ${DIM}%-30s %10s %8s %4s${NC}\n" "SSID" "SIGNAL" "FREQ" "CH"
    echo "$all_ssids" | while IFS='|' read -r s_ssid s_bssid s_sig s_freq s_ch; do
        [ -z "$s_bssid" ] && continue
        local display_ssid="${s_ssid}"
        [ -z "$display_ssid" ] && display_ssid="(hidden)"
        local s_int=${s_sig%.*}
        s_int=${s_int:--100}
        local s_color
        if [ "$s_int" -ge "$GOOD" ]; then s_color="$GREEN"
        elif [ "$s_int" -ge "$FAIR" ]; then s_color="$YELLOW"
        else s_color="$RED"
        fi
        printf "    %-30s ${s_color}%7s dBm${NC}  %6s  %3s\n" "${display_ssid:0:30}" "$s_sig" "$s_freq" "$s_ch"
    done
    echo ""

    # ── Step-based input with instant menus and back navigation ──
    # Most fields are single-keypress. Free text fields use Enter.

    local field_labels=("Loc" "Flr" "Room" "I/O" "Dist" "Walls" "Mat" "Glass" "Interf" "Notes")
    local field_values=("" "" "" "" "" "" "" "" "" "")
    local step=0
    local total_steps=10

    # prompt_step runs each field's input. Free text uses /dev/tty directly.
    # Menu functions already use /dev/tty internally.
    prompt_step() {
        local s=$1
        local val=""
        case "$s" in
            0) read -rp "  Location name: " val < /dev/tty > /dev/tty ;;
            1) val=$(quick_select "Floor:" \
                    "1:ground" "2:1st" "3:2nd" "4:3rd" "5:basement" "6:mezzanine" "7:roof") ;;
            2) val=$(quick_select "Room:" \
                    "1:bedroom" "2:bathroom" "3:kitchen" "4:living" "5:office" \
                    "6:garage" "7:hallway" "8:stairwell" "9:outdoor") ;;
            3) val=$(quick_select "In/Out:" "1:indoor" "2:outdoor") ;;
            4) read -rp "  Distance from router (m): " val < /dev/tty > /dev/tty ;;
            5) val=$(quick_select "Walls:" "1:0" "2:1" "3:2" "4:3" "5:4" "6:5+") ;;
            6) val=$(quick_select "Material:" \
                    "1:drywall" "2:brick" "3:concrete" "4:wood" "5:glass" "6:mixed") ;;
            7) val=$(quick_select "Glass doors:" "1:0" "2:1" "3:2" "4:3") ;;
            8) val=$(toggle_select "Interference:" \
                    "none" "microwave" "bluetooth" "baby mon" "cordless" "other APs" "TV/screen") ;;
            9) read -rp "  Notes (Enter=skip): " val < /dev/tty > /dev/tty
               [ -z "$val" ] && val="-" ;;
        esac
        echo "$val"
    }

    while [ "$step" -lt "$total_steps" ]; do
        show_mark_summary field_labels field_values "$step" /dev/stdout

        local val
        val=$(prompt_step "$step")

        if [ "$val" = "b" ]; then
            [ "$step" -gt 0 ] && step=$((step - 1))
            continue
        fi

        field_values[$step]="$val"
        step=$((step + 1))
    done

    # Show final summary and confirm
    echo ""
    show_mark_summary field_labels field_values -1 /dev/stdout
    echo ""
    echo -e "  ${GREEN}c${NC}=save  ${YELLOW}1-9,0${NC}=edit field  ${RED}x${NC}=cancel"

    while true; do
        read -rsn1 confirm
        if [ "$confirm" = "c" ] || [ "$confirm" = "C" ]; then
            break
        elif [ "$confirm" = "x" ] || [ "$confirm" = "X" ]; then
            echo -e "  ${RED}✗ Cancelled${NC}"
            echo ""
            start_monitor &
            MONITOR_PID=$!
            return
        elif [[ "$confirm" =~ ^[0-9]$ ]]; then
            local edit_step
            if [ "$confirm" = "0" ]; then edit_step=9; else edit_step=$((confirm - 1)); fi
            if [ "$edit_step" -lt "$total_steps" ]; then
                local val
                val=$(prompt_step "$edit_step")
                [ "$val" != "b" ] && field_values[$edit_step]="$val"
                echo ""
                show_mark_summary field_labels field_values -1 /dev/stdout
                echo ""
                echo -e "  ${GREEN}c${NC}=save  ${YELLOW}1-9,0${NC}=edit field  ${RED}x${NC}=cancel"
            fi
        fi
    done

    # Extract values
    local location="${field_values[0]}"
    local floor="${field_values[1]}"
    local room_type="${field_values[2]}"
    local indoor_outdoor="${field_values[3]}"
    local distance="${field_values[4]}"
    local walls="${field_values[5]}"
    local wall_material="${field_values[6]}"
    local glass="${field_values[7]}"
    local interference="${field_values[8]}"
    local notes="${field_values[9]}"

    # Auto-capture: network performance tests
    echo ""
    echo -e "  ${DIM}Running quick network tests...${NC}"

    echo -ne "    Gateway latency... "
    local gw_latency
    gw_latency=$(quick_ping "$GATEWAY")
    echo -e "${GREEN}done${NC}"

    echo -ne "    Internet latency... "
    local inet_latency
    inet_latency=$(quick_ping "8.8.8.8")
    echo -e "${GREEN}done${NC}"

    echo -ne "    DNS resolution... "
    local dns_time
    dns_time=$(quick_dns)
    echo -e "${GREEN}done${NC}"

    echo -ne "    HTTP TTFB... "
    local http_ttfb
    http_ttfb=$(quick_http)
    echo -e "${GREEN}done${NC}"

    echo ""
    echo -e "    Gateway:  $gw_latency"
    echo -e "    Internet: $inet_latency"
    echo -e "    DNS:      $dns_time"
    echo -e "    HTTP:     $http_ttfb"

    # Sanitise CSV fields
    location="${location//,/;}"
    notes="${notes//,/;}"
    interference="${interference//,/;}"
    wall_material="${wall_material//,/;}"
    room_type="${room_type//,/;}"
    local ts=$(date '+%Y-%m-%d %H:%M:%S')

    # Extract numeric DNS and HTTP values for CSV
    local dns_num=$(echo "$dns_time" | grep -oP '^\d+' || echo "")
    local http_num=$(echo "$http_ttfb" | grep -oP '^\d+' || echo "")

    # Write to main CSV
    echo "${ts},${location},${floor},${room_type},${indoor_outdoor},${distance},${walls},${wall_material},${glass},${interference},${sig},${sig_min},${sig_max},${sig_avg},${sig_samples},${quality},${noise},${retries},${failed},${bloss},${SSID},${current_bssid},${FREQ},${rx_br},${tx_br},${ssid_count},${gw_latency},${dns_num},${http_num},${inet_latency},${notes}" >> "$CSV_FILE"

    # Write all SSIDs for this location
    echo "$all_ssids" | while IFS='|' read -r s_ssid s_bssid s_sig s_freq s_ch; do
        [ -z "$s_bssid" ] && continue
        local clean_ssid="${s_ssid//,/;}"
        echo "${ts},${location},${clean_ssid},${s_bssid},${s_sig},${s_freq},${s_ch}" >> "$SSID_CSV"
    done

    # Write to human-readable log
    {
        echo "=== MARK #$((MARK_COUNT + 1)) ==="
        echo "  Time:            $ts"
        echo "  Location:        $location"
        echo "  Floor:           $floor"
        echo "  Room type:       $room_type"
        echo "  Indoor/outdoor:  $indoor_outdoor"
        echo "  Distance:        ${distance}m from router"
        echo "  Walls:           $walls ($wall_material)"
        echo "  Glass doors:     $glass"
        echo "  Interference:    $interference"
        echo ""
        echo "  Signal:          ${sig} dBm (${quality})"
        echo "  Signal range:    ${sig_min} to ${sig_max} dBm (avg: ${sig_avg}, samples: ${sig_samples})"
        echo "  Noise floor:     ${noise:-n/a} dBm"
        [ -n "$noise" ] && echo "  SNR:             $(( sig_int - noise )) dB"
        echo "  RX Bitrate:      $rx_br"
        echo "  TX Bitrate:      $tx_br"
        echo "  TX retries:      ${retries:-0}"
        echo "  TX failed:       ${failed:-0}"
        echo "  Beacon loss:     ${bloss:-0}"
        echo "  Connected AP:    $current_bssid"
        echo ""
        echo "  Gateway latency: $gw_latency"
        echo "  Internet:        $inet_latency"
        echo "  DNS resolution:  $dns_time"
        echo "  HTTP TTFB:       $http_ttfb"
        echo ""
        echo "  Nearby SSIDs:    $ssid_count"
        printf "    %-30s %10s %8s %4s\n" "SSID" "SIGNAL" "FREQ" "CH"
        printf "    %-30s %10s %8s %4s\n" "-----" "------" "----" "--"
        echo "$all_ssids" | while IFS='|' read -r s_ssid s_bssid s_sig s_freq s_ch; do
            [ -z "$s_bssid" ] && continue
            local display_ssid="${s_ssid}"
            [ -z "$display_ssid" ] && display_ssid="(hidden)"
            printf "    %-30s %8s dBm %6s  %3s\n" "${display_ssid:0:30}" "$s_sig" "$s_freq" "$s_ch"
        done
        echo ""
        echo "  Notes:           $notes"
        echo ""
    } >> "$LOG_FILE"

    MARK_COUNT=$((MARK_COUNT + 1))

    echo ""
    echo -e "  ${GREEN}✓ Location #${MARK_COUNT} marked: ${location} @ ${sig} dBm (${quality})${NC}"
    echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
    echo ""
    echo ""

    start_monitor &
    MONITOR_PID=$!
}

# =============================================================================
# Quick note function
# =============================================================================

add_note() {
    kill "$MONITOR_PID" 2>/dev/null
    wait "$MONITOR_PID" 2>/dev/null

    echo ""
    local note
    read -rp "  Note: " note
    local ts=$(date '+%Y-%m-%d %H:%M:%S')
    local sig=$(get_signal)
    echo "${ts},NOTE,,,,,,,,,${sig},,,,,,,,,,${SSID},${BSSID},${FREQ},,,,,,,,${note}" >> "$CSV_FILE"
    echo "[${ts}] NOTE (${sig} dBm): ${note}" >> "$LOG_FILE"
    echo -e "  ${GREEN}✓ Note added${NC}"
    echo ""

    start_monitor &
    MONITOR_PID=$!
}

# =============================================================================
# Stats snapshot
# =============================================================================

show_stats() {
    kill "$MONITOR_PID" 2>/dev/null
    wait "$MONITOR_PID" 2>/dev/null

    echo ""
    echo -e "${BOLD}${CYAN}── STATS SNAPSHOT ─────────────────────────────────────────${NC}"

    local sig=$(get_signal)
    local sig_int=${sig:--100}
    local noise=$(get_noise)
    local bitrate=$(get_bitrate)
    local rx_br=$(echo "$bitrate" | sed 's/.*RX:\(.*\) TX:.*/\1/')
    local tx_br=$(echo "$bitrate" | sed 's/.*TX://')
    local retries=$(get_tx_retries)
    local failed=$(get_tx_failed)
    local bloss=$(get_beacon_loss)
    local current_bssid=$(get_bssid)

    echo -e "  Signal:      ${BOLD}${sig} dBm${NC} ($(signal_label "$sig_int"))"
    [ -n "$noise" ] && echo -e "  Noise:       ${noise} dBm  SNR: $(( sig_int - noise )) dB"
    echo -e "  BSSID:       $current_bssid"
    echo -e "  Bitrate:     ${rx_br} RX / ${tx_br} TX"
    echo -e "  TX retries:  ${retries:-0}  failed: ${failed:-0}  beacon loss: ${bloss:-0}"

    # Quick ping stats from log
    if [ -f "$PING_CSV" ]; then
        local total lost
        total=$(wc -l < "$PING_CSV")
        total=$((total - 1))
        lost=$({ grep -c ',timeout$' "$PING_CSV" 2>/dev/null || true; })
        local avg_rtt
        avg_rtt=$(awk -F, 'NR>1 && $4=="ok" {s+=$3; c++} END {if(c>0) printf "%.1f", s/c; else print "n/a"}' "$PING_CSV")
        echo -e "  Ping stats:  ${total} pings, ${lost} lost, avg ${avg_rtt} ms"
    fi

    echo -e "  Marks:       $MARK_COUNT locations recorded"
    echo -e "  Duration:    running since $(head -2 "$TIMESERIES_CSV" | tail -1 | cut -d, -f1)"
    echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
    echo ""
    echo ""

    start_monitor &
    MONITOR_PID=$!
}

# =============================================================================
# Summary and analysis
# =============================================================================

show_summary() {
    kill "$MONITOR_PID" 2>/dev/null
    wait "$MONITOR_PID" 2>/dev/null
    kill "$SIGNAL_LOG_PID" 2>/dev/null
    kill "$PING_LOG_PID" 2>/dev/null
    MONITOR_PID=""
    SIGNAL_LOG_PID=""
    PING_LOG_PID=""

    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║                      SURVEY SUMMARY & ANALYSIS                  ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${CYAN}Site:${NC}        $SITE_NAME"
    echo -e "  ${CYAN}Locations:${NC}   $MARK_COUNT marked"
    echo -e "  ${CYAN}Files:${NC}"
    echo -e "    Survey CSV:     $CSV_FILE"
    echo -e "    SSIDs CSV:      $SSID_CSV"
    echo -e "    Time series:    $TIMESERIES_CSV"
    echo -e "    Ping log:       $PING_CSV"
    echo -e "    Readable log:   $LOG_FILE"

    # ── Location Results Table ──
    if [ "$MARK_COUNT" -gt 0 ]; then
        echo ""
        echo -e "${BOLD}  ── LOCATION RESULTS ─────────────────────────────────────────────${NC}"
        printf "  ${BOLD}%-20s %7s %7s %5s %5s %5s %8s${NC}\n" "LOCATION" "SIGNAL" "AVG" "WALLS" "GLASS" "FLOOR" "QUALITY"
        echo -e "  ${DIM}──────────────────────────────────────────────────────────────────${NC}"

        while IFS=, read -r ts location floor room_type io distance walls wmat glass interf sig smin smax savg ssamples quality rest; do
            [ "$location" = "location" ] && continue
            [ "$location" = "NOTE" ] && continue
            [ -z "$location" ] && continue
            local color
            case "$quality" in
                excellent|good) color="$GREEN" ;;
                fair|weak)      color="$YELLOW" ;;
                *)              color="$RED" ;;
            esac
            printf "  %-20s ${color}%6s${NC}  %6s  %4s  %4s  %5s  ${color}%8s${NC}\n" \
                "${location:0:20}" "${sig}dB" "${savg}dB" "$walls" "$glass" "$floor" "$quality"
        done < "$CSV_FILE"
        echo -e "  ${DIM}──────────────────────────────────────────────────────────────────${NC}"

        # Stats
        local signals
        signals=$(awk -F, 'NR>1 && $2!="NOTE" && $11!="" {print $11}' "$CSV_FILE")
        if [ -n "$signals" ]; then
            local best worst avg count dead_spots
            best=$(echo "$signals" | sort -n | tail -1)
            worst=$(echo "$signals" | sort -n | head -1)
            count=$(echo "$signals" | wc -l)
            avg=$(echo "$signals" | awk '{s+=$1} END {printf "%.0f", s/NR}')
            dead_spots=$(echo "$signals" | awk -v w="$WEAK" '$1 < w' | wc -l)

            echo ""
            echo -e "  ${BOLD}Signal Stats:${NC}"
            echo -e "    Best:       ${GREEN}${best} dBm${NC}"
            echo -e "    Worst:      ${RED}${worst} dBm${NC}"
            echo -e "    Average:    ${avg} dBm"
            echo -e "    Dead spots: ${dead_spots} of ${count} locations"
        fi
    fi

    # ── Ping Statistics ──
    if [ -f "$PING_CSV" ] && [ "$(wc -l < "$PING_CSV")" -gt 1 ]; then
        echo ""
        echo -e "${BOLD}  ── CONTINUOUS PING STATISTICS ───────────────────────────────────${NC}"
        local total lost avg_rtt max_rtt min_rtt
        total=$(awk 'NR>1' "$PING_CSV" | wc -l)
        lost=$({ grep -c ',timeout$' "$PING_CSV" 2>/dev/null || true; })
        local loss_pct
        loss_pct=$(awk "BEGIN{printf \"%.1f\", ($lost/$total)*100}")
        avg_rtt=$(awk -F, 'NR>1 && $4=="ok" {s+=$3; c++} END {if(c>0) printf "%.1f", s/c; else print "n/a"}' "$PING_CSV")
        min_rtt=$(awk -F, 'NR>1 && $4=="ok" {print $3}' "$PING_CSV" | sort -n | head -1)
        max_rtt=$(awk -F, 'NR>1 && $4=="ok" {print $3}' "$PING_CSV" | sort -n | tail -1)

        echo -e "    Total pings:  $total"
        echo -e "    Packet loss:  ${lost} (${loss_pct}%)"
        echo -e "    Latency:      min ${min_rtt:-n/a} / avg ${avg_rtt} / max ${max_rtt:-n/a} ms"
    fi

    # ── Roaming Events ──
    local roam_count
    roam_count=$(grep -c 'ROAMING EVENT' "$LOG_FILE" 2>/dev/null || echo 0)
    if [ "$roam_count" -gt 0 ]; then
        echo ""
        echo -e "${BOLD}  ── ROAMING EVENTS ──────────────────────────────────────────────${NC}"
        echo -e "    $roam_count AP switch(es) detected during survey"
        grep 'ROAMING EVENT' "$LOG_FILE" | while read -r line; do
            echo -e "    ${YELLOW}$line${NC}"
        done
    fi

    # ── Channel Congestion Analysis ──
    if [ -f "$SSID_CSV" ] && [ "$(wc -l < "$SSID_CSV")" -gt 1 ]; then
        echo ""
        echo -e "${BOLD}  ── CHANNEL CONGESTION ANALYSIS ─────────────────────────────────${NC}"

        # 2.4 GHz channels (< 3000 MHz)
        echo ""
        echo -e "  ${CYAN}2.4 GHz Band:${NC}"
        local ch_data
        ch_data=$(awk -F, 'NR>1 && $6<3000 && $7!="" {print $7}' "$SSID_CSV" | sort | uniq -c | sort -rn)
        if [ -n "$ch_data" ]; then
            printf "    ${DIM}%-10s %10s %s${NC}\n" "CHANNEL" "NETWORKS" ""
            echo "$ch_data" | while read -r count ch; do
                local bar=""
                for ((i=0; i<count; i++)); do bar+="█"; done
                local ch_color="$GREEN"
                [ "$count" -ge 3 ] && ch_color="$YELLOW"
                [ "$count" -ge 5 ] && ch_color="$RED"
                printf "    Ch %-5s ${ch_color}%5s${NC}     ${ch_color}%s${NC}\n" "$ch" "$count" "$bar"
            done

            # Check for non-1/6/11 usage (overlapping channels)
            local bad_channels
            bad_channels=$(awk -F, 'NR>1 && $6<3000 && $7!="" && $7!=1 && $7!=6 && $7!=11 {print $7}' "$SSID_CSV" | sort -u)
            if [ -n "$bad_channels" ]; then
                echo ""
                echo -e "    ${YELLOW}⚠ Networks on overlapping channels: $(echo $bad_channels | tr '\n' ' ')${NC}"
                echo -e "    ${DIM}  Best practice: only use channels 1, 6, and 11 for 2.4 GHz${NC}"
            fi
        else
            echo "    No 2.4 GHz networks found"
        fi

        # 5 GHz channels (>= 5000 MHz)
        echo ""
        echo -e "  ${CYAN}5 GHz Band:${NC}"
        ch_data=$(awk -F, 'NR>1 && $6>=5000 && $7!="" {print $7}' "$SSID_CSV" | sort | uniq -c | sort -rn)
        if [ -n "$ch_data" ]; then
            printf "    ${DIM}%-10s %10s %s${NC}\n" "CHANNEL" "NETWORKS" ""
            echo "$ch_data" | while read -r count ch; do
                local bar=""
                for ((i=0; i<count; i++)); do bar+="█"; done
                local ch_color="$GREEN"
                [ "$count" -ge 3 ] && ch_color="$YELLOW"
                [ "$count" -ge 5 ] && ch_color="$RED"
                printf "    Ch %-5s ${ch_color}%5s${NC}     ${ch_color}%s${NC}\n" "$ch" "$count" "$bar"
            done
        else
            echo "    No 5 GHz networks found"
        fi

        # 2.4 vs 5 GHz comparison
        echo ""
        echo -e "  ${CYAN}Band Comparison:${NC}"
        local avg_24 avg_5 count_24 count_5
        avg_24=$(awk -F, 'NR>1 && $6<3000 && $5!="" {s+=$5; c++} END {if(c>0) printf "%.0f", s/c; else print "n/a"}' "$SSID_CSV")
        avg_5=$(awk -F, 'NR>1 && $6>=5000 && $5!="" {s+=$5; c++} END {if(c>0) printf "%.0f", s/c; else print "n/a"}' "$SSID_CSV")
        count_24=$(awk -F, 'NR>1 && $6<3000' "$SSID_CSV" | wc -l)
        count_5=$(awk -F, 'NR>1 && $6>=5000' "$SSID_CSV" | wc -l)
        echo -e "    2.4 GHz: ${count_24} networks seen, avg signal ${avg_24} dBm"
        echo -e "    5 GHz:   ${count_5} networks seen, avg signal ${avg_5} dBm"
    fi

    # ── Dead Spot Recommendations ──
    if [ "$MARK_COUNT" -gt 0 ]; then
        echo ""
        echo -e "${BOLD}  ── RECOMMENDATIONS ─────────────────────────────────────────────${NC}"

        local has_issues=false

        # Find dead spots
        while IFS=, read -r ts location floor room_type io distance walls wmat glass interf sig rest; do
            [ "$location" = "location" ] && continue
            [ "$location" = "NOTE" ] && continue
            [ -z "$location" ] && continue
            local sig_int=${sig:--100}
            if [ "$sig_int" -lt "$WEAK" ]; then
                has_issues=true
                echo -e "    ${RED}✗ DEAD SPOT: ${location}${NC} (${sig} dBm)"
                echo -e "      ${distance}m away, ${walls} walls (${wmat}), ${glass} glass doors"
                if [ -n "$interf" ] && [ "$interf" != "none" ]; then
                    echo -e "      Interference: ${interf}"
                fi
                # Suggest fix based on data
                if [ "${walls:-0}" -ge 3 ] || [ "${distance:-0}" -ge 15 ]; then
                    echo -e "      ${CYAN}→ Consider adding an access point closer to this area${NC}"
                elif [ "${wmat}" = "concrete" ] || [ "${wmat}" = "brick" ]; then
                    echo -e "      ${CYAN}→ Dense wall material blocking signal — consider a mesh AP on this side${NC}"
                else
                    echo -e "      ${CYAN}→ Consider repositioning router or adding a repeater/mesh node${NC}"
                fi
                echo ""
            elif [ "$sig_int" -lt "$FAIR" ]; then
                has_issues=true
                echo -e "    ${YELLOW}⚠ WEAK: ${location}${NC} (${sig} dBm)"
                echo -e "      ${distance}m away, ${walls} walls, ${glass} glass doors"
                echo ""
            fi
        done < "$CSV_FILE"

        # Ping quality
        if [ -f "$PING_CSV" ]; then
            local loss_pct
            local total=$(awk 'NR>1' "$PING_CSV" | wc -l)
            local lost=$({ grep -c ',timeout$' "$PING_CSV" 2>/dev/null || true; })
            if [ "$total" -gt 0 ]; then
                loss_pct=$(awk "BEGIN{printf \"%.1f\", ($lost/$total)*100}")
                local lp_int=${loss_pct%.*}
                if [ "${lp_int:-0}" -ge 5 ]; then
                    has_issues=true
                    echo -e "    ${RED}✗ HIGH PACKET LOSS: ${loss_pct}%${NC}"
                    echo -e "      ${CYAN}→ Indicates unstable connection — check for interference or congestion${NC}"
                    echo ""
                elif [ "${lp_int:-0}" -ge 1 ]; then
                    has_issues=true
                    echo -e "    ${YELLOW}⚠ MODERATE PACKET LOSS: ${loss_pct}%${NC}"
                    echo ""
                fi
            fi
        fi

        # Channel congestion warning
        local max_ch_count
        max_ch_count=$(awk -F, 'NR>1 && $6<3000 && $7!="" {print $7}' "$SSID_CSV" 2>/dev/null | sort | uniq -c | sort -rn | head -1 | awk '{print $1}')
        if [ "${max_ch_count:-0}" -ge 5 ]; then
            has_issues=true
            echo -e "    ${YELLOW}⚠ HIGH 2.4 GHz CONGESTION: up to ${max_ch_count} networks on same channel${NC}"
            echo -e "      ${CYAN}→ Consider using 5 GHz band where possible${NC}"
            echo ""
        fi

        if [ "$has_issues" = false ]; then
            echo -e "    ${GREEN}✓ No significant issues detected. Coverage looks good.${NC}"
        fi
    fi

    # ── Write analysis to log ──
    {
        echo ""
        echo "============================================================================="
        echo "  ANALYSIS SUMMARY"
        echo "============================================================================="
        echo "  Generated: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "  Locations surveyed: $MARK_COUNT"
        if [ -f "$PING_CSV" ] && [ "$(wc -l < "$PING_CSV")" -gt 1 ]; then
            echo "  Ping samples: $(awk 'NR>1' "$PING_CSV" | wc -l)"
            echo "  Packet loss: $({ grep -c ',timeout$' "$PING_CSV" 2>/dev/null || true; })"
        fi
        if [ -f "$TIMESERIES_CSV" ] && [ "$(wc -l < "$TIMESERIES_CSV")" -gt 1 ]; then
            echo "  Signal samples: $(awk 'NR>1' "$TIMESERIES_CSV" | wc -l)"
        fi
        echo ""
    } >> "$LOG_FILE"

    echo ""
    echo -e "  ${DIM}Files saved to: $SURVEY_DIR${NC}"
    echo ""

    read -rp "  Send all files to dev server? [y/N] " send
    if [[ "$send" =~ ^[Yy]$ ]]; then
        local dev="jason@10.0.10.21"
        local dest="~/site-reports/"
        ssh "$dev" "mkdir -p $dest" 2>/dev/null
        scp "$CSV_FILE" "$dev:$dest" 2>/dev/null && echo -e "  ${GREEN}✓ Survey CSV sent${NC}"
        scp "$SSID_CSV" "$dev:$dest" 2>/dev/null && echo -e "  ${GREEN}✓ SSIDs CSV sent${NC}"
        scp "$TIMESERIES_CSV" "$dev:$dest" 2>/dev/null && echo -e "  ${GREEN}✓ Time series sent${NC}"
        scp "$PING_CSV" "$dev:$dest" 2>/dev/null && echo -e "  ${GREEN}✓ Ping log sent${NC}"
        scp "$LOG_FILE" "$dev:$dest" 2>/dev/null && echo -e "  ${GREEN}✓ Log sent${NC}"
    fi
    echo ""
}

# =============================================================================
# Main input loop
# =============================================================================

while true; do
    read -rsn1 key
    case "$key" in
        m|M) mark_location ;;
        n|N) add_note ;;
        s|S) show_stats ;;
        q|Q) show_summary; break ;;
    esac
done
