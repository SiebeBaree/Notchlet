# Releasing

Releases are built, signed, notarized and published by
[`.github/workflows/release.yml`](.github/workflows/release.yml) on a macOS
runner. Nothing is built from a laptop.

## Cutting a release

```sh
# 1. Put the changes at the top of CHANGELOG.md under the new version.
# 2. Tag from main.
git tag v0.1.0
git push origin v0.1.0
```

That is the whole process. About twelve minutes later there is a notarized DMG
on the releases page and an appcast on GitHub Pages pointing at it.

**Never bump a version number by hand.** `MARKETING_VERSION` comes from the tag
and `CURRENT_PROJECT_VERSION` from the workflow's run number. Sparkle compares
`CURRENT_PROJECT_VERSION`, so a hand-edited value that fails to rise means the
update is invisible to everyone already running the app. Letting CI own both
numbers is what makes that failure impossible.

To rehearse without publishing, run the workflow manually from the Actions tab.
It builds, signs, notarizes and runs the Gatekeeper check, then stops before
creating the release or touching the feed.

## What the pipeline does

1. Imports the Developer ID certificate into a throwaway keychain.
2. Writes `Config/Secrets.xcconfig` from the `POSTHOG_API_KEY` secret, failing
   if it is empty rather than shipping a build that silently reports nothing.
3. Archives with the version numbers injected.
4. Notarizes the `.app` and staples the ticket into the bundle, so a copy
   installed by Sparkle passes Gatekeeper with no network.
5. Builds a DMG, signs it, notarizes and staples that too, so the download
   opens without a warning. Two tickets, because Apple issues one per artifact.
6. Runs `spctl --assess`, which is the same decision a stranger's Mac makes.
7. Creates the GitHub release and uploads the DMG.
8. Signs the update with the Sparkle EdDSA key, generates `appcast.xml` and
   deploys it to Pages. The release is published first because the feed points
   at its download URL.

## Secrets

Set once, in repository settings.

| Secret | What it is |
| --- | --- |
| `CERT_P12_BASE64` | Developer ID Application certificate and private key, exported as `.p12` and base64 encoded |
| `CERT_P12_PASSWORD` | Password on that `.p12` |
| `APPLE_API_KEY_P8` | App Store Connect API key, for notarization |
| `APPLE_API_KEY_ID` | That key's ID |
| `APPLE_API_ISSUER_ID` | Team issuer UUID from the same page |
| `SPARKLE_PRIVATE_KEY` | EdDSA key, exported with `generate_keys -x` |
| `POSTHOG_API_KEY` | PostHog project key |

The Sparkle key is the dangerous one. Anyone holding it can sign a build that
every installed copy of Notchlet will accept and install without asking.

The Developer ID certificate expires 2027-02-01. Re-export and update
`CERT_P12_BASE64` before then. Builds already notarized keep working, because
the secure timestamp outlives the certificate, but nothing new will sign.

## The update feed

`SUFeedURL` in `Notchlet/Info.plist` points at
`https://siebebaree.github.io/Notchlet/appcast.xml`. That URL is compiled into
every binary ever shipped, so it can never change: anyone still running an old
version would be stranded with no way to reach them.

GitHub Pages hosts it rather than notchlet.com, on the grounds that the domain
is the likelier of the two to change. The consequence is that
`siebebaree.github.io/Notchlet/` has to keep answering forever, including after
a rename or a move to an organization. If the repo ever moves, keep a
repository named `Notchlet` on the `SiebeBaree` account whose Pages site
redirects to the new feed. Editing the plist does nothing for anyone already
running the app.

The download URLs inside the feed are less fragile. GitHub redirects release
assets permanently after a rename or transfer, so those survive a move on their
own.

`generate_appcast` rewrites every entry with one download URL prefix, and GitHub
download URLs carry the tag, so CI keeps exactly one release in the folder and
publishes a single-item feed. That is all Sparkle needs. Someone on an old
version is still offered the newest build, because Sparkle compares against what
the app is running rather than against the feed's history.

## After a release

Update the Homebrew cask in `SiebeBaree/homebrew-tap`:

```sh
shasum -a 256 Notchlet-0.1.0.dmg
```

```ruby
cask "notchlet" do
  version "0.1.0"
  sha256 "..."

  url "https://github.com/SiebeBaree/Notchlet/releases/download/v#{version}/Notchlet-#{version}.dmg"
  name "Notchlet"
  desc "Agent CLI usage limits in the macOS notch"
  homepage "https://github.com/SiebeBaree/Notchlet"

  livecheck do
    url :url
    strategy :github_latest
  end

  # Sparkle owns upgrades, so brew should not fight the app over which copy is newer.
  auto_updates true
  depends_on macos: ">= :sonoma"

  app "Notchlet.app"

  zap trash: ["~/Library/Preferences/be.baree.Notchlet.plist"]
end
```

## When it fails

**`codesign` cannot find the identity.** The `.p12` was exported without its
private key. In Keychain Access this happens when you export from the
Certificates category instead of My Certificates. Expand the entry, confirm a
key sits underneath it, export again.

**notarytool returns 403.** The App Store Connect key's role is too narrow.
Regenerate it as App Manager.

**notarytool returns Invalid.** Ask Apple what it objected to:

```sh
xcrun notarytool log <submission-id> --key AuthKey.p8 \
  --key-id <id> --issuer <uuid>
```

**Sparkle finds no update after a release.** Check that `CFBundleVersion` in the
published build is higher than the one users are running. If the workflow file
was renamed, `github.run_number` reset and the build number went backwards.
Switch it to `git rev-list --count HEAD`.

## The app icon

`Scripts/AppIcon.svg` is the source. It is the website's icon with a widened
viewBox that insets the artwork to the macOS icon grid. Re-render the asset
catalog after editing it:

```sh
./Scripts/make-appicon.sh
```
