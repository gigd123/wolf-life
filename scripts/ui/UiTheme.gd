class_name UiTheme
extends RefCounted

# 介面外觀集中在 assets/ui/theme.tres（project.godot 的 gui/theme/custom）：
# - 樣式變體：元件設 theme_type_variation（例如 "HintLabel"、"OverlayPanel"），字級、顏色、底色都在 theme.tres 改
# - 調色盤：Theme 管不到的顏色（ColorRect 底色、BBCode 文字色、RichTextLabel 的整體調色）放在 Palette 類型，用這裡取
# 換正式美術（HD-2D）時改 theme.tres 就好，不用動程式。

const PALETTE := "Palette"


static func color(name: String) -> Color:
	var theme := ThemeDB.get_project_theme()
	if theme != null and theme.has_color(name, PALETTE):
		return theme.get_color(name, PALETTE)
	push_warning("UiTheme：theme.tres 的 Palette 沒有顏色 " + name)
	return Color.WHITE


# BBCode 用的 #rrggbb
static func html(name: String) -> String:
	return "#" + color(name).to_html(false)
