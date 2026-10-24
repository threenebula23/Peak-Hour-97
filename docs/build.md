# Сборка и проверки

## Переменные окружения

```bash
export GODOT=/home/eq/techlb/tools/godot/Godot_v4.7.2-stable_linux.x86_64
export PROJECT=/home/eq/techlb/peak-hour
```

Секретов проект не требует. Если позже появится деплой в CI — токены только
через CI/CD-переменные (masked/protected), не в файлах репозитория.

## 1. Проверка парсинга и импорта

Сразу после клона (`.godot/` не хранится в git) выполнить импорт ассетов:

```bash
"$GODOT" --headless --path "$PROJECT" --import
```

Первый прогон `--import` может один раз ругнуться на отсутствующий
`.godot/imported/...` для шрифта (тема грузится до импорта) — это ожидаемо;
повторный прогон и обычный запуск проходят без ошибок.

```bash
"$GODOT" --headless --path "$PROJECT" --quit
```

Ожидаемо: нет `SCRIPT ERROR` / `Parse Error`. Каталог `.godot/` в `.gitignore`.

## 2. Web-экспорт

```bash
mkdir -p "$PROJECT/build/web"
"$GODOT" --headless --path "$PROJECT" \
  --export-release "Web" "$PROJECT/build/web/index.html"
```

Проверка артефактов:

```bash
ls -lh "$PROJECT/build/web"
```

Нужны минимум `index.html`, `index.wasm`, `index.pck`.

Требование к окружению: export templates 4.7.2
(`~/.local/share/godot/export_templates/4.7.2.stable/web_nothreads_release.zip`).

## 3. Локальный просмотр билда

```bash
python3 -m http.server 8000 --directory "$PROJECT/build/web"
```

Открыть `http://localhost:8000`. Пресет собран без threads, поэтому
COOP/COEP-заголовки не нужны.

## 4. Частые проблемы

| Симптом | Причина | Решение |
| --- | --- | --- |
| `Could not find template` / `No export template` | нет шаблонов 4.7.2 | установить export templates нужной версии |
| `Export preset "Web" not found` | пресет переименован/удалён | сверить `name="Web"` в `export_presets.cfg` |
| Пустая/белая страница в браузере | открыт `file://` | запускать через HTTP-сервер |
| `SharedArrayBuffer` ошибки | включены threads | держать `variant/thread_support=false` |
| Шрифт «квадратики» | нет глифов (Pixelify Sans: П/О) | использовать Press Start 2P / доп. шрифт |

## Откат

Каркас не трогает прод. Откат локальный:

```bash
git -C "$PROJECT" log --oneline           # выбрать целевой коммит
git -C "$PROJECT" revert <commit>         # безопасно, без reset --hard
```
