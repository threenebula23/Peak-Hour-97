# AI_REPORT — PEAK HOUR 97

## 1. Инструменты и модели

Работа велась в **OpenCode** с субагентами (backend, frontend, designer,
test-writer, explorer, feis-regulator, oracle):

| Модель | Роль |
| --- | --- |
| **DeepSeek V4.1 Flash** | оркестратор, основной код Godot/GDScript |
| **GLM-5.3-Flash** | документация, RU-тексты, данные |
| **MiniMax M3.1 Flash** | баланс, экономика, прогрессия |
| **MiMo-V2.6-Flash** | аудио: SFX, ambient, фон |
| дефолтные модели субагентов | поиск, тесты, ревью |

MR-ревью — агент **oracle** (`opencode-go/deepseek-v4.1-flash`): dry-run
74–90 с, комментарий в MR, без мержа.

## 2. Где применялся ИИ

- **Код:** `GameController`, `HourDirector`, `AttackDirector`, `Shop`,
  `SaveManager`, UI, мини-игры.
- **UI v2:** Kaleidos, маскот **БАЙТ**, туториал.
- **Ambient:** 4 WAV (`audio/amb`, PSU/fan/room/seek), генератор
  `generate_ambient.py`, autoload после первого жеста, mute/пауза/громкость.
- **VHS:** `shaders/vhs.gdshader` + `vhs_overlay.gd`, только главное меню,
  чекбокс в настройках, HEADLESS без рендера.
- **Баланс/мета:** SLA, 10 апгрейдов, таймеры, канал, мета 3/5/9.
- **Аудит:** calm-фон, Esc итогов, уничтожение, тосты/fullscreen.
- **Тесты/доки/звук:** unit/fuzz/интеграция/полный забег; `docs/`;
  18 SFX + `hum.wav` на Python.

## 3. Приём: «враждебный критик»

Промпт просил быть враждебным критиком: «найди блокеры, из-за которых
прототип нельзя собрать; не хвали». Нашлось **6 блокеров**. Один из них:
выбор мини-игры по самому сложному типу ломал смешанные запросы. Заменили на
средний коэффициент:

```
difficulty = sum(coeff(required)) / n
coeff = {text: 1.0, sound: 2.0, photo: 3.0, video: 4.0}
```

Это изменило §8.4 и §10 GDD и решение D17; пороги `<1.5 / <2.5 / <3.5`
зафиксированы в `data/balance.json` и проверяются в `test_minigame.gd`.

## 4. Что сделано без ИИ

Идея, логлайн, исходная спецификация, ключевые решения (1997 год, 9 часов,
4 атаки, экономика, тон 90-х) и финальная приёмка — человеком, автором
проекта. ИИ не придумывал игру: он помогал формулировать, писать код,
считать баланс и искать противоречия.

## 5. Ассеты и лицензии

- **Handjet** и **Press Start 2P** — SIL OFL 1.1, тексты в
  `art/fonts/OFL-Handjet.txt` и `OFL-PressStart2P.txt`.
- Pixelify Sans в теме не используется (нет глифов `О`/`П`); файл и OFL
  оставлены в `art/fonts/`.
- UI, иконки и `icon.svg` — команда проекта, MIT.
- SFX, ambient и `hum.wav` — скрипты проекта, MIT/CC0.
- Код — MIT (`LICENSE`); OFL-шрифты совместимы с MIT при сохранении
  лицензий. Подробности — в `ASSETS.md`.

## 6. Проверки и ограничения

- **22/22 PASS** (21 тест + parse). Core 543, hour 133, shop 116, minigame
  51, slots 34, audio 37; fuzz 3249, integration 231, attacks 173,
  controller 143.
- `test_full_playthrough` — 294 на сидах `1/42/777`: 3/3 victory, 9/9,
  SLA 200; main 350, toast 14, fullscreen 31, ui 135, ambient 74.
- Web-экспорт — exit 0; Chromium **1920×1080**: меню → «Новый забег» →
  подготовка, JS-ошибок нет.

Ограничения: туториал — маскот и подсказки; web-save — IndexedDB; плейтест,
громкость и масштаб — за человеком; remote push ещё не выполнен.
