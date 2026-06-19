# Security Policy

## Container Image Security

### Latest Scan Results

| Check | Status |
|-------|--------|
| Trivy Security Scan | [![Security Scan](https://img.shields.io/github/workflow/status/vibhuvioio/openldap-docker/Docker%20Publish?label=Trivy&logo=aquasecurity)](https://github.com/vibhuvioio/openldap-docker/actions/workflows/docker-publish.yml) |
| Image Signing | ![Signed](https://img.shields.io/badge/Signed-cosign-blue?logo=sigstore) |
| SBOM | ![SBOM](https://img.shields.io/badge/SBOM-SPDX-green) |
| Vulnerabilities | ![Vulns](https://img.shields.io/badge/dynamic/json?color=blue&label=Known%20Vulns&query=%24%5B%27vulnerabilities%27%5D&url=https%3A%2F%2Fapi.github.com%2Frepos%2Fvibhuvioio%2Fopenldap-docker%2Fcode-scanning%2Falerts%3Ftool_name%3DTrivy) |

### Container Image

```
vibhuvioio/openldap:latest
```

### Verifying Image Signature

```bash
cosign verify \
  --certificate-identity-regexp="https://github.com/vibhuvioio/openldap-docker/.github/workflows/docker-publish.yml@refs/tags/v*" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  vibhuvioio/openldap:latest
```

### Viewing Vulnerability Reports

Trivy scans the container image on every build and uploads results to GitHub Security:

1. Go to [GitHub Security tab](../../security/code-scanning)
2. Click "Code scanning alerts"
3. Filter by tool: "Trivy"

#### Current Vulnerability Status

![Trivy Scan](https://img.shields.io/github/workflow/status/vibhuvioio/openldap-docker/Docker%20Publish?label=Last%20Scan&logo=aquasecurity)

### Reporting Security Issues

Please report security vulnerabilities by:

- Opening a [GitHub Issue](../../issues)
- Emailing: **contact@vibhuvioio.com**

## Security Features

- ✅ **Trivy vulnerability scanning** on every build
- ✅ **cosign/Sigstore image signing** for supply chain security
- ✅ **SPDX SBOM generation** for complete bill of materials
- ✅ **Multi-arch builds** (linux/amd64, linux/arm64)
- ✅ **Non-root container execution**
- ✅ **Read-only root filesystem** support
- ✅ **Capability dropping** (runs with minimal privileges)
