<!-- Thanks for this. The sign-off check runs automatically; the rest is below. See CONTRIBUTING.md. -->

## What this changes

<!-- One or two sentences. "Fixes #12" if it does. -->

## How it was checked

<!--
Which device or simulator and which iOS version, which server you pointed it at,
and what you did. For widgets: that you saw them reload, and what they showed
before and after. For push: that one arrived, that tapping it opened the right
page and date, and what happened with the app killed rather than backgrounded.
-->

## Checklist

- [ ] Every commit is signed off (`git commit -s`)
- [ ] New `.swift` files carry the three-line MPL header
- [ ] No signing-team or provisioning changes in the diff
- [ ] No new third-party dependency
- [ ] Figures still come from the server, not computed on the phone
- [ ] Secrets go to the keychain, not `UserDefaults`
- [ ] Builds for a simulator
