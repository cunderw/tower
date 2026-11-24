#!/usr/bin/env bash
#
# Captures the App Store screenshot tour from **demo mode**, and frames the captures for
# the store.
#
#   scripts/screenshots.sh [--kind iphone-69|ipad-13] [--simulator-id <udid>] [out-dir]
#   scripts/screenshots.sh --frame [--kind iphone-69|ipad-13] [out-dir]
#   scripts/screenshots.sh --help
#
#   out-dir              default: docs/app-store-assets/
#   --kind KIND          one size only. Without it, both sizes run, one after the other.
#   --simulator-id UDID  capture on this simulator instead of the named one for KIND
#                        (needs --kind). For a caller that manages its own simulator, so
#                        the check for another live xcodebuild is skipped.
#   --frame              no tour: frame the committed raw captures again. It touches no
#                        simulator and runs no xcodebuild.
#   --help               this text. It touches no simulator.
#
# Three directories under out-dir:
#
#   raw/<kind>/      the tour's captures, named for what they show (dashboard.png).
#                    Committed, so --frame runs without a simulator.
#   <kind>/          the store images, NN-<name>.png. Each is a raw capture in a device
#                    frame under a caption. These are what the store upload reads. It reads
#                    only the top level of each set folder, so raw/ and background/ never
#                    upload.
#   background/      one generated image per kind, drawn behind the device. Without it the
#                    framer draws a charcoal gradient with an orange glow.
#
# scripts/frame-screenshots.swift owns LISTING, the store order and the caption for each
# capture. `swift scripts/frame-screenshots.swift --list` prints the order. A capture that
# LISTING does not name is not published. The tour photographs more screens than the store
# set uses, and some of them show UI-test fixtures.
#
# Demo mode, not the UI-test fakes: the listing shows what a reviewer sees after "Try the
# Demo", and the fakes are tuned to make failure paths reachable.
#
# The 6.9" set needs its own device. `Tower iPhone 17`, the gate device, is 6.3". `Tower
# iPhone 17 Pro Max` is 6.9" and `Tower iPad` is 13". This script creates neither, and
# CLAUDE.md has the `simctl create` commands. The tour stays in light appearance.
#
# The status bar is overridden for a tour: 9:41 on a fixed date, full bars, a full battery.
# It is cleared when the script exits, also when the run fails. Without it every image
# carries the time it was taken at, and the iPad's the date.
#
# Everything is made in a staging directory first. Only when every check for every kind
# has passed does the script copy the staged images into out-dir. A failure changes nothing
# there and prints where the staged images are.
#
# Never pipe this into `head` or `grep`. You lose the progress output, and `$?` becomes the
# pipe's status.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT
readonly FRAMER="$REPO_ROOT/scripts/frame-screenshots.swift"

# Only the demo captures. The rest of the tour (`vms-list`, `share-detail`, the log viewer)
# verifies screens and shows UI-test fixtures.
readonly TOUR="TowerUITests/ScreenshotTourUITests/testCaptureDemoMode"

# Where this run makes everything before it is copied into out-dir.
STAGE=""

note() { printf '\033[36m==>\033[0m %s\n' "$*"; }
die() {
  printf '\033[31merror:\033[0m %s\n' "$*" >&2
  [[ -z "$STAGE" ]] || printf '\033[31mNothing in the output directory changed. This run is in %s.\033[0m\n' "$STAGE" >&2
  exit 1
}
# Every leading comment line after the shebang, up to the first line that is not one.
usage() { awk 'NR==1{next} /^#/{print; next} {exit}' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

# The named simulator for each kind.
device_for() {
  case "$1" in
    iphone-69) echo "Tower iPhone 17 Pro Max" ;;
    ipad-13) echo "Tower iPad" ;;
    *) return 1 ;;
  esac
}

# The capture and store image size for each kind. App Store Connect rejects any other.
expected_size() {
  case "$1" in
    iphone-69) echo "1320x2868" ;;
    ipad-13) echo "2064x2752" ;;
    *) return 1 ;;
  esac
}

FRAME_ONLY=0
KIND=""
KIND_SET=0
SIM_ID=""
OUT=""
while (( $# )); do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --frame) FRAME_ONLY=1; shift ;;
    --kind) [[ $# -ge 2 ]] || die "--kind needs a value"; KIND="$2"; KIND_SET=1; shift 2 ;;
    --simulator-id) [[ $# -ge 2 && -n "$2" ]] || die "--simulator-id needs a value"; SIM_ID="$2"; shift 2 ;;
    -*) die "unknown option $1 (see --help)" ;;
    *) [[ -z "$OUT" ]] || die "more than one output directory given"; OUT="$1"; shift ;;
  esac
done

(( ! KIND_SET )) || device_for "$KIND" >/dev/null || die "--kind must be iphone-69 or ipad-13, not '$KIND'"
[[ -z "$SIM_ID" || -n "$KIND" ]] || die "--simulator-id needs --kind, to know which size it captures"
(( ! FRAME_ONLY )) || [[ -z "$SIM_ID" ]] || die "--frame runs no tour, so --simulator-id means nothing with it"

KINDS=(iphone-69 ipad-13)
[[ -z "$KIND" ]] || KINDS=("$KIND")

for tool in swift sips xcrun python3; do
  command -v "$tool" >/dev/null 2>&1 || die "$tool is not on PATH"
done
(( FRAME_ONLY )) || command -v npx >/dev/null 2>&1 || die "npx is not on PATH"

# LISTING, read from the framer, so the order lives in one place. A `while read` loop,
# because macOS's bash 3.2 has no `mapfile`.
LISTED=()
listing_text="$(swift "$FRAMER" --list)" || die "cannot read LISTING from $FRAMER"
while IFS= read -r stem; do
  [[ -z "$stem" ]] || LISTED+=("$stem")
done <<< "$listing_text"
(( ${#LISTED[@]} > 0 )) || die "LISTING in $FRAMER is empty"
# App Store Connect takes at most ten per size. An eleventh would be rejected at upload,
# long after this ran, so refuse here.
(( ${#LISTED[@]} <= 10 )) || die "LISTING has ${#LISTED[@]} entries; App Store Connect takes at most 10"

# Fails unless the directory holds exactly `want` images.
check_count() {
  local what="$1" dir="$2" want="$3" got
  got="$(find "$dir" -maxdepth 1 -name '*.png' | wc -l | tr -d ' ')"
  [[ "$got" == "$want" ]] || die "$what has $got images in $dir, expected $want"
}

# Fails unless the image is `want` pixels (WxH) and, when `opaque` is given, has no alpha
# channel. App Store Connect rejects a screenshot with one.
check_image() {
  local image="$1" want="$2" opaque="${3:-}" got alpha
  got="$(sips -g pixelWidth -g pixelHeight "$image" \
    | awk '/pixelWidth/{w=$2} /pixelHeight/{h=$2} END{print w "x" h}')"
  [[ "$got" == "$want" ]] || die "$image is $got, expected $want"
  if [[ -n "$opaque" ]]; then
    alpha="$(sips -g hasAlpha "$image" | awk '/hasAlpha/{print $2}')"
    [[ "$alpha" == "no" ]] || die "$image has an alpha channel (hasAlpha: $alpha)"
  fi
}

# Makes `out` hold exactly the PNGs in `from`, so a reordered LISTING leaves no stale
# NN- file beside the new ones.
replace_set() {
  local from="$1" out="$2"
  rm -rf "$out"
  mkdir -p "$out" || die "cannot create $out"
  cp "$from"/*.png "$out"/ || die "cannot copy $from into $out"
}

# The devices whose status bar this run has overridden. One EXIT trap for the whole script.
OVERRIDDEN=()
# Best-effort: it runs from the trap, and a failure here must not hide the run's status.
clear_status_bars() {
  local udid
  for udid in ${OVERRIDDEN[@]+"${OVERRIDDEN[@]}"}; do
    xcrun simctl status_bar "$udid" clear >/dev/null 2>&1 || true
  done
}

# The devices this run has put in Full Screen Apps, each as `udid=previous`. `previous` is
# the key's earlier value, or empty when the device had no value.
FULL_SCREEN=()
# Best-effort, like `clear_status_bars`: a failure prints a warning and does not change the
# run's status. Other gates run on the same simulators, so the multitasking mode goes back
# to what it was. `defaults read` prints a bool as 1 or 0, and `defaults write -bool`
# rejects both, so the value is mapped to true or false first.
restore_multitasking() {
  local entry udid previous value
  for entry in ${FULL_SCREEN[@]+"${FULL_SCREEN[@]}"}; do
    udid="${entry%%=*}"
    previous="${entry#*=}"
    case "$previous" in
      "")
        xcrun simctl spawn "$udid" defaults delete com.apple.springboard \
          SBMedusaMultitaskingEnabled >/dev/null 2>&1 \
          || printf 'warning: cannot delete SBMedusaMultitaskingEnabled on %s\n' "$udid" >&2
        continue
        ;;
      1) value=true ;;
      0) value=false ;;
      *)
        printf 'warning: cannot restore SBMedusaMultitaskingEnabled on %s: it was %s, not a bool\n' \
          "$udid" "$previous" >&2
        continue
        ;;
    esac
    xcrun simctl spawn "$udid" defaults write com.apple.springboard \
      SBMedusaMultitaskingEnabled -bool "$value" >/dev/null 2>&1 \
      || printf 'warning: cannot restore SBMedusaMultitaskingEnabled=%s on %s\n' "$value" "$udid" >&2
  done
}
trap 'clear_status_bars; restore_multitasking' EXIT

# The UDID of the one available device with this name. `simctl status_bar` takes a UDID, and
# two devices under one name would make "booted" ambiguous.
device_udid() {
  xcrun simctl list -j devices available | DEVICE_NAME="$1" python3 -c '
import json, os, sys
name = os.environ["DEVICE_NAME"]
found = [d["udid"] for ds in json.load(sys.stdin)["devices"].values() for d in ds if d["name"] == name]
if len(found) != 1:
    sys.exit(f"{len(found)} available simulators are named {name!r}, expected exactly 1")
print(found[0])
'
}

# The time the status bar is fixed at, in the one form `simctl status_bar` takes as a date:
# ISO 8601 with milliseconds and a colon in the offset. It rejects `2007-01-09T09:41:00` and
# `…00Z` as "non-ISO", and a bare `9:41` leaves the iPad's date at today's. The offset is
# this Mac's on that day, because the simulator draws the time in the Mac's zone.
#
# 2007-01-09 is a Tuesday, the date of the iPhone's announcement, and the iPad draws it as
# "Tue Jan 9". This holds only when `--time` goes in an override call of its own, after
# every other flag. See `override_status_bar`.
#
# `/bin/date`, because a GNU `date` first on PATH has no `-j`.
tour_time() {
  local offset
  offset="$(/bin/date -j -f '%Y-%m-%d %H:%M:%S' '2007-01-09 09:41:00' '+%z' 2>/dev/null)" \
    || offset=""
  [[ "$offset" =~ ^[+-][0-9]{4}$ ]] \
    || die "cannot read this Mac's UTC offset from /bin/date -j (got '$offset')"
  echo "2007-01-09T09:41:00.000${offset:0:3}:${offset:3:2}"
}

# Shuts the device down and boots it again (a warm boot, never an erase), then overrides
# its status bar. SpringBoard hides the home indicator only while the simulator reports
# that attention is lost, and a device that has stayed booted can stop sending those
# reports, so every capture then draws the indicator. The iPad drew it in all ten
# captures on 2026-11-23, and a boot brings the reports back. The shutdown stops anything
# else on that simulator, so run the tour through the device lock. `bootstatus -b`
# returns when the boot has finished, and the override fails on a device that is shut
# down.
override_status_bar() {
  local udid="$1" bar_time
  xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$udid" -b >/dev/null || die "cannot boot simulator $udid"
  # Its own assignment, because a failure inside an argument's `$(…)` does not stop the run.
  bar_time="$(tour_time)" || exit 1
  OVERRIDDEN+=("$udid")
  # `discharging`, because a level alone draws a green charging battery.
  xcrun simctl status_bar "$udid" override \
    --cellularBars 4 --batteryLevel 100 --batteryState discharging \
    || die "cannot override the status bar on $udid"
  # The time in a call of its own, and last. An override call that sets any other
  # flag, with `--time` or after it, keeps the month and day but loses the year:
  # the iPad then draws the weekday of that date in 2000, "Sun Jan 9" for a Tuesday
  # (issue #49).
  xcrun simctl status_bar "$udid" override --time "$bar_time" \
    || die "cannot override the status bar time on $udid"
}

# Puts the device in Full Screen Apps (Settings > Multitasking & Gestures) for the run. The
# iPad simulator runs in Windowed Apps, which draws a resize grip in the bottom-right corner
# of every window, a full-size one too, so every iPad capture showed it. Full Screen Apps
# draws no grip and changes nothing else in a capture. SpringBoard reads the key at the
# next app launch, with no reboot. Measured on the iOS 27.2 runtime. Only the iPad has
# multitasking modes, so only the iPad run sets it.
use_full_screen_apps() {
  local udid="$1" previous
  previous="$(xcrun simctl spawn "$udid" defaults read com.apple.springboard \
    SBMedusaMultitaskingEnabled 2>/dev/null)" || previous=""
  FULL_SCREEN+=("$udid=$previous")
  xcrun simctl spawn "$udid" defaults write com.apple.springboard \
    SBMedusaMultitaskingEnabled -bool false \
    || die "cannot set Full Screen Apps on $udid"
}

# Runs the tour for one kind into $STAGE/raw/<kind>, and keeps only the LISTING captures.
capture() {
  local kind="$1" udid="$SIM_ID" device dir
  device="$(device_for "$kind")"
  dir="$STAGE/raw/$kind"
  if [[ -z "$udid" ]]; then
    udid="$(device_udid "$device")" || die "cannot find the simulator '$device'"
  fi
  note "capturing $kind on $device ($udid)"
  override_status_bar "$udid"
  [[ "$kind" != ipad-13 ]] || use_full_screen_apps "$udid"
  rm -rf "$dir"
  mkdir -p "$dir" || die "cannot create $dir"
  # The tour reads its output directory from `TOWER_SCREENSHOT_DIR`
  # (`TowerUITests/ScreenshotTourUITests.swift`). It runs in the test runner process, not
  # this shell, so the value has to arrive as test-runner environment. `--extra-args` is
  # flag-only, so this uses XcodeBuildMCP's `--json` form with a `testRunnerEnv` object.
  npx -y xcodebuildmcp@2.7.0 simulator test \
    --project-path "$REPO_ROOT/Tower.xcodeproj" \
    --scheme Tower \
    --simulator-id "$udid" \
    --json "$(printf '{"extraArgs":["-only-testing:%s"],"testRunnerEnv":{"TOWER_SCREENSHOT_DIR":"%s"}}' "$TOUR" "$dir")" \
    --output json \
    >| "$STAGE/$kind.capture.json" \
    || die "$kind capture failed. Read $STAGE/$kind.capture.json"
  xcrun simctl status_bar "$udid" clear >/dev/null 2>&1 || true

  local stem want
  for stem in "${LISTED[@]}"; do
    [[ -f "$dir/$stem.png" ]] || die "the tour produced no $stem.png, so LISTING is stale"
  done
  # Anything else is a tour capture the listing does not use.
  local file keep
  for file in "$dir"/*.png; do
    keep=0
    for stem in "${LISTED[@]}"; do
      [[ "$(basename "$file")" != "$stem.png" ]] || keep=1
    done
    (( keep )) || rm -f "$file"
  done
  check_count "$kind captures" "$dir" "${#LISTED[@]}"
  want="$(expected_size "$kind")"
  for file in "$dir"/*.png; do
    check_image "$file" "$want"
  done
  note "$kind: ${#LISTED[@]} captures, all $want"
}

# Frames one kind's staged raw captures into its staged store set.
frame() {
  local kind="$1" raw="$STAGE/raw/$1" out="$STAGE/$1" want file
  note "$kind: framing the captures"
  rm -rf "$out"
  mkdir -p "$out" || die "cannot create $out"
  swift "$FRAMER" "$kind" "$raw" "$out" || die "$kind: the framing failed"
  check_count "$kind store set" "$out" "${#LISTED[@]}"
  want="$(expected_size "$kind")"
  for file in "$out"/*.png; do
    check_image "$file" "$want" opaque
  done
  note "$kind: ${#LISTED[@]} store images, all $want, no alpha"
}

# **One run per checkout and per simulator.** A second run in one checkout shares its
# DerivedData, and a second run on one simulator installs over the first. So without
# --simulator-id, a tour refuses while any xcodebuild is live. `pgrep -x` matches the
# process name exactly, so it cannot match its own invocation. --frame runs no xcodebuild,
# so it skips this.
if (( ! FRAME_ONLY )) && [[ -z "$SIM_ID" ]] \
  && { pgrep -x xcodebuild >/dev/null 2>&1 || pgrep -x swiftpm-testing-helper >/dev/null 2>&1; }; then
  die "another xcodebuild or swiftpm-testing-helper run is active; wait for it (pgrep -xl xcodebuild)"
fi

# Resolve the output directory against the caller's directory before changing to the repo
# root. The test runner needs an absolute path anyway.
OUT="${OUT:-$REPO_ROOT/docs/app-store-assets}"
mkdir -p "$OUT" || die "cannot create $OUT"
OUT="$(cd "$OUT" && pwd)"
readonly OUT

# XcodeBuildMCP reads `.xcodebuildmcp/config.yaml` from the working directory. Run from
# another checkout, it would build and photograph that checkout's code, so work from this
# repo's root and pass the project explicitly as well.
cd "$REPO_ROOT" || die "cannot cd to $REPO_ROOT"

STAGE="$(mktemp -d)" || die "cannot make a staging directory"
for kind in "${KINDS[@]}"; do
  if (( FRAME_ONLY )); then
    [[ -d "$OUT/raw/$kind" ]] || die "there are no raw captures in $OUT/raw/$kind to frame"
    mkdir -p "$STAGE/raw/$kind" || die "cannot create $STAGE/raw/$kind"
    for stem in "${LISTED[@]}"; do
      cp "$OUT/raw/$kind/$stem.png" "$STAGE/raw/$kind/" \
        || die "$OUT/raw/$kind has no $stem.png, which LISTING names"
    done
  else
    capture "$kind"
  fi
  frame "$kind"
done

# Every check for every kind has passed.
for kind in "${KINDS[@]}"; do
  (( FRAME_ONLY )) || replace_set "$STAGE/raw/$kind" "$OUT/raw/$kind"
  replace_set "$STAGE/$kind" "$OUT/$kind"
done
rm -rf "$STAGE"
STAGE=""

note "done: $OUT"
for kind in "${KINDS[@]}"; do
  find "$OUT/$kind" -name '*.png' | sort
done
printf '\033[33m%s\033[0m\n' "Now open them. A generated screenshot that nobody opened is not evidence."
