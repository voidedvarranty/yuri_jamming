extends Control


@export_group("Scenes")
@export var fallback_level_scene: String = "main"
@export var main_menu_scene: String = "main_menu"
@export var retry_transition_duration: float = 1.0
@export var main_menu_transition_duration: float = 1.0

@export_group("Pause Input")
@export var pause_key: Key = KEY_BACKSPACE
@export var add_input_blocker: bool = true

@export_group("Pause Exceptions")
@export var keep_music_player_running_when_paused: bool = true
@export var keep_sfx_player_running_when_paused: bool = true

@export_group("UI Sounds")
@export var button_hover_sound: AudioStream
@export var button_click_sound: AudioStream
@export var slider_hover_sound: AudioStream
@export var slider_grab_sound: AudioStream

@export_group("Slider Visual Padding")
@export_range(0.0, 0.25, 0.01) var slider_visual_edge_padding: float = 0.05

@export_group("Percentage Labels")
@export var show_slider_percentage_labels: bool = true
@export var percentage_label_min_width: float = 30.0
@export var percentage_label_suffix: String = "%"

var slider_percentage_labels: Dictionary[HSlider, Label] = {}
var is_setting_slider_values: bool = false
var input_blocker: ColorRect = null

@onready var master_slider: HSlider = %MasterSlider
@onready var retry_button: Button = %RetryButton
@onready var music_slider: HSlider = %MusicSlider
@onready var sfx_slider: HSlider = %SFXSlider



func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	set_node_and_children_process_always(self)
	set_pause_exempt_audio_players()

	if add_input_blocker:
		create_input_blocker()

	visible = false

	_setup_sliders()
	_setup_slider_percentage_labels()
	_setup_saved_values()
	_connect_settings_signals()
	_connect_ui_sound_signals()


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey

		if key_event.pressed and not key_event.echo and key_event.keycode == pause_key:
			get_viewport().set_input_as_handled()
			toggle_pause()


func _on_retry_button_pressed() -> void:
	play_ui_sfx(button_click_sound)

	get_tree().paused = false
	visible = false

	var level_scene: String = get_retry_scene()

	SceneManager.go(level_scene, retry_transition_duration, true)


func _on_back_button_pressed() -> void:
	play_ui_sfx(button_click_sound)
	resume_game()


func _on_main_menu_button_pressed() -> void:
	play_ui_sfx(button_click_sound)

	get_tree().paused = false
	visible = false

	SceneManager.go(main_menu_scene, main_menu_transition_duration)


func get_retry_scene() -> String:
	var current_scene_path: String = get_current_scene_path()

	if current_scene_path.strip_edges() != "":
		return current_scene_path

	if GameData.has_method("get_current_level"):
		var current_level_scene: String = GameData.get_current_level()

		if current_level_scene.strip_edges() != "":
			return current_level_scene

	return fallback_level_scene


func get_current_scene_path() -> String:
	var current_scene: Node = get_tree().current_scene

	if current_scene == null:
		return ""

	if current_scene.scene_file_path.strip_edges() == "":
		return ""

	return current_scene.scene_file_path


func toggle_pause() -> void:
	if get_tree().paused:
		resume_game()
	else:
		pause_game()


func pause_game() -> void:
	_setup_saved_values()
	set_pause_exempt_audio_players()

	get_tree().paused = true
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP

	if input_blocker != null:
		input_blocker.visible = true
		input_blocker.mouse_filter = Control.MOUSE_FILTER_STOP


func resume_game() -> void:
	get_tree().paused = false
	visible = false

	if input_blocker != null:
		input_blocker.visible = false
		input_blocker.mouse_filter = Control.MOUSE_FILTER_IGNORE


func create_input_blocker() -> void:
	if input_blocker != null:
		return

	input_blocker = ColorRect.new()
	input_blocker.name = "PauseInputBlocker"
	input_blocker.color = Color(0.0, 0.0, 0.0, 0.0)
	input_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	input_blocker.process_mode = Node.PROCESS_MODE_ALWAYS
	input_blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	add_child(input_blocker)
	move_child(input_blocker, 0)

	input_blocker.visible = false


func set_pause_exempt_audio_players() -> void:
	if keep_music_player_running_when_paused:
		set_node_and_children_process_always(MusicPlayer)

	if keep_sfx_player_running_when_paused:
		set_node_and_children_process_always(SfxPlayer)


func set_node_and_children_process_always(node: Node) -> void:
	if node == null:
		return

	node.process_mode = Node.PROCESS_MODE_ALWAYS

	for child: Node in node.get_children():
		set_node_and_children_process_always(child)


func _setup_sliders() -> void:
	setup_slider(master_slider)
	setup_slider(music_slider)
	setup_slider(sfx_slider)


func setup_slider(slider: HSlider) -> void:
	if slider == null:
		return

	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01


func _setup_slider_percentage_labels() -> void:
	if not show_slider_percentage_labels:
		return

	_setup_percentage_label_for_slider(master_slider, "MasterPercentageLabel")
	_setup_percentage_label_for_slider(music_slider, "MusicPercentageLabel")
	_setup_percentage_label_for_slider(sfx_slider, "SFXPercentageLabel")


func _setup_percentage_label_for_slider(slider: HSlider, label_name: String) -> void:
	if slider == null:
		return

	var parent_node: Node = slider.get_parent()

	if parent_node == null:
		return

	var percentage_label: Label = parent_node.get_node_or_null(label_name) as Label

	if percentage_label == null:
		percentage_label = Label.new()
		percentage_label.name = label_name
		parent_node.add_child(percentage_label)

	percentage_label.custom_minimum_size.x = percentage_label_min_width
	percentage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	percentage_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	slider_percentage_labels[slider] = percentage_label
	update_slider_percentage_label(slider)


func _setup_saved_values() -> void:
	is_setting_slider_values = true

	if master_slider != null:
		master_slider.value = volume_to_slider_value(GameData.master_volume)

	if music_slider != null:
		music_slider.value = volume_to_slider_value(GameData.music_volume)

	if sfx_slider != null:
		sfx_slider.value = volume_to_slider_value(GameData.sfx_volume)

	is_setting_slider_values = false

	update_all_slider_percentage_labels()


func _connect_settings_signals() -> void:
	if (
		master_slider != null
		and not master_slider.value_changed.is_connected(_on_master_slider_value_changed)
	):
		master_slider.value_changed.connect(_on_master_slider_value_changed)

	if (
		music_slider != null
		and not music_slider.value_changed.is_connected(_on_music_slider_value_changed)
	):
		music_slider.value_changed.connect(_on_music_slider_value_changed)

	if (
		sfx_slider != null
		and not sfx_slider.value_changed.is_connected(_on_sfx_slider_value_changed)
	):
		sfx_slider.value_changed.connect(_on_sfx_slider_value_changed)


func _connect_ui_sound_signals() -> void:
	connect_button_ui_sounds()
	connect_slider_ui_sounds(master_slider)
	connect_slider_ui_sounds(music_slider)
	connect_slider_ui_sounds(sfx_slider)


func connect_button_ui_sounds() -> void:
	for node: Node in find_children("*", "Button", true, false):
		var button: Button = node as Button

		if button == null:
			continue

		var mouse_entered_callable: Callable = _on_button_mouse_entered.bind(button)
		var button_down_callable: Callable = _on_button_down.bind(button)

		if not button.mouse_entered.is_connected(mouse_entered_callable):
			button.mouse_entered.connect(mouse_entered_callable)

		if not button.button_down.is_connected(button_down_callable):
			button.button_down.connect(button_down_callable)


func connect_slider_ui_sounds(slider: HSlider) -> void:
	if slider == null:
		return

	var mouse_entered_callable: Callable = _on_slider_mouse_entered.bind(slider)
	var gui_input_callable: Callable = _on_slider_gui_input.bind(slider)
	var drag_started_callable: Callable = _on_slider_drag_started.bind(slider)

	if not slider.mouse_entered.is_connected(mouse_entered_callable):
		slider.mouse_entered.connect(mouse_entered_callable)

	if not slider.gui_input.is_connected(gui_input_callable):
		slider.gui_input.connect(gui_input_callable)

	if (
		slider.has_signal("drag_started")
		and not slider.is_connected("drag_started", drag_started_callable)
	):
		slider.connect("drag_started", drag_started_callable)


func _on_button_mouse_entered(_button: Button) -> void:
	if not visible:
		return

	play_ui_sfx(button_hover_sound)


func _on_button_down(_button: Button) -> void:
	if not visible:
		return

	play_ui_sfx(button_click_sound)


func _on_slider_mouse_entered(_slider: HSlider) -> void:
	if not visible:
		return

	play_ui_sfx(slider_hover_sound)


func _on_slider_drag_started(_slider: HSlider) -> void:
	if not visible:
		return

	play_ui_sfx(slider_grab_sound)


func _on_slider_gui_input(event: InputEvent, _slider: HSlider) -> void:
	if not visible:
		return

	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton

		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			play_ui_sfx(slider_grab_sound)


func _on_master_slider_value_changed(value: float) -> void:
	update_slider_percentage_label(master_slider)

	if is_setting_slider_values:
		return

	GameData.set_master_volume(slider_value_to_volume(value))


func _on_music_slider_value_changed(value: float) -> void:
	update_slider_percentage_label(music_slider)

	if is_setting_slider_values:
		return

	GameData.set_music_volume(slider_value_to_volume(value))


func _on_sfx_slider_value_changed(value: float) -> void:
	update_slider_percentage_label(sfx_slider)

	if is_setting_slider_values:
		return

	GameData.set_sfx_volume(slider_value_to_volume(value))


func update_all_slider_percentage_labels() -> void:
	update_slider_percentage_label(master_slider)
	update_slider_percentage_label(music_slider)
	update_slider_percentage_label(sfx_slider)


func update_slider_percentage_label(slider: HSlider) -> void:
	if slider == null:
		return

	if not slider_percentage_labels.has(slider):
		return

	var percentage_label: Label = slider_percentage_labels[slider] as Label

	if percentage_label == null:
		return

	var volume_value: float = slider_value_to_volume(slider.value)
	var percentage: int = roundi(volume_value * 100.0)

	percentage_label.text = str(percentage) + percentage_label_suffix


func slider_value_to_volume(slider_value: float) -> float:
	var padding: float = clampf(slider_visual_edge_padding, 0.0, 0.49)

	if slider_value <= padding:
		return 0.0

	if slider_value >= 1.0 - padding:
		return 1.0

	return inverse_lerp(padding, 1.0 - padding, slider_value)


func volume_to_slider_value(volume: float) -> float:
	var padding: float = clampf(slider_visual_edge_padding, 0.0, 0.49)
	var clamped_volume: float = clampf(volume, 0.0, 1.0)

	if clamped_volume <= 0.0:
		return padding

	if clamped_volume >= 1.0:
		return 1.0 - padding

	return lerpf(padding, 1.0 - padding, clamped_volume)


func play_ui_sfx(sound: AudioStream) -> void:
	if sound == null:
		return

	SfxPlayer.play(sound)
