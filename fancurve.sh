#!/bin/bash
# Fan curve for MacBook Pro M4 Pro (Mac16,8) using Stats.app's bundled smc tool.
#
#   ./fancurve.sh --dry-run [seconds]   read temps, print what would be set (default)
#   ./fancurve.sh --table               print the curve for 40..100 °C
#   sudo ./fancurve.sh --apply          actually drive the fans (not used yet)
#
# Curve: below T_ON macOS keeps control (automatic). From T_ON to T_FULL fans ramp
# linearly MIN -> MAX. At T_FULL and above fans run at MAX. Fans go back to automatic
# only once the temperature drops below T_OFF (hysteresis).

SMC=/Applications/Stats.app/Contents/Resources/smc
FANS=(0 1)
MIN_RPM=4500
MAX_RPM=7826
T_OFF=85     # back to automatic below this
T_ON=90      # take over above this
T_FULL=100   # full speed at/above this
INTERVAL=1

mode=${1:---dry-run}
duration=${2:-30}

# Hottest CPU core sensor (Tpxx = performance cores, Texx = efficiency cores).
cpu_temp() {
  "$SMC" list -t 2>/dev/null |
    awk '/^\[T[pe][0-9A-Za-z][0-9A-Za-z]\]/ { v=$2+0; if (v>m) m=v } END { printf "%.1f", m }'
}

# Target RPM for a temperature, or "auto".
target_for() {
  awk -v t="$1" -v on="$T_ON" -v full="$T_FULL" -v lo="$MIN_RPM" -v hi="$MAX_RPM" 'BEGIN {
    if (t < on)        print "auto"
    else if (t >= full) print hi
    else               printf "%d", lo + (hi - lo) * (t - on) / (full - on)
  }'
}

fan_rpm() {
  "$SMC" fans 2>/dev/null | awk -v id="$1" '
    $0 ~ "^"id": " { f=1 } f && /Actual speed/ { printf "%d", $3; exit }'
}

run() {
  if [ "$mode" = "--apply" ]; then "$@"; else echo "    would run: $*"; fi
}

case "$mode" in
  --table)
    printf "%6s  %s\n" "°C" "target"
    for t in $(seq 40 5 100); do printf "%6s  %s\n" "$t" "$(target_for "$t")"; done
    exit 0 ;;
  --dry-run|--apply) ;;
  *) echo "usage: $0 [--dry-run [seconds] | --table | --apply]"; exit 1 ;;
esac

if [ "$mode" = "--apply" ]; then
  [ "$(id -u)" -eq 0 ] || { echo "--apply needs sudo"; exit 1; }
  trap '"$SMC" reset; exit 0' INT TERM EXIT
fi

manual=0
end=$(( $(date +%s) + duration ))
while [ "$mode" = "--apply" ] || [ "$(date +%s)" -lt "$end" ]; do
  t=$(cpu_temp)
  target=$(target_for "$t")
  # Hysteresis: once in manual, stay there until below T_OFF.
  if [ "$target" = "auto" ] && [ "$manual" -eq 1 ] && awk -v t="$t" -v off="$T_OFF" 'BEGIN{exit !(t>=off)}'; then
    target=$MIN_RPM
  fi

  printf "%s  CPU %5s°C  fans %s/%s rpm  -> %s\n" "$(date +%T)" "$t" "$(fan_rpm 0)" "$(fan_rpm 1)" "$target"

  if [ "$target" = "auto" ]; then
    if [ "$manual" -eq 1 ]; then run "$SMC" reset; manual=0; fi
  else
    for f in "${FANS[@]}"; do
      [ "$manual" -eq 0 ] && run "$SMC" fan "$f" -m 1
      run "$SMC" fan "$f" -v "$target"
    done
    manual=1
  fi
  sleep "$INTERVAL"
done
