# Distribution — notarized release + Homebrew

This is the playbook to ship a **notarized** OpenSuperWhisper build, publish it as a GitHub
release artifact, and install it via Homebrew. The app is **not** App-Store distributed, so it
must be signed with a **Developer ID Application** certificate and notarized by Apple, otherwise
Gatekeeper blocks it.

## ⚠️ Decisions needed first (Maxim)

The repo is still on the upstream identity. Before the first real release, decide:

1. **Apple team for distribution.** The project's `DEVELOPMENT_TEAM` is `8LLDD7HWZK` (Starmel's,
   inherited from the fork). Pick one of *your* teams to own the Developer ID cert + notarization.
2. **Bundle identifier.** Currently `ru.starmel.OpenSuperWhisper`. Keep it, or move to a
   My-Monkey one (e.g. `fr.my-monkey.opensuperwhisper`). Changing it resets existing users'
   preferences/permissions, so decide early.

Once decided, set `DEVELOPMENT_TEAM` + `PRODUCT_BUNDLE_IDENTIFIER` in the Xcode project.

## One-time Apple setup

1. **Developer ID Application certificate**
   - Keychain Access → Certificate Assistant → *Request a Certificate from a Certificate
     Authority* → save the CSR to disk.
   - https://developer.apple.com/account/resources/certificates/list → **+** → *Developer ID
     Application* (on the chosen team) → upload the CSR → download the `.cer` → double-click to
     install it into the **login** keychain.
   - Verify: `security find-identity -v -p codesigning` should now list a
     `Developer ID Application: … (<TEAMID>)` identity.

2. **Notarization credentials** (App Store Connect API key — preferred for CI)
   - https://appstoreconnect.apple.com/access/integrations/api → **+** → role *Developer* →
     download the `.p8` (once only) and note the **Key ID** + **Issuer ID**.
   - Store a reusable notarytool profile:
     ```sh
     xcrun notarytool store-credentials osw-notary \
       --key /path/to/AuthKey_XXXX.p8 --key-id <KEY_ID> --issuer <ISSUER_ID>
     ```
   - (Alternative: an app-specific password from https://account.apple.com → Sign-In & Security.)

## Cutting a release

```sh
# from the repo root
DEVELOPER_ID="Developer ID Application: Maxim Costa (<TEAMID>)" \
NOTARY_PROFILE="osw-notary" \
VERSION="0.3.0" \
./Scripts/release.sh
```

`Scripts/release.sh` builds Release, signs with the Developer ID + hardened runtime, packages a
DMG, notarizes it, staples the ticket, and leaves `dist/OpenSuperWhisper-<version>.dmg` ready to
attach to the GitHub release:

```sh
gh release create <version> --repo my-monkeys/OpenSuperWhisper \
  dist/OpenSuperWhisper-<version>.dmg --title "v<version> — …" --notes-file notes.md
```

## Homebrew cask

`packaging/Casks/opensuperwhisper.rb` is the cask. After a release:

1. Update `version` and `sha256` (`shasum -a 256 dist/OpenSuperWhisper-<version>.dmg`).
2. Host it in a tap repo, e.g. `my-monkeys/homebrew-tap`, then:
   ```sh
   brew tap my-monkeys/tap
   brew install --cask opensuperwhisper
   ```

## Auto-update (Sparkle) — later

For in-app auto-update (beyond the existing "Check for Updates" tab), add **Sparkle**:
- Add the `Sparkle` SPM package; set `SUFeedURL` (an `appcast.xml` hosted on the releases) and a
  generated EdDSA public key (`SUPublicEDKey`) in Info.plist.
- Sign each release with Sparkle's `sign_update`, append the item to `appcast.xml`.
- Updates only install cleanly when the app is Developer-ID-signed + notarized (above), which is
  why this comes after the notarization setup.
