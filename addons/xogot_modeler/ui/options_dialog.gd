@tool
extends AcceptDialog

## The Modeler's Options: a category list and the category's settings.
## Changes apply at once and are saved in the editor settings.

const ParameterForm := preload("parameter_form.gd")

var bridge: RefCounted

var _categories: ItemList
var _form: ParameterForm


func setup(native_bridge: RefCounted) -> void:
	bridge = native_bridge
	title = tr("Modeler Options")
	ok_button_text = tr("Close")
	add_button(tr("Reset to Defaults"), true, "reset")
	custom_action.connect(func(action: StringName) -> void:
		if action == &"reset":
			bridge.reset_preferences()
			_form.refresh())

	var split := HSplitContainer.new()
	add_child(split)
	_categories = ItemList.new()
	_categories.custom_minimum_size.x = 200 * EditorInterface.get_editor_scale()
	_categories.item_selected.connect(_on_category_selected)
	split.add_child(_categories)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(scroll)
	_form = ParameterForm.new()
	_form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_form)


func open(category := "") -> void:
	_categories.clear()
	var select := 0
	for entry in bridge.option_categories():
		_categories.add_item(entry["title"])
		_categories.set_item_metadata(_categories.item_count - 1, entry["id"])
		if entry["id"] == category:
			select = _categories.item_count - 1
	if _categories.item_count > 0:
		_categories.select(select)
		_on_category_selected(select)
	popup_centered(Vector2i(Vector2(680, 440) * EditorInterface.get_editor_scale()))


func refresh() -> void:
	if visible:
		_form.refresh()


func _on_category_selected(index: int) -> void:
	_form.setup(bridge, "options:" + str(_categories.get_item_metadata(index)))
