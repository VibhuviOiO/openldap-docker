# LDAP Manager

Modern LDAP management interface with TypeScript + React + FastAPI.

## Quick Start

### Docker (Auto-reload on code changes)
```bash
docker-compose up
# Backend: http://localhost:8000
# Frontend: http://localhost:5173
# Edit code in backend/app/ or frontend/src/ - auto-reloads!
```

### Configuration

Edit `config.yml` to add your LDAP clusters:

```yaml
clusters:
  - name: "My LDAP Cluster"
    host: "ldap.example.com"
    port: 389
    base_dn: "dc=example,dc=com"
    bind_dn: "cn=Manager,dc=example,dc=com"
    bind_password: "password"
    readonly: false  # Set true for read-only access
    description: "Production cluster"
```

### Development (Local)

**Backend:**
```bash
cd backend
pip install -r requirements.txt
uvicorn app.main:app --reload --port 8000
```

**Frontend:**
```bash
cd frontend
npm install
npm run dev
# Access: http://localhost:5173
```

## Features

- Pre-configured clusters via config.yml
- Read-only and read-write modes
- Dashboard - Connect to LDAP
- Directory Browser - Search/manage entries
- Monitoring - Cluster metrics
- Green theme with shadcn/ui

## Tech Stack

- Backend: FastAPI + python-ldap
- Frontend: React + TypeScript + Vite
- UI: shadcn/ui + Tailwind CSS
