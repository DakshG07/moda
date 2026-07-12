# Security Policy

## Reporting a vulnerability

Please do not open a public issue for a vulnerability involving media-key interception, Accessibility permission, code signing, or unintended control of system hardware.

Instead, use GitHub's private vulnerability reporting feature for this repository. Include the affected macOS version, Moda revision, reproduction steps, and expected impact. Avoid attaching signing keys, certificates, or personal system logs.

## Scope

Moda runs outside the App Sandbox because it installs an Accessibility-authorized event tap and interacts with local system audio/display APIs. It does not include analytics, an update service, or intentional network communication.

Only builds produced by the repository owner should be treated as official Moda builds. Verify downloaded artifacts before granting Accessibility permission.
