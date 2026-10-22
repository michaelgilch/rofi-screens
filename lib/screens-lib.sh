# shellcheck shell=bash
# shellcheck disable=SC2154  # globals are set in rofi-screens and screens-lib.sh
# Shared helpers for rofi-screens. Sourced, not executed.

# ------------------------------------------------------------------ backends

# Every other lib/*.sh file is a backend that registers itself with backend()
# when sourced. rofi-screens builds the top menu and the command line from
# this registry.
_backend_names=()
_backend_prefixes=()
_backend_orders=()
_backend_labels=()
_backend_icons=()

# backend <name> <prefix> <order> <label> <icon>
# <name> is the command line argument, <order> the position in the top menu.
# The backend must define <prefix>_available and <prefix>_menu [back], and
# may define <prefix>_init for `rofi-screens --init`.
backend() {
    _backend_names+=("$1")
    _backend_prefixes+=("$2")
    _backend_orders+=("$3")
    _backend_labels+=("$4")
    _backend_icons+=("$5")
}

# Prints registry indexes sorted by order.
backend_indexes() {
    local i
    for i in "${!_backend_names[@]}"; do
        printf '%s\t%s\n' "${_backend_orders[i]}" "$i"
    done | sort -n -k1,1 | cut -f2
}

# ------------------------------------------------------------------ rofi rows

# Rows are collected in parallel arrays and printed by menu(). Each row has a
# key, which is what menu() returns, so callers never parse display labels.
menu_reset() {
    _keys=()
    _labels=()
    _icons=()
}

# row <key> <label> [icon]
row() {
    _keys+=("$1")
    _labels+=("$2")
    _icons+=("${3:-}")
}

# menu <prompt> [rofi args...]
# Shows the collected rows and prints the key of the chosen one.
# Returns non-zero on Escape.
menu() {
    local prompt=$1 idx i
    shift
    idx=$(
        for i in "${!_labels[@]}"; do
            if [[ -n ${_icons[i]} ]]; then
                printf '%s\0icon\x1f%s\n' "${_labels[i]}" "${_icons[i]}"
            else
                printf '%s\n' "${_labels[i]}"
            fi
        done | rofi -dmenu -i -no-custom -format i -p "$prompt" "${rofi_args[@]}" "$@"
    ) || return 1
    [[ $idx =~ ^[0-9]+$ ]] || return 1
    printf '%s\n' "${_keys[idx]}"
}

# ------------------------------------------------------------------- xrandr

# xr_query: snapshot `xrandr --query` into xr_state for the helpers below.
# Call it again after changing modes or outputs.
xr_query() {
    xr_state=$(xrandr --query)
}

# xr_internal: prints the first connected internal panel (eDP, LVDS, DSI),
# else the primary output.
xr_internal() {
    awk '
        $2 == "connected" && $1 ~ /^(eDP|LVDS|DSI)/ { print $1; found = 1; exit }
        $2 == "connected" && $3 == "primary" && primary == "" { primary = $1 }
        END { if (!found && primary != "") print primary }
    ' <<<"$xr_state"
}

# xr_modes <output>: prints "WxH<TAB>flags" per mode of the output, where
# flags holds "*" for the current mode and "+" for the preferred one.
# Interlaced modes are skipped.
xr_modes() {
    awk -v out="$1" '
        /^[^ \t]/ { active = ($1 == out); next }
        active && $1 ~ /^[0-9]+x[0-9]+$/ {
            flags = ""
            if ($0 ~ /\*/) flags = flags "*"
            if ($0 ~ /\+/) flags = flags "+"
            print $1 "\t" flags
        }
    ' <<<"$xr_state"
}

# ------------------------------------------------------------ side effects

# notify <summary> [body] [urgency]
notify() {
    notify-send -a rofi-screens -u "${3:-normal}" "$1" "${2:-}"
}

on_change() {
    [[ -n $ON_CHANGE ]] || return 0
    setsid -f bash -c "$ON_CHANGE" &>/dev/null || true
}

# run_bg <success summary> <failure summary> <command...>
# Runs the command in the background, reports the result, then closes the menu.
run_bg() {
    local ok=$1 fail=$2
    shift 2
    (
        local out
        if out=$("$@" 2>&1); then
            notify "$ok"
        else
            notify "$fail" "$out" critical
        fi
        on_change
    ) &>/dev/null &
    exit 0
}
