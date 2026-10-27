#!/usr/bin/env bash
#
# Generates the App Store screenshot set from **demo mode**.
#
# Not from the UI-test fakes: the store listing should show the dataset a
# reviewer actually sees when they tap "Try the Demo", and the fakes are tuned to
# make failure paths reachable (a container whose every action fails). Demo mode
# is also deterministic, which is what makes this reproducible rather than a
# manual capture session.
#
# Usage:
#   scripts/screenshots.sh [--kind iphone-69|ipad-13] [--simulator-id <udid>] [output-dir]
#
#   output-dir           default: docs/app-store-assets/
#   --kind KIND          capture one size only; without it, both run one after
#                        the other
#   --simulator-id UDID  capture on this simulator instead of the named one for
#                        KIND (needs --kind). For a caller that manages its own
#                        simulator, so the check for another live build is skipped.
#
# Output layout, one directory per required size:
#   <out>/iphone-69/…  <out>/ipad-13/…
#
# The output is **committed**. These are the assets uploaded to App Store
# Connect, so the diff is the listing's diff, and a set led by the wrong screen
# (an empty connect screen, say) shows up in review instead of on the store.
# Regenerating replaces each directory wholesale.
#
# App Store Connect requires one 6.9" iPhone set and, for a universal app, one
# 13" iPad set. Every other size is derived from those.
#
# The 6.9" set needs its own device. `Tower iPhone 17`, the gate device, is
# 6.3" (1206x2622). `Tower iPhone 17 Pro Max` (1320x2868) covers 6.9", and
# `Tower iPad` is already 13". This script creates neither; CLAUDE.md has the
# `simctl create` commands.
#
# Never pipe this into `head` or `grep`. You lose the progress output, and `$?`
# becomes the pipe's status.
set -uo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

note() { printf '\033[36m==>\033[0m %s\n' "$*"; }
die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
usage() { sed -n '11,19s/^# \{0,1\}//p' "${BASH_SOURCE[0]}"; }

# Only the demo captures. The rest of the tour (`vms-list`, `share-detail`, the
# log viewer) exists to *verify* screens and shows UI-test fixtures, which name
# things like `uitest-vm-1` — not something to put in a store listing.
readonly TOUR="TowerUITests/ScreenshotTourUITests/testCaptureDemoMode"

# **The listing, in order.** App Store Connect takes at most ten screenshots per
# size and the tour captures more than that, so the set is curated here rather
# than by whatever the tour happens to photograph. Keeping the order in one
# array, instead of in the capture names, means adding a tour capture does not
# renumber committed assets, and reordering the listing is a diff of this list.
#
# The listing leads with server administration screens: the dashboard, then the
# surfaces only an administration client has (Docker, VMs, shares), then the
# service hub and the read-only status screens. **Four captures are deliberately
# excluded**: `search`, `downloads`, `radarr-queue` and `indexers`. The features
# still exist and the description still names them; they are not what the
# listing leads with. The connect screen is also **not** in the set, because an
# empty sign-in form shows nothing the app does.
readonly -a LISTING=(
  dashboard
  docker
  vms
  shares
  services
  radarr-library
  streams
  requests
  music
  subtitles
)

# The named simulator for each --kind.
device_for() {
  case "$1" in
    iphone-69) echo "Tower iPhone 17 Pro Max" ;;
    ipad-13) echo "Tower iPad" ;;
    *) return 1 ;;
  esac
}

KIND=""
KIND_SET=0
SIM_ID=""
OUT=""
while (( $# )); do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --kind) [[ $# -ge 2 ]] || die "--kind needs a value"; KIND="$2"; KIND_SET=1; shift 2 ;;
    --simulator-id) [[ $# -ge 2 && -n "$2" ]] || die "--simulator-id needs a value"; SIM_ID="$2"; shift 2 ;;
    -*) die "unknown option $1 (see --help)" ;;
    *) [[ -z "$OUT" ]] || die "more than one output directory given"; OUT="$1"; shift ;;
  esac
done

(( ! KIND_SET )) || device_for "$KIND" >/dev/null || die "--kind must be iphone-69 or ipad-13, not '$KIND'"
[[ -z "$SIM_ID" || -n "$KIND" ]] || die "--simulator-id needs --kind, to know which size it captures"

# App Store Connect takes at most ten per size. An eleventh would be rejected at
# upload, long after this ran, so refuse here.
(( ${#LISTING[@]} <= 10 )) || die "LISTING has ${#LISTING[@]} entries; App Store Connect takes at most 10"

# Renames the chosen captures into store order and removes everything else the
# tour took. The tour photographs more than the listing needs on purpose — those
# extra captures verify screens (see `ScreenshotTourUITests`) and several show
# UI-test fixtures that must never reach a listing.
curate() {
  local dir="$1" index=1 name
  for name in "${LISTING[@]}"; do
    [[ -f "$dir/$name.png" ]] || die "the tour produced no $name.png — listing order is stale"
    mv "$dir/$name.png" "$dir/$(printf '%02d' "$index")-$name.png"
    index=$((index + 1))
  done
  # Anything left is a tour capture the listing doesn't use.
  find "$dir" -name '*.png' -not -name '[0-9][0-9]-*' -delete
}

# capture KIND [UDID]: one size, on the simulator with that UDID or, without
# one, on the named simulator for KIND.
capture() {
  local kind="$1" udid="${2:-}" device dir
  device="$(device_for "$kind")"
  dir="$OUT/$kind"
  local target=(--simulator-name "$device")
  [[ -n "$udid" ]] && target=(--simulator-id "$udid")
  note "capturing $kind on ${udid:-$device} → $dir"
  rm -rf "$dir"
  mkdir -p "$dir"
  # The tour reads its output directory from `TOWER_SCREENSHOT_DIR`
  # (`TowerUITests/ScreenshotTourUITests.swift`). It runs in the test runner
  # process, not this shell, so the value has to arrive as test-runner
  # environment. `--extra-args` is flag-only, so this uses XcodeBuildMCP's
  # `--json` form with a `testRunnerEnv` object.
  npx -y xcodebuildmcp@2.7.0 simulator test \
    --project-path "$REPO_ROOT/Tower.xcodeproj" \
    --scheme Tower \
    "${target[@]}" \
    --json "$(printf '{"extraArgs":["-only-testing:%s"],"testRunnerEnv":{"TOWER_SCREENSHOT_DIR":"%s"}}' "$TOUR" "$dir")" \
    --output json \
    >| "$dir.capture.json" \
    || die "$kind capture failed — read $dir.capture.json"
  local count; count="$(find "$dir" -name '*.png' | wc -l | tr -d ' ')"
  [[ "$count" -gt 0 ]] || die "$kind capture produced no PNGs"
  curate "$dir"
  count="$(find "$dir" -name '*.png' | wc -l | tr -d ' ')"
  [[ "$count" -eq "${#LISTING[@]}" ]] || die "$kind: curated $count, expected ${#LISTING[@]}"
  note "$kind: $count screenshot(s)"
}

# **One run per checkout and per simulator.** A second run in one checkout shares
# its DerivedData, and a second run on one simulator installs over the first.
# Either way a run can execute a bundle the other is rebuilding. So without
# --simulator-id, refuse while any xcodebuild is live. `pgrep -x` matches the
# process name exactly, so it cannot match its own invocation. A caller that
# passes --simulator-id has picked a free simulator and owns that check.
if [[ -z "$SIM_ID" ]] \
  && { pgrep -x xcodebuild >/dev/null 2>&1 || pgrep -x swiftpm-testing-helper >/dev/null 2>&1; }; then
  die "another xcodebuild or swiftpm-testing-helper run is active; wait for it (pgrep -xl xcodebuild)"
fi

# Resolve the output directory against the caller's directory before changing
# to the repo root. The test runner needs an absolute path anyway.
OUT="${OUT:-$REPO_ROOT/docs/app-store-assets}"
mkdir -p "$OUT" || die "cannot create $OUT"
OUT="$(cd "$OUT" && pwd)"
readonly OUT

# XcodeBuildMCP reads `.xcodebuildmcp/config.yaml` from the working directory.
# Run from another checkout, it would build and photograph that checkout's code,
# so work from this repo's root and pass the project explicitly as well.
cd "$REPO_ROOT" || die "cannot cd to $REPO_ROOT"

if [[ -n "$KIND" ]]; then
  capture "$KIND" "$SIM_ID"
else
  capture iphone-69
  capture ipad-13
fi

note "done: $OUT"
find "$OUT" -name '*.png' | sort
