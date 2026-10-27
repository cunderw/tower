# Contributing to Tower

Thanks for looking. This file is the workflow: what to open before you write code, how to
branch and open a pull request, which tests to run, and what evidence a pull request is
expected to carry. [`README.md`](README.md#building-it) has the build setup.
[`CLAUDE.md`](CLAUDE.md) is the long list of conventions and traps this project has
already paid for, written for coding agents and worth skimming before your first change.
Everyone who takes part follows the [Code of Conduct](CODE_OF_CONDUCT.md).

## Before you write code

**Open an issue first**, unless the change is a typo or a one-line obvious fix. A pull
request that argues with a settled decision is a hard conversation to have after the code
exists.

Two things are settled:

- **Tower has no backend, no account and no telemetry.** It talks directly to the user's
  own server and the services the user adds.
- **Tower manages servers and services the user already runs.** It does not provide, host,
  stream or download media.

## Filing an issue

Use a template (bug, feature, chore or design) and fill in every section. The bar is that
**someone with no context can implement and verify it**: what the deliverable is, why it
matters, and acceptance criteria concrete enough to test against. "Works correctly" is not
a criterion. "The dashboard shows the new disk within one refresh" is.

Every issue carries **exactly one `area:` label and exactly one `type:` label**.

| `area:` | |
| --- | --- |
| `area:ios` | The app, its screens, its tests |
| `area:api` | The Unraid GraphQL API and the service clients in `TowerKit` |
| `area:infra` | Build, release, tooling, the local gates |
| `area:design` | Product and interaction decisions |

| `type:` | |
| --- | --- |
| `type:feature` | New capability |
| `type:bug` | Something is wrong |
| `type:chore` | Maintenance, tooling, tests, docs |
| `type:design` | A decision to be made, not code to be written |

The issue templates apply the `type:` label and ask you for the area. A maintainer applies
the `area:` label from your answer.

## Working on an issue

- **Comment on the issue before you start, to say you are taking it.** A maintainer
  assigns it to you. An issue with no assignee is free to take.
- **Outside contributors work from a fork** and open the pull request from it.
- **One issue per branch.** Name it with the issue number and a short slug.
- **Everything merges to `main` through a squash pull request whose body contains
  `Closes #<n>`.**
- **Do not touch files outside the issue's scope.** Three shared files collide between
  branches more than any others: `Tower.xcodeproj/project.pbxproj`,
  `graphql/schema.graphqls` and `apollo-codegen-config.json`. If one has to change, say so
  on the issue.
- **Reproduce before you fix.** Write the failing test first and watch it fail as an
  assertion, not as a compile error. A test that has never been red proves nothing about
  the bug it claims to cover.
- **Do not commit a change to `DEVELOPMENT_TEAM`.** Sign locally with your own team.
  [`README.md`](README.md#signing) says what to change for a device build.
- **A live Unraid server is someone's real machine.** Tests run against demo data and
  fakes, never a server. If you try a change against your own server, read-only requests
  are fine. Check an action that starts, stops or restarts something against the seeded
  fakes in `Tower/Debug/UITestSupport.swift` first.
- **Never commit a credential.** A server address or API key must not reach a committed
  file, log, screenshot or test fixture.

## Tests

There are three tiers, cheapest first:

| Tier | What it is | What belongs there |
| --- | --- | --- |
| Kit | SwiftPM tests in `TowerKit` (`TowerCoreTests`, `TowerDataTests`), no simulator | Formatters, `AppError` mapping, store state transitions, Apollo fixture to domain mapping |
| Unit | `TowerTests`, hosted in the app on a simulator | App stores, demo data, anything that needs the app target |
| UI | `TowerUITests`, XCUITest on a simulator. Every test relaunches the app | Wiring, navigation and rendering: that a screen appears, that a tap routes somewhere |

A new UI test should say why it cannot be a kit or unit test.

### Which tests to run

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

- **Every edit: the `TowerKit` tests**, plus the UI classes you touched.
- **Before a pull request: `TowerTests`, whole, plus the UI classes your diff can
  reach.** Name them from the diff. Add the iPad pass, filtered the same way, when a
  screen's layout changes. [`CLAUDE.md`](CLAUDE.md#simulators) has the command that
  creates the `Tower iPad` device.
- **Say in the pull request which UI classes you ran and which you did not.** The full UI
  suite is for a release or a maintainer's request.

A pull request to this repository runs the `TowerKit` tests on a hosted runner, and
nothing else. `TowerTests` and the UI classes are yours to run, and a green claim about
them is only as good as the output you read.

### A green run is not a pass until you check what ran

`xcodebuild` exits 0 when an `-only-testing:` filter matches nothing, so one mistyped class
name turns a gate into a no-op. One good filter beside one typo runs only the good one,
which no count can catch.

Run with `--output json`, read `request.onlyTesting`, and confirm every filter in it
appears in `tests.selected`.

`.xcodebuildmcp/config.yaml`'s `projectPath` is relative, so a run started from a linked
worktree can build and test a different checkout. From a worktree, pass an absolute
`--project-path`, and check that the run's `request.projectPath` is your worktree.

### Two runs in one checkout or on one simulator give a wrong result

Two runs in one checkout share DerivedData, and two runs on one simulator install over
each other. Either way a run can execute a test bundle the other is rebuilding. The
symptom is a failure message and line number that do not match the source on disk. Run
one at a time, and check that nothing is running first:

```sh
pgrep -xl xcodebuild
pgrep -xl swiftpm-testing-helper
```

A hit is a run in progress. Wait for it to finish.

## The warnings check

The build is kept **warning-free**. A new warning is a bug.

After the `TowerKit` and `TowerTests` runs, grep each run's log for warnings. A run with
`--output json` reports its log at `artifacts.buildLogPath`. A simulator run prints that
path with a leading `~`, which a shell does not expand inside quotes, so the second line
expands it:

```sh
LOG="<artifacts.buildLogPath from the run>"
grep -n 'warning:' "${LOG/#\~/$HOME}"
```

Fix every hit in a file your diff touches. Swift emits a file's diagnostics only when it
recompiles that file, so this grep proves your diff, not the tree. The clean sweep proves
the tree. It is expensive, and it is for a release or a change to build settings:

```sh
xbm simulator build --build-for-testing --output json
swift build --build-tests --package-path TowerKit
```

Run the first line against fresh DerivedData. A plain `swift build` skips the test
targets.

## Regenerating `TowerAPI`

`TowerAPI/` is generated, and its sources are committed. After a change to
`graphql/operations/` or `graphql/schema.graphqls`, run `scripts/codegen.sh` and commit the
regenerated files with the change. The script needs the Apollo CLI, which you install once:

```sh
cd TowerKit && swift package --allow-writing-to-package-directory --allow-network-connections all apollo-cli-install && cd ..
```

Apollo's generated types never leave `TowerData`: map them into `TowerCore` types at the
repository boundary.

## Comments

A comment says why the code that exists now has its shape. A reader must understand it
without the issue tracker, the git history or the conversation that produced the code.

Write a comment for:

- an invariant the type system does not enforce
- a protocol or API constraint of the server or a service
- a security property, and what breaks it
- a platform behaviour that was measured, with the number when the number matters
- a deliberate tradeoff, and what the other choice would cost
- a regression trap: the change that looks like a cleanup and is not, and what it breaks

Do not write the history of the change, a description of code that no longer exists, or
a restatement of the next line. Keep a comment as short as its reason.

## Pull requests

Scan your commits for secrets before you push. Get gitleaks from its
[repository](https://github.com/gitleaks/gitleaks), then run this from the repository root:

```sh
gitleaks git --redact --log-opts=upstream/main..HEAD
```

Use your branch's base in place of `upstream/main`: from a fork, `upstream/main` (add the
`upstream` remote first); from a clone, `origin/main`.

`.gitleaks.toml` extends the default rules and allows one made-up key in a preview by path
and exact text. Do not widen it. A new key in that file must still fail the scan.

Fill in the pull request template. Each verification line wants a fact: the command you
ran and the counts you saw, the UI classes you ran and the ones you did not, and the log
you grepped for warnings. Write "Not applicable" where a line does not apply. Attach
screenshots for anything a user can see.

Say what changed and why. If you found something surprising on the way, put it in the pull
request body.
