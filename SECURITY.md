# Security Policy

## Container Image Security

### Latest Scan Results

| Check | Status |
|-------|--------|
| Trivy Security Scan | [![Security Scan](https://img.shields.io/github/workflow/status/vibhuvioio/openldap-docker/Docker%20Publish?label=Trivy&logo=aquasecurity)](https://github.com/vibhuvioio/openldap-docker/actions/workflows/docker-publish.yml) |
| Image Signing | ![Signed](https://img.shields.io/badge/Signed-cosign-blue?logo=sigstore) |
| SBOM | ![SBOM](https://img.shields.io/badge/SBOM-SPDX-green) |

### Container Image

```
ghcr.io/vibhuvioio/openldap:latest
```

### Verifying Image Signature

```bash
cosign verify \
  --certificate-identity-regexp="https://github.com/vibhuvioio/openldap-docker/.github/workflows/docker-publish.yml@refs/tags/v*" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  ghcr.io/vibhuvioio/openldap:latest
```

### Viewing Vulnerability Reports

1. Go to [GitHub Security tab](../../security)
2. Click "Code scanning alerts"
3. Filter by tool: "Trivy"

### Reporting Security Issues

Please report security vulnerabilities by opening a [GitHub Issue](../../issues).

## Security Features

- ✅ **Trivy vulnerability scanning** on every build
- ✅ **cosign/Sigstore image signing** for supply chain security
- ✅ **SPDX SBOM generation** for complete bill of materials
- ✅ **Multi-arch builds** (linux/amd64, linux/arm64)
- ✅ **Non-root container execution**
- ✅ **Read-only root filesystem** support
- ✅ **Capability dropping** (runs with minimal privileges)
