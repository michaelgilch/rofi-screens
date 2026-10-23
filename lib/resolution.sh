# shellcheck shell=bash
# shellcheck disable=SC2154  # globals are set in rofi-screens and screens-lib.sh
# Resolution menu: switch the internal panel between modes at its native
# aspect ratio, adding scaled modes the driver doesn't offer.
#
# Modes added with `xrandr --newmode` only last until X restarts. The menu
# adds any missing ones each time it opens, and `rofi-screens --init` does it
# up front (window manager startup, or an autorandr preswitch hook so a saved
# profile can use them). `rofi-screens --xorg-conf` makes them permanent.
#
# The mode picked from the menu is saved, and `rofi-screens --init` restores
# it, so it survives restarts. Opening the menu never restores.

backend resolution res 10 "Resolution" video-display

# Settings are documented in config.example. An empty RES_MODES means
# "generate from RES_SCALES".
RES_OUTPUT=${RES_OUTPUT:-}
declare -p RES_SCALES &>/dev/null || RES_SCALES=(90 80 67)
declare -p RES_MODES &>/dev/null || RES_MODES=()
RES_REMEMBER=${RES_REMEMBER:-1}

# res_load: sets res_output, res_native, res_current and res_have (every mode
# the output has). Fails if there's no usable output.
res_load() {
    xr_query
    res_output=${RES_OUTPUT:-$(xr_internal)}
    res_have=() res_native="" res_current=""
    [[ -n $res_output ]] || return 1
    local mode flags
    while IFS=$'\t' read -r mode flags; do
        res_have+=("$mode")
        [[ $flags == *+* && -z $res_native ]] && res_native=$mode
        [[ $flags == *'*'* ]] && res_current=$mode
    done < <(xr_modes "$res_output")
    ((${#res_have[@]} > 0)) || return 1
    [[ -n $res_native ]] || res_native=${res_have[0]}
}

res_available() {
    res_load
}

# res_gcd <a> <b>
res_gcd() {
    local a=$1 b=$2 t
    while ((b)); do
        t=$((a % b)) a=$b b=$t
    done
    echo "$a"
}

# res_targets: prints the modes to add, one per line: RES_MODES if set, else
# one per RES_SCALES percentage of the native mode.
res_targets() {
    if ((${#RES_MODES[@]} > 0)); then
        printf '%s\n' "${RES_MODES[@]}"
        return
    fi
    local w=${res_native%x*} h=${res_native#*x} g rw rh step k s
    g=$(res_gcd "$w" "$h")
    rw=$((w / g)) rh=$((h / g))
    # cvt rounds widths to a multiple of 8. Stepping k in these units keeps
    # rw*k on that grid, so the mode stays at exactly the native ratio.
    step=$((8 / $(res_gcd "$rw" 8)))
    for s in "${RES_SCALES[@]}"; do
        k=$(((w * s / 100 / rw + step / 2) / step * step))
        ((k > 0 && rw * k < w)) && echo "$((rw * k))x$((rh * k))"
    done
}

# res_timings <WxH>: prints cvt's 60 Hz timings for the mode, without a name.
res_timings() {
    cvt "${1%x*}" "${1#*x}" 60 | sed -nE 's/^Modeline +"[^"]+" +//p'
}

# res_xorg_conf: prints a Monitor section that defines the target modes from
# X startup, so nothing has to add them at runtime.
res_xorg_conf() {
    if ! res_load; then
        echo "rofi-screens: no internal display found. Set RES_OUTPUT" >&2
        return 1
    fi
    if ! command -v cvt >/dev/null; then
        echo "rofi-screens: cvt not found. Install libxcvt" >&2
        return 1
    fi
    local mode
    printf 'Section "Monitor"\n    Identifier "%s"\n' "$res_output"
    while read -r mode; do
        printf '    Modeline "%s"  %s\n' "$mode" "$(res_timings "$mode")"
    done < <(res_targets)
    printf 'EndSection\n'
}

# res_add_modes: adds missing target modes to the output. Idempotent.
res_add_modes() {
    res_load || return 1
    if ! command -v cvt >/dev/null; then
        notify "cvt not found" "Install libxcvt to add scaled modes" critical
        return 1
    fi
    local mode params added=""
    while read -r mode; do
        [[ " ${res_have[*]} " == *" $mode "* ]] && continue
        params=$(res_timings "$mode")
        [[ -n $params ]] || continue
        # Named after the plain resolution rather than cvt's "_60.00" default,
        # so the check above and the menu labels stay clean. --newmode fails
        # harmlessly if another output already defined it.
        # shellcheck disable=SC2086  # params is the list of timings
        xrandr --newmode "$mode" $params 2>/dev/null
        xrandr --addmode "$res_output" "$mode" 2>/dev/null && added=1
    done < <(res_targets)
    [[ -z $added ]] || res_load
}

res_state_file() {
    echo "${XDG_STATE_HOME:-$HOME/.local/state}/rofi-screens/resolution"
}

# res_set <output> <mode>: switches the output to the mode and, if
# RES_REMEMBER is on, saves it as "output<TAB>mode" for res_restore.
res_set() {
    xrandr --output "$1" --mode "$2" || return 1
    ((RES_REMEMBER)) || return 0
    local file
    file=$(res_state_file)
    mkdir -p "${file%/*}" && printf '%s\t%s\n' "$1" "$2" >"$file"
}

# res_restore: switches back to the saved mode. Skipped if it was saved for
# another output (renamed, or RES_OUTPUT changed), the output no longer has
# it, or it's already current.
res_restore() {
    ((RES_REMEMBER)) || return 0
    local file output mode
    file=$(res_state_file)
    [[ -f $file ]] || return 0
    IFS=$'\t' read -r output mode <"$file" || return 0
    [[ $output == "$res_output" && $mode != "$res_current" ]] || return 0
    [[ " ${res_have[*]} " == *" $mode "* ]] || return 0
    if xrandr --output "$res_output" --mode "$mode"; then
        on_change
    else
        notify "Failed to restore $mode" "" critical
        return 1
    fi
}

# res_init: for `rofi-screens --init`. Adds the modes, then restores the
# saved one.
res_init() {
    res_add_modes # the saved mode may be one the driver offers anyway
    res_restore
}

# res_choices: prints the menu's modes, largest first: everything the output
# has at the native ratio, plus any RES_MODES that were added.
res_choices() {
    local w=${res_native%x*} h=${res_native#*x} mode
    for mode in "${res_have[@]}"; do
        if ((${mode%x*} * h == ${mode#*x} * w)) ||
            [[ " ${RES_MODES[*]} " == *" $mode "* ]]; then
            echo "$mode"
        fi
    done | sort -t x -u -k1,1nr -k2,2nr
}

res_menu() {
    local back=${1:-} key mode label g
    if ! res_available; then
        notify "Resolution" "No internal display found. Set RES_OUTPUT"
        exit 0
    fi
    res_add_modes # failures are reported; the driver's modes still work

    menu_reset
    while read -r mode; do
        label=$mode
        [[ $mode == "$res_native" ]] && label+="  (native)"
        [[ $mode == "$res_current" ]] && label+="  ✓"
        row "$mode" "$label"
    done < <(res_choices)

    [[ -n $back ]] && row back "Back" go-previous
    g=$(res_gcd "${res_native%x*}" "${res_native#*x}")
    key=$(menu "Resolution ($((${res_native%x*} / g)):$((${res_native#*x} / g)))") || exit 0
    case $key in
    back) return 0 ;;
    "$res_current") exit 0 ;;
    *)
        run_bg "$res_output now at $key" "Failed to set $key" \
            res_set "$res_output" "$key"
        ;;
    esac
}
