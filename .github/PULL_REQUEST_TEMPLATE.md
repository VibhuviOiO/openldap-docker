## What changed

<!-- One or two lines. What does this change do, and why? -->

## Which feature did you touch?

<!-- The integration suite is organised by feature. Tick what applies. -->

- [ ] Startup / configuration (LDIF templates, `config.sh`)
- [ ] Replication (syncrepl, syncprov, serverID, SID map)
- [ ] ACLs / access control
- [ ] TLS / certificates
- [ ] Overlays (memberof, ppolicy, auditlog)
- [ ] Health check / readiness
- [ ] Dockerfile / base image / image size
- [ ] CI or tooling only (no runtime behaviour)

## Proof

<!-- Paste the command and its output. "Tests pass" is not proof. -->

```
```

## Checklist

- [ ] `make lint` passes (`shellcheck` is clean)
- [ ] New/changed LDIF templates are valid and every `{{PLACEHOLDER}}` is supplied by a script
- [ ] If I added a `*_FILE` variable, a missing or unreadable file fails loudly (it must not
      silently fall back to a default password)
- [ ] If I added an LDIF `to attrs=` clause, every attribute exists in a schema loaded *before*
      that step runs — an unknown attribute fails the whole modify
- [ ] If I added an `olcDbIndex`, it does not duplicate the RPM-shipped definition, and it does
      not use two alias names for the same attribute (`sn`/`surname`)
- [ ] If I changed a template from `add:` to `replace:` (or back), I said why in the description
- [ ] I ran the integration suite locally: `docker build -t openldap:local . && bash tests/integration/single-node.sh openldap:local`
- [ ] I ran the replication suite if I touched replication: `bash tests/integration/replication.sh openldap:local`

## Failure mode

<!-- If this fixes a bug: what did it look like in production, and how would someone recognise it? -->
