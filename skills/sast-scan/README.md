# sast-scan

Local SAST (Static Application Security Testing) using SonarQube Community Edition. Manages SonarQube via Docker/Podman, runs scans, and iteratively fixes issues until your codebase hits its quality targets.

## Prerequisites

A container runtime — any of these:

| macOS | RHEL / Linux |
|-------|--------------|
| Docker Desktop | Podman (default on RHEL 8+) |
| Rancher Desktop | Docker CE |
| Colima | |
| Podman Desktop | |

The setup command auto-detects which runtime you have. No manual configuration needed.

## Usage

### First-time setup

```
/sast-scan setup
```

This will:
1. Detect your container runtime (Docker or Podman)
2. Pull the SonarQube Community Edition image
3. Start SonarQube on `localhost:9000`
4. Change the default admin password (shown once — save it if you need web UI access)
5. Generate an API token
6. Save URL, token, and runtime to `~/.claude/sast-config.json` (chmod 600)

SonarQube takes 1-3 minutes to start. Data is persisted in Docker volumes so it survives restarts.

### Run a scan

```
/sast-scan run
/sast-scan run src/
```

This will:
1. Verify SonarQube is running
2. Resolve sonar source/test/exclusion paths (asks you if ambiguous)
3. Detect your test framework and run tests with coverage
4. Run sonar-scanner with coverage report and source paths
5. Fetch results: bugs, vulnerabilities, code smells, coverage
6. Auto-fix simple issues (null checks, resource leaks, unused imports, etc.)
7. Present options for complex/architectural issues
8. Write tests for uncovered code paths
9. Re-scan and compare — repeat until quality gate passes and all targets met
10. Maximum 5 cycles to prevent runaway loops

### Set quality targets

```
/sast-scan target                              # show all current targets
/sast-scan target coverage 85                  # set one
/sast-scan target cognitive-complexity 25       # set another
```

Available targets:

| Key | Default | Description |
|-----|---------|-------------|
| `coverage` | 90 | Line coverage % |
| `cognitive-complexity` | 15 | Max cognitive complexity per function |
| `duplicated-lines` | 3 | Max duplicated lines % |
| `maintainability-rating` | 1 | Max rating (1=A, 2=B, 3=C, 4=D, 5=E) |
| `reliability-rating` | 1 | Max rating (1=A .. 5=E) |
| `security-rating` | 1 | Max rating (1=A .. 5=E) |

### Check status

```
/sast-scan
```

Shows SonarQube status, current config, and usage hints.

## Config Files

| File | Scope | Contains |
|------|-------|----------|
| `~/.claude/sast-config.json` | User-wide | SonarQube URL, API token, container runtime |
| `.claude/sast-config.json` | Per-repo | Project key, quality targets, sonar source/test/exclusion paths |

The user config is created by `/sast-scan setup`. The repo config is created on first scan or by `/sast-scan target`.

### Sonar scan properties

On first run, the skill inspects your project layout and sets `sonar.sources`, `sonar.tests`, and `sonar.exclusions`. Without these, SonarQube counts all files (including tests) as source code — making coverage appear much lower than reality.

These are saved in `.claude/sast-config.json` and reused on subsequent runs. If the layout is ambiguous, you'll be asked.

## Platform Support

| Feature | macOS | RHEL |
|---------|-------|------|
| Runtime detection | Docker Desktop, Rancher, Colima, Podman | Podman (default), Docker CE |
| SELinux handling | N/A | Automatic (`--security-opt label=disable`) |
| vm.max_map_count | Handled by Docker Desktop VM | Checked and warned if too low |
| Scanner networking | `host.docker.internal` | `--network host` |

## How It Decides What to Fix

**Auto-fixes (no user input):**
- Null/undefined checks, resource leaks, unused imports
- Simple code smells (magic numbers, empty catch blocks)
- Obvious security issues (hardcoded test credentials)

**Asks for user input:**
- Architectural changes (class extraction, pattern changes)
- Security design decisions
- Changes affecting public APIs

**Test gaps:**
- Writes tests matching your project's existing style and framework
- Auto-detects test framework from project files

## Stopping SonarQube

SonarQube runs as a background container. To stop it:

```bash
docker stop sonarqube-claude    # or: podman stop sonarqube-claude
```

Data is preserved in named volumes. Starting it again is instant (no re-setup needed).
