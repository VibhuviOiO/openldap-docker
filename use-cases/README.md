# Use-Cases Testing

Test all use-cases locally before pushing to GitHub.

## Quick Test

```bash
# Test single use-case
cd use-cases/docker-secrets
./test.sh

# Test with specific image tag
cd use-cases/docker-secrets
./test.sh latest
```

## Test All Use-Cases

```bash
for dir in use-cases/*/; do
  echo "Testing: $(basename $dir)"
  cd "$dir"
  ./test.sh && echo "✓ PASSED" || echo "✗ FAILED"
  cd - > /dev/null
done
```

## Docker Image

The GitHub Action will build and publish to:
- `ghcr.io/vibhuvioio/openldap:latest`
- `ghcr.io/vibhuvioio/openldap:2.6.8` (OpenLDAP version)

## Publishing New Image

```bash
# Create version tag
git tag v2.6.8
git push origin v2.6.8

# GitHub Action automatically builds and publishes
```

## Running the Container

```bash
docker compose up -d
```

## Default LDAP credentials
```bash
DN: cn=admin,dc=example,dc=org
Password: admin
```
Or manually trigger via GitHub Actions UI with "Build without cache" option.
