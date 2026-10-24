# tests/

Каталог под автотесты. Пока пусто: реализации, которую стоит тестировать, нет.

План:

- чистая логика (`scripts/core`, `scripts/systems`) — юнит-тесты на GDScript,
  запуск headless;
- данные (`data/*.json`) — валидация схемы/ключей;
- дымовой тест — `--headless --quit` без ошибок парсинга (см. `docs/build.md`).

Запуск заготовки (когда появится фреймворк, например GUT/GdUnit4):

```bash
/home/eq/techlb/tools/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path . --quit
```
