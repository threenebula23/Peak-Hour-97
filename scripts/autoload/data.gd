extends Node
## Data — доступ к JSON-данным из res://data (autoload).
##
## TODO: ленивая загрузка и кэширование balance.json / strings_ru.json / names_ru.json.
## Пока это заглушка: ничего не читает и не парсит.

const DATA_DIR := "res://data"

var _cache: Dictionary = {}


## TODO: вернуть словарь из data/<name>.json (с кэшем).
func load_json(_file_name: String) -> Dictionary:
	return {}


## TODO: строка локализации по ключу.
func text(_key: StringName) -> String:
	return ""
