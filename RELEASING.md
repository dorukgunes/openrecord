# Releasing OpenRecord

This guide covers a signed macOS release and the Sparkle feed used by **Check for Updates…**. Users install updates
from OpenRecord; GitHub Releases hosts the ZIP and `appcast.xml` assets.

## One-time setup

1. Install Xcode and a **Developer ID Application** certificate. Store notarization credentials in the Keychain:

   ```sh
   xcrun notarytool store-credentials openrecord-notary --apple-id <apple-id> --team-id <team-id>
   ```

2. Generate Sparkle's EdDSA key once using the `generate_keys` tool shipped with Sparkle. It saves the private key in
   the login Keychain and prints the public key. Keep the private key safe; do not commit it or put it in a public CI log.
3. Add the public key as `SUPublicEDKey` in `Resources/Info.plist`, then release that build. Updates cannot be verified
   by an older build that does not contain this key.
4. Use the stable feed URL already in `Resources/Info.plist`:
   `https://github.com/dorukgunes/openrecord/releases/latest/download/appcast.xml`.

## Each release

1. Set a new `CFBundleShortVersionString` and increment `CFBundleVersion` in `Resources/Info.plist`.
2. Move the relevant notes from **Unreleased** in `CHANGELOG.md` into a versioned section. Use that section as the
   GitHub release notes.
3. Build, sign, notarize, and staple the app:

   ```sh
   NOTARY_PROFILE=openrecord-notary make release
   ```

   This writes `OpenRecord-X.Y.Z.zip` and `SHA256SUMS.txt` under `dist/`. A Developer ID signature and successful
   notarization are required for distribution and self-updates.
4. `make release` generates `dist/appcast.xml` and signs the update entry using the Keychain key. It also outputs
   `SHA256SUMS.txt`. The generated enclosure URL resolves to the versioned GitHub asset.
5. Create and push the release tag, then upload **both** the versioned ZIP and the generated `appcast.xml` to the
   GitHub Release. `SHA256SUMS.txt` may be attached for manual-download verification.

Example release creation (replace the version and notes file):

```sh
git tag vX.Y.Z
git push origin main vX.Y.Z
gh release create vX.Y.Z dist/OpenRecord-X.Y.Z.zip dist/appcast.xml \
  --verify-tag --title "OpenRecord X.Y.Z" --notes-file notes.md
```

The `appcast.xml` asset must be attached to every new release: GitHub's `latest/download` URL then serves the newest
feed. Check it in a browser before announcing the release, and use **Check for Updates…** from a build that includes
Sparkle to verify the update is offered and installs successfully.

## First Sparkle-enabled release

Existing installations do not contain Sparkle and cannot update themselves. Users must install the first Sparkle-enabled
release manually from the GitHub Releases page. Subsequent releases can be installed in-app.
