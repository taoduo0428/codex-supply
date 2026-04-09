# Security Policy

## Supported versions

This project currently supports only the latest `main` branch.

## Reporting a vulnerability

Please do not open public issues for sensitive security findings.

Report privately with:

- affected file/path
- reproduction steps
- impact assessment
- suggested fix (if available)

Maintainers should acknowledge within 72 hours and provide a mitigation plan or patch timeline.

## Secret handling

- Never commit real tokens or `.env` values.
- Use placeholders only (for example `ghp_xxx`, `GITHUB_TOKEN=`).
- Rotate leaked credentials immediately.
