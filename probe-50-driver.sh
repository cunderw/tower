#!/bin/zsh
# usage: 50-probe.sh <worktree> <n> <label> [nooverride]
WT=$1; N=$2; LABEL=$3; MODE=$4
UDID=$GATE_DEVICE_UDID
[[ -n $UDID ]] || { echo "no GATE_DEVICE_UDID"; exit 2; }
echo "device $GATE_DEVICE_NAME $UDID"
for i in $(seq 1 $N); do
  xcrun simctl shutdown $UDID >/dev/null 2>&1
  xcrun simctl bootstatus $UDID -b >/dev/null || { echo boot failed; exit 3; }
  if [[ $MODE != nooverride ]]; then
    xcrun simctl status_bar $UDID override --time "2007-01-09T09:41:00.000-06:00" --cellularBars 4 --batteryLevel 100 --batteryState discharging
  fi
  uptime; OUT=$(dirname $0)/50-probe-$LABEL-$i-$(date +%H%M%S).json
  rm -f $OUT
  npx -y xcodebuildmcp@2.7.0 simulator test --project-path $WT/Tower.xcodeproj --scheme Tower \
    --simulator-id $UDID --json '{"extraArgs":["-only-testing:TowerUITests/InlineTitleProbeUITests"]}' \
    --output json >| $OUT
  echo "run $i exit $? -> $OUT"
  LOG=$(python3 -c "import json,sys;d=json.load(open('$OUT'));import os;print(os.path.expanduser(d['data']['artifacts'].get('buildLogPath','')))" 2>/dev/null)
  echo "log $LOG"
  [[ -n $LOG ]] && grep -h "\[probe\]\|error:" $LOG | grep -v "^\s*t =" | cut -c1-400
  xcrun simctl status_bar $UDID clear >/dev/null 2>&1
done
