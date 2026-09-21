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

var player: AudioStreamPlayer
var current_track_index: int = 0
var is_user_paused: bool = false
var _cached_streams: Dictionary = {}
var _play_order: Array[int] = []
var _order_pos: int = 0


func setup(p_player: AudioStreamPlayer, p_autoplay: bool = true) -> void:
	player = p_player
	player.bus = &"Music"
	player.finished.connect(_on_track_finished)
	_preload_tracks()
	_shuffle_order()
	if p_autoplay:
		_play_at_order_pos(0)
	else:
		current_track_index = _play_order[0] if not _play_order.is_empty() else 0
		is_user_paused = true


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
		player.stream = stream
		player.play()
		is_user_paused = false
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
	if current_track_index >= 0 and current_track_index < TRACKS.size():
		return TRACKS[current_track_index].title
	return "No Track"


func is_playing() -> bool:
	return player != null and player.playing and not player.stream_paused


func _on_track_finished() -> void:
	if not is_user_paused:
		next_track()
