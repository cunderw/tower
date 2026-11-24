# Tower repo conventions

Native iOS Unraid server client. Monorepo: SwiftUI app in `Tower/`, shared kit in
`TowerKit/` (SwiftPM, modules `TowerCore` and `TowerData`), Apollo-generated GraphQL code in
`TowerAPI/`. No backend of our own. Tower talks directly to a live Unraid box's GraphQL
API and to the media services (the *arr apps, download clients, Overseerr, Tautulli) the
user adds.

## Ground rules

- **Apollo's generated types never leave `TowerData`.** `TowerAPI` results are mapped into
  plain `TowerCore` structs at the repository boundary. This keeps views and stores
  testable without Apollo, makes demo mode just another `Repository` conformance, and
  confines schema churn to one layer. Never `import TowerAPI` outside `TowerData` and its
  tests.
- **The scheme is committed** at `Tower.xcodeproj/xcshareddata/xcschemes/Tower.xcscheme`.
  Edit it by hand. Do not add an empty `<TestPlans></TestPlans>` element: xcodebuild then
  says the scheme "is not currently configured for the test action".
- **The Xcode project is hand-authored, not generated.** The project file is
  `Tower.xcodeproj/project.xcproj`, Xcode's JSON5 project format. Its top-level folders are
  synced (`"kind": "folder"`), so a new file needs no project edit. A new target or
  package product dependency needs a direct `project.xcproj` edit and a build. Do not add
  a generate step or `ci_scripts/`.
  - **`xcrun xcprojformatter --update Tower.xcodeproj` is the canonical printer.** Run it
    after a hand edit. Xcode and the formatter strip comments from the file, so the
    project's reasons live in the three bullets below, not in `project.xcproj`.
  - **The `Tower` folder excludes `Info.plist` from the `Tower` target**
    (`membership-exceptions`). The build reads the file through `INFOPLIST_FILE` and
    `GENERATE_INFOPLIST_FILE`, and does not copy it as a bundle resource. Without the
    exception, the synced folder also puts it in the Copy Bundle Resources phase, which
    collides with the generated `Info.plist` at the same output path.
  - **`THIRD-PARTY-NOTICES.md` is the only file entry outside a synced folder.** It sits
    at the repository root, so it needs its own entry with `Tower/resources` membership
    to reach the app's resources. `TowerTests/ThirdPartyNoticesTests.swift` fails if the
    entry is dropped.
  - **`TowerTests` declares no package products of its own.** It loads into the
    `Tower.app` process through `BUNDLE_LOADER` and `TEST_HOST`. The app already links
    `TowerCore` and `TowerData` (and, through them, Apollo) as static code in
    `Tower.debug.dylib`, which `@testable import Tower` links. A package product on
    `TowerTests` as well builds and embeds each framework a second time under
    `Tower.app/PlugIns/TowerTests.xctest/Frameworks/`, so it loads twice at runtime.
    Apple's docs warn that this "may cause spurious casting failures and mysterious
    crashes." Do not add a `package-product-members` entry to `TowerTests` without a
    check that `Tower.app/PlugIns/TowerTests.xctest` in the built products holds no
    `.framework` bundles.
- **Secrets (Unraid API key, server URL) come from `.env.local`**, which is gitignored.
  Never commit them, and never let one reach a committed schema, log or test fixture.
- **Never write a credential into a file, not even a temporary one.** Pass it through the
  environment: `set -a; source .env.local; set +a`, then read
  `ProcessInfo.processInfo.environment`. For XCUITest, `SIMCTL_CHILD_*` or
  `TEST_RUNNER_*`-prefixed variables forward into the app. A key written into a scratch
  file stays out of git but still lands in editor and agent transcripts.
- **A live Unraid server is someone's real machine.** Read-only queries are fine.
  Anything that starts, stops or restarts a service needs the server owner's explicit
  approval first. Verify action paths against the seeded fakes in
  `Tower/Debug/UITestSupport.swift`.
- **Keep the build warning-free.** A new warning is a bug. After the `TowerKit` and
  `TowerTests` runs, grep each run's `artifacts.buildLogPath` for `warning:` and fix any
  in files the diff touched. Swift only emits diagnostics for files it recompiles, so that
  grep proves the diff, not the tree. The clean warnings sweep proves the tree. It covers
  both build systems: a clean `build-for-testing` for the app and its test targets, and
  `swift build --build-tests` for `TowerKit`. A plain `swift build` skips test targets.

## Build and test

A kit-tier workflow (`.github/workflows/tests.yml`) runs the `TowerKit` tests on pull
requests in the public repository. A push to `main` that touches the app's paths runs
`.github/workflows/testflight.yml`, which runs those `TowerKit` tests and then uploads a
TestFlight build. Every other gate below runs locally, and a green claim must come from
output you read.

Define `xbm` once in each shell you open. It holds the version pin, and it works in zsh
and in bash:

```sh
xbm() { npx -y xcodebuildmcp@2.7.0 "$@"; }
```

The `TowerKit` tests, `TowerTests`, one UI class, and the same UI class on the iPad:

```sh
xbm swift-package test --package-path TowerKit --output json
xbm simulator test --extra-args -only-testing:TowerTests --output json
xbm simulator test --extra-args -only-testing:TowerUITests/DemoModeUITests --output json
xbm simulator test --simulator-name "Tower iPad" \
  --extra-args -only-testing:TowerUITests/DemoModeUITests --output json
```

The clean warnings sweep, both halves. Run the first line against fresh DerivedData:

```sh
xbm simulator build --build-for-testing --output json
swift build --build-tests --package-path TowerKit
```

`.xcodebuildmcp/config.yaml` supplies the project, scheme and default simulator.
Pass one `-only-testing:` per UI class.

- **Tiers.** `TowerKit` has the SwiftPM tests (`TowerCoreTests`, `TowerDataTests`); they
  are the cheapest tier. `TowerAPI` has no tests. `TowerTests` is the unit bundle.
  `TowerUITests` is the UI bundle, and every test relaunches the app.
- **Cadence.**
  - Every edit: the `TowerKit` tests, plus the UI classes you touched.
  - Before a PR merges: the whole `TowerTests` bundle, plus the UI classes your diff can
    reach. Name them from the diff. Add the iPad pass, filtered the same way, when a
    screen's layout changes. Say in the PR which classes you ran and which you did not.
    Then grep the `TowerKit` and `TowerTests` build logs for warnings, as Ground rules
    says.
  - Before a release, or when a maintainer asks: the full `TowerUITests` bundle, plus
    the clean warnings sweep. This catches cross-feature regressions, which a targeted
    run cannot.
- **No durations are written here.** A written number gets believed and goes stale as the
  suite grows. Measure a recent run when you need a cost.
- **`xcodebuild` exits 0 when an `-only-testing:` filter matches nothing**, and one typo
  beside a good filter runs only the good one. Check that every filter appears in the
  selected tests before you call a run green.
- **Read an accessibility dump before you write a UI query.** Each status row publishes
  two static texts (`"Container"` and the `more.status` one, `"Container, Docker"`), so a
  label-only query finds the wrong one. A compound `identifier == … AND label BEGINSWITH …`
  predicate never resolves for `scrollTo`.
- **Check that a property is in the accessibility tree before you test it.** A toolbar
  control's width is not. A width assertion passed before and after the fix. When a
  property is only visible to the eye, verify by screenshot and say so.

### Simulators

Tower uses its own named devices, so another project's erase or wedge cannot reach its
gates. Nothing creates them. Make the ones you need:

```sh
xcrun simctl list devices available | grep -q '    Tower iPhone 17 (' ||
  xcrun simctl create "Tower iPhone 17" com.apple.CoreSimulator.SimDeviceType.iPhone-17
xcrun simctl list devices available | grep -q '    Tower iPad (' ||
  xcrun simctl create "Tower iPad" com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M4-8GB
xcrun simctl list devices available | grep -q '    Tower iPhone 17 Pro Max (' ||
  xcrun simctl create "Tower iPhone 17 Pro Max" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max
xcrun simctl list devices available | grep -q '    Tower iPhone Duo (' ||
  xcrun simctl create "Tower iPhone Duo" com.apple.CoreSimulator.SimDeviceType.iPhone-Duo
```

`simctl create` does not check the name, so without the `grep` guard a second run makes a
second device with the same name. With no runtime argument, it uses the newest installed
runtime the device type supports.

| Name | Device type | Use |
| --- | --- | --- |
| `Tower iPhone 17` | `iPhone-17` | Default, 6.3" |
| `Tower iPad` | `iPad-Pro-13-inch-M4-8GB` | iPad pass and 13" screenshots |
| `Tower iPhone 17 Pro Max` | `iPhone-17-Pro-Max` | 6.9" App Store screenshots only |
| `Tower iPhone Duo` | `iPhone-Duo` | Foldable iPhone; manual checks of the folded and unfolded layouts |

On Xcode 27.1 the iOS 27.1 runtime supports only the iPhone Duo, so the Duo gets 27.1 and the
other three devices get iOS 27.0, the newest runtime that supports them, and `simctl create`
with no runtime argument picks that correctly.

Keep a name and its device type together. An iPad name on an iPhone type lets the iPad
checks pass against a phone.

**When a UI test cannot type, erase the simulator before you suspect the test.** The
symptom is `"…" TextField never gained keyboard focus after tap`, then
`Failed to get matching snapshot: Timed out while evaluating UI query` on every test that
types. `sample $(pgrep -x Tower) 6` shows the main thread in
`-[UISearchTextField becomeFirstResponder]` waiting on a synchronous XPC reply from the
pasteboard daemon. It is simulator-wide. Confirm with
`ConnectFlowUITests/testInvalidURLShowsAnError`. Restarting the pasteboard service does not
clear it; erasing the device does.

## UI test traps

### iPad

Run the iPad pass whenever a screen's layout changes. It found the detail screens' action
rows centred in a very wide row. Each trap below passes in a single-class run and
fails in the full suite.

- **A `swipeRight()` in the split view's narrow list column commits the action** instead
  of parking the row open. Tap the revealed button only `if` it appeared, and assert on the
  row's resulting state.
- **Never set `XCUIDevice.shared.orientation` in this suite.** One rotation made every
  later test fail at launch. A 13" iPad is regular width in both orientations anyway.
- **iPadOS opens `.sidebarAdaptable` on the top tab bar**, and the sidebar choice persists
  in the simulator across launches and runs. `ServicesHubUITests` restores the tab bar in
  `tearDown`, and classes that navigate by tab call `useTabBarLayout`
  (`TowerUITests/XCTestCase+Sidebar.swift`) on launch. Keep both.
- **The sidebar toggle's identifier changes case with its state**: `ToggleSideBar` with
  the tab bar showing, `ToggleSidebar` with the sidebar up. Address it by identifier,
  with a case-sensitive match. Never use the label `Hide Sidebar`: the Services hub's
  split-view column toggle has that label too, and no identifier.
- **With the sidebar showing, two elements are labelled "Services"**: the hub tab and the
  collapsible section header. Tapping by label can collapse the section.
- **`navigationBars.buttons` by index is not "back" on iPad.** `navigationBars` spans both
  split-view columns, so `firstMatch` or `element(boundBy: 0)` returns a leading-column
  toolbar button ("Add Service" or "Add Movie"). The shell's root has no back
  button, because the hub is beside it. A screen pushed inside the detail column does have
  one, identifier `BackButton`. Match it by `identifier == 'BackButton' OR label == 'Back'`,
  and check whether the hub is already visible before you look for one.
- **`exists` is not hittable, and `app.swipeUp()` scrolls the wrong column.** A `List`
  keeps scrolled-past rows in the tree, so `tap()` lands on nothing and reports success.
  Use `scrollUntilHittable(_:in:within:)` (`TowerUITests/XCTestCase+Scrolling.swift`) and
  pass an element in the column you mean.
- **Scrolling past a row removes it from the tree.** Assert on a row before you scroll
  beyond it.

### Any device

- **Tapping a SwiftUI `Toggle` row does nothing.** Only the trailing switch responds.
  Tap the descendant switch, `app.switches[id].switches.firstMatch`, as the `flip` helpers
  in `RadarrAddEditUITests` and `SonarrLibraryUITests` do.
- **Do not drive a list row's context menu from a UI test.** `press(forDuration:)` on a
  list row takes about a minute here. Use the swipe action, a toolbar button or a
  detail-screen button. A long press on a text field for "Select All" is fine.
- **An accessibility identifier on a container overwrites every child's.** A plain
  `VStack` renamed the rows under it. Put the identifier on the control you want to
  address.
- **`ContentUnavailableView` overwrites its children's identifiers.** Query its action
  button as the button carrying the container's identifier (`app.buttons["services.empty"]`).

## Screenshots

`scripts/screenshots.sh [out-dir]` captures demo mode through `ScreenshotTourUITests` on
`Tower iPhone 17 Pro Max` (1320×2868) and `Tower iPad` (2064×2752), then frames each
capture for the store. The gate device is 6.3", not 6.9", so it cannot produce the store
set. Three folders under `docs/app-store-assets/` hold the result, and all three are
committed:

| Folder | Holds |
| --- | --- |
| `raw/<kind>/` | The tour's captures, named for what they show (`dashboard.png`). `--frame` reads them. |
| `<kind>/` | The store images, `NN-<name>.png`: a capture in a device frame under a caption. The upload reads these. |
| `background/<kind>.png` | The generated image behind each set. Without it, the framer draws a charcoal gradient with an orange glow. |

`<kind>` is `iphone-69` or `ipad-13`. The upload reads only the top level of each set
folder, so `raw/` and `background/` never reach App Store Connect.

- **`scripts/frame-screenshots.swift` owns `LISTING`**: the store order and the caption for
  each capture. Reorder or recaption by editing that table. `swift
  scripts/frame-screenshots.swift --list` prints the order, and the shell script reads it
  from there.
- The framer numbers the store images `%02d`. The upload order comes from a lexicographic
  sort of the filenames, so an unpadded `10-` would sort before `2-`.
- The tour photographs screens that must never ship, such as UI-test fixtures. Only what
  `LISTING` names reaches `raw/` and the store set.
- The App Store accepts at most ten screenshots per size, and the script refuses a
  `LISTING` longer than that. It also checks each store image's count, size, and
  `hasAlpha: no`.
- The framer fails the run when white caption text reads below 4.5:1 on the lightest
  pixel under it. Fix a failing background, never the check.
- The app UI inside a frame is the unedited capture, scaled. App Review guideline 2.3.3
  requires that. The framer draws only the background, the frame, the phone's Dynamic
  Island and the caption.
- **`--frame`** frames the committed raw captures again with no tour, no simulator and no
  `xcodebuild`. Use it after a change to `LISTING`, a caption or a background.
- **The tour overrides the status bar**: 9:41 on 2007-01-09, full bars, 100% battery with
  `--batteryState discharging` (a level alone draws a charging battery). `simctl` takes the
  date only as ISO 8601 with milliseconds and an offset, such as
  `2007-01-09T09:41:00.000-06:00`. An EXIT trap clears the override, also when the run fails.
- **The tour shuts its simulator down and boots it again first.** A device that stays booted
  can stop hiding the home indicator, and then every capture draws it. Run the tour through
  the device lock, because the shutdown stops anything else on that simulator.
- The script builds everything in a staging folder. It copies into `out-dir` only after
  every check for every kind passes.
- `--kind iphone-69` or `--kind ipad-13` does one size. `--simulator-id <udid>` (with
  `--kind`) captures on that simulator instead of the named one, for a caller that
  manages its own simulators. Without it, a tour refuses to start while another
  `xcodebuild` runs. `--help` prints the usage.
- The script changes to its own repo root and passes the project explicitly, so it
  builds its own checkout's code whatever directory you run it from.
- The tour reads `TOWER_SCREENSHOT_DIR` in the test runner process, so it has to arrive as
  test-runner environment (`testRunnerEnv`, or a `TEST_RUNNER_`-prefixed host variable).
  An unprefixed host variable is ignored and the tour writes to its default path.
- The tour stays in light appearance.
- The backgrounds come from a headless ComfyUI run. The header comment of
  `scripts/frame-screenshots.swift` records the model, sampler, steps, prompt and seeds.

## Style

- Swift 6 language mode, strict concurrency. SwiftUI and `@Observable` stores
  (`@MainActor`), not MVVM delegates.
- `TowerCore` (models, `Loadable`, the store effect layer, `AppError`, formatters) has no
  Apollo dependency. `TowerData` (keychain, Apollo client, repositories) is the only
  module that imports `TowerAPI`.
- No service locator. Repositories are protocols. `AppEnvironment` holds the live or demo
  instances and is passed down through initialisers, not the SwiftUI environment
  (`ArrServiceScreen.swift` says why).
- The accent colour is the system default. Use semantic colours only, and no hard-coded
  brand hex. The goal is to look like a system app.
- Tests accompany domain-logic changes: formatters, `AppError` mapping, store state
  transitions, Apollo-fixture to domain mapping.

## Identifiers

- **Do not commit a change to `DEVELOPMENT_TEAM`.** Sign locally with your own team.

## Releases

The release procedure lives outside this repo. These are the facts about the tree.

- **`MARKETING_VERSION` appears once** in `project.xcproj`, under the `Tower` target's
  `build-settings`, and applies to Debug and Release. `Tower/Info.plist` has no version
  key, because `GENERATE_INFOPLIST_FILE = YES` supplies it.
- **Never commit a `CURRENT_PROJECT_VERSION` bump.** The committed value is a placeholder.
  The build number is passed on the archive command line.
- **A push to `main` that touches `Tower/`, `TowerKit/`, `TowerAPI/` or `Tower.xcodeproj/`
  uploads a TestFlight build** through `.github/workflows/testflight.yml`, numbered from
  App Store Connect's newest build plus one. It is a beta, not a release: the release
  gates still run locally before App Store submission.
- **The App Store listing is `docs/app-store-copy.json`.** The screenshots are the two
  committed sets in `docs/app-store-assets/iphone-69` and `docs/app-store-assets/ipad-13`.
- **Release gates**, all green before the archive: the `TowerKit` tests, the whole
  `TowerTests` bundle, the whole `TowerUITests` bundle, and a clean warnings sweep of both
  halves.

## Project management

GitHub Issues track all work.

- **One issue per branch.** Everything merges to `main` through a squash PR whose body
  has `Closes #<n>`. Commits reference their issue.
- **Stay inside the issue's scope.** Flag a change to a shared file on the issue:
  `project.xcproj`, `graphql/schema.graphqls`, `apollo-codegen-config.json`.
- **Labels: exactly one `area:` and one `type:` per issue.** `area:` is `ios`, `api`,
  `infra` or `design`. `type:` is `feature`, `bug`, `chore` or `design`.
