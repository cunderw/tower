# Tower

A native iOS and iPadOS client for your [Unraid](https://unraid.net) server, and for the
self-hosted services you run beside it. Tower talks straight to your own machine. There is
no account to create, no service in the middle, and no backend of ours. The one exception
is artwork: posters and covers load from the image hosts your services point to, such as
TMDb and TheTVDB. [Privacy](#privacy) says what those hosts see.

Tower does not provide, host, stream, or download any media. It is a remote management
interface for a server and the applications you already run on your own hardware.

The project page, which links the privacy policy, is
[cunderw.dev/projects/tower](https://cunderw.dev/projects/tower/).

## What it does

For the Unraid server, through its GraphQL API:

- Array status, capacity and parity state, CPU, memory, uptime, and each disk's
  temperature and usage
- Docker containers: start, stop, restart, pause and resume, with logs, ports and volumes
- Virtual machines: state and power actions, including force stop
- User shares, notifications and system logs

For the services on that server, each through its own local API, once you give Tower its
address and key:

- Sonarr, Radarr and Lidarr: library, calendar and history; add, edit or remove a series,
  movie or artist; start a search on your server
- NZBGet: queue, progress and speeds; pause, resume or remove a download
- Prowlarr: indexer health, and adding, testing, enabling and removing indexers
- Bazarr: subtitle status, and a subtitle search your server carries out
- Overseerr: search, request, and approve or decline requests
- Tautulli: current streams, bandwidth and transcoding

Tower sends the instruction. The applications on your own server do the work.

## Demo mode

Tap **Try the Demo** on the first screen. The whole app then runs offline against
invented sample data, every service and every action included. Demo mode needs no server,
no key and no network. The App Store screenshots are captured from demo mode.

To use Tower with a real server you need an Unraid server with its GraphQL API, an API key
for it (Unraid's Settings ▸ Management Access), and network access to the server from
your device.

## Privacy

- Tower connects directly to your own server and services, over your own network.
- Artwork is the exception. The device loads posters and covers directly from
  third-party image hosts. Sonarr, Radarr and Lidarr send the image addresses, on hosts
  such as TMDb and TheTVDB. For Overseerr, Tower builds the address on `image.tmdb.org`
  from the path Overseerr sends. Those hosts see your device's IP address and which titles
  it shows.
- Every API key, username and password is stored in the iOS keychain on the device.
- Tower has no accounts, no analytics, no ads, no telemetry and no backend.

[`.github/SECURITY.md`](.github/SECURITY.md) says how to report a vulnerability, and what
an `http://` address exposes.

## Building it

The tests and demo mode need no server. You need:

- A Mac with Xcode 27 and the iOS 27 simulator runtime
- Node.js and npm, which provide `npx`

The deployment target is iOS 26.0.

```sh
git clone https://github.com/cunderw/tower.git
cd tower
xcrun simctl list devices available | grep -q '    Tower iPhone 17 (' ||
  xcrun simctl create "Tower iPhone 17" com.apple.CoreSimulator.SimDeviceType.iPhone-17
xbm() { npx -y xcodebuildmcp@2.7.0 "$@"; }
xbm simulator build
```

`xbm` holds the version pin of [XcodeBuildMCP](https://github.com/getsentry/MobileBuildMCP),
a third-party tool that `npx` downloads from npm. Define it once in each shell you open.
It works in zsh and in bash. `.xcodebuildmcp/config.yaml` is committed and names the
project, scheme and simulator, so the commands need no arguments when you run them from
the repository root. It also sets `sentryDisabled: true`, which turns off the tool's error
reports and usage metrics.

Tower runs on its own named simulator, `Tower iPhone 17`, rather than the machine's stock
device. The `grep` guard creates it only if no available device has that name, because
`simctl create` does not check names. [`CLAUDE.md`](CLAUDE.md#simulators) lists the iPad
device, which the iPad pass needs.

| Command | What it runs |
| --- | --- |
| `xbm simulator build` | The app |
| `xbm swift-package test --package-path TowerKit` | The `TowerKit` tests. Fast, no simulator. Run these first |
| `xbm simulator test --extra-args -only-testing:TowerTests` | `TowerTests`, the unit bundle |
| `xbm simulator test --extra-args -only-testing:TowerUITests/DemoModeUITests` | One UI class. Pass one `-only-testing:` per class |

Add `--output json` to any of them and the result carries the counts, the tests that ran,
and paths to the full log and result bundle.

A pull request to this repository runs the `TowerKit` tests on a hosted runner. Every
other gate runs locally. [`CONTRIBUTING.md`](CONTRIBUTING.md#tests) says which tests to
run for a given change, how to check what ran, and what a pull request has to show.

### Signing

**A simulator build and every test need no Apple Developer team.** The app builds for the
simulator with `CODE_SIGN_IDENTITY = "-"` and `CODE_SIGNING_REQUIRED = NO`. The unit and
UI test targets set `CODE_SIGNING_ALLOWED = NO`.

A device build signs automatically with an Apple Development identity. The project file
names the maintainer's team in `DEVELOPMENT_TEAM` and the bundle identifier
`com.cunderw.tower`. To run on your own device, change `DEVELOPMENT_TEAM` and
`PRODUCT_BUNDLE_IDENTIFIER` in the app target's Debug and Release configurations in
`Tower.xcodeproj/project.pbxproj`, in your working copy only. Do not commit either change.

## How it is put together

A SwiftUI app in `Tower/` over a SwiftPM package in `TowerKit/`, and an Apollo-generated
package in `TowerAPI/`.

| Module | Holds | Rule |
| --- | --- | --- |
| `TowerCore` | Models, `Loadable`, the store effect layer, `AppError`, formatters | No Apollo dependency |
| `TowerData` | Keychain, the Apollo client, repositories, the service clients | The only module that imports `TowerAPI` |
| `TowerAPI` | Code generated from `graphql/schema.graphqls` and `graphql/operations/` | Its types never leave `TowerData` |

Views and stores see only `TowerCore` types. That keeps them testable without Apollo, and
it makes demo mode one more repository conformance.

The service clients are hand-written and cover the part of each API that Tower uses. These
are the upstream API documents they were written against:

- Unraid: the GraphQL API in [unraid/api](https://github.com/unraid/api). Tower's copy of
  the schema is [`graphql/schema.graphqls`](graphql/schema.graphqls).
- [Radarr API v3](https://raw.githubusercontent.com/Radarr/Radarr/develop/src/Radarr.Api.V3/openapi.json)
- [Sonarr API v3](https://raw.githubusercontent.com/Sonarr/Sonarr/develop/src/Sonarr.Api.V3/openapi.json)
- [Lidarr API v1](https://raw.githubusercontent.com/Lidarr/Lidarr/develop/src/Lidarr.Api.V1/openapi.json)
- [Prowlarr API v1](https://raw.githubusercontent.com/Prowlarr/Prowlarr/develop/src/Prowlarr.Api.V1/openapi.json)
- [Overseerr API v1](https://raw.githubusercontent.com/sct/overseerr/develop/overseerr-api.yml)

Bazarr, NZBGet and Tautulli publish no OpenAPI document in their repositories. Their
clients follow each project's own API documentation and the responses a running instance
sends.

Conventions and the traps this project has already paid for are in
[`CLAUDE.md`](CLAUDE.md).

## Not affiliated

Tower is an independent project. It is not affiliated with or endorsed by Lime
Technology, Inc. (Unraid), Plex Inc., or the projects whose APIs it uses: Sonarr, Radarr,
Lidarr, Prowlarr, Bazarr, NZBGet, Overseerr and Tautulli. Their names are used only to say
what Tower works with.

## Contributing

[`CONTRIBUTING.md`](CONTRIBUTING.md) has the workflow: what to open before you write code,
the labels, branch and pull request conventions, which tests to run, and the evidence a
pull request is expected to carry. By taking part you agree to the
[Code of Conduct](CODE_OF_CONDUCT.md).

The release procedure is not kept in this repository.

## License

[MIT](LICENSE). The license of apollo-ios, and the GPL notice that covers the Unraid API
schema and the code generated from it, are in
[`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md).
