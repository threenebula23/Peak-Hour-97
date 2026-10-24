extends SceneTree
## Dev-инструмент: пересобирает art/fonts/ui_theme.tres из Theme90.
## godot --headless --path . --script scripts/ui/build_theme.gd

func _initialize() -> void:
	var theme := Theme90.build_theme()
	var err := ResourceSaver.save(theme, "res://art/fonts/ui_theme.tres")
	print("ui_theme.tres saved: err=", err, " font=", theme.default_font, " size=", theme.default_font_size)
	quit(0 if err == OK else 1)
