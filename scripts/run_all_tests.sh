#!/usr/bin/env bash
# run_all_tests.sh — прогон всех headless-тестов PEAK HOUR 97 (v2).
#
# Запуск:
#   bash scripts/run_all_tests.sh
#   GODOT_BIN=/path/to/godot bash scripts/run_all_tests.sh
#   GODOT_BIN="/d/Apps/godot/Godot_v4.7.2-stable_win64_console.exe" bash scripts/run_all_tests.sh
#
# GODOT_BIN имеет приоритет. Если он не задан и Linux-путь по умолчанию
# отсутствует, скрипт пробует `godot4`/`godot` из PATH.
#
# Каждый тест — отдельный процесс Godot с таймаутом 180 с. XDG_DATA_HOME
# выносится во временный каталог. В конце — проверка парсинга проекта.
# Отсутствующие файлы тестов пропускаются (SKIP), а не считаются FAIL:
# волны разработки иногда удаляют модули.
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

GODOT_BIN="${GODOT_BIN:-/home/eq/techlb/tools/godot/Godot_v4.7.2-stable_linux.x86_64}"
TEST_TIMEOUT="${TEST_TIMEOUT:-180}"

if [[ ! -x "$GODOT_BIN" ]]; then
  for candidate in godot4 godot; do
    if command -v "$candidate" >/dev/null 2>&1; then
      GODOT_BIN="$(command -v "$candidate")"
      break
    fi
  done
fi
if [[ ! -x "$GODOT_BIN" ]]; then
  echo "FAIL: Godot binary is not executable: $GODOT_BIN" >&2
  echo "Set GODOT_BIN=... explicitly." >&2
  exit 1
fi

TMP_BASE="$(mktemp -d "${TMPDIR:-/tmp}/peak-hour-tests.XXXXXX")"
XDG_DATA_HOME="$TMP_BASE/xdg-data"
LOG_DIR="$TMP_BASE/logs"
mkdir -p "$XDG_DATA_HOME" "$LOG_DIR"
export XDG_DATA_HOME

cleanup() {
  find "$TMP_BASE" -mindepth 1 -delete 2>/dev/null || true
  rmdir "$TMP_BASE" 2>/dev/null || true
}
trap cleanup EXIT

# Aggregator + all standalone v2 suites. New wave-D1 suites are included.
TESTS=(
  "res://tests/run_tests.gd"
  "res://tests/test_hour.gd"
  "res://tests/test_slots.gd"
  "res://tests/test_shop.gd"
  "res://tests/test_minigame.gd"
  "res://tests/test_send_games.gd"
  "res://tests/test_attack_games.gd"
  "res://tests/test_file_grid.gd"
  "res://tests/test_shop_modal.gd"
  "res://tests/test_audio.gd"
  "res://tests/test_ambient.gd"
  "res://tests/test_fuzz.gd"
  "res://tests/test_integration.gd"
  "res://tests/test_attacks.gd"
  "res://tests/test_controller.gd"
  "res://tests/test_main_prep.gd"
  "res://tests/test_main_hour.gd"
  "res://tests/test_main_interactions.gd"
  "res://tests/test_main_attacks.gd"
  "res://tests/test_main_pause.gd"
  "res://tests/test_main_fullscreen.gd"
  "res://tests/test_main_polish.gd"
  "res://tests/test_toast.gd"
  "res://tests/test_full_playthrough.gd"
  "res://scripts/ui/ui_smoke.gd"
)

EXISTING_TESTS=()
SKIPPED_NAMES=()
for t in "${TESTS[@]}"; do
  local_path="${ROOT_DIR}/${t#res://}"
  if [[ -f "$local_path" ]]; then
    EXISTING_TESTS+=("$t")
  else
    SKIPPED_NAMES+=("$(basename "$t" .gd)")
  fi
done

ERROR_RE='SCRIPT ERROR|Parse Error|USER ERROR|Failed to load|Cannot open file|FAIL|SMOKE FAILED'
LEAK_RE='ObjectDB instances leaked|leaked at exit'

PASSED=0
FAILED=0
FAILED_NAMES=()

print_log_tail() {
  local log="$1"
  echo "----- вывод (последние 40 строк) -----"
  tail -n 40 "$log" || true
  echo "-------------------------------------"
}

run_one() {
  local script="$1"
  local name log rc started elapsed
  name="$(basename "$script" .gd)"
  log="$LOG_DIR/$name.log"

  echo ""
  echo ">>> $script"
  started="$(date +%s)"
  set +e
  timeout "$TEST_TIMEOUT" "$GODOT_BIN" --headless --path . --script "$script" >"$log" 2>&1
  rc=$?
  set -e
  elapsed=$(( $(date +%s) - started ))

  if [[ "$rc" -eq 124 ]]; then
    echo "FAIL  $name (timeout ${TEST_TIMEOUT}s)"
    print_log_tail "$log"
    FAILED=$((FAILED + 1))
    FAILED_NAMES+=("$name")
    return 0
  fi

  if [[ "$rc" -eq 0 ]]; then
    if grep -qE "$ERROR_RE" "$log"; then
      echo "FAIL  $name (exit 0, но в логе есть ошибки)"
      print_log_tail "$log"
      FAILED=$((FAILED + 1))
      FAILED_NAMES+=("$name")
      return 0
    fi
    echo "PASS  $name (${elapsed}s)"
    PASSED=$((PASSED + 1))
    return 0
  fi

  if grep -qE "$ERROR_RE" "$log"; then
    echo "FAIL  $name (exit $rc, ${elapsed}s)"
    print_log_tail "$log"
    FAILED=$((FAILED + 1))
    FAILED_NAMES+=("$name")
    return 0
  fi

  if grep -qE "$LEAK_RE" "$log" && ! grep -qE 'ERROR:' "$log"; then
    echo "PASS  $name (exit $rc, только безвредный ObjectDB leak-warning)"
    PASSED=$((PASSED + 1))
    return 0
  fi

  echo "FAIL  $name (exit $rc, ${elapsed}s)"
  print_log_tail "$log"
  FAILED=$((FAILED + 1))
  FAILED_NAMES+=("$name")
}

echo "PEAK HOUR 97 — headless tests (v2)"
echo "Godot: $GODOT_BIN"
echo "XDG_DATA_HOME: $XDG_DATA_HOME"
if [[ ${#SKIPPED_NAMES[@]} -gt 0 ]]; then
  echo "SKIP (нет файлов): ${SKIPPED_NAMES[*]}"
fi

for t in "${EXISTING_TESTS[@]}"; do
  run_one "$t"
done

# Финальная проверка: проект импортируется и парсится без ошибок.
echo ""
echo ">>> parse check: --headless --path . --quit"
PARSE_LOG="$LOG_DIR/parse_check.log"
set +e
timeout "$TEST_TIMEOUT" "$GODOT_BIN" --headless --path . --quit >"$PARSE_LOG" 2>&1
PARSE_RC=$?
set -e

if [[ "$PARSE_RC" -eq 0 ]] || { grep -qE "$LEAK_RE" "$PARSE_LOG" && ! grep -qE 'ERROR:' "$PARSE_LOG"; }; then
  echo "PASS  parse-check"
  PASSED=$((PASSED + 1))
else
  echo "FAIL  parse-check (exit $PARSE_RC)"
  print_log_tail "$PARSE_LOG"
  FAILED=$((FAILED + 1))
  FAILED_NAMES+=("parse-check")
fi

echo ""
echo "================================"
echo "Итог: PASS=$PASSED FAIL=$FAILED SKIP=${#SKIPPED_NAMES[@]}"
if [[ "$FAILED" -ne 0 ]]; then
  echo "Провалены: ${FAILED_NAMES[*]}"
  echo "Логи: $LOG_DIR"
  if [[ -n "${CI:-}" ]]; then
    mkdir -p "$ROOT_DIR/build/test-logs"
    for n in "${FAILED_NAMES[@]}"; do
      cp "$LOG_DIR/$n.log" "$ROOT_DIR/build/test-logs/" 2>/dev/null || true
    done
  fi
  exit 1
fi
echo "Все тесты прошли."
exit 0
