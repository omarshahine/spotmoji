# Releasing Spotmoji

Spotmoji ships as a signed and notarized app through GitHub Releases and the public `omarshahine/homebrew-tap` repository.

## One-time setup

Create a **Developer ID Application** certificate in the Apple Developer portal and export it as a password-protected `.p12` file.

Configure these GitHub Actions secrets on the Spotmoji repository:

| Name | Purpose |
|---|---|
| `DEVELOPER_ID_CERTIFICATE_BASE64` | Base64-encoded `.p12` containing the Developer ID Application certificate and private key |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | Password used when exporting the `.p12` |
| `APP_STORE_CONNECT_API_KEY_ID` | App Store Connect team API key ID |
| `APP_STORE_CONNECT_API_ISSUER_ID` | App Store Connect team API issuer ID |
| `APP_STORE_CONNECT_API_PRIVATE_KEY` | Contents of the matching `AuthKey_*.p8` private key |
| `HOMEBREW_TAP_TOKEN` | GitHub token with Contents read/write access to `omarshahine/homebrew-tap` |

Configure this GitHub Actions repository variable:

| Name | Purpose |
|---|---|
| `APPLE_TEAM_ID` | Apple Developer Team ID used to validate the imported signing identity |

Never commit certificates, passwords, tokens, provisioning profiles, or `.env` files.

## Publish a release

1. Confirm the working tree is clean and CI passes.
2. Create and push a semantic version tag such as `v1.0.0`.
3. Watch the **Release** GitHub Actions workflow.
4. Verify the Spotmoji GitHub release and public tap release were created.
5. Run the clean-machine installation check:

```sh
brew update
brew install --cask omarshahine/tap/spotmoji
codesign --verify --deep --strict --verbose=2 /Applications/Spotmoji.app
spctl --assess --type execute --verbose=2 /Applications/Spotmoji.app
```

The workflow tests the package, imports the signing identity into a temporary keychain, builds with the hardened runtime, notarizes with the App Store Connect API key, staples the ticket, creates the release archive, validates the cask, and updates the public tap.

## Mac App Store

Mac App Store distribution is intentionally deferred. It will require an App Store signing profile, App Store Connect metadata, sandbox review, and a separate release workflow. The Homebrew build remains the current distribution target.
