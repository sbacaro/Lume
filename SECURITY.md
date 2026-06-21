# Security Policy

## Supported versions

Lume is an actively developed macOS app. Security fixes are applied to the **latest
released version** only. Please make sure you are running the most recent release (the app
auto-updates via Sparkle) before reporting an issue.

## Reporting a vulnerability

Please **do not** open a public GitHub issue for security vulnerabilities.

Instead, report privately through GitHub's coordinated disclosure flow:

1. Go to the repository's **Security** tab.
2. Choose **Report a vulnerability** to open a private advisory.

If private advisories are unavailable, contact the maintainer directly and avoid posting
details publicly until a fix is released.

When reporting, please include:

- A description of the vulnerability and its impact.
- Steps to reproduce, or a proof of concept.
- The Lume version (see **Lume → About Lume**) and your macOS version.

## Scope and handling

- We aim to acknowledge new reports within a few days and to keep you updated on progress.
- Please give us a reasonable window to investigate and ship a fix before any public
  disclosure.
- Lume stores API keys and tokens in the macOS **Keychain**, not in its database or in
  plain files. Reports involving secret handling, the sandbox, code execution in the
  agent's shell, or the update/signature verification path are especially welcome.

Thank you for helping keep Lume and its users safe.
