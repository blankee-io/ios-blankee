# Blankee for iOS

The iOS companion to [Blankee](https://github.com/blankee-io/blankee-app), a
self-hosted budgeting application. This app does nothing on its own: it points at
a Blankee server you run, signs in there, and adds what a browser cannot — home
screen widgets and push notifications.

Licensed under the [Mozilla Public License 2.0](LICENSE). The server is
AGPL-3.0; the app is MPL so that it can live in the App Store, where a strong
copyleft licence and Apple's terms do not sit comfortably together. What MPL asks
in return is simple: if you change these files and ship them, publish those
files' source.

## What is in it

| Target | What it is |
|---|---|
| `blankee` | the app — a web view over your server, plus the native plumbing around it |
| `BlankeeDayBoxWidget` | home screen widgets: a day's box, and the balance trend |
| `NotificationServiceExtension` | fetches a notification's text after the push arrives, so the relay never sees it |
| `BlankeeShared` | the bits both processes need: the keychain, the API client, Font Awesome, Nunito |

Widgets and the notification extension are separate processes: they cannot read
the web view's session, so they authenticate with a long-lived widget token the
server issues and the app stores in the keychain shared through an app group.

## Building it

Xcode 26 or newer, and an iOS 17 device or simulator.

```bash
git clone https://github.com/blankee-io/ios-blankee.git && cd ios-blankee
open blankee.xcodeproj
```

Signing is the only thing you must change: set **your** team under Signing &
Capabilities for all four targets. The team IDs in `project.pbxproj` are the
maintainer's, and a pull request that changes them will be asked to drop that
hunk — leave your team out of your commits.

To build and run on a simulator without touching signing settings at all:

```bash
xcodebuild -project blankee.xcodeproj -scheme blankee \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

## What a fork must change

Everything below is Blankee's own identity. A fork that keeps it will collide
with this app on a device, and the push relay will refuse it.

| Thing | Value | Where |
|---|---|---|
| Bundle identifiers | `io.blankee.app`, and `.BlankeeDayBoxWidget` / `.NotificationServiceExtension` beneath it | `blankee.xcodeproj/project.pbxproj` |
| App group | `group.io.blankee.blankee` | `BlankeeShared/WidgetStore.swift`, and the three `.entitlements` files |
| Push relay | `https://push.blankee.io` | `blankee/Config.swift` |
| URL scheme | `blankee` | `blankee/Info.plist` |
| Push environment | `development` | `blankee/blankee.entitlements` — a release build needs `production` |

The relay only sends pushes for Blankee's own bundle identifier, because the APNs
key it holds is tied to it. A fork wanting push needs its own Apple key and its
own relay; `relay/` in the server's repository is the whole thing, and it is
about two hundred lines.

## Third-party components

Bundled and under their own licences, not this one:

- **Font Awesome Free 7.2.0** (`BlankeeShared/FontAwesome/`) — icons CC BY 4.0,
  fonts SIL OFL 1.1, code MIT.
- **Nunito** (`BlankeeShared/Fonts/`) — SIL OFL 1.1.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). In short: a branch, a pull request, every
commit signed off with `git commit -s`, and say how you checked it — on which
device or simulator, and against which server.

App Store builds are cut by the maintainer, since they need the signing identity
and the App Store Connect record.
