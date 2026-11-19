#!/usr/bin/env bash
# Rebuild the throwaway database asset_mvp_starter_test and run invariant checks.
# Drops only that database. Does not start a web server or contact the network.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DB="asset_mvp_starter_test"
MIGRATION="$ROOT/db/migrations/001_initial.sql"
FIXTURES="$ROOT/db/fixtures/synthetic.sql"
TEST_DIR="$ROOT/db/tests"

sql_passed=0
sql_failed=0
concurrent_passed=0
concurrent_failed=0
background_pids=()

cleanup_background() {
  local pid
  for pid in "${background_pids[@]}"; do
    kill "$pid" >/dev/null 2>&1 || true
  done
}
trap cleanup_background EXIT

psql_base=()
if psql -d postgres -tA -c 'SELECT 1' >/dev/null 2>&1; then
  psql_base=(psql)
elif sudo -n -u postgres psql -d postgres -tA -c 'SELECT 1' >/dev/null 2>&1; then
  psql_base=(sudo -n -u postgres psql)
else
  echo "PostgreSQL is not reachable." >&2
  echo "Install and start PostgreSQL 14 or newer, then rerun $0." >&2
  echo "UNTESTED: every database test in this repository." >&2
  exit 2
fi

run_psql() {
  "${psql_base[@]}" "$@"
}

echo "postgresql: $(run_psql -d postgres -tA -c 'SHOW server_version')"

recreate_db() {
  run_psql -d postgres -v ON_ERROR_STOP=1 -q -c \
    "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${DB}' AND pid <> pg_backend_pid();" \
    >/dev/null
  run_psql -d postgres -v ON_ERROR_STOP=1 -q -c "DROP DATABASE IF EXISTS ${DB};"
  run_psql -d postgres -v ON_ERROR_STOP=1 -q -c "CREATE DATABASE ${DB};"
  run_psql -d "$DB" -v ON_ERROR_STOP=1 -q -f "$MIGRATION"
  run_psql -d "$DB" -v ON_ERROR_STOP=1 -q -f "$FIXTURES"
}

run_sql_file() {
  local name="$1"
  recreate_db
  if run_psql -d "$DB" -v ON_ERROR_STOP=1 -q -f "$TEST_DIR/$name"; then
    echo "PASS $name"
    sql_passed=$((sql_passed + 1))
  else
    echo "FAIL $name"
    sql_failed=$((sql_failed + 1))
  fi
}

confirm_code() {
  grep -E '^(confirmed|already_confirmed|conflict|already_conflict|cancelled|not_found)$' "$1" | head -n 1 || true
}

wait_for_asset_lock() {
  local i locks
  for i in $(seq 1 50); do
    locks="$(run_psql -d "$DB" -tA -c \
      "SELECT count(*) FROM pg_locks l JOIN pg_class c ON c.oid = l.relation JOIN pg_stat_activity a ON a.pid = l.pid WHERE c.relname = 'assets' AND l.granted AND a.datname = current_database() AND a.pid <> pg_backend_pid() AND a.state IN ('active', 'idle in transaction');")"
    if [[ "${locks:-0}" -ge 1 ]]; then
      return 0
    fi
    sleep 0.2
  done
  return 1
}

require_uuid() {
  if [[ ! "$1" =~ ^[0-9a-fA-F-]{36}$ ]]; then
    echo "expected a transfer uuid, got: $1" >&2
    exit 1
  fi
}

run_concurrent_case() {
  local label="$1"
  local sql_a="$2"
  local sql_b="$3"
  local expect_a="$4"
  local expect_b="$5"
  local check_sql="$6"
  local dir pid_a pid_b code_a code_b
  dir="$(mktemp -d)"
  # The server user must be able to read these files when psql runs via sudo.
  chmod 755 "$dir"
  printf '%s\n' "$sql_a" >"$dir/a.sql"
  printf '%s\n' "$sql_b" >"$dir/b.sql"
  chmod 644 "$dir/a.sql" "$dir/b.sql"
  run_psql -d "$DB" -v ON_ERROR_STOP=1 -q -tA -f "$dir/a.sql" >"$dir/a.out" 2>"$dir/a.err" &
  pid_a=$!
  background_pids+=("$pid_a")
  if ! wait_for_asset_lock; then
    kill "$pid_a" >/dev/null 2>&1 || true
    wait "$pid_a" >/dev/null 2>&1 || true
    echo "FAIL $label"
    echo "session A did not hold an asset lock" >&2
    cat "$dir/a.err" >&2 || true
    concurrent_failed=$((concurrent_failed + 1))
    rm -rf "$dir"
    return
  fi
  run_psql -d "$DB" -v ON_ERROR_STOP=1 -q -tA -f "$dir/b.sql" >"$dir/b.out" 2>"$dir/b.err" &
  pid_b=$!
  background_pids+=("$pid_b")
  wait "$pid_a" >/dev/null 2>&1 || true
  wait "$pid_b" >/dev/null 2>&1 || true
  code_a="$(confirm_code "$dir/a.out")"
  code_b="$(confirm_code "$dir/b.out")"
  if [[ "$code_a" != "$expect_a" || "$code_b" != "$expect_b" ]]; then
    echo "FAIL $label"
    echo "codes a=${code_a:-<empty>} b=${code_b:-<empty>}; expected ${expect_a} and ${expect_b}" >&2
    echo "--- session A stderr ---" >&2
    cat "$dir/a.err" >&2 || true
    echo "--- session B stderr ---" >&2
    cat "$dir/b.err" >&2 || true
    concurrent_failed=$((concurrent_failed + 1))
    rm -rf "$dir"
    return
  fi
  if ! run_psql -d "$DB" -v ON_ERROR_STOP=1 -q -c "$check_sql"; then
    echo "FAIL $label"
    echo "final database state did not match the concurrent outcome" >&2
    concurrent_failed=$((concurrent_failed + 1))
    rm -rf "$dir"
    return
  fi
  echo "PASS $label"
  concurrent_passed=$((concurrent_passed + 1))
  rm -rf "$dir"
}

for file in "$TEST_DIR"/[0-9]*.sql; do
  run_sql_file "$(basename "$file")"
done

recreate_db
t1="$(run_psql -d "$DB" -tA -c "SELECT initiate_transfer((SELECT id FROM assets WHERE asset_tag = 'AST-SYN-002'), (SELECT id FROM rooms WHERE code = 'RM-101'))")"
t2="$(run_psql -d "$DB" -tA -c "SELECT initiate_transfer((SELECT id FROM assets WHERE asset_tag = 'AST-SYN-002'), (SELECT id FROM rooms WHERE code = 'RM-102'))")"
require_uuid "$t1"
require_uuid "$t2"
run_concurrent_case \
  "11_concurrent_conflict" \
  "BEGIN; SELECT confirm_transfer('${t1}'::uuid); SELECT pg_sleep(6); COMMIT;" \
  "BEGIN; SET statement_timeout = '15s'; SELECT confirm_transfer('${t2}'::uuid); COMMIT;" \
  "confirmed" \
  "conflict" \
  "DO \$\$ BEGIN IF (SELECT status FROM transfers WHERE id = '${t1}') <> 'confirmed' OR (SELECT status FROM transfers WHERE id = '${t2}') <> 'conflict' OR (SELECT count(*) FROM location_audit_events WHERE transfer_id IN ('${t1}', '${t2}')) <> 1 OR NOT location_audit_is_consistent() THEN RAISE EXCEPTION 'concurrent conflict final state'; END IF; END \$\$;"

recreate_db
t1="$(run_psql -d "$DB" -tA -c "SELECT initiate_transfer((SELECT id FROM assets WHERE asset_tag = 'AST-SYN-002'), (SELECT id FROM rooms WHERE code = 'RM-101'))")"
require_uuid "$t1"
run_concurrent_case \
  "12_concurrent_duplicate_confirm" \
  "BEGIN; SELECT confirm_transfer('${t1}'::uuid); SELECT pg_sleep(6); COMMIT;" \
  "BEGIN; SET statement_timeout = '15s'; SELECT confirm_transfer('${t1}'::uuid); COMMIT;" \
  "confirmed" \
  "already_confirmed" \
  "DO \$\$ BEGIN IF (SELECT status FROM transfers WHERE id = '${t1}') <> 'confirmed' OR (SELECT count(*) FROM location_audit_events WHERE transfer_id = '${t1}') <> 1 OR (SELECT location_revision FROM assets WHERE asset_tag = 'AST-SYN-002') <> 2 OR NOT location_audit_is_consistent() THEN RAISE EXCEPTION 'concurrent duplicate final state'; END IF; END \$\$;"

echo "SUMMARY sql_passed=${sql_passed} sql_failed=${sql_failed} concurrent_passed=${concurrent_passed} concurrent_failed=${concurrent_failed}"
echo "NOT IN THIS RUN: browser UI, Three.js, glTF parsing, IFC parsing, file import, authentication, least-privilege roles, deployment."
if [[ "$sql_failed" -ne 0 || "$concurrent_failed" -ne 0 ]]; then
  exit 1
fi
