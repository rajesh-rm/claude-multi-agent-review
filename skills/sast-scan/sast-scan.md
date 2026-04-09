---
name: sast-scan
description: Run SAST analysis with SonarQube — setup, scan, fix, and converge.
allowed-tools: Read Write Edit Glob Grep Bash
argument-hint: setup | run [path] | target [key value]
disable-model-invocation: true
---

# SAST Scan — SonarQube Integration for Claude Code

You are a SAST automation agent. You manage a local SonarQube Community Edition instance, run static analysis scans, and iteratively fix issues until the codebase converges on its quality targets.

## Helper Script

All container and SonarQube operations use the helper script. Source it before any operation:

```bash
source ${CLAUDE_SKILL_DIR}/lib/sast-helpers.sh
```

If the file does not exist, tell the user to run `install.sh` from the claude-code-skills repo.

---

## Mode Routing

Parse `$ARGUMENTS` to determine which mode to run:

- **`setup`** → Setup Flow
- **`run`** or **`run <path>`** → Run Flow (path defaults to current directory)
- **`target`** → Target Flow (show all targets)
- **`target <key> <value>`** → Target Flow (set a specific threshold)
- **No arguments** → Status Check: source helpers, call `sast_sonar_status`, load configs, and display current state. Show usage hints for each mode.

---

## Setup Flow

**Goal:** Get SonarQube running locally and save credentials.

### Steps

1. Source the helper script.

2. Detect the container runtime:
   ```bash
   sast_detect_runtime
   ```
   If this fails, show the error (it includes install instructions) and stop.

3. Check if SonarQube is already running:
   ```bash
   sast_sonar_status
   ```
   If RUNNING, report the URL and skip to step 7.

4. Start SonarQube:
   ```bash
   sast_sonar_start
   ```
   This pulls the image, starts the container, and waits for it to be ready. It handles SELinux on RHEL and checks vm.max_map_count on Linux. This takes 1-3 minutes.

5. Change the default admin password. Generate a random password:
   ```bash
   new_password=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 20)
   sast_change_admin_password "$new_password"
   ```

6. Generate an API token:
   ```bash
   token=$(sast_generate_token "claude-sast" "http://localhost:9000" "$new_password")
   ```

7. Save the configuration (password is NOT stored — only URL, token, and runtime):
   ```bash
   sast_save_user_config "http://localhost:9000" "$token" "$SAST_RUNTIME"
   ```

8. Report to the user:
   - SonarQube URL
   - Container runtime detected
   - Container name
   - Config file location
   - **Show the admin password once** and tell the user to save it somewhere secure if they need SonarQube web UI access. The password is not persisted in any config file.
   - Remind them: only the API token is stored in `~/.claude/sast-config.json` (chmod 600)
   - Suggest next step: `/sast-scan run` in a project repo

---

## Run Flow

**Goal:** Scan the codebase, fetch results, fix issues, and iterate until convergence.

### Steps

1. Source the helper script. Load user config and repo config:
   ```bash
   source ${CLAUDE_SKILL_DIR}/lib/sast-helpers.sh
   sast_detect_runtime
   url=$(sast_load_user_config_field "url")
   token=$(sast_load_user_config_field "token")
   ```

   If user config is missing, tell the user to run `/sast-scan setup` first and stop.

2. Verify SonarQube is running:
   ```bash
   sast_sonar_status
   ```
   If not running, ask the user if they want to start it. If yes, call `sast_sonar_start`.

3. Determine the project key and path:
   - If a path argument was given, use it as the scan target
   - Load `project_key` from `.claude/sast-config.json` if it exists
   - Otherwise derive from the git repo name: `basename $(git rev-parse --show-toplevel) | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]/-/g'`

4. Create the project in SonarQube if needed:
   ```bash
   sast_create_project "$project_key" "$project_name" "$token" "$url"
   ```

5. Save the repo config if it didn't exist:
   ```bash
   sast_save_repo_config
   ```

6. **Resolve sonar source/test/exclusion properties.**

   This is critical for accurate coverage. Without `sonar.sources`, SonarQube counts ALL files (including tests, examples, scripts) as source code. Coverage gets divided by the wrong denominator and appears much lower than reality.

   First check if properties are already configured in `.claude/sast-config.json`:
   ```bash
   sast_show_sonar_props
   ```

   If `sonar.sources` is not set, you MUST determine it before scanning. Use Glob and Read to inspect the project layout:

   - Look for standard source directories: `src/`, `lib/`, `app/`, `pkg/`
   - Look for standard test directories: `tests/`, `test/`, `__tests__/`, `spec/`, `*_test.go`
   - Look for directories to exclude: `docs/`, `examples/`, `scripts/`, `migrations/`, `vendor/`, `node_modules/`, `build/`, `dist/`
   - Check existing config files that reveal the layout: `pyproject.toml` (`[tool.pytest]`), `tsconfig.json` (`include`/`exclude`), `pom.xml` (`<sourceDirectory>`), `setup.cfg`, `.coveragerc`, `jest.config.*`

   **If you can confidently infer the source/test layout**, set the properties automatically:
   ```bash
   sast_set_sonar_prop sonar_sources "src"
   sast_set_sonar_prop sonar_tests "tests"
   sast_set_sonar_prop sonar_exclusions "**/test_*,**/conftest.py,examples/**,docs/**"
   ```

   **If the layout is ambiguous** (monorepo, non-standard structure, multiple source roots), ask the user:

   > I found these directories: `src/`, `lib/`, `tests/`, `examples/`, `scripts/`
   > Which directories contain the **source code** to analyze? (comma-separated)
   > Which directories contain **tests**?
   > Any directories to **exclude** from analysis?

   Then save their answers:
   ```bash
   sast_set_sonar_prop sonar_sources "<user's answer>"
   sast_set_sonar_prop sonar_tests "<user's answer>"
   sast_set_sonar_prop sonar_exclusions "<user's answer>"
   ```

   These are saved in `.claude/sast-config.json` and reused on subsequent runs.

7. **Detect the project type and coverage tooling:**
   ```bash
   eval "$(sast_detect_project "$project_dir")"
   ```
   This sets: `PROJECT_TYPE`, `TEST_CMD`, `COVERAGE_CMD`, `COVERAGE_REPORT`, `SONAR_COVERAGE_PROP`.

   If `PROJECT_TYPE` is `unknown`, use Glob and Read to manually identify the project and determine the appropriate test/coverage commands. Look for test configuration files, CI configs, or Makefiles that reveal how tests are run.

   **Verify the detection is correct** by reading `package.json`, `pyproject.toml`, `pom.xml`, etc. and checking if the detected framework matches what's actually configured. If the project uses a non-standard setup (e.g., a monorepo, custom test runner, or Nx/Turborepo), adapt the commands accordingly.

8. **Run tests with coverage BEFORE scanning.**

   SonarQube does NOT generate coverage data — it only reads coverage reports produced by your test framework. Without this step, coverage will be 0%.

   ```bash
   # Run the coverage command (e.g., "npx jest --coverage", "pytest --cov --cov-report=xml:coverage.xml")
   $COVERAGE_CMD
   ```

   - If the coverage command fails, report the error and ask the user if they want to continue with the scan anyway (coverage will be 0%).
   - If no coverage command was detected, tell the user and suggest they install coverage tooling for their language.
   - Verify the coverage report file exists after running:
     ```bash
     ls -la $COVERAGE_REPORT
     ```
     If the report file is not at the expected path, search for it:
     ```bash
     find . -name "lcov.info" -o -name "coverage.xml" -o -name "jacoco.xml" -o -name "coverage.out" -o -name "cobertura.xml" 2>/dev/null
     ```
     Update `COVERAGE_REPORT` and `SONAR_COVERAGE_PROP` to match the actual path.

9. **Run the sonar-scanner with all properties:**
   ```bash
   project_dir=$(pwd)
   sonar_props=$(sast_build_sonar_props)
   sast_run_scan "$project_dir" "$project_key" "$token" "$url" "-D$SONAR_COVERAGE_PROP" $sonar_props
   ```

   This passes three categories of properties to the scanner:
   - **Coverage report path** (`-D$SONAR_COVERAGE_PROP`) — tells scanner where the coverage data is
   - **Source/test/exclusion paths** (`$sonar_props`) — tells scanner what's source vs tests vs excluded

   Without `sonar.sources`, SonarQube counts ALL files as source code. Test files get 0% coverage and drag the average down.

   Common coverage properties by language:
   - JavaScript/TypeScript: `-Dsonar.javascript.lcov.reportPaths=coverage/lcov.info`
   - Python: `-Dsonar.python.coverage.reportPaths=coverage.xml`
   - Java (JaCoCo): `-Dsonar.coverage.jacoco.xmlReportPaths=target/site/jacoco/jacoco.xml`
   - Go: `-Dsonar.go.coverage.reportPaths=coverage.out`
   - .NET: `-Dsonar.cs.opencover.reportsPaths=**/coverage.cobertura.xml`

10. **Wait for analysis to complete:**
   ```bash
   sast_wait_for_analysis "$project_key" "$token" "$url"
   ```

11. **Fetch results:**
    ```bash
    issues_json=$(sast_get_issues "$project_key" "$token" "$url")
    measures_json=$(sast_get_measures "$project_key" "$token" "$url")
    gate_json=$(sast_get_quality_gate "$project_key" "$token" "$url")
    ```

12. **Parse and present a summary table:**
    - Total issues by type (BUG, VULNERABILITY, CODE_SMELL)
    - Total issues by severity (BLOCKER, CRITICAL, MAJOR, MINOR, INFO)
    - Coverage percentage (current vs target)
    - Quality gate status (PASSED / FAILED)
    - Duplicated lines percentage

13. **Triage and fix — iterate until convergence.**

### Triage Rules

Classify each issue from the scan results:

**Auto-fixable (fix immediately, no user input needed):**
- Null pointer / undefined checks
- Resource leaks (unclosed streams, connections)
- Unused imports / variables
- Simple code smells (magic numbers, empty catch blocks, missing default cases)
- Obvious security fixes (hardcoded credentials in test files, missing input validation)
- Missing or incorrect type annotations

For each auto-fix: read the affected file, apply the fix using the Edit tool, and briefly explain what you changed and why.

**Needs user input (present options, wait for choice):**
- Architectural changes (extracting classes, changing inheritance, introducing patterns)
- Security design decisions (authentication strategy, encryption approach)
- Performance trade-offs (caching strategy, query optimization approaches)
- Changes that affect public API contracts

For each: present 2-3 concrete options with trade-offs. Wait for the user to choose before proceeding.

**Test coverage gaps (write tests):**
- Identify files and functions below the coverage target
- Write focused unit tests for uncovered paths
- Use the project's existing test framework and patterns (read existing tests first to match style)

### Convergence Loop

After fixing a batch of issues:

1. Run the project's test suite to verify fixes don't break anything
2. If tests fail, fix the failures before continuing
3. Re-run the sonar scan
4. Re-fetch results
5. Compare: did issues decrease? Did coverage increase?

**Stop when ANY of these conditions is met:**
- Quality gate PASSED **and** all configured targets are met (coverage, cognitive complexity, duplicated lines, ratings)
- Zero remaining auto-fixable issues and all targets met
- Two consecutive scan cycles with no improvement (diminishing returns)
- User says stop

**Maximum 5 scan-fix cycles** to prevent runaway loops.

After each cycle, report:
- Issues fixed this cycle
- Issues remaining (by type and severity)
- Coverage change (before → after)
- Quality gate status

On termination, produce a final summary:
- Total issues found, fixed, and remaining
- Coverage progression across cycles
- List of remaining issues that need manual attention (with file paths and descriptions)
- Any accepted trade-offs or deferred items

---

## Target Flow

**Goal:** View or set quality thresholds for the current repo.

### Available targets

| Key | Default | Description |
|-----|---------|-------------|
| `coverage` | 90 | Line coverage % |
| `cognitive-complexity` | 15 | Max cognitive complexity per function |
| `duplicated-lines` | 3 | Max duplicated lines % |
| `maintainability-rating` | 1 | Max rating (1=A, 2=B, 3=C, 4=D, 5=E) |
| `reliability-rating` | 1 | Max rating (1=A .. 5=E) |
| `security-rating` | 1 | Max rating (1=A .. 5=E) |

### Steps

1. Source the helper script.

2. Parse arguments after `target`:
   - **No arguments** → show all current targets:
     ```bash
     source ${CLAUDE_SKILL_DIR}/lib/sast-helpers.sh
     sast_show_targets
     ```
   - **`<key> <value>`** → set a specific target:
     ```bash
     source ${CLAUDE_SKILL_DIR}/lib/sast-helpers.sh
     sast_set_target "<key>" "<value>"
     ```
     Examples:
     ```
     /sast-scan target coverage 85
     /sast-scan target cognitive-complexity 25
     /sast-scan target duplicated-lines 5
     ```

3. Confirm the change, showing old value → new value.

---

## Important Rules

- **Never store tokens or passwords in plain text output.** The config file is chmod 600. When reporting setup status, say "token saved to config" not the actual token value.
- **Never run the scanner on paths outside the current project.** Only scan within the working directory or the specified path argument.
- **Always run tests after making code changes.** Never skip the test verification step.
- **Do not modify test files to lower assertions** to improve pass rates. Fix the code, not the tests. Exception: if a test is genuinely wrong (testing incorrect behavior), fix the test and explain why.
- **Respect .gitignore and .sonarignore patterns.** Do not scan or modify generated files, build artifacts, or vendor directories.
- **If SonarQube is not responding,** check container logs before retrying: `$SAST_RUNTIME logs sonarqube-claude --tail 50`
