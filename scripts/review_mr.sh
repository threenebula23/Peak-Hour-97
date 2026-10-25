#!/usr/bin/env bash
# review_mr.sh — MR-review бот для Gitea (PEAK HOUR 97).
#
# Читает событие pull_request (GITHUB_EVENT_PATH), забирает diff MR через
# Gitea API, просит OpenCode (agent oracle) провести строгое ревью и
# публикует результат комментарием в MR. Никогда не одобряет и не мержит.
#
# Переменные окружения:
#   GITEA_TOKEN  — токен бота (обязателен, кроме DRY_RUN).
#   GITEA_URL    — база Gitea (default: https://git.194-146-38-78.sslip.io).
#   REPO         — owner/repo (default: admin/Game-JAM).
#   DRY_RUN=1    — только напечатать ревью, ничего не постить.
#   INPUT_DIFF   — локальный файл с diff'ом; если задан и существует, Gitea API
#                  не вызывается (DIFF_CODE=200).
#   OPENCODE_BIN — путь к opencode (default: из PATH или ~/.opencode/bin).
#   REVIEW_MODEL — модель ревьюера (default: opencode-go/glm-5.3-flash).
#   REVIEW_TIMEOUT_SEC — жёсткий таймаут OpenCode, сек (default: 600).
#
# Запуск локально:
#   GITHUB_EVENT_PATH=/tmp/event.json DRY_RUN=1 bash scripts/review_mr.sh
#   INPUT_DIFF=/tmp/x.diff DRY_RUN=1 GITHUB_EVENT_PATH=/tmp/event.json \
#     bash scripts/review_mr.sh
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

GITEA_URL="${GITEA_URL:-https://git.194-146-38-78.sslip.io}"
REPO="${REPO:-admin/Game-JAM}"
GITEA_TOKEN="${GITEA_TOKEN:-}"
DRY_RUN="${DRY_RUN:-0}"
INPUT_DIFF="${INPUT_DIFF:-}"
REVIEW_DIR="${REVIEW_DIR:-/tmp/opencode}"
DIFF_LIMIT_BYTES="${DIFF_LIMIT_BYTES:-80000}"
REVIEW_MODEL="${REVIEW_MODEL:-opencode-go/glm-5.3-flash}"
REVIEW_TIMEOUT_SEC="${REVIEW_TIMEOUT_SEC:-600}"

PR=""
MR_TITLE=""
BASE_REF="dev"
HEAD_SHA=""
REVIEW_FILE=""
FAILED_NOTIFIED=0

mkdir -p "$REVIEW_DIR"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/peak-hour-review.XXXXXX")"
cleanup() {
  find "$TMP_DIR" -mindepth 1 -delete 2>/dev/null || true
  rmdir "$TMP_DIR" 2>/dev/null || true
}
trap cleanup EXIT

log() { echo "[review_mr] $*" >&2; }

post_comment() {
  # $1 — готовый Markdown текста комментария (без префикса).
  local body_text="$1"
  local body_file="$TMP_DIR/comment_body.json"
  python3 - "$body_text" >"$body_file" <<'PY'
import json, sys
print(json.dumps({"body": sys.argv[1]}, ensure_ascii=False))
PY
  local code
  code="$(curl -sS -o "$TMP_DIR/post_resp.json" -w '%{http_code}' \
    -X POST \
    -H "Authorization: token ${GITEA_TOKEN}" \
    -H "Accept: application/json" \
    -H "Content-Type: application/json" \
    --data-binary @"$body_file" \
    "${GITEA_URL}/api/v1/repos/${REPO}/issues/${PR}/comments")" || return 1
  if [[ "$code" != "201" && "$code" != "200" ]]; then
    log "POST comment failed: HTTP $code: $(head -c 500 "$TMP_DIR/post_resp.json" 2>/dev/null || true)"
    return 1
  fi
  return 0
}

fail() {
  local msg="$1"
  log "FAILED: $msg"
  if [[ "$DRY_RUN" != "1" && -n "$GITEA_TOKEN" && -n "$PR" && "$FAILED_NOTIFIED" == "0" ]]; then
    FAILED_NOTIFIED=1
    post_comment "## 🤖 OpenCode review

OpenCode review failed: ${msg}" || true
  fi
  exit 1
}

on_unexpected_error() {
  local rc=$?
  fail "unexpected error at line ${LINENO} (exit ${rc})"
}
trap on_unexpected_error ERR

# --- 1. Метаданные MR -------------------------------------------------------
if [[ -n "${GITHUB_EVENT_PATH:-}" && -f "${GITHUB_EVENT_PATH}" ]]; then
  IFS=$'\t' read -r PR MR_TITLE BASE_REF HEAD_SHA < <(
    python3 - "${GITHUB_EVENT_PATH}" <<'PY'
import json, sys
try:
    ev = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    print("\t\t\t")
    raise SystemExit(0)
pr = ev.get("pull_request") or {}
num = str(pr.get("number") or ev.get("number") or "")
title = (pr.get("title") or "").replace("\n", " ").replace("\t", " ").strip()
base = ((pr.get("base") or {}).get("ref") or "").strip()
sha = ((pr.get("head") or {}).get("sha") or "").strip()
print("\t".join([num, title, base, sha]))
PY
  )
fi
[[ -n "${BASE_REF:-}" ]] || BASE_REF="${GITHUB_BASE_REF:-}"

if [[ -z "$PR" && -n "${GITHUB_REF:-}" ]]; then
  # refs/pull/<N>/head или refs/pull/<N>/merge
  if [[ "$GITHUB_REF" =~ refs/pull/([0-9]+)/ ]]; then
    PR="${BASH_REMATCH[1]}"
  fi
fi
[[ -n "$HEAD_SHA" ]] || HEAD_SHA="${GITHUB_SHA:-unknown}"
[[ -n "$BASE_REF" ]] || BASE_REF="dev"
[[ -n "$MR_TITLE" ]] || MR_TITLE="(заголовок недоступен)"

if [[ -z "$PR" ]]; then
  fail "cannot determine pull request number (GITHUB_EVENT_PATH/GITHUB_REF)"
fi
if [[ ! "$PR" =~ ^[0-9]+$ ]]; then
  fail "invalid pull request number: $PR"
fi

REVIEW_FILE="$REVIEW_DIR/review_${PR}.md"
log "MR #$PR '$MR_TITLE' base=$BASE_REF head=$HEAD_SHA"

if [[ "$DRY_RUN" != "1" && -z "$GITEA_TOKEN" ]]; then
  fail "GITEA_TOKEN is not set"
fi

# --- 2. Diff из Gitea -------------------------------------------------------
DIFF_FILE="$TMP_DIR/mr.diff"
DIFF_CODE=""
if [[ -n "$INPUT_DIFF" && -f "$INPUT_DIFF" ]]; then
  # Локальный diff (dry-run/офлайн): Gitea API не трогаем.
  cp -- "$INPUT_DIFF" "$DIFF_FILE"
  DIFF_CODE="200"
  log "using local diff: $INPUT_DIFF"
elif [[ -n "$GITEA_TOKEN" ]]; then
  DIFF_CODE="$(curl -sS -o "$DIFF_FILE" -w '%{http_code}' \
    -H "Authorization: token ${GITEA_TOKEN}" \
    -H "Accept: text/plain" \
    "${GITEA_URL}/api/v1/repos/${REPO}/pulls/${PR}.diff")" || fail "curl diff request failed"
else
  # DRY_RUN без токена: пробуем публичный diff (может быть 404/401).
  DIFF_CODE="$(curl -sS -o "$DIFF_FILE" -w '%{http_code}' \
    -H "Accept: text/plain" \
    "${GITEA_URL}/api/v1/repos/${REPO}/pulls/${PR}.diff")" || true
fi

if [[ "$DIFF_CODE" != "200" ]]; then
  fail "cannot fetch diff (HTTP $DIFF_CODE)"
fi
if [[ ! -s "$DIFF_FILE" ]]; then
  fail "diff is empty (HTTP $DIFF_CODE)"
fi

DIFF_BYTES="$(wc -c <"$DIFF_FILE" | tr -d ' ')"
TRUNCATED_NOTE=""
if [[ "$DIFF_BYTES" -gt "$DIFF_LIMIT_BYTES" ]]; then
  python3 - "$DIFF_FILE" "$DIFF_LIMIT_BYTES" <<'PY'
import sys
path, limit = sys.argv[1], int(sys.argv[2])
data = open(path, "rb").read()
cut = data[:limit]
# Не рвём многобайтовую UTF-8 последовательность на границе среза.
while cut and (cut[-1] & 0xC0) == 0x80:
    cut = cut[:-1]
with open(path, "wb") as fh:
    fh.write(cut.decode("utf-8", "ignore").encode("utf-8"))
PY
  TRUNCATED_NOTE="

> ⚠️ Diff обрезан до ${DIFF_LIMIT_BYTES} байт из ${DIFF_BYTES}. Ревью ниже
> покрывает только видимую часть — проверьте остаток диффа вручную."
  log "diff truncated: $DIFF_BYTES -> $DIFF_LIMIT_BYTES bytes"
fi

# --- 3. Промпт ревьюера -----------------------------------------------------
PROMPT_FILE="$TMP_DIR/prompt.txt"
{
  cat <<EOF
Ты — строгий технический ревьюер проекта PEAK HOUR 97 (Godot 4.7.2, GDScript,
HTML5 без потоков, RU-only, 1280×720). Ревьюь MR #${PR} «${MR_TITLE}»
(base: ${BASE_REF}, head: ${HEAD_SHA}).

Источники истины:
- docs/GDD.md — геймдизайн и правила.
- docs/DECISIONS.md — принятые решения (D01, D02, ...). При противоречии
  GDD и DECISIONS приоритет у DECISIONS.
- Читать эти файлы не обязательно: весь нужный контекст — в diff ниже.

Проверь diff ниже и найди РЕАЛЬНЫЕ проблемы, а не стилистические придирки.
Фокус:
1. Логические баги и неверные формулы/баланс.
2. Утечки состояния между часами/забегами, забытые сбросы, сигналы,
   таймеры, утечки нод.
3. Противоречия спецификации (GDD/DECISIONS) — указывай конкретный пункт.
4. Отсутствующие или неполные тесты для нового поведения.
5. Риски парсинга GDScript (типы, await, preload, null, enum, сигнатуры).
6. UI/UX-регрессии: раскладка 1280×720, скролл, модалки, ввод, доступность.
7. Производительность: лишние аллокации в _process, перерисовка, IO.

Правила:
- ЖЁСТКОЕ ПРАВИЛО: НЕ запускай shell-команды, не читай файлы репозитория и не
  используй инструменты. Весь контекст — в diff ниже. Если чего-то не хватает —
  отметь как вопрос. Ответь сразу Markdown по разделам.
- Единственное допустимое действие — вернуть текстовый ответ; diff уже в промпте,
  ничего не открывай и не дочитывай.
- НЕ меняй файлы и не предлагай патчи целиком — только замечания.
- Ссылайся на файл и строку/фрагмент, объясняй риск и как проверить.
- Не выдумывай проблемы: если сомневаешься — помечай как вопрос.
- Если блокеров нет — так и напиши.

Формат ответа — только Markdown, ровно такие разделы:

## Blockers
## High
## Medium
## Test gaps
## Verdict

В каждом разделе — список пунктов (или «нет»). Verdict: одно из
«APPROVE», «APPROVE WITH NITS», «REQUEST CHANGES» + 1–2 строки обоснования.
Пиши по-русски.

=== MR DIFF START ===
EOF
  cat "$DIFF_FILE"
  printf '\n=== MR DIFF END ===\n%s\n' "$TRUNCATED_NOTE"
} >"$PROMPT_FILE"

# --- 4. OpenCode ------------------------------------------------------------
OPENCODE_BIN="${OPENCODE_BIN:-}"
if [[ -z "$OPENCODE_BIN" ]]; then
  if command -v opencode >/dev/null 2>&1; then
    OPENCODE_BIN="$(command -v opencode)"
  elif [[ -x /home/eq/.opencode/bin/opencode ]]; then
    OPENCODE_BIN=/home/eq/.opencode/bin/opencode
  else
    fail "opencode binary not found (set OPENCODE_BIN)"
  fi
fi

RAW_OUT="$TMP_DIR/opencode.jsonl"
log "running opencode: $OPENCODE_BIN run --format json --agent oracle --model $REVIEW_MODEL (timeout ${REVIEW_TIMEOUT_SEC}s)"
set +e
timeout "$REVIEW_TIMEOUT_SEC" "$OPENCODE_BIN" run --format json --agent oracle --model "$REVIEW_MODEL" "$(cat "$PROMPT_FILE")" >"$RAW_OUT" 2>"$TMP_DIR/opencode.err"
OC_RC=$?
set -e
if [[ "$OC_RC" -eq 124 ]]; then
  tail -n 20 "$TMP_DIR/opencode.err" >&2 || true
  fail "review timeout (${REVIEW_TIMEOUT_SEC}s)"
fi
if [[ "$OC_RC" -ne 0 ]]; then
  tail -n 20 "$TMP_DIR/opencode.err" >&2 || true
  fail "opencode exited with code $OC_RC"
fi

python3 - "$RAW_OUT" "$REVIEW_FILE" <<'PY' || fail "cannot parse opencode output"
import json, sys

raw_path, out_path = sys.argv[1], sys.argv[2]
texts = []
saw_json = False
with open(raw_path, encoding="utf-8", errors="replace") as fh:
    for line in fh:
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        saw_json = True
        if obj.get("type") != "text":
            continue
        part = obj.get("part") or {}
        if isinstance(part, dict) and part.get("type") == "text" and part.get("text"):
            texts.append(part["text"])

text = "".join(texts).strip()
if not text:
    # Фолбэк: некоторые версии opencode пишут обычный текст.
    with open(raw_path, encoding="utf-8", errors="replace") as fh:
        raw = fh.read().strip()
    text = raw
if not text:
    print("empty review", file=sys.stderr)
    sys.exit(2)
with open(out_path, "w", encoding="utf-8") as fh:
    fh.write(text)
    if not text.endswith("\n"):
        fh.write("\n")
PY

if [[ ! -s "$REVIEW_FILE" ]]; then
  fail "review file is empty: $REVIEW_FILE"
fi
log "review written to $REVIEW_FILE"

# --- 5. Публикация ----------------------------------------------------------
if [[ "$DRY_RUN" == "1" ]]; then
  echo "===== DRY RUN: review for MR #$PR (not posted) ====="
  cat "$REVIEW_FILE"
  echo "===== END DRY RUN ====="
  exit 0
fi

REVIEW_TEXT="$(cat "$REVIEW_FILE")"
if ! post_comment "## 🤖 OpenCode review

${REVIEW_TEXT}"; then
  fail "cannot post review comment to MR #$PR"
fi
log "review posted to MR #$PR"
exit 0
