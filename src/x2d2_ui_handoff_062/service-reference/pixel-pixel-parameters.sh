#!/system/bin/sh
# RAM-only parameter bridge. No capture methods, arbitrary properties or eval.
root=${X2D_PIXEL_RAM_ROOT:-/tmp/x2d-native-multishot}
trap 'exit 0' HUP INT TERM
get_value() {
    timeout 3 dbus-send --system --print-reply --dest=com.hasselblad.camera /camera \
        org.freedesktop.DBus.Properties.Get string:com.hasselblad.camera "string:$1" |
        awk '/variant[[:space:]]+int32[[:space:]]/{print $NF}'
}
snapshot() {
    # One DBus snapshot avoids seven serial round trips per menu refresh.
    raw=$(timeout 3 dbus-send --system --print-reply --dest=com.hasselblad.camera /camera \
        org.freedesktop.DBus.Properties.GetAll string:com.hasselblad.camera) || return 1
    values=$(printf '%s\n' "$raw" | awk '
      /dict entry\(/ { key="" }
      /^[[:space:]]*string "[A-Za-z_]+"[[:space:]]*$/ { split($0,a,"\""); key=a[2] }
      /variant[[:space:]]+int32[[:space:]]+-?[0-9]+[[:space:]]*$/ {
        if(key ~ /^(multishot_control_mode|flash_recharge_delay|su_status|can_change|exposure_status|selftimer_sound_level|exposures_in_multishot_session)$/) {
          if(seen[key]++) bad=1
          v=$NF+0
          if(v < -2147483648 || v > 2147483647) bad=1
          # DBus transports this flags property as signed int32.
          if(key=="can_change" && v<0) v+=4294967296
          value[key]=sprintf("%.0f",v)
        }
        key=""
      }
      END {
        n=split("multishot_control_mode flash_recharge_delay su_status can_change exposure_status selftimer_sound_level exposures_in_multishot_session",keys," ")
        for(i=1;i<=n;i++) if(seen[keys[i]]!=1) bad=1
        if(bad) exit 1
        for(i=1;i<=n;i++) printf "%s%s",value[keys[i]],(i==n?"\n":" ")
      }') || return 1
    set -f
    set -- $values
    [ "$#" = 7 ] || return 1
    mode=$1; wait_ms=$2; su=$3; change=$4; exposure=$5; sound_level=$6; frames=$7
    initial_ms=0
    if [ -f "$root/initial-delay.target" ]; then
        initial_ms=$(sh "$root/pixel-initial-delay.sh" read) || return 1
    fi
    for number in "$mode" "$wait_ms" "$su" "$change" "$exposure" "$initial_ms" "$sound_level" "$frames"; do
        case "$number" in ''|*[!0-9]*) return 1;; esac
    done
    [ "$mode" -le 6 ] && [ "$wait_ms" -le 600000 ] && [ "$su" -le 255 ] && [ "$sound_level" -le 3 ] && [ "$frames" -le 1000 ]
}
set_value() {
    timeout 3 dbus-send --system --print-reply --dest=com.hasselblad.camera /camera \
        org.freedesktop.DBus.Properties.Set string:com.hasselblad.camera "string:$1" "variant:int32:$2" >/dev/null
}
idle_snapshot() { [ "$((change & 16))" -ne 0 ] && [ "$((exposure & 1299))" -eq 0 ] && [ "$su" -ne 6 ]; }
set_mode_and_frames() {
    old_mode=$mode; old_frames=$frames; wanted_frames=$frames
    case "$value" in 1) wanted_frames=4;; 2) wanted_frames=6;; 3) wanted_frames=16;; esac
    wrote_frames=0; wrote_mode=0
    # Mode selects the sensor positions; this independent property controls
    # the original state machine's requested exposure count.
    if [ "$frames" = "$wanted_frames" ] || set_value exposures_in_multishot_session "$wanted_frames"; then
        [ "$frames" = "$wanted_frames" ] || wrote_frames=1
        if snapshot && idle_snapshot && [ "$frames" = "$wanted_frames" ]; then
            if [ "$mode" = "$value" ] || set_value multishot_control_mode "$value"; then
                [ "$mode" = "$value" ] || wrote_mode=1
                if snapshot && [ "$mode" = "$value" ] && [ "$frames" = "$wanted_frames" ]; then
                    okay=true;reason=saved;return
                fi
            fi
        fi
    fi
    reason=rejected
    # Roll back only this transaction's acknowledged values, while idle.
    if snapshot && idle_snapshot; then
        if [ "$wrote_mode" = 1 ] && [ "$mode" = "$value" ]; then
            set_value multishot_control_mode "$old_mode" || reason=rollback_failed
        fi
        if [ "$wrote_frames" = 1 ] && [ "$frames" = "$wanted_frames" ]; then
            set_value exposures_in_multishot_session "$old_frames" || reason=rollback_failed
        fi
        snapshot || reason=read_failed
    else reason=read_failed
    fi
}
reply() {
    if [ "$reason" = read_failed ]; then
        printf '{"seq":"%s","ready":false,"ok":false,"reason":"read_failed"}\n' "$seq" >"$root/parameters.state.new"
    else
        printf '{"seq":"%s","ready":true,"ok":%s,"reason":"%s","mode":%s,"frames":%s,"wait":%s,"initial":%s,"sound":%s,"suStatus":%s,"canChange":%s,"exposureStatus":%s}\n' \
            "$seq" "$okay" "$reason" "$mode" "$frames" "$wait_ms" "$initial_ms" "$sound_level" "$su" "$change" "$exposure" >"$root/parameters.state.new"
    fi
    mv "$root/parameters.state.new" "$root/parameters.state"
}
last_seq=0
while :; do
    if [ -z "${X2D_PIXEL_OFFLINE_TEST:-}" ]; then
        gui=$(cat "$root/gui.pid" 2>/dev/null)
        case "$gui" in ''|*[!0-9]*) exit 20;; esac
        kill -0 "$gui" 2>/dev/null || exit 21
    fi
    seq= kind= value= extra=
    IFS='|' read -r seq kind value extra 2>/dev/null <"$root/parameters.request"
    case "$seq" in ''|*[!0-9]*) sleep 0.05;continue;; esac
    [ "$seq" != "$last_seq" ] || { sleep 0.05;continue; }
    last_seq=$seq;okay=false;reason=bad_request
    if ! snapshot; then
        printf '{"seq":"%s","ready":false,"ok":false,"reason":"read_failed"}\n' "$seq" >"$root/parameters.state.new"
        mv "$root/parameters.state.new" "$root/parameters.state"
        continue
    fi
    prop=
    if [ -z "$extra" ]; then
        case "$kind:$value" in
            refresh:0) okay=true;reason=read;;
            mode:0|mode:1|mode:2|mode:3) prop=multishot_control_mode;;
            wait:0|wait:500|wait:1000|wait:2000|wait:5000) prop=flash_recharge_delay;;
            sound:0|sound:1|sound:2|sound:3) prop=selftimer_sound_level;;
            initial:0) prop=initial;;
            initial:*)
                case "$value" in ''|*[!0-9]*) ;; *)
                    if [ "$value" -ge 2000 ] && [ "$value" -le 60000 ] && [ "$((value % 1000))" -eq 0 ]; then prop=initial; fi;;
                esac;;
        esac
    fi
    if [ -n "$prop" ]; then
        if [ "$((change & 16))" -eq 0 ] || [ "$((exposure & 1299))" -ne 0 ] || [ "$su" -eq 6 ]; then
            reason=busy
        elif [ "$prop" = multishot_control_mode ]; then
            set_mode_and_frames
        elif [ "$prop" = initial ]; then
            previous_initial=$initial_ms
            preference=/blackbox/.x2d-play-software/pixel-initial
            if [ -L /blackbox/.x2d-play-software ] || [ -L "$preference" ] || [ -L "$preference.next" ]; then reason=rejected;reply;continue;fi
            if [ -f "$root/initial-delay.target" ] && sh "$root/pixel-initial-delay.sh" set "$value" && snapshot && [ "$initial_ms" = "$value" ]; then
                if (umask 077; printf '%s\n' "$value" >/blackbox/.x2d-play-software/pixel-initial.next && mv /blackbox/.x2d-play-software/pixel-initial.next /blackbox/.x2d-play-software/pixel-initial && sync); then
                    okay=true;reason=saved
                else
                    sh "$root/pixel-initial-delay.sh" set "$previous_initial" && snapshot || exit 54
                    reason=rejected
                fi
            else reason=rejected;fi
        elif timeout 3 dbus-send --system --print-reply --dest=com.hasselblad.camera /camera \
            org.freedesktop.DBus.Properties.Set string:com.hasselblad.camera "string:$prop" "variant:int32:$value" >/dev/null; then
            if snapshot; then
                actual=$mode;[ "$kind" != wait ] || actual=$wait_ms
                [ "$kind" != sound ] || actual=$sound_level
                if [ "$actual" = "$value" ]; then okay=true;reason=saved;else reason=rejected;fi
            else
                printf '{"seq":"%s","ready":false,"ok":false,"reason":"read_failed"}\n' "$seq" >"$root/parameters.state.new"
                mv "$root/parameters.state.new" "$root/parameters.state"
                continue
            fi
        else reason=rejected
        fi
    fi
    reply
done
