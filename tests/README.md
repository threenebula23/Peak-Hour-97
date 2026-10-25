# tests/

Headless-автотесты и симулятор баланса.

## Полный прогон

```bash
bash scripts/run_all_tests.sh
# Windows:
powershell -ExecutionPolicy Bypass -File scripts/run_all_tests.ps1
```

Скрипт запускает **25 headless-наборов + parse-check** (итого 26 проверок),
каждый в отдельном процессе Godot с таймаутом и в изолированных временных
XDG-каталогах. Отсутствующие файлы тестов помечаются `SKIP`, а не `FAIL`.
Путь к Godot задаётся через `GODOT_BIN` (иначе ищется `godot4`/`godot` в
`PATH`). Подробности — в `README` §Тесты и в самом `scripts/run_all_tests.sh`.

## Что покрыто

- **Ядро и экономика:** `run_tests.gd`, `test_hour.gd`, `test_slots.gd`,
  `test_shop.gd`, `test_attacks.gd`, `test_fuzz.gd`, `test_integration.gd`,
  `test_controller.gd`.
- **UI:** `scripts/ui/ui_smoke.gd`, `test_file_grid.gd`,
  `test_shop_modal.gd`, `test_toast.gd`.
- **Мини-игры:** `test_minigame.gd`, `test_send_games.gd`,
  `test_attack_games.gd`.
- **Сцены и полный забег:** `test_main_*.gd`, `test_full_playthrough.gd`.
- **Аудио:** `test_audio.gd`, `test_ambient.gd`.
- **Баланс:** `sim_balance.py` — 240 сидов, 9 часов; отчёт
  `tests/SIM_BALANCE_REPORT.md`.

Полный список наборов — в массиве `TESTS` внутри `scripts/run_all_tests.sh`.

## Одиночный запуск

```bash
export XDG_DATA_HOME="$(mktemp -d)"
"$GODOT" --headless --path . --script tests/run_tests.gd
```

Используйте уникальный `XDG_DATA_HOME` на каждый запуск: сейвы и настройки
Godot иначе пересекаются с реальным профилем и между прогонами, что даёт
нестабильные результаты.

Симулятор баланса запускается обычным Python 3 без зависимостей:

```bash
python3 tests/sim_balance.py
```
