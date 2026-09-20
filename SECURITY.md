# Security

This app holds a token that reads somebody's financial data and a session to
their server. Reports are taken seriously and answered.

## Reporting

**Do not open a public issue.** Use GitHub's private vulnerability reporting —
the **Report a vulnerability** button under
[Security](https://github.com/blankee-io/ios-blankee/security) — or email
**info@blankee.io**.

Useful to include: the app version and build, the iOS version, whether the
problem needs the device to be unlocked, and the smallest sequence of steps that
shows it.

You will get an acknowledgement within a few days. This is a one-maintainer
project; a fix may take longer than that, and you will be told where it stands
rather than left guessing. Say if you would like credit in the release notes, and
how you would like to be named.

## What is in scope

- The widget token and the relay secret: how they are stored (the keychain,
  shared through an app group), how they are issued, and anything that would let
  another app on the device read them.
- The web view: anything that lets a page outside your own server run in it, or
  reach the native bridge.
- The notification extension: it fetches a notification's text from your server
  after the push arrives, so the relay only ever learns an id — a way to make it
  fetch from somewhere else, or leak the text, matters.
- Deep links: `blankee://` handling, and anything that makes the app act on a
  link it should not trust.

Out of scope: anything that needs a jailbroken or already-compromised device,
and anything that needs the passcode.

## What the relay can and cannot see

The push relay exists so that a self-hosted server can send a notification
without holding an Apple key. It is told a device token and a notification id,
and nothing else — no text, no amounts, no account. The extension then asks
*your* server for the words. If you find a way for the relay to learn more than
that, or to push to a device that never registered with it, that is the most
valuable report you can send.

## Server-side issues

The server, the bank sync and the release mechanism live in
[blankee-app](https://github.com/blankee-io/blankee-app); report those through
its own SECURITY.md.
