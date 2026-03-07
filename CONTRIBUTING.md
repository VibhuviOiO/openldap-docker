# Contributing to OpenLDAP Docker

Thank you for your interest in contributing! This guide will help you get started.

## How to Contribute

### Reporting Bugs

- Use [GitHub Issues](https://github.com/VibhuviOiO/openldap-docker/issues) with the Bug Report template
- Include your Docker version, OS, and steps to reproduce
- Attach relevant logs (`docker logs <container>`)

### Suggesting Features

- Open a [Feature Request](https://github.com/VibhuviOiO/openldap-docker/issues/new) issue
- Describe the use case and expected behavior

### Pull Requests

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Make your changes
4. Test locally (see below)
5. Commit with clear messages (`git commit -m 'Add feature X'`)
6. Push and open a Pull Request

## Development Setup

```bash
# Clone
git clone https://github.com/VibhuviOiO/openldap-docker.git
cd openldap-docker

# Build
docker build --no-cache -t openldap:dev .

# Run tests
make test
```

## Testing

Before submitting a PR, verify:

```bash
# Basic functionality
./scripts/test-basic.sh

# Run a use-case
cd use-cases/vibhuvi-com-singlenode
docker compose up -d
# Verify LDAP is healthy
docker compose exec ldap ldapsearch -x -H ldap://localhost -b "dc=vibhuvi,dc=com" -D "cn=admin,dc=vibhuvi,dc=com" -w admin "(objectClass=*)" dn
docker compose down -v
```

## Code Standards

- **Shell scripts**: Follow [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html)
- Use `set -eo pipefail` in all scripts
- Use structured logging via `utils.sh` (`log_info`, `log_warn`, `log_error`)
- LDIF templates use `{{PLACEHOLDER}}` syntax for variable substitution
- All LDIF files in `ldif/templates/` must be idempotent

## Commit Messages

Use clear, descriptive commit messages:

```
feat: add password complexity validation
fix: correct memberOf overlay initialization order
docs: update TLS configuration guide
test: add multi-node replication test
```

## Security

If you discover a security vulnerability, **do NOT open a public issue**. See [SECURITY.md](SECURITY.md) for reporting instructions.

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
