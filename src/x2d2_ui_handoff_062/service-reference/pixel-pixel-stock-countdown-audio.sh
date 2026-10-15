#!/system/bin/sh
# X2D 4.2.0: use the stock player and stock assets; no custom library mapping.
export PATH=/system/bin:/system/xbin:/sbin
root=/tmp/x2d-native-multishot
player=/system/bin/test_audio_client
last=0
cleanup() {
 trap - EXIT
 rm -f "$root/countdown-audio.ready"
}
trap cleanup EXIT
trap 'exit 143' HUP INT TERM
[ -x "$player" ] || exit 51
[ -r /system/usr/share/system-sound/selftimer_short_beep.wav ] || exit 52
[ -r /system/usr/share/system-sound/selftimer_long_beep.wav ] || exit 52
printf 'READY\n' >"$root/countdown-audio.ready" || exit 53
while :;do
 if [ -r "$root/countdown-audio.request" ];then
  read -r magic seq kind level end extra <"$root/countdown-audio.request"
  case "$seq" in ''|*[!0-9]*) seq=0;;esac
  if [ "$magic" = NPA1 ] && [ "$end" = END ] && [ -z "$extra" ] &&
     [ "${#seq}" -le 8 ] && [ "$seq" -gt "$last" ];then
   last=$seq
   case "$kind" in short|long) ;; *) sleep .05;continue;;esac
   case "$level" in 1) stream=20;;2) stream=40;;3) stream=100;;*) sleep .05;continue;;esac
   # The stock tool defaults device volume to 60. Preserve the actual current
   # equal L/R volume explicitly; refuse asymmetric or unreadable states.
   volumes=$("$player" get_dev_volume speaker 2>&1 | sed -n 's/.*volume = \([0-9]*\)(L)-\([0-9]*\)(R).*/\1 \2/p')
   set -f
   set -- $volumes
   if [ "$#" -ne 2 ] || [ "$1" != "$2" ];then echo COUNTDOWN_VOLUME_UNKNOWN;continue;fi
   case "$1" in ''|*[!0-9]*) echo COUNTDOWN_VOLUME_UNKNOWN;continue;;esac
   if [ "${#1}" -gt 3 ] || [ "$1" -gt 100 ];then echo COUNTDOWN_VOLUME_UNKNOWN;continue;fi
   "$player" stream_play speaker -f "/system/usr/share/system-sound/selftimer_${kind}_beep.wav" -sv "$stream" -v "$1" -i wav
   code=$?
   if [ "$code" -eq 0 ];then echo COUNTDOWN_AUDIO_PLAYED;else echo COUNTDOWN_AUDIO_FAILED;fi
  fi
 fi
 sleep .05
done
