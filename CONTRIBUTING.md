# Contributing to Blankee for iOS

This is the companion app to a self-hosted budgeting server, maintained by one
person, and it holds a token that reads somebody's real financial data. So the
bar is less "is this clever" than "will this still be right on a stranger's phone
in a year".

Changes are welcome, including small ones. There is no automated test suite worth
the name, so review is by reading — a pull request that says what it changed and
how it was checked gets merged, one that does not sits waiting.

## Before writing code

- **A bug** — open an issue. The app version and build, your iOS version, and
  what you were doing are usually enough.
- **A feature** — say so in an issue first. The app is deliberately thin: the
  server owns the budgeting, the app owns what a browser cannot do (widgets,
  push, deep links). Something that reimplements server logic on the phone will
  be declined, however well written.
- **A security problem** — not an issue. See [SECURITY.md](SECURITY.md).

## Getting it building

Xcode 26 or newer. [README.md](README.md) has the details; the one thing you must
change is your signing team, and the one thing you must not commit is that change.

You also need a Blankee server to point at. The quickest is Docker, from the
[server repository](https://github.com/blankee-io/blankee-app) — its
`docker compose up -d --build` gives you an instance on your machine in a couple
of minutes, and the simulator can reach it on your Mac's LAN address.

## How a change lands

1. Branch off `main`, one topic per branch.
2. Open a pull request. The sign-off check runs on it.
3. It is reviewed by reading, and **squash-merged** — one commit, authored by you.
4. App Store builds are cut by the maintainer, since they need the signing
   identity and the App Store Connect record. Your change ships in the next one.

## Sign your work

Every commit needs a `Signed-off-by` line, which `git commit -s` adds. It is the
[Developer Certificate of Origin](https://developercertificate.org): a statement
that you wrote the change, or have the right to submit it, and that you are
content for it to be distributed under this project's licence. Nothing to sign,
nothing to post.

Forgot on the last commit:

```bash
git commit -s --amend --no-edit && git push --force-with-lease
```

## Conventions

**Licence header.** Every `.swift` file starts with the three-line MPL header.
New files get it too — copy it from any existing file.

**The server owns the numbers.** Every figure the app or a widget shows is
computed on the server and arrives ready to display. Do not add arithmetic on the
phone: the same money must not be worked out twice in two places, because the two
will disagree eventually and the phone will be the one that is wrong.

**Widgets and the extension are separate processes.** They cannot see the web
view's session. They authenticate with the widget token in the keychain, shared
through the app group, and they must handle it being absent or rejected —
"Signed out" in a widget is usually that, not a bug in the widget.

**The relay learns nothing.** A push carries an id and a kind. The notification
extension then fetches the text from the user's own server. Do not put text,
amounts or account names in the push payload, however convenient.

**Store secrets in the keychain**, never in `UserDefaults` — not the widget
token, not the relay secret, not the server URL's credentials. The app group's
`UserDefaults` is fine for things that are not secret, like which widget account
is selected.

**No third-party dependencies**, please. There are none today: no SPM packages,
no CocoaPods, no Carthage. Every dependency is something a future maintainer has
to keep working on a phone, and the app is small enough not to need any.

## Saying how you tested it

Which device or simulator and iOS version, which server you pointed it at, and
what you did. For widgets: that you saw them reload, and what they showed before
and after. For push: that a notification arrived, that tapping it opened the
right page and date, and what happened when the app was killed rather than
backgrounded.

## Licence

This app is [MPL-2.0](LICENSE). By contributing you agree your contribution is
licensed under it, and your sign-off records that you have the right to make it.
The bundled Font Awesome Free and Nunito files keep their own licences; do not
add your header to them.
