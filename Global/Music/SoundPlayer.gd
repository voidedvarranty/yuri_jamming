extends Node

# WARNING:
# This is an advanced shared audio script.
# Beginners should only use the public functions near the top:
# play(), crossfade_to(), switch_track_at_current_position(), stop(), and stop_audio().
# Do not edit the private helper functions unless you know what they do.
# Audio code gets fucked very quickly.

const FADE_IN_START_VOLUME_DB: float = -80.0
const FADE_OUT_TARGET_VOLUME_DB: float = -80.0
const MIN_LINEAR_VOLUME: float = 0.0001
const SOURCE_AUDIO_META_KEY: String = "source_audio"

# Set true on MusicPlayer, false on SfxPlayer.
@export var default_looping: bool = false

# Tracks active fade tweens per player.
var fade_tweens: Dictionary[AudioStreamPlayer, Tween] = {}

# Used to cancel old delayed play calls.
var play_token: int = 0

# Used for synced track switching.
var last_synced_stream_player: AudioStreamPlayer = null
var last_synced_playback_position: float = 0.0

# The one required child AudioStreamPlayer.
# Extra players are spawned automatically when sounds overlap.
@onready var player: AudioStreamPlayer = $AudioStreamPlayer


# Plays audio with options for single playback, fading, start position, crossfade, and looping.
func play(
	audio: AudioStream,
	single: bool = false,
	fade_out: bool = false,
	fade_duration: float = 0.5,
	fade_in: bool = false,
	volume_db: float = 0.0,
	start_position: float = 0.0,
	crossfade: bool = false,
	loop: Variant = null
) -> void:
	if audio == null:
		return

	var should_loop: bool = default_looping if loop == null else bool(loop)
	var safe_start_position: float = max(start_position, 0.0)
	var local_play_token: int = play_token

	# Do not restart the same single track from the beginning.
	if single and is_playing(audio) and safe_start_position <= 0.0:
		return

	# Single/crossfade calls cancel older delayed single/crossfade calls.
	if single or crossfade:
		play_token += 1
		local_play_token = play_token

	if crossfade:
		_crossfade_to_player(audio, fade_duration, volume_db, safe_start_position, should_loop)
		return

	if single:
		stop(fade_out, fade_duration, false)

		if fade_out:
			await get_tree().create_timer(fade_duration).timeout

			if local_play_token != play_token:
				return

	_start_player(
		_get_or_create_free_player(),
		audio,
		volume_db,
		safe_start_position,
		should_loop,
		fade_in,
		fade_duration
	)


# Easier way to crossfade to a new track.
func crossfade_to(
	audio: AudioStream,
	fade_duration: float = 1.0,
	volume_db: float = 0.0,
	start_position: float = 0.0,
	loop: Variant = null
) -> void:
	play(audio, true, false, fade_duration, false, volume_db, start_position, true, loop)


# Switches to another track while keeping the current playback position.
func switch_track_at_current_position(
	audio: AudioStream,
	fade_out: bool = true,
	fade_duration: float = 1.0,
	fade_in: bool = true,
	volume_db: float = 0.0,
	crossfade: bool = true,
	loop: Variant = null
) -> void:
	if audio == null:
		return

	var current_position: float = get_current_playback_position()

	if crossfade:
		play(audio, true, false, fade_duration, false, volume_db, current_position, true, loop)
		return

	if fade_out:
		current_position += fade_duration

	play(audio, true, fade_out, fade_duration, fade_in, volume_db, current_position, false, loop)


# Returns the playback position of the current active player.
func get_current_playback_position(use_hardware_clock: bool = true) -> float:
	var stream_player: AudioStreamPlayer = _get_active_playing_player()

	if stream_player == null:
		last_synced_stream_player = null
		last_synced_playback_position = 0.0
		return 0.0

	var current_position: float = stream_player.get_playback_position()

	# Hardware clock gives better timing for synced music switching.
	if use_hardware_clock:
		current_position += AudioServer.get_time_since_last_mix()
		current_position -= AudioServer.get_output_latency()

	current_position = max(current_position, 0.0)

	if stream_player != last_synced_stream_player:
		last_synced_stream_player = stream_player
		last_synced_playback_position = current_position
		return current_position

	# Prevent tiny backwards timing jumps.
	if current_position < last_synced_playback_position:
		return last_synced_playback_position

	last_synced_playback_position = current_position
	return current_position


# Checks whether a specific audio stream is currently playing.
func is_playing(audio: AudioStream) -> bool:
	if audio == null:
		return false

	for stream_player: AudioStreamPlayer in _get_players(true):
		if _player_matches_audio(stream_player, audio):
			return true

	return false


# Stops all currently playing audio on this player.
func stop(
	fade_out: bool = false, fade_duration: float = 0.5, cancel_pending_single_plays: bool = true
) -> void:
	if cancel_pending_single_plays:
		play_token += 1

	for stream_player: AudioStreamPlayer in _get_players(true):
		_stop_player(stream_player, fade_out, fade_duration)


# Stops only one specific audio stream.
func stop_audio(audio: AudioStream, fade_out: bool = false, fade_duration: float = 0.5) -> void:
	if audio == null:
		return

	for stream_player: AudioStreamPlayer in _get_players(true):
		if _player_matches_audio(stream_player, audio):
			_stop_player(stream_player, fade_out, fade_duration)


# Handles smooth crossfading between old players and a new player.
func _crossfade_to_player(
	audio: AudioStream, fade_duration: float, volume_db: float, start_position: float, loop: bool
) -> void:
	var old_players: Array[AudioStreamPlayer] = _get_players(true)
	var new_player: AudioStreamPlayer = _get_or_create_free_player()
	var old_start_volumes: Dictionary[AudioStreamPlayer, float] = {}

	for old_player: AudioStreamPlayer in old_players:
		old_start_volumes[old_player] = old_player.volume_db
		_kill_fade_tween(old_player)

	_kill_fade_tween(new_player)

	# Start new audio silent, then blend it in.
	_prepare_player(new_player, audio, FADE_OUT_TARGET_VOLUME_DB, loop)
	new_player.play(start_position)
	last_synced_stream_player = new_player
	last_synced_playback_position = max(start_position, 0.0)

	if fade_duration <= 0.0:
		new_player.volume_db = volume_db

		for old_player: AudioStreamPlayer in old_players:
			if old_player != new_player:
				_clear_player(old_player)

		return

	var tween: Tween = create_tween()
	fade_tweens[new_player] = tween

	for old_player: AudioStreamPlayer in old_players:
		fade_tweens[old_player] = tween

	_update_equal_power_crossfade(0.0, new_player, old_players, old_start_volumes, volume_db)

	tween.tween_method(
		_update_equal_power_crossfade.bind(new_player, old_players, old_start_volumes, volume_db),
		0.0,
		1.0,
		fade_duration
	)

	tween.tween_callback(_finish_crossfade.bind(new_player, old_players, volume_db))


# Updates volume during an equal-power crossfade.
func _update_equal_power_crossfade(
	blend: float,
	new_player: AudioStreamPlayer,
	old_players: Array[AudioStreamPlayer],
	old_start_volumes: Dictionary[AudioStreamPlayer, float],
	target_volume_db: float
) -> void:
	var safe_blend: float = clampf(blend, 0.0, 1.0)

	# Equal-power fade avoids a quiet dip in the middle.
	var old_gain: float = cos(safe_blend * PI * 0.5)
	var new_gain: float = sin(safe_blend * PI * 0.5)

	_set_player_volume_with_gain(new_player, target_volume_db, new_gain)

	for old_player: AudioStreamPlayer in old_players:
		if old_player == null or old_player == new_player:
			continue

		var old_volume_db: float = old_start_volumes.get(old_player, old_player.volume_db)
		_set_player_volume_with_gain(old_player, old_volume_db, old_gain)


# Cleans up after a crossfade.
func _finish_crossfade(
	new_player: AudioStreamPlayer, old_players: Array[AudioStreamPlayer], target_volume_db: float
) -> void:
	if new_player != null:
		new_player.volume_db = target_volume_db
		fade_tweens.erase(new_player)

	for old_player: AudioStreamPlayer in old_players:
		if old_player != null and old_player != new_player:
			_clear_player(old_player)


# Applies linear gain to a player safely.
func _set_player_volume_with_gain(
	stream_player: AudioStreamPlayer, base_volume_db: float, gain: float
) -> void:
	if stream_player == null:
		return

	if gain <= MIN_LINEAR_VOLUME:
		stream_player.volume_db = FADE_OUT_TARGET_VOLUME_DB
		return

	var final_linear_volume: float = db_to_linear(base_volume_db) * gain

	if final_linear_volume <= MIN_LINEAR_VOLUME:
		stream_player.volume_db = FADE_OUT_TARGET_VOLUME_DB
		return

	stream_player.volume_db = linear_to_db(final_linear_volume)


# Starts one player with optional fade-in.
func _start_player(
	stream_player: AudioStreamPlayer,
	audio: AudioStream,
	volume_db: float,
	start_position: float,
	loop: bool,
	fade_in: bool,
	fade_duration: float
) -> void:
	_kill_fade_tween(stream_player)

	var start_volume_db: float = FADE_IN_START_VOLUME_DB if fade_in else volume_db

	_prepare_player(stream_player, audio, start_volume_db, loop)
	stream_player.play(start_position)

	last_synced_stream_player = stream_player
	last_synced_playback_position = max(start_position, 0.0)

	if not fade_in:
		return

	if fade_duration <= 0.0:
		stream_player.volume_db = volume_db
		return

	var tween: Tween = create_tween()
	fade_tweens[stream_player] = tween

	tween.tween_property(stream_player, "volume_db", volume_db, fade_duration)
	tween.tween_callback(_erase_fade_tween.bind(stream_player))


# Sets up a player with audio, volume, loop behaviour, and original-audio tracking.
func _prepare_player(
	stream_player: AudioStreamPlayer, audio: AudioStream, volume_db: float, loop: bool
) -> void:
	stream_player.volume_db = volume_db
	stream_player.stream = _make_playback_audio(audio, loop)
	stream_player.set_meta(SOURCE_AUDIO_META_KEY, audio)


# Stops a player now or fades it out first.
func _stop_player(stream_player: AudioStreamPlayer, fade_out: bool, fade_duration: float) -> void:
	if stream_player == null:
		return

	_kill_fade_tween(stream_player)

	if not fade_out or fade_duration <= 0.0:
		_clear_player(stream_player)
		return

	var tween: Tween = create_tween()
	fade_tweens[stream_player] = tween

	tween.tween_property(stream_player, "volume_db", FADE_OUT_TARGET_VOLUME_DB, fade_duration)
	tween.tween_callback(_clear_player.bind(stream_player))


# Gets all AudioStreamPlayer children.
func _get_players(only_playing: bool = false) -> Array[AudioStreamPlayer]:
	var audio_players: Array[AudioStreamPlayer] = []

	for child: Node in get_children():
		var stream_player: AudioStreamPlayer = child as AudioStreamPlayer

		if stream_player == null:
			continue

		if only_playing and not stream_player.playing:
			continue

		audio_players.append(stream_player)

	return audio_players


# Gets a free player, or creates one if needed.
func _get_or_create_free_player() -> AudioStreamPlayer:
	for stream_player: AudioStreamPlayer in _get_players():
		if not stream_player.playing:
			return stream_player

	var new_player: AudioStreamPlayer = AudioStreamPlayer.new()
	add_child(new_player)
	new_player.bus = player.bus
	return new_player


# Gets the active player used for synced playback position.
func _get_active_playing_player() -> AudioStreamPlayer:
	if last_synced_stream_player != null and last_synced_stream_player.playing:
		return last_synced_stream_player

	var playing_players: Array[AudioStreamPlayer] = _get_players(true)

	if playing_players.is_empty():
		return null

	return playing_players[0]


# Removes the fade tween reference for one player.
func _erase_fade_tween(stream_player: AudioStreamPlayer) -> void:
	fade_tweens.erase(stream_player)


# Kills the fade tween linked to a player.
func _kill_fade_tween(stream_player: AudioStreamPlayer) -> void:
	if stream_player == null:
		return

	var old_tween: Tween = fade_tweens.get(stream_player) as Tween

	if old_tween == null:
		fade_tweens.erase(stream_player)
		return

	old_tween.kill()

	# Crossfades can store the same tween on multiple players.
	for tween_key: AudioStreamPlayer in fade_tweens.keys():
		if fade_tweens.get(tween_key) == old_tween:
			fade_tweens.erase(tween_key)


# Resets a player so it can be reused.
func _clear_player(stream_player: AudioStreamPlayer) -> void:
	if stream_player == null:
		return

	stream_player.stop()
	stream_player.stream = null
	stream_player.volume_db = 0.0
	fade_tweens.erase(stream_player)

	if stream_player.has_meta(SOURCE_AUDIO_META_KEY):
		stream_player.remove_meta(SOURCE_AUDIO_META_KEY)

	if last_synced_stream_player == stream_player:
		last_synced_stream_player = null
		last_synced_playback_position = 0.0


# Duplicates audio and applies the wanted loop setting.
func _make_playback_audio(audio: AudioStream, loop: bool) -> AudioStream:
	var playback_audio: AudioStream = audio.duplicate() as AudioStream

	if playback_audio == null:
		playback_audio = audio

	if _audio_has_property(playback_audio, "loop"):
		playback_audio.set("loop", loop)

	return playback_audio


# Checks whether an AudioStream has a specific property.
func _audio_has_property(audio: AudioStream, property_name: String) -> bool:
	for property: Dictionary in audio.get_property_list():
		if String(property.get("name", "")) == property_name:
			return true

	return false


# Checks if a player is using a specific original audio stream.
func _player_matches_audio(stream_player: AudioStreamPlayer, audio: AudioStream) -> bool:
	if stream_player == null or audio == null:
		return false

	if stream_player.stream == audio:
		return true

	return (
		stream_player.has_meta(SOURCE_AUDIO_META_KEY)
		and stream_player.get_meta(SOURCE_AUDIO_META_KEY) == audio
	)
