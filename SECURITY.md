# Security Policy

## Supported Versions

| Version | Supported          |
|---------|--------------------|
| latest  | :white_check_mark: |
| < latest | :x:               |

Only the latest release is actively supported with security updates.

## Reporting a Vulnerability

**Please do NOT report security vulnerabilities through public GitHub issues.**

Instead, report vulnerabilities by emailing **security@vibhuvioio.com**.

Please include:

- Description of the vulnerability
- Steps to reproduce
- Impact assessment
- Suggested fix (if any)

You should receive an acknowledgment within **48 hours**. We aim to provide a fix or mitigation within **7 days** for critical issues.

## Security Practices

This project follows these security practices:

- **Non-root execution** — Container runs as `ldap` user (UID 55)
- **Minimal base image** — AlmaLinux 9 with only required packages (`--nodocs`)
- **No secrets in image** — All credentials passed via environment variables or Docker secrets
- **Container scanning** — Trivy vulnerability scanning on every build
- **Image signing** — Published images are signed with cosign/Sigstore
- **SBOM attestation** — Software Bill of Materials attached to every image
- **Secure ACLs** — Password attributes protected, authenticated access required
- **TLS support** — StartTLS and LDAPS for encrypted connections
- **Read-only root filesystem compatible** — Writable paths are limited and documented
- **`STOPSIGNAL SIGTERM`** — Graceful shutdown support
- **Dropped capabilities** — Only `NET_BIND_SERVICE` retained

## Verifying Image Signatures

```bash
cosign verify ghcr.io/vibhuvioio/openldap:latest \
  --certificate-identity-regexp="https://github.com/VibhuviOiO/openldap-docker" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com"
```

## Verifying SBOM

```bash
cosign verify-attestation ghcr.io/vibhuvioio/openldap:latest \
  --type spdx \
  --certificate-identity-regexp="https://github.com/VibhuviOiO/openldap-docker" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com"
```
