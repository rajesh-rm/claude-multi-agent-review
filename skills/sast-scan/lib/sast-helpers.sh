#!/usr/bin/env bash
# sast-helpers.sh — Bash functions for the sast-scan Claude Code skill
# Source this file before calling any sast_* function.
# Works on macOS (Docker Desktop, Rancher Desktop, Colima, Podman) and RHEL (Podman, Docker CE).
#
# NOTE: This is a library — do NOT use set -euo pipefail here.
# Functions handle their own errors and return meaningful exit codes.

# ── Globals (set by detect functions) ──────────────────────────────
SAST_RUNTIME=""          # docker | podman
SAST_COMPOSE=""          # "docker compose" | docker-compose | podman-compose | ""
SAST_CONTAINER="sonarqube-claude"
SAST_SCANNER_IMAGE="sonarsource/sonar-scanner-cli"
SAST_SONAR_IMAGE="sonarqube:community"
SAST_USER_CONFIG="$HOME/.claude/sast-config.json"

# ── Container Runtime Detection ────────────────────────────────────

sast_detect_runtime() {
  if command -v docker &>/dev/null; then
    SAST_RUNTIME="docker"
  elif command -v podman &>/dev/null; then
    SAST_RUNTIME="podman"
  else
    echo "ERROR: No container runtime found. Install Docker or Podman first." >&2
    echo "" >&2
    echo "  macOS:  brew install --cask docker       (Docker Desktop)" >&2
    echo "          brew install --cask rancher       (Rancher Desktop)" >&2
    echo "          brew install colima && colima start" >&2
    echo "  RHEL:   sudo dnf install -y podman" >&2
    return 1
  fi

  # Detect compose variant
  SAST_COMPOSE=""
  if command -v docker &>/dev/null && docker compose version &>/dev/null 2>&1; then
    SAST_COMPOSE="docker compose"
  elif command -v docker-compose &>/dev/null; then
    SAST_COMPOSE="docker-compose"
  elif command -v podman-compose &>/dev/null; then
    SAST_COMPOSE="podman-compose"
  fi

  echo "Runtime: $SAST_RUNTIME"
  if [[ -n "$SAST_COMPOSE" ]]; then echo "Compose: $SAST_COMPOSE"; fi
  return 0
}

# ── Platform Detection ─────────────────────────────────────────────

sast_is_macos() {
  [[ "$(uname -s)" == "Darwin" ]]
}

sast_is_linux() {
  [[ "$(uname -s)" == "Linux" ]]
}

sast_is_rhel() {
  [[ -f /etc/redhat-release ]] || grep -qi 'rhel\|red hat\|centos\|fedora' /etc/os-release 2>/dev/null
}

# ── HTTP helpers (no -f flag, handle errors explicitly) ────────────

# GET request, returns body. Caller checks exit code.
_sast_curl_get() {
  local url="$1"
  shift
  curl -s --max-time 10 "$@" "$url" 2>/dev/null
}

# POST request, returns body. Caller checks exit code.
_sast_curl_post() {
  local url="$1"
  local data="$2"
  shift 2
  curl -s --max-time 10 -X POST -d "$data" "$@" "$url" 2>/dev/null
}

# ── SonarQube Lifecycle ────────────────────────────────────────────

sast_sonar_status() {
  # Check if container exists and is running
  local state
  state=$($SAST_RUNTIME inspect --format '{{.State.Status}}' "$SAST_CONTAINER" 2>/dev/null) || state="not_found"

  if [[ "$state" == "running" ]]; then
    local url
    url=$(sast_load_user_config_field "url") || url="http://localhost:9000"
    if [[ -z "$url" ]]; then url="http://localhost:9000"; fi
    echo "RUNNING url=$url"
    return 0
  elif [[ "$state" == "exited" || "$state" == "created" || "$state" == "stopped" ]]; then
    echo "STOPPED"
    return 1
  else
    echo "NOT_FOUND"
    return 2
  fi
}

sast_sonar_start() {
  local status_line
  status_line=$(sast_sonar_status 2>/dev/null) || true

  if [[ "$status_line" == RUNNING* ]]; then
    echo "SonarQube is already running."
    return 0
  fi

  if [[ "$status_line" == "STOPPED" ]]; then
    echo "Starting existing SonarQube container..."
    $SAST_RUNTIME start "$SAST_CONTAINER"
    sast_sonar_wait_ready
    return $?
  fi

  echo "Pulling SonarQube Community image..."
  $SAST_RUNTIME pull "$SAST_SONAR_IMAGE"

  # Check vm.max_map_count on Linux (required by Elasticsearch inside SonarQube)
  if sast_is_linux; then
    local mapcount
    mapcount=$(cat /proc/sys/vm/max_map_count 2>/dev/null) || mapcount="0"
    if [[ "$mapcount" -lt 524288 ]]; then
      echo ""
      echo "WARNING: vm.max_map_count is $mapcount (SonarQube needs >= 524288)."
      echo "Run:  sudo sysctl -w vm.max_map_count=524288"
      echo "Persist: echo 'vm.max_map_count=524288' | sudo tee -a /etc/sysctl.conf"
      echo ""
    fi
  fi

  echo "Starting SonarQube container..."
  local extra_args=()

  # SELinux workaround for Podman on RHEL
  if [[ "$SAST_RUNTIME" == "podman" ]] && sast_is_linux; then
    extra_args+=(--security-opt label=disable)
  fi

  $SAST_RUNTIME run -d --name "$SAST_CONTAINER" \
    -p 9000:9000 \
    -v sonarqube_claude_data:/opt/sonarqube/data \
    -v sonarqube_claude_extensions:/opt/sonarqube/extensions \
    -v sonarqube_claude_logs:/opt/sonarqube/logs \
    "${extra_args[@]}" \
    "$SAST_SONAR_IMAGE"

  sast_sonar_wait_ready
  return $?
}

sast_sonar_stop() {
  echo "Stopping SonarQube container (data preserved in volumes)..."
  $SAST_RUNTIME stop "$SAST_CONTAINER" 2>/dev/null || true
}

sast_sonar_wait_ready() {
  local url="${1:-http://localhost:9000}"
  local timeout=180
  local elapsed=0
  local interval=5

  echo "Waiting for SonarQube to start (up to ${timeout}s)..."

  while [[ $elapsed -lt $timeout ]]; do
    # Use a subshell to isolate pipe failures
    local response
    response=$(_sast_curl_get "$url/api/system/status") || response=""

    local status=""
    if [[ -n "$response" ]]; then
      status=$(echo "$response" | grep -o '"status":"[^"]*"' | cut -d'"' -f4) || status=""
    fi

    if [[ "$status" == "UP" ]]; then
      echo "SonarQube is ready at $url"
      return 0
    fi

    sleep "$interval"
    elapsed=$((elapsed + interval))
    echo "  ... waiting (${elapsed}s, status: ${status:-connecting})"
  done

  echo "ERROR: SonarQube did not become ready within ${timeout}s" >&2
  echo "Check logs: $SAST_RUNTIME logs $SAST_CONTAINER" >&2
  return 1
}

# ── SonarQube API ──────────────────────────────────────────────────

sast_api_get() {
  local endpoint="$1"
  local token="$2"
  local url="${3:-http://localhost:9000}"

  _sast_curl_get "$url$endpoint" -H "Authorization: Bearer $token"
}

sast_api_post() {
  local endpoint="$1"
  local data="$2"
  local token="$3"
  local url="${4:-http://localhost:9000}"

  _sast_curl_post "$url$endpoint" "$data" -H "Authorization: Bearer $token"
}

sast_change_admin_password() {
  local new_password="$1"
  local url="${2:-http://localhost:9000}"

  local response http_code
  # Use -w to capture HTTP status code separately
  response=$(curl -s -o /dev/null -w "%{http_code}" -X POST -u "admin:admin" \
    -d "login=admin&previousPassword=admin&password=$new_password" \
    "$url/api/users/change_password" 2>/dev/null) || response="000"

  if [[ "$response" == "200" || "$response" == "204" ]]; then
    echo "Admin password changed successfully."
    return 0
  elif [[ "$response" == "401" ]]; then
    echo "NOTE: Default password already changed (got 401). Skipping."
    return 0
  else
    echo "WARNING: Password change returned HTTP $response" >&2
    # Try to get the response body for debugging
    local body
    body=$(curl -s -X POST -u "admin:admin" \
      -d "login=admin&previousPassword=admin&password=$new_password" \
      "$url/api/users/change_password" 2>/dev/null) || body=""
    if [[ -n "$body" ]]; then echo "  Response: $body" >&2; fi
    return 1
  fi
}

sast_generate_token() {
  local token_name="${1:-claude-sast}"
  local url="${2:-http://localhost:9000}"
  local admin_password="${3:-admin}"

  local response
  response=$(_sast_curl_post "$url/api/user_tokens/generate" "name=$token_name" -u "admin:$admin_password") || response=""

  if [[ -z "$response" ]]; then
    echo "ERROR: Failed to generate token. Is SonarQube running?" >&2
    return 1
  fi

  # Extract token value from JSON response
  local token
  token=$(echo "$response" | grep -o '"token":"[^"]*"' | cut -d'"' -f4) || token=""

  if [[ -z "$token" ]]; then
    echo "ERROR: Token not found in response: $response" >&2
    return 1
  fi

  echo "$token"
}

sast_create_project() {
  local project_key="$1"
  local project_name="$2"
  local token="$3"
  local url="${4:-http://localhost:9000}"

  # Check if project already exists
  local existing
  existing=$(sast_api_get "/api/projects/search?projects=$project_key" "$token" "$url") || existing=""

  if echo "$existing" | grep -q "\"key\":\"$project_key\"" 2>/dev/null; then
    echo "Project '$project_key' already exists."
    return 0
  fi

  echo "Creating project '$project_key'..."
  local result
  result=$(sast_api_post "/api/projects/create" "project=$project_key&name=$project_name" "$token" "$url") || result=""

  if echo "$result" | grep -q "\"key\":\"$project_key\"" 2>/dev/null; then
    echo "Project created."
    return 0
  else
    echo "WARNING: Unexpected response when creating project: $result" >&2
    # Don't fail — project might have been created despite unexpected response format
    return 0
  fi
}

sast_get_issues() {
  local project_key="$1"
  local token="$2"
  local url="${3:-http://localhost:9000}"
  local severities="${4:-}"
  local types="${5:-}"

  local params="componentKeys=$project_key&statuses=OPEN,CONFIRMED,REOPENED&ps=500"
  if [[ -n "$severities" ]]; then params="$params&severities=$severities"; fi
  if [[ -n "$types" ]]; then params="$params&types=$types"; fi

  sast_api_get "/api/issues/search?$params" "$token" "$url"
}

sast_get_measures() {
  local project_key="$1"
  local token="$2"
  local url="${3:-http://localhost:9000}"

  local metrics="coverage,line_coverage,branch_coverage,bugs,vulnerabilities,code_smells,duplicated_lines_density,ncloc,complexity,cognitive_complexity"

  sast_api_get "/api/measures/component?component=$project_key&metricKeys=$metrics" "$token" "$url"
}

sast_get_quality_gate() {
  local project_key="$1"
  local token="$2"
  local url="${3:-http://localhost:9000}"

  sast_api_get "/api/qualitygates/project_status?projectKey=$project_key" "$token" "$url"
}

sast_wait_for_analysis() {
  local project_key="$1"
  local token="$2"
  local url="${3:-http://localhost:9000}"
  local timeout=120
  local elapsed=0
  local interval=5

  echo "Waiting for analysis to complete..."

  while [[ $elapsed -lt $timeout ]]; do
    local response
    response=$(sast_api_get "/api/ce/activity?component=$project_key&ps=1&status=PENDING,IN_PROGRESS" "$token" "$url") || response=""

    local task_count
    task_count=$(echo "$response" | grep -o '"total":[0-9]*' | cut -d: -f2) || task_count="1"
    if [[ -z "$task_count" ]]; then task_count="1"; fi

    if [[ "$task_count" == "0" ]]; then
      echo "Analysis complete."
      return 0
    fi

    sleep "$interval"
    elapsed=$((elapsed + interval))
    echo "  ... analysis in progress (${elapsed}s)"
  done

  echo "WARNING: Analysis did not complete within ${timeout}s" >&2
  return 1
}

# ── Project Detection ──────────────────────────────────────────────

# Detect project type, test command, coverage command, and coverage report paths.
# Outputs KEY=VALUE lines that can be eval'd by the caller.
sast_detect_project() {
  local project_dir="${1:-.}"

  local project_type=""
  local test_cmd=""
  local coverage_cmd=""
  local coverage_report=""
  local sonar_coverage_prop=""

  # ── Node.js / TypeScript ──
  if [[ -f "$project_dir/package.json" ]]; then
    project_type="nodejs"

    # Check which test framework / runner is used
    local pkg_content
    pkg_content=$(cat "$project_dir/package.json" 2>/dev/null) || pkg_content=""

    if echo "$pkg_content" | grep -q '"vitest"'; then
      test_cmd="npx vitest run"
      coverage_cmd="npx vitest run --coverage"
      coverage_report="coverage/lcov.info"
    elif echo "$pkg_content" | grep -q '"jest"'; then
      test_cmd="npx jest"
      coverage_cmd="npx jest --coverage"
      coverage_report="coverage/lcov.info"
    elif echo "$pkg_content" | grep -q '"c8\|\"nyc"'; then
      test_cmd="npm test"
      coverage_cmd="npx c8 npm test"
      coverage_report="coverage/lcov.info"
    else
      # Fallback: use npm test scripts
      test_cmd="npm test"
      coverage_cmd="npm test -- --coverage"
      coverage_report="coverage/lcov.info"
    fi

    sonar_coverage_prop="sonar.javascript.lcov.reportPaths=$coverage_report"

  # ── Python ──
  elif [[ -f "$project_dir/pyproject.toml" ]] || [[ -f "$project_dir/setup.py" ]] || [[ -f "$project_dir/requirements.txt" ]]; then
    project_type="python"
    test_cmd="python -m pytest"
    coverage_cmd="python -m pytest --cov --cov-report=xml:coverage.xml"
    coverage_report="coverage.xml"
    sonar_coverage_prop="sonar.python.coverage.reportPaths=$coverage_report"

  # ── Java / Maven ──
  elif [[ -f "$project_dir/pom.xml" ]]; then
    project_type="java-maven"
    test_cmd="mvn test"
    coverage_cmd="mvn test"  # JaCoCo plugin generates report during test phase
    coverage_report="target/site/jacoco/jacoco.xml"
    sonar_coverage_prop="sonar.coverage.jacoco.xmlReportPaths=$coverage_report"

  # ── Java / Gradle ──
  elif [[ -f "$project_dir/build.gradle" ]] || [[ -f "$project_dir/build.gradle.kts" ]]; then
    project_type="java-gradle"
    test_cmd="./gradlew test"
    coverage_cmd="./gradlew test jacocoTestReport"
    coverage_report="build/reports/jacoco/test/jacocoTestReport.xml"
    sonar_coverage_prop="sonar.coverage.jacoco.xmlReportPaths=$coverage_report"

  # ── Go ──
  elif [[ -f "$project_dir/go.mod" ]]; then
    project_type="go"
    test_cmd="go test ./..."
    coverage_cmd="go test -coverprofile=coverage.out ./..."
    coverage_report="coverage.out"
    sonar_coverage_prop="sonar.go.coverage.reportPaths=$coverage_report"

  # ── .NET ──
  elif ls "$project_dir"/*.csproj &>/dev/null || find "$project_dir" -maxdepth 3 -name "*.csproj" -print -quit 2>/dev/null | grep -q .; then
    project_type="dotnet"
    test_cmd="dotnet test"
    coverage_cmd="dotnet test --collect:\"XPlat Code Coverage\""
    coverage_report="**/coverage.cobertura.xml"
    sonar_coverage_prop="sonar.cs.opencover.reportsPaths=$coverage_report"

  # ── Rust ──
  elif [[ -f "$project_dir/Cargo.toml" ]]; then
    project_type="rust"
    test_cmd="cargo test"
    coverage_cmd="cargo tarpaulin --out xml"
    coverage_report="cobertura.xml"
    sonar_coverage_prop="sonar.coverageReportPaths=$coverage_report"

  else
    project_type="unknown"
    test_cmd=""
    coverage_cmd=""
    coverage_report=""
    sonar_coverage_prop=""
  fi

  echo "PROJECT_TYPE='$project_type'"
  echo "TEST_CMD='$test_cmd'"
  echo "COVERAGE_CMD='$coverage_cmd'"
  echo "COVERAGE_REPORT='$coverage_report'"
  echo "SONAR_COVERAGE_PROP='$sonar_coverage_prop'"
}

# ── Scanner ────────────────────────────────────────────────────────

# Run sonar-scanner. Pass extra -D properties as arguments after the 4 required ones.
# Example: sast_run_scan /path key token url "-Dsonar.javascript.lcov.reportPaths=coverage/lcov.info"
sast_run_scan() {
  local project_dir="$1"
  local project_key="$2"
  local token="$3"
  local url="${4:-http://localhost:9000}"
  shift 4
  local extra_props="$*"  # remaining args are extra -D properties

  # Determine the SonarQube host URL from the scanner container's perspective
  local scanner_sonar_url="$url"

  if sast_is_macos; then
    # On macOS, containers run in a VM — use host.docker.internal to reach host ports
    scanner_sonar_url="http://host.docker.internal:9000"
  fi

  echo "Running sonar-scanner on $project_dir (project: $project_key)..."

  local docker_args=()

  # On Linux, use host network so scanner can reach SonarQube on localhost
  if sast_is_linux; then
    docker_args+=(--network host)
    scanner_sonar_url="http://localhost:9000"
  fi

  # Build SONAR_SCANNER_OPTS with project key and any extra properties
  local scanner_opts="-Dsonar.projectKey=$project_key -Dsonar.projectBaseDir=/usr/src"
  if [[ -n "$extra_props" ]]; then
    scanner_opts="$scanner_opts $extra_props"
  fi

  $SAST_RUNTIME run --rm \
    -e SONAR_HOST_URL="$scanner_sonar_url" \
    -e SONAR_TOKEN="$token" \
    -e SONAR_SCANNER_OPTS="$scanner_opts" \
    -v "$project_dir:/usr/src" \
    -v sonarqube_claude_scanner_cache:/opt/sonar-scanner/.sonar/cache \
    "${docker_args[@]}" \
    "$SAST_SCANNER_IMAGE"
}

# ── Config Management ──────────────────────────────────────────────

sast_load_user_config_field() {
  local field="$1"
  if [[ -f "$SAST_USER_CONFIG" ]]; then
    local value
    value=$(grep -o "\"$field\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$SAST_USER_CONFIG" | head -1 | cut -d'"' -f4) || value=""
    echo "$value"
  fi
}

sast_save_user_config() {
  local url="$1"
  local token="$2"
  local runtime="$3"

  mkdir -p "$(dirname "$SAST_USER_CONFIG")"
  cat > "$SAST_USER_CONFIG" <<JSONEOF
{
  "url": "$url",
  "token": "$token",
  "runtime": "$runtime",
  "container_name": "$SAST_CONTAINER",
  "setup_date": "$(date +%Y-%m-%d)"
}
JSONEOF

  chmod 600 "$SAST_USER_CONFIG"
  echo "Config saved to $SAST_USER_CONFIG"
}

sast_load_repo_config_field() {
  local field="$1"
  local config_file=".claude/sast-config.json"
  if [[ -f "$config_file" ]]; then
    local value
    value=$(grep -o "\"$field\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$config_file" | head -1 | cut -d'"' -f4) || value=""
    echo "$value"
  fi
}

sast_load_repo_config_number() {
  local field="$1"
  local config_file=".claude/sast-config.json"
  if [[ -f "$config_file" ]]; then
    local value
    value=$(grep -o "\"$field\"[[:space:]]*:[[:space:]]*[0-9]*" "$config_file" | head -1 | grep -o '[0-9]*$') || value=""
    echo "$value"
  fi
}

# ── Repo Config (supports multiple targets) ───────────────────────
#
# Config file: .claude/sast-config.json
# Format: flat JSON with target_ prefix for thresholds.
#
# Supported targets and their defaults:
#   coverage                  90    Line coverage %
#   cognitive-complexity      15    Max cognitive complexity per function
#   duplicated-lines          3     Max duplicated lines %
#   maintainability-rating    1     Max rating (1=A, 2=B, 3=C, 4=D, 5=E)
#   reliability-rating        1     Max rating
#   security-rating           1     Max rating
#
# Keys use hyphens in the CLI, underscores in the JSON file.

# All known target keys (underscored form)
SAST_TARGET_KEYS="coverage cognitive_complexity duplicated_lines maintainability_rating reliability_rating security_rating"

# Default value for a target key
_sast_target_default() {
  case "$1" in
    coverage)                 echo 90 ;;
    cognitive_complexity)     echo 15 ;;
    duplicated_lines)         echo 3 ;;
    maintainability_rating)   echo 1 ;;
    reliability_rating)       echo 1 ;;
    security_rating)          echo 1 ;;
    *)                        echo "" ;;
  esac
}

# Human-readable label for a target key
_sast_target_label() {
  case "$1" in
    coverage)                 echo "Line coverage %" ;;
    cognitive_complexity)     echo "Max cognitive complexity per function" ;;
    duplicated_lines)         echo "Max duplicated lines %" ;;
    maintainability_rating)   echo "Max rating (1=A .. 5=E)" ;;
    reliability_rating)       echo "Max rating (1=A .. 5=E)" ;;
    security_rating)          echo "Max rating (1=A .. 5=E)" ;;
    *)                        echo "" ;;
  esac
}

# Convert CLI key (hyphens) to config key (underscores)
_sast_normalize_key() {
  echo "$1" | tr '-' '_'
}

# Check if a key is a known target
_sast_is_valid_key() {
  local key="$1"
  for k in $SAST_TARGET_KEYS; do
    if [[ "$k" == "$key" ]]; then
      return 0
    fi
  done
  return 1
}

sast_save_repo_config() {
  local config_file=".claude/sast-config.json"

  # Load existing values or use defaults
  local project_key
  project_key=$(sast_load_repo_config_field "project_key") || project_key=""
  if [[ -z "$project_key" ]]; then
    project_key=$(basename "$(pwd)" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]/-/g')
  fi

  # Load existing sonar properties (preserve across saves)
  local sonar_sources sonar_tests sonar_exclusions
  sonar_sources=$(sast_load_repo_config_field "sonar_sources") || sonar_sources=""
  sonar_tests=$(sast_load_repo_config_field "sonar_tests") || sonar_tests=""
  sonar_exclusions=$(sast_load_repo_config_field "sonar_exclusions") || sonar_exclusions=""

  mkdir -p .claude

  # Build JSON — project_key, sonar properties, then all target_ fields
  local json="{
  \"project_key\": \"$project_key\",
  \"sonar_sources\": \"$sonar_sources\",
  \"sonar_tests\": \"$sonar_tests\",
  \"sonar_exclusions\": \"$sonar_exclusions\""

  for key in $SAST_TARGET_KEYS; do
    local val default
    val=$(sast_load_repo_config_number "target_$key") || val=""
    default=$(_sast_target_default "$key")
    if [[ -z "$val" ]]; then val="$default"; fi
    json="$json,
  \"target_$key\": $val"
  done

  json="$json
}"

  echo "$json" > "$config_file"
  echo "Repo config saved to $config_file"
}

# Set a sonar property in the repo config.
# Keys: sonar_sources, sonar_tests, sonar_exclusions
sast_set_sonar_prop() {
  local prop="$1"
  local value="$2"
  local config_file=".claude/sast-config.json"

  # Validate prop name
  case "$prop" in
    sonar_sources|sonar_tests|sonar_exclusions) ;;
    *)
      echo "ERROR: Unknown sonar property '$prop'. Valid: sonar_sources, sonar_tests, sonar_exclusions" >&2
      return 1
      ;;
  esac

  # Ensure config exists
  if [[ ! -f "$config_file" ]]; then
    sast_save_repo_config
  fi

  # Update or add the field
  local tmpfile
  tmpfile=$(mktemp)

  if grep -q "\"$prop\"" "$config_file"; then
    # Replace existing value — match "key": "value" pattern
    sed "s|\"${prop}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"|\"${prop}\": \"${value}\"|" "$config_file" > "$tmpfile"
  else
    # Add new field before closing brace (portable — no \n in sed)
    # Remove trailing }, append new field, re-add }
    sed '$ s/}//' "$config_file" | sed '$ s/[[:space:]]*$//' > "$tmpfile"
    printf ',\n  "%s": "%s"\n}\n' "$prop" "$value" >> "$tmpfile"
  fi

  mv "$tmpfile" "$config_file"

  local display_prop
  display_prop=$(echo "$prop" | sed 's/sonar_/sonar./')
  echo "$display_prop = $value"
}

# Build scanner -D flags from repo config sonar properties.
# Returns a string of -D flags ready to append to sast_run_scan.
sast_build_sonar_props() {
  local props=""

  local sources tests exclusions
  sources=$(sast_load_repo_config_field "sonar_sources") || sources=""
  tests=$(sast_load_repo_config_field "sonar_tests") || tests=""
  exclusions=$(sast_load_repo_config_field "sonar_exclusions") || exclusions=""

  if [[ -n "$sources" ]]; then
    props="$props -Dsonar.sources=$sources"
  fi
  if [[ -n "$tests" ]]; then
    props="$props -Dsonar.tests=$tests"
  fi
  if [[ -n "$exclusions" ]]; then
    props="$props -Dsonar.exclusions=$exclusions"
  fi

  echo "$props"
}

# Show current sonar properties for this repo
sast_show_sonar_props() {
  local config_file=".claude/sast-config.json"

  echo "Sonar scan properties for this repo:"
  echo ""

  local sources tests exclusions
  sources=$(sast_load_repo_config_field "sonar_sources") || sources=""
  tests=$(sast_load_repo_config_field "sonar_tests") || tests=""
  exclusions=$(sast_load_repo_config_field "sonar_exclusions") || exclusions=""

  printf "  %-24s %s\n" "sonar.sources" "${sources:-(not set — scanner uses '.')}"
  printf "  %-24s %s\n" "sonar.tests" "${tests:-(not set)}"
  printf "  %-24s %s\n" "sonar.exclusions" "${exclusions:-(not set)}"
  echo ""
  echo "These tell SonarQube which directories are source code vs tests."
  echo "Without sonar.sources, ALL files count as source — inflating the denominator"
  echo "and making coverage look lower than it really is."
}

sast_set_target() {
  local key="$1"
  local value="$2"

  # Normalize: hyphens → underscores
  local norm_key
  norm_key=$(_sast_normalize_key "$key")

  # Validate key is known
  if ! _sast_is_valid_key "$norm_key"; then
    echo "ERROR: Unknown target '$key'." >&2
    echo "" >&2
    echo "Available targets:" >&2
    for k in $SAST_TARGET_KEYS; do
      local display_key label default
      display_key=$(echo "$k" | tr '_' '-')
      label=$(_sast_target_label "$k")
      default=$(_sast_target_default "$k")
      printf "  %-28s %s (default: %s)\n" "$display_key" "$label" "$default" >&2
    done
    return 1
  fi

  # Validate value is a number
  if ! [[ "$value" =~ ^[0-9]+$ ]]; then
    echo "ERROR: Value must be a number, got '$value'." >&2
    return 1
  fi

  # Range validation for specific keys
  if [[ "$norm_key" == "coverage" || "$norm_key" == "duplicated_lines" ]]; then
    if [[ "$value" -lt 0 || "$value" -gt 100 ]]; then
      echo "ERROR: $key must be between 0 and 100." >&2
      return 1
    fi
  fi

  if [[ "$norm_key" == *_rating ]]; then
    if [[ "$value" -lt 1 || "$value" -gt 5 ]]; then
      echo "ERROR: $key must be between 1 (A) and 5 (E)." >&2
      return 1
    fi
  fi

  # Ensure config file exists with all defaults
  local config_file=".claude/sast-config.json"
  if [[ ! -f "$config_file" ]]; then
    sast_save_repo_config
  fi

  # Read current file, update the specific field, rewrite
  # Use a temp file to avoid partial writes
  local tmpfile
  tmpfile=$(mktemp)

  if grep -q "\"target_$norm_key\"" "$config_file"; then
    # Replace existing value
    sed "s/\"target_${norm_key}\"[[:space:]]*:[[:space:]]*[0-9]*/\"target_${norm_key}\": ${value}/" "$config_file" > "$tmpfile"
  else
    # Add new field before closing brace (portable — no \n in sed)
    sed '$ s/}//' "$config_file" | sed '$ s/[[:space:]]*$//' > "$tmpfile"
    printf ',\n  "target_%s": %s\n}\n' "$norm_key" "$value" >> "$tmpfile"
  fi

  mv "$tmpfile" "$config_file"

  local display_key label
  display_key=$(echo "$norm_key" | tr '_' '-')
  label=$(_sast_target_label "$norm_key")
  echo "$display_key set to $value ($label)"
}

sast_show_targets() {
  local config_file=".claude/sast-config.json"

  echo "SAST Targets for this repo:"
  echo ""
  printf "  %-28s %-10s %-10s %s\n" "TARGET" "CURRENT" "DEFAULT" "DESCRIPTION"
  printf "  %-28s %-10s %-10s %s\n" "------" "-------" "-------" "-----------"

  for key in $SAST_TARGET_KEYS; do
    local current default display_key label
    default=$(_sast_target_default "$key")
    display_key=$(echo "$key" | tr '_' '-')
    label=$(_sast_target_label "$key")
    current=""

    if [[ -f "$config_file" ]]; then
      current=$(sast_load_repo_config_number "target_$key") || current=""
    fi
    if [[ -z "$current" ]]; then current="$default"; fi

    local marker=""
    if [[ "$current" != "$default" ]]; then marker=" *"; fi

    printf "  %-28s %-10s %-10s %s%s\n" "$display_key" "$current" "$default" "$label" "$marker"
  done

  echo ""
  echo "  * = modified from default"
  echo ""
  echo "Set a target:  /sast-scan target <key> <value>"
  echo "Example:       /sast-scan target cognitive-complexity 25"
}
