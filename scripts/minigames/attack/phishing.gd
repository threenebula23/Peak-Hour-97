class_name PhishingGame
extends MiniGame
## Атака «Паспорт» (phishing). Очередь клиентов: две «бумаги» — заявка и
## пропуск. Игрок сверяет поля и жмёт ВЫДАТЬ или ОТКАТАТЬ.
##
## У каждого клиента ровно один правильный ответ. Подделка отличается ровно
## одним проверяемым полем (имя / отдел / ID / срок действия), причём ID
## использует кириллическую похожую букву. Отмена решения невозможна,
## таймера нет; после решения — короткая печать 0.12 с.
##
## Качество: q = correct / total_clients.

const GAME_ID := "phishing"
const TITLE_RU := "ПАСПОРТ"

const ISSUE_RECT := Rect2(142.0, 274.0, 166.0, 30.0)
const DENY_RECT := Rect2(332.0, 274.0, 166.0, 30.0)
const FILE_RECT := Rect2(24.0, 62.0, 286.0, 206.0)
const PASS_RECT := Rect2(330.0, 62.0, 286.0, 206.0)
const STAMP_TTL := 0.12

const TIERS := {
	1: {"clients": 3, "checks": ["name"], "threshold": 0.75},
	2: {"clients": 4, "checks": ["name", "department"], "threshold": 0.75},
	3: {"clients": 5, "checks": ["name", "department", "id"], "threshold": 0.80},
	4: {"clients": 6, "checks": ["name", "department", "id", "photo", "expiry"],
		"threshold": 0.80},
}

const PEOPLE := [
	{"surname": "Иванов", "first": "Пётр", "female": false},
	{"surname": "Смирнова", "first": "Анна", "female": true},
	{"surname": "Кузнецов", "first": "Илья", "female": false},
	{"surname": "Попова", "first": "Мария", "female": true},
	{"surname": "Соколов", "first": "Артём", "female": false},
	{"surname": "Лебедева", "first": "Ольга", "female": true},
	{"surname": "Новиков", "first": "Денис", "female": false},
	{"surname": "Морозова", "first": "Вера", "female": true},
	{"surname": "Волков", "first": "Сергей", "female": false},
	{"surname": "Зайцева", "first": "Нина", "female": true},
	{"surname": "Павлов", "first": "Максим", "female": false},
	{"surname": "Орлова", "first": "Елена", "female": true},
	{"surname": "Фёдоров", "first": "Олег", "female": false},
	{"surname": "Егорова", "first": "Ирина", "female": true},
	{"surname": "Белов", "first": "Антон", "female": false},
	{"surname": "Гусева", "first": "Дарья", "female": true},
	{"surname": "Тихонов", "first": "Роман", "female": false},
	{"surname": "Киселёва", "first": "Света", "female": true},
	{"surname": "Борисов", "first": "Кирилл", "female": false},
	{"surname": "Андреева", "first": "Таня", "female": true},
]

const DEPARTMENTS := [
	"БУХГАЛТЕРИЯ", "ОТДЕЛ КАДРОВ", "ЛОГИСТИКА", "ПРОДАЖИ", "ИТ-ОТДЕЛ",
	"ЮРОТДЕЛ", "СКЛАД", "ДИСПЕТЧЕРСКАЯ", "АРХИВ", "СНАБЖЕНИЕ",
	"КЛИЕНТСКИЙ ОТДЕЛ", "ТРАНСПОРТ",
]

## ASCII → кириллический двойник. ID всегда содержит буквы из ключей.
const LOOKALIKE := {
	"A": "А", "B": "В", "C": "С", "E": "Е", "H": "Н", "K": "К",
	"M": "М", "O": "О", "P": "Р", "T": "Т", "X": "Х", "Y": "У",
}
const ID_LETTERS := "ABEKMHOPCTX"

const CHECK_LABELS := {
	"name": "ИМЯ",
	"dept": "ОТДЕЛ",
	"id": "ID",
	"expiry": "СРОК",
	"photo": "ФОТО",
}

var _clients: Array = []
var _index: int = 0
var _correct: int = 0
var _wrong: int = 0
var _stamp_ttl: float = 0.0
var _last_ok: bool = false
var _last_choice: String = ""
var _hover: String = ""


func _own_game_id() -> String:
	return GAME_ID


func title() -> String:
	return TITLE_RU


func quality() -> float:
	if _finished:
		return quality_value
	return phishing_quality(_correct, _clients.size())


func _setup() -> void:
	_clients = generate_clients(tier, seed_value)
	_index = 0
	_correct = 0
	_wrong = 0
	_stamp_ttl = 0.0
	_last_ok = false
	_last_choice = ""
	_hover = ""
	mouse_default_cursor_shape = Control.CURSOR_ARROW


# --- параметры -------------------------------------------------------------

static func tier_params(p_tier: int) -> Dictionary:
	var t := clampi(p_tier, 1, 4)
	var base: Dictionary = (TIERS.get(t, TIERS[1]) as Dictionary).duplicate(true)
	var row := MiniGame.data_minigame_tier(GAME_ID, t)
	if row.is_empty():
		base["checks"] = _normalized_checks(base.get("checks", []))
		return base
	if row.has("clients"):
		base["clients"] = int(row["clients"])
	if row.has("checks"):
		base["checks"] = _normalized_checks(row["checks"])
	else:
		base["checks"] = _normalized_checks(base.get("checks", []))
	if row.has("threshold"):
		base["threshold"] = float(row["threshold"])
	return base


static func _normalized_checks(raw) -> Array:
	var out: Array = []
	if raw is Array:
		for entry in raw:
			match str(entry).to_lower():
				"name":
					if not out.has("name"):
						out.append("name")
				"department", "dept":
					if not out.has("dept"):
						out.append("dept")
				"id":
					if not out.has("id"):
						out.append("id")
				"expiry", "expires", "date":
					if not out.has("expiry"):
						out.append("expiry")
				"photo", "avatar":
					if not out.has("photo"):
						out.append("photo")
	if out.is_empty():
		out = ["name"]
	return out


# --- генерация -------------------------------------------------------------

static func generate_clients(p_tier: int, seed: int) -> Array:
	var t := clampi(p_tier, 1, 4)
	var p := tier_params(t)
	var total := clampi(int(p.get("clients", 3)), 2, 12)
	var clients: Array = []
	for i in range(total):
		clients.append(generate_client(t, seed, i, -1))

	var valid_count := 0
	var fake_count := 0
	for client in clients:
		if bool((client as Dictionary).get("valid", true)):
			valid_count += 1
		else:
			fake_count += 1
	if fake_count == 0 and total >= 2:
		clients[0] = generate_client(t, seed, 0, 1)
	elif valid_count == 0 and total >= 2:
		clients[0] = generate_client(t, seed, 0, 0)
	return clients


## force_fake: -1 — случайно, 0 — честный, 1 — подделка.
static func generate_client(p_tier: int, seed: int, index: int = 0,
		force_fake: int = -1) -> Dictionary:
	var t := clampi(p_tier, 1, 4)
	var p := tier_params(t)
	var checks: Array = p.get("checks", ["name"])
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + index * 104729 + 17

	var person: Dictionary = PEOPLE[rng.randi_range(0, PEOPLE.size() - 1)]
	var dept := str(DEPARTMENTS[rng.randi_range(0, DEPARTMENTS.size() - 1)])
	var id_value := _make_id(rng)
	var expiry := _random_expiry(rng)
	var photo := {
		"jacket": rng.randi_range(0, 3),
		"hair": rng.randi_range(0, 3),
		"skin": rng.randi_range(0, 2),
		"female": bool(person.get("female", false)),
	}
	var full_name := "%s %s" % [str(person.get("surname", "")), str(person.get("first", ""))]

	var file_data := {
		"name": full_name,
		"dept": dept,
		"id": id_value,
		"expiry": expiry,
		"photo": photo.duplicate(true),
	}
	var pass_data := {
		"name": full_name,
		"dept": dept,
		"id": id_value,
		"expiry": expiry,
		"photo": photo.duplicate(true),
	}

	var make_fake := false
	if force_fake == 1:
		make_fake = true
	elif force_fake == 0:
		make_fake = false
	else:
		make_fake = rng.randf() < 0.5

	var mismatch := ""
	if make_fake:
		var kinds: Array = []
		for check in checks:
			if check in ["name", "dept", "id", "expiry"]:
				kinds.append(str(check))
		if kinds.is_empty():
			kinds = ["name"]
		var kind := str(kinds[rng.randi_range(0, kinds.size() - 1)])
		_apply_fake(pass_data, kind, rng)
		mismatch = kind

	return {
		"id": index,
		"file": file_data,
		"pass": pass_data,
		"mismatch": mismatch,
		"valid": mismatch.is_empty(),
		"expected": "deny" if not mismatch.is_empty() else "issue",
		"checks": checks.duplicate(),
	}


static func _apply_fake(pass_data: Dictionary, kind: String, rng: RandomNumberGenerator) -> void:
	match kind:
		"name":
			var full := str(pass_data.get("name", ""))
			var space := full.find(" ")
			if space > 0:
				pass_data["name"] = _surname_variant(full.substr(0, space)) + full.substr(space)
			else:
				pass_data["name"] = _surname_variant(full)
		"dept":
			var current := str(pass_data.get("dept", ""))
			var current_index := DEPARTMENTS.find(current)
			if current_index < 0:
				current_index = 0
			var offset := rng.randi_range(1, DEPARTMENTS.size() - 1)
			pass_data["dept"] = str(DEPARTMENTS[(current_index + offset) % DEPARTMENTS.size()])
		"id":
			pass_data["id"] = _lookalike_id(str(pass_data.get("id", "")))
		"expiry":
			pass_data["expiry"] = _shift_expiry(str(pass_data.get("expiry", "")))


static func _surname_variant(surname: String) -> String:
	if surname.ends_with("ов") or surname.ends_with("ев") or surname.ends_with("ин"):
		return surname + "а"
	if surname.ends_with("а"):
		return surname.substr(0, surname.length() - 1)
	return surname + "а"


static func _make_id(rng: RandomNumberGenerator) -> String:
	var out := "id_"
	out += ID_LETTERS[rng.randi_range(0, ID_LETTERS.length() - 1)]
	out += str(rng.randi_range(0, 9))
	out += str(rng.randi_range(0, 9))
	out += ID_LETTERS[rng.randi_range(0, ID_LETTERS.length() - 1)]
	return out


static func _lookalike_id(id_value: String) -> String:
	for i in range(id_value.length()):
		var ch := id_value.substr(i, 1)
		if LOOKALIKE.has(ch):
			return id_value.substr(0, i) + str(LOOKALIKE[ch]) + id_value.substr(i + 1)
	return id_value + "К"


static func _random_expiry(rng: RandomNumberGenerator) -> String:
	var day := rng.randi_range(1, 28)
	var month := rng.randi_range(1, 12)
	var year := 97 + rng.randi_range(0, 1)
	return "%02d.%02d.%02d" % [day, month, year]


static func _shift_expiry(value: String) -> String:
	var parts := value.split(".")
	if parts.size() != 3:
		return "01.01.98"
	var day := clampi(int(parts[0]), 1, 28)
	var month := clampi(int(parts[1]), 1, 12)
	var year := int(parts[2])
	if year >= 98:
		year = 97
	else:
		year += 1
	return "%02d.%02d.%02d" % [day, month, year]


# --- проверка --------------------------------------------------------------

static func _same_photo(a: Dictionary, b: Dictionary) -> bool:
	return int(a.get("jacket", -1)) == int(b.get("jacket", -2)) \
		and int(a.get("hair", -1)) == int(b.get("hair", -2)) \
		and int(a.get("skin", -1)) == int(b.get("skin", -2)) \
		and bool(a.get("female", false)) == bool(b.get("female", true))


static func client_diff_fields(client: Dictionary) -> Array:
	var out: Array = []
	var file_data: Dictionary = client.get("file", {})
	var pass_data: Dictionary = client.get("pass", {})
	for field in ["name", "dept", "id", "expiry"]:
		if str(file_data.get(field, "")) != str(pass_data.get(field, "")):
			out.append(field)
	if not _same_photo(file_data.get("photo", {}), pass_data.get("photo", {})):
		out.append("photo")
	return out


static func validate_client(client: Dictionary, p_tier: int) -> bool:
	var checks: Array = tier_params(p_tier).get("checks", ["name"])
	var diffs := client_diff_fields(client)
	if diffs.size() > 1:
		return false
	var valid_now := diffs.is_empty()
	if valid_now != bool(client.get("valid", false)):
		return false
	if str(client.get("expected", "")) != ("issue" if valid_now else "deny"):
		return false
	if not valid_now:
		if not checks.has(str(diffs[0])):
			return false
		if str(client.get("mismatch", "")) != str(diffs[0]):
			return false
	else:
		if not str(client.get("mismatch", "")).is_empty():
			return false
	return true


static func validate_clients(clients: Array, p_tier: int) -> bool:
	if clients.is_empty():
		return false
	for client in clients:
		if not validate_client(client, p_tier):
			return false
	return true


static func phishing_quality(correct: int, total_clients: int) -> float:
	if total_clients <= 0:
		return 0.0
	return clampf(float(correct) / float(total_clients), 0.0, 1.0)


# --- игра ------------------------------------------------------------------

func _current_client() -> Dictionary:
	if _index < 0 or _index >= _clients.size():
		return {}
	return _clients[_index]


func _decide(choice: String) -> void:
	if _finished or _stamp_ttl > 0.0:
		return
	var client := _current_client()
	if client.is_empty():
		return
	var expected := "issue" if bool(client.get("valid", false)) else "deny"
	var ok := choice == expected
	if ok:
		_correct += 1
	else:
		_wrong += 1
	_last_ok = ok
	_last_choice = choice
	_stamp_ttl = STAMP_TTL
	_hover = ""
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	_play_sfx(&"ok" if ok else &"bad")
	queue_redraw()


func _advance() -> void:
	_index += 1
	_last_ok = false
	_last_choice = ""
	if _index >= _clients.size():
		var q := phishing_quality(_correct, _clients.size())
		_result_detail = _with_context("ВЕРНО %d ИЗ %d · ОШИБОК %d" % [
			_correct, _clients.size(), _wrong])
		_finish(q)
	else:
		queue_redraw()


func _with_context(text: String) -> String:
	var parts: Array = []
	var reward := str(context.get("reward_text", ""))
	var penalty := str(context.get("penalty_text", ""))
	if not reward.is_empty():
		parts.append(reward)
	if not penalty.is_empty():
		parts.append(penalty)
	parts.append(text)
	return " · ".join(parts)


func _process(delta: float) -> void:
	if _finished:
		return
	if _stamp_ttl <= 0.0:
		return
	_stamp_ttl = maxf(0.0, _stamp_ttl - delta)
	if _stamp_ttl <= 0.0:
		_advance()
	queue_redraw()


func _on_pointer_pressed(local: Vector2, _event: InputEvent) -> bool:
	if _finished or _stamp_ttl > 0.0:
		return false
	if ISSUE_RECT.has_point(local):
		_decide("issue")
		return true
	if DENY_RECT.has_point(local):
		_decide("deny")
		return true
	return false


func _on_pointer_moved(local: Vector2, _event: InputEvent) -> void:
	if _finished:
		return
	var next := ""
	if _stamp_ttl <= 0.0:
		if ISSUE_RECT.has_point(local):
			next = "issue"
		elif DENY_RECT.has_point(local):
			next = "deny"
	if next != _hover:
		_hover = next
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if not next.is_empty() \
			else Control.CURSOR_ARROW
		queue_redraw()


func _on_key_pressed(keycode: int, _event: InputEvent) -> bool:
	if _finished or _stamp_ttl > 0.0:
		return false
	match keycode:
		KEY_1, KEY_A:
			_decide("issue")
			return true
		KEY_2, KEY_D:
			_decide("deny")
			return true
	return false


# --- отрисовка -------------------------------------------------------------

func _draw_game() -> void:
	var total := _clients.size()
	var shown := mini(_index + 1, total)
	_draw_label("КЛИЕНТ %d / %d" % [shown, total], Vector2(24.0, 44.0), 12,
		Theme90.INK, 220.0)
	_draw_label("ВЕРНО %d · ОШИБОК %d" % [_correct, _wrong], Vector2(380.0, 44.0),
		12, Theme90.ERROR if _wrong > 0 else Theme90.SHADE, 230.0,
		HORIZONTAL_ALIGNMENT_RIGHT)

	var client := _current_client()
	if client.is_empty():
		_draw_label("ОЧЕРЕДЬ ОБРАБОТАНА", Vector2(24.0, 140.0), 24, Theme90.NAVY_DEEP, 604.0,
			HORIZONTAL_ALIGNMENT_CENTER)
		return

	_draw_file(FILE_RECT, client)
	_draw_pass(PASS_RECT, client)
	_draw_action_button(ISSUE_RECT, "ВЫДАТЬ", true, true)
	_draw_action_button(DENY_RECT, "ОТКАТАТЬ", true, false)
	if _hover == "issue":
		draw_rect(ISSUE_RECT.grow(2.0), Theme90.ACCENT, false, 2.0)
	elif _hover == "deny":
		draw_rect(DENY_RECT.grow(2.0), Theme90.ACCENT, false, 2.0)

	if _stamp_ttl > 0.0:
		_draw_stamp()


func _draw_file(rect: Rect2, client: Dictionary) -> void:
	draw_style_box(Theme90.box(Theme90.PAPER_HI, Theme90.BORDER, 4, 1, Theme90.SHADOW), rect)
	_draw_paper_header(rect, "ЗАЯВКА")
	var data: Dictionary = client.get("file", {})
	var x := rect.position.x + 14.0
	var w := rect.size.x - 90.0
	_draw_avatar(Rect2(rect.end.x - 68.0, rect.position.y + 30.0, 54.0, 66.0),
		data.get("photo", {}))
	Theme90.text(self, Theme90.ui(), Vector2(x, rect.position.y + 30.0), "ВЛАДЕЛЕЦ",
		10, Theme90.NAVY_DEEP, w)
	Theme90.text(self, Theme90.ui(), Vector2(x, rect.position.y + 42.0),
		Theme90.fit(Theme90.ui(), str(data.get("name", "")), 16, w), 16, Theme90.INK, w)
	Theme90.text(self, Theme90.ui(), Vector2(x, rect.position.y + 72.0), "ОТДЕЛ",
		10, Theme90.NAVY_DEEP, w)
	Theme90.text(self, Theme90.ui(), Vector2(x, rect.position.y + 84.0),
		Theme90.fit(Theme90.ui(), str(data.get("dept", "")), 12, w), 12, Theme90.DARK, w)
	Theme90.text(self, Theme90.ui(), Vector2(x, rect.position.y + 110.0), "ID",
		10, Theme90.NAVY_DEEP, w)
	Theme90.text(self, Theme90.ui(), Vector2(x, rect.position.y + 122.0),
		str(data.get("id", "")), 12, Theme90.DARK, w)
	Theme90.text(self, Theme90.ui(), Vector2(x, rect.position.y + 148.0), "ДЕЙСТВУЕТ ДО",
		10, Theme90.NAVY_DEEP, w)
	Theme90.text(self, Theme90.ui(), Vector2(x, rect.position.y + 160.0),
		str(data.get("expiry", "")), 12, Theme90.DARK, w)


func _draw_pass(rect: Rect2, client: Dictionary) -> void:
	draw_style_box(Theme90.box(Theme90.PAPER_HI, Theme90.BORDER, 4, 1, Theme90.SHADOW), rect)
	_draw_paper_header(rect, "ПРОПУСК")
	var data: Dictionary = client.get("pass", {})
	_draw_avatar(Rect2(rect.position.x + 14.0, rect.position.y + 32.0, 58.0, 72.0),
		data.get("photo", {}))
	var x := rect.position.x + 84.0
	var w := rect.size.x - 98.0
	Theme90.text(self, Theme90.ui(), Vector2(x, rect.position.y + 36.0),
		Theme90.fit(Theme90.ui(), str(data.get("name", "")), 16, w), 16, Theme90.INK, w)
	Theme90.text(self, Theme90.ui(), Vector2(x, rect.position.y + 68.0),
		Theme90.fit(Theme90.ui(), str(data.get("dept", "")), 12, w), 12, Theme90.DARK, w)
	Theme90.text(self, Theme90.ui(), Vector2(x, rect.position.y + 94.0),
		str(data.get("id", "")), 12, Theme90.DARK, w)
	Theme90.text(self, Theme90.ui(), Vector2(x, rect.position.y + 120.0),
		"СРОК " + str(data.get("expiry", "")), 12, Theme90.DARK, w)
	var checks: Array = client.get("checks", [])
	var check_text := "ПРОВЕРКА: "
	var labels: Array = []
	for check in checks:
		labels.append(str(CHECK_LABELS.get(str(check), str(check))))
	check_text += " · ".join(labels)
	Theme90.text(self, Theme90.ui(), Vector2(x, rect.position.y + 150.0),
		Theme90.fit(Theme90.ui(), check_text, 10, w), 10, Theme90.SHADE, w)


func _draw_paper_header(rect: Rect2, text: String) -> void:
	var header := Rect2(rect.position, Vector2(rect.size.x, 20.0))
	draw_style_box(Theme90.top_box(Theme90.NAVY, 4), header)
	draw_rect(Rect2(header.position.x, header.end.y - 1.0, header.size.x, 1.0),
		Theme90.NAVY_DEEP)
	Theme90.text(self, Theme90.ui(), Vector2(header.position.x + 10.0,
		header.position.y + 5.0), text, 10, Theme90.WHITE, header.size.x - 20.0)


func _draw_avatar(rect: Rect2, photo: Dictionary) -> void:
	draw_style_box(Theme90.box(Theme90.ACCENT_PALE, Theme90.BORDER, 2, 1), rect)
	var jackets := [Theme90.NAVY, Theme90.ACCENT, Color(0.43, 0.48, 0.37), Color(0.48, 0.41, 0.36)]
	var hairs := [Color(0.23, 0.21, 0.18), Color(0.35, 0.29, 0.23), Color(0.42, 0.38, 0.35),
		Color(0.18, 0.23, 0.27)]
	var skins := [Color(0.85, 0.76, 0.65), Color(0.79, 0.68, 0.56), Color(0.88, 0.80, 0.71)]
	var jacket: Color = jackets[clampi(int(photo.get("jacket", 0)), 0, jackets.size() - 1)]
	var hair: Color = hairs[clampi(int(photo.get("hair", 0)), 0, hairs.size() - 1)]
	var skin: Color = skins[clampi(int(photo.get("skin", 0)), 0, skins.size() - 1)]
	var cx := rect.get_center().x
	var bottom := rect.end.y - 3.0
	draw_colored_polygon(PackedVector2Array([
		Vector2(cx - 22.0, bottom), Vector2(cx - 14.0, bottom - 24.0),
		Vector2(cx + 14.0, bottom - 24.0), Vector2(cx + 22.0, bottom)]), jacket)
	draw_rect(Rect2(cx - 4.0, bottom - 38.0, 8.0, 14.0), skin)
	draw_circle(Vector2(cx, bottom - 44.0), 11.0, skin)
	draw_circle(Vector2(cx, bottom - 46.0), 11.0, hair)
	draw_rect(Rect2(cx - 10.0, bottom - 46.0, 20.0, 8.0), skin)
	if bool(photo.get("female", false)):
		draw_rect(Rect2(cx - 12.0, bottom - 42.0, 4.0, 12.0), hair)
		draw_rect(Rect2(cx + 8.0, bottom - 42.0, 4.0, 12.0), hair)


func _draw_stamp() -> void:
	var label := "ВЕРНО" if _last_ok else "ПРОМАХ"
	var color := Theme90.SUCCESS if _last_ok else Theme90.ERROR
	var rect := Rect2(250.0, 148.0, 140.0, 36.0)
	draw_style_box(Theme90.box(Theme90.PAPER_HI, color, 4, 2, Theme90.SHADOW), rect)
	Theme90.text_vcenter(self, Theme90.ui(), rect, label, 16, color, -1,
		HORIZONTAL_ALIGNMENT_CENTER)


func _draw_footer_hint() -> void:
	if _finished:
		return
	var checks: Array = tier_params(tier).get("checks", ["name"])
	var labels: Array = []
	for check in checks:
		labels.append(str(CHECK_LABELS.get(str(check), str(check))))
	_draw_label("СВЕРЬТЕ: " + " · ".join(labels), Vector2(18.0, 350.0), 10,
		Theme90.SHADE, 604.0)
