extends RefCounted

static func apply(tabs: TabContainer) -> void:
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color("efdbb6")
	panel.border_color = Color("ad9068")
	panel.set_border_width_all(1)
	panel.content_margin_left = 12
	panel.content_margin_right = 12
	panel.content_margin_top = 12
	panel.content_margin_bottom = 12
	tabs.add_theme_stylebox_override("panel", panel)
	for state: String in ["tab_selected", "tab_unselected", "tab_hovered"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color("efdbb6") if state == "tab_selected" else Color("d5b88d")
		if state == "tab_hovered": box.bg_color = Color("e7cda2")
		box.border_color = Color("6b5138") if state == "tab_selected" else Color("ad9068")
		box.set_border_width_all(1)
		box.content_margin_left = 16
		box.content_margin_right = 16
		box.content_margin_top = 9
		box.content_margin_bottom = 9
		tabs.add_theme_stylebox_override(state, box)
		tabs.get_tab_bar().add_theme_stylebox_override(state, box)
	for control: Control in [tabs, tabs.get_tab_bar()]:
		control.add_theme_font_size_override("font_size", 16)
		for key: String in ["font_selected_color", "font_unselected_color", "font_hovered_color"]:
			control.add_theme_color_override(key, Color("392c21"))
