# Contributing to Moda

Thanks for helping improve Moda. Small, focused changes are easiest to review.

## Before opening an issue

- Confirm the issue still occurs on macOS 26 or newer.
- Note the output device or display involved.
- Include whether BetterDisplay is installed and its version when reporting brightness behavior.
- Check whether Reduce Motion is enabled.

Please do not include private signing keys, certificates, system logs containing personal information, or unrelated crash reports.

## Development setup

1. Install a matching Xcode and macOS SDK.
2. Clone the repository.
3. Run `swift test --disable-sandbox`.
4. Build the app with `./Scripts/build-app.sh`.
5. Grant the resulting app Accessibility permission when testing media-key interception.

The packaging script uses ad-hoc signing when no development identity is available. You can set `MODA_CODE_SIGN_IDENTITY` to use your own certificate.

## Pull requests

- Keep changes scoped to one behavior or fix.
- Add or update tests for logic that can be exercised without hardware.
- Manually verify affected media keys and HUD behavior on supported hardware.
- Explain any private API or system-framework dependency introduced by the change.
- Do not commit `.build`, `DerivedData`, certificates, keys, or provisioning material.

By contributing, you agree that your contribution will be licensed under the MIT License.
