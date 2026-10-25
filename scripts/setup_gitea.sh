#!/usr/bin/env bash
# setup_gitea.sh — идемпотентная настройка репозитория admin/Game-JAM:
#   1) ветка dev (от main);
#   2) branch protections для main и dev (push/merge/force-push только admin);
#   3) Actions secret REVIEWER_TOKEN для workflow review.yml.
#
# Переменные окружения:
#   GITEA_TOKEN    — админ-токен для настройки репозитория (обязателен).
#   REVIEWER_TOKEN — токен бота для Actions secret REVIEWER_TOKEN. Если не
#                    задан, секрет не трогаем: он уже создан бот-агентом, и
#                    перезапись админским токеном сломала бы review.yml.
#   GITEA_URL      — default: https://git.194-146-38-78.sslip.io
#   REPO           — default: admin/Game-JAM
#
# Запуск: GITEA_TOKEN=... [REVIEWER_TOKEN=...] bash scripts/setup_gitea.sh
#
# Токены нигде не печатаются. Если Gitea-инстанс ожидает base64 в secret API,
# скрипт автоматически повторит PUT с base64-значением (см. put_secret()).
set -euo pipefail

GITEA_URL="${GITEA_URL:-https://git.194-146-38-78.sslip.io}"
REPO="${REPO:-admin/Game-JAM}"
GITEA_TOKEN="${GITEA_TOKEN:-}"
REVIEWER_TOKEN="${REVIEWER_TOKEN:-}"

if [[ -z "$GITEA_TOKEN" ]]; then
  echo "ERROR: GITEA_TOKEN is not set" >&2
  exit 1
fi

API="${GITEA_URL%/}/api/v1/repos/${REPO}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/peak-hour-gitea.XXXXXX")"
RESP_BODY=""
RESP_CODE=""

cleanup() {
  find "$TMP_DIR" -mindepth 1 -delete 2>/dev/null || true
  rmdir "$TMP_DIR" 2>/dev/null || true
}
trap cleanup EXIT

log() { echo "[setup_gitea] $*"; }

# api METHOD PATH [JSON_DATA]
# Заполняет RESP_CODE/RESP_BODY. Возвращает 2 при сетевой ошибке curl.
api() {
  local method="$1" path="$2" data="${3:-}"
  local out="$TMP_DIR/resp.json"
  local -a args=(
    -sS
    -X "$method"
    -H "Authorization: token ${GITEA_TOKEN}"
    -H "Accept: application/json"
    -o "$out"
    -w '%{http_code}'
  )
  if [[ -n "$data" ]]; then
    args+=(-H "Content-Type: application/json" --data-binary "$data")
  fi
  if ! RESP_CODE="$(curl "${args[@]}" "${API}${path}")"; then
    log "network error: $method $path"
    RESP_BODY=""
    return 2
  fi
  RESP_BODY="$(cat "$out" 2>/dev/null || true)"
  return 0
}

require_code() {
  local expected="$1" context="$2"
  local code="${RESP_CODE:-000}"
  if [[ ",$expected," != *",$code,"* ]]; then
    log "ERROR: $context — HTTP $code"
    printf '%s\n' "$RESP_BODY" | head -c 600 >&2 || true
    echo >&2
    exit 1
  fi
}

print_protection() {
  local branch="$1"
  api GET "/branch_protections/${branch}"
  if [[ "$RESP_CODE" != "200" ]]; then
    log "$branch: не удалось прочитать правила (HTTP $RESP_CODE)"
    return 0
  fi
  RESP_BODY="$RESP_BODY" python3 - "$branch" <<'PY'
import json, os, sys
branch = sys.argv[1]
try:
    d = json.loads(os.environ.get("RESP_BODY") or "{}")
except Exception:
    print(f"{branch}: (ответ не JSON)")
    raise SystemExit(0)
keys = [
    "enable_push", "enable_push_whitelist", "push_whitelist_usernames",
    "enable_merge_whitelist", "merge_whitelist_usernames",
    "enable_force_push", "enable_force_push_allowlist",
    "force_push_allowlist_usernames", "required_approvals",
    "enable_status_check", "block_admin_merge_override",
]
print(f"  {branch}: " + ", ".join(f"{k}={d.get(k)!r}" for k in keys if k in d))
PY
}

# --- 1. Ветка dev -----------------------------------------------------------
log "repo: $REPO @ $GITEA_URL"

api GET "/branches/dev"
case "$RESP_CODE" in
  200)
    log "ветка dev уже существует"
    ;;
  404)
    log "ветки dev нет — создаю от main"
    # Gitea 28.2+: CreateBranchOption использует new_branch_name (иначе 422
    # «[BranchName]: Required»). Для старых сборок — fallback на branch_name.
    api POST "/branches" '{"new_branch_name":"dev","old_branch_name":"main"}'
    if [[ "$RESP_CODE" != "201" && "$RESP_CODE" != "200" ]]; then
      log "new_branch_name не принят (HTTP $RESP_CODE) — пробую legacy branch_name"
      api POST "/branches" '{"branch_name":"dev","old_branch_name":"main"}'
    fi
    require_code "201,200" "create branch dev"
    log "ветка dev создана"
    ;;
  *)
    require_code "200,404" "check branch dev"
    ;;
esac

# --- 2. Branch protections --------------------------------------------------
# admin — единственный, кто может пушить/мержить/force-push в main и dev.
# required_approvals=0: мерж не блокируется формальными approve (решает admin).
# enable_status_check=false: CI/review — обязательные по процессу, но не
# технический блок мержа (можно включить позже, см. docs/WORKFLOW.md).
protection_payload() {
  local branch="$1" include_name="$2"
  local name_field=""
  if [[ "$include_name" == "1" ]]; then
    name_field="\"branch_name\": \"${branch}\", "
  fi
  printf '{%s"enable_push": true, "enable_push_whitelist": true, "push_whitelist_usernames": ["admin"], "enable_merge_whitelist": true, "merge_whitelist_usernames": ["admin"], "enable_force_push": true, "enable_force_push_allowlist": true, "force_push_allowlist_usernames": ["admin"], "required_approvals": 0, "enable_status_check": false, "block_admin_merge_override": false}' "$name_field"
}

for branch in main dev; do
  payload_post="$(protection_payload "$branch" 1)"
  payload_patch="$(protection_payload "$branch" 0)"

  api GET "/branch_protections/${branch}"
  case "$RESP_CODE" in
    200)
      log "правила для $branch существуют — обновляю (PATCH)"
      api PATCH "/branch_protections/${branch}" "$payload_patch"
      require_code "200" "update protection $branch"
      ;;
    404)
      log "правил для $branch нет — создаю (POST)"
      api POST "/branch_protections" "$payload_post"
      require_code "201,200" "create protection $branch"
      ;;
    *)
      require_code "200,404" "check protection $branch"
      ;;
  esac
done

log "итоговые правила branch protection:"
print_protection main
print_protection dev

# --- 3. Actions secret REVIEWER_TOKEN -------------------------------------
# Gitea запрещает имена секретов с префиксами GITEA_/GITHUB_ (HTTP 400),
# поэтому секрет называется REVIEWER_TOKEN, а workflow разворачивает его
# в env-переменную GITEA_TOKEN:
#   env: GITEA_TOKEN: ${{ secrets.REVIEWER_TOKEN }}
# Gitea ожидает {"data": "<value>"}. Часть сборок/форков принимает только
# base64 — на 4xx повторяем с base64 и фиксируем это в сообщении.
# ВАЖНО: значение секрета — отдельный бот-токен REVIEWER_TOKEN, НЕ админский
# GITEA_TOKEN. Если REVIEWER_TOKEN не передан, секрет не трогаем.
put_secret() {
  local data_json="$1" label="$2"
  api PUT "/actions/secrets/REVIEWER_TOKEN" "$data_json"
  if [[ "$RESP_CODE" == "201" || "$RESP_CODE" == "204" || "$RESP_CODE" == "200" ]]; then
    log "secret REVIEWER_TOKEN создан/обновлён ($label)"
    return 0
  fi
  return 1
}

if [[ -z "$REVIEWER_TOKEN" ]]; then
  log "REVIEWER_TOKEN не задан — Actions secret не трогаю (предполагается, что он уже создан бот-агентом)"
else
  log "обновляю Actions secret REVIEWER_TOKEN"
  PLAIN_JSON="$(REVIEWER_TOKEN="$REVIEWER_TOKEN" python3 -c 'import json,os; print(json.dumps({"data": os.environ["REVIEWER_TOKEN"]}))')"
  if ! put_secret "$PLAIN_JSON" "plain"; then
    code="$RESP_CODE"
    log "plain secret API ответил HTTP $code — пробую base64 (совместимость)"
    B64_JSON="$(REVIEWER_TOKEN="$REVIEWER_TOKEN" python3 -c 'import base64,json,os; print(json.dumps({"data": base64.b64encode(os.environ["REVIEWER_TOKEN"].encode()).decode()}))')"
    if ! put_secret "$B64_JSON" "base64"; then
      log "ERROR: не удалось создать secret REVIEWER_TOKEN (HTTP $RESP_CODE)"
      printf '%s\n' "$RESP_BODY" | head -c 600 >&2 || true
      echo >&2
      log "Проверьте, что Actions включены и у админ-токена есть права admin на repo."
      exit 1
    fi
    log "внимание: инстанс принял base64-вариант data; workflow получит исходный токен"
  fi
fi

log "готово: dev + protections(main, dev) + secret REVIEWER_TOKEN (если задан)"
