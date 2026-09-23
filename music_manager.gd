class_name MusicManager
extends Node

signal track_changed(track_title: String)
signal playback_state_changed(is_playing: bool)

const TRACKS: Array[Dictionary] = [
	{"title": "Glacial Orbit", "file": "res://music/Glacial_Orbit.mp3"},
	{"title": "Beyond the Last Star", "file": "res://music/Beyond_the_Last_Star.mp3"},
	{"title": "Stillness Between Stars", "file": "res://music/Stillness_Between_Stars.mp3"},
	{"title": "Orbits Left Behind", "file": "res://music/Orbits_Left_Behind.mp3"},
	{"title": "Hull Pressure Rising", "file": "res://music/Hull_Pressure_Rising.mp3"},
]

const FADE_OUT_SECONDS := 2.5
const FADE_IN_SECONDS := 1.5
const SILENT_DB := -40.0

var player: AudioStreamPlayer
var current_track_index: int = 0
var is_user_paused: bool = false
var _cached_streams: Dictionary = {}
var _play_order: Array[int] = []
var _order_pos: int = 0

var intro_track_path: String = ""
var intro_track_title: String = "Intro"
var _playing_intro: bool = false
var _fade_out_started: bool = false
var _fade_tween: Tween


func setup(p_player: AudioStreamPlayer, p_autoplay: bool = true, p_intro_path: String = "") -> void:
	player = p_player
	player.bus = &"Music"
	player.finished.connect(_on_track_finished)
	intro_track_path = p_intro_path
	_preload_tracks()
	_shuffle_order()
	if p_autoplay:
		if intro_track_path != "":
			_play_intro()
		else:
			_play_at_order_pos(0)
	else:
		current_track_index = _play_order[0] if not _play_order.is_empty() else 0
		is_user_paused = true


func _process(_delta: float) -> void:
	if player == null or not player.playing or is_user_paused or _fade_out_started:
		return
	var stream: AudioStream = player.stream
	if stream == null:
		return
	var length: float = stream.get_length()
	if length <= 0.0:
		return
	var remaining: float = length - player.get_playback_position()
	if remaining <= FADE_OUT_SECONDS:
		_start_fade_out(remaining)


func _start_fade_out(remaining: float) -> void:
	_fade_out_started = true
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = player.create_tween()
	_fade_tween.tween_property(player, "volume_db", SILENT_DB, max(remaining, 0.05))


func _fade_in() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	player.volume_db = SILENT_DB
	_fade_tween = player.create_tween()
	_fade_tween.tween_property(player, "volume_db", 0.0, FADE_IN_SECONDS)


func _play_intro() -> void:
	var stream: AudioStream = _load_stream(intro_track_path)
	if stream == null:
		_play_at_order_pos(0)
		return
	_playing_intro = true
	_fade_out_started = false
	player.stream = stream
	player.play()
	is_user_paused = false
	_fade_in()
	track_changed.emit(intro_track_title)
	playback_state_changed.emit(true)


func _shuffle_order() -> void:
	_play_order = Array(range(TRACKS.size()), TYPE_INT, &"", null)
	_play_order.shuffle()
	_order_pos = 0


func _play_at_order_pos(pos: int) -> void:
	if _play_order.is_empty():
		return
	_order_pos = posmod(pos, _play_order.size())
	play_track(_play_order[_order_pos])


func _preload_tracks() -> void:
	for track in TRACKS:
		var path: String = track.file
		var stream: AudioStream = _load_stream(path)
		if stream != null:
			_cached_streams[path] = stream


func _load_stream(path: String) -> AudioStream:
	if ResourceLoader.exists(path):
		var res = load(path)
		if res is AudioStream:
			return res
	var file := FileAccess.open(path, FileAccess.READ)
	if file != null:
		var mp3 := AudioStreamMP3.new()
		mp3.data = file.get_buffer(file.get_length())
		file.close()
		return mp3
	return null


func play_track(index: int) -> void:
	if TRACKS.is_empty():
		return
	current_track_index = posmod(index, TRACKS.size())
	var track: Dictionary = TRACKS[current_track_index]
	var stream: AudioStream = _cached_streams.get(track.file)
	if stream == null:
		stream = _load_stream(track.file)
		if stream != null:
			_cached_streams[track.file] = stream

	if stream != null and player != null:
		_playing_intro = false
		_fade_out_started = false
		player.stream = stream
		player.play()
		is_user_paused = false
		_fade_in()
		track_changed.emit(track.title)
		playback_state_changed.emit(true)


func next_track() -> void:
	if _play_order.is_empty():
		return
	_order_pos += 1
	if _order_pos >= _play_order.size():
		_shuffle_order()
	play_track(_play_order[_order_pos])


func prev_track() -> void:
	if _play_order.is_empty():
		return
	_order_pos -= 1
	if _order_pos < 0:
		_order_pos = _play_order.size() - 1
	play_track(_play_order[_order_pos])


func toggle_playback() -> void:
	if player == null:
		return
	if is_playing():
		player.stream_paused = true
		is_user_paused = true
		playback_state_changed.emit(false)
	else:
		if is_user_paused:
			player.stream_paused = false
			is_user_paused = false
			playback_state_changed.emit(true)
		else:
			play_track(current_track_index)


func get_current_track_title() -> String:
	if _playing_intro:
		return intro_track_title
	if current_track_index >= 0 and current_track_index < TRACKS.size():
		return TRACKS[current_track_index].title
	return "No Track"


func is_playing() -> bool:
	return player != null and player.playing and not player.stream_paused


func _on_track_finished() -> void:
	if is_user_paused:
		return
	if _playing_intro:
		_playing_intro = false
		_play_at_order_pos(0)
		return
	next_track()
