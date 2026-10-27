extends AudioStreamPlayer

# 43C49F selects a CD-DA track; each entry/enable restarts from its original beginning.
const SCENES := [34,35,36,38,40,41,42,44,46,49,50,51,53,43,0,99]
var current_scene := -1
var enabled := true
var loop_enabled := true
var _suspensions := {}
var _suspend_id := 0
# 41B8E9/43C76B: an entry movie/TXT clears playback eligibility, not
# the user's preference. Focus changes and mute toggles must respect it.
func suspend_playback() -> int:
	_suspend_id += 1
	_suspensions[_suspend_id] = true
	stop()
	return _suspend_id
func resume_playback(token: int) -> void:
	_suspensions.erase(token)
func playback_suspended() -> bool:
	return not _suspensions.is_empty()
func _ready() -> void:
	var cfg := ConfigFile.new()
	cfg.load("user://dlz_config.cfg")
	enabled = bool(cfg.get_value("audio","music_enabled",true))
	apply_volume()
	finished.connect(_try_loop)
	get_window().focus_entered.connect(_try_loop)
func _try_loop() -> void:
	if enabled and not playback_suspended() and loop_enabled and not playing and get_window().has_focus() and stream != null and DisplayServer.get_name()!="headless": play()

func release_playback() -> void:
	# Let the mixer retire its Ogg playback before SceneTree shutdown. This does
	# not change the persisted music preference and is also safe when muted.
	stop()
	stream=null
func apply_volume() -> void:
	var cfg := ConfigFile.new()
	cfg.load("user://dlz_config.cfg")
	volume_db = -14 + linear_to_db(clampf(float(cfg.get_value("audio","bgm_volume",0.8)),0,1))
func play_scene(scene: int, restart := true) -> void:
	if not restart and current_scene == scene and playing: return
	var track := SCENES.find(scene)+2
	if track < 2: return
	current_scene = scene
	stop()
	var path := "res://assets/audio/bgm_track_%02d.ogg" % track
	if not ResourceLoader.exists(path): return
	stream = load(path)
	if stream is AudioStreamOggVorbis: stream.loop = false
	apply_volume()
	# Headless structural tests have no audio sink/focus. Loading still verifies
	# the original track, but starting an orphan Ogg mixer playback on shutdown
	# leaks engine packet-sequence resources. Desktop playback is unchanged.
	if enabled and not playback_suspended() and DisplayServer.get_name() != "headless": play()
func toggle() -> void:
	enabled = not enabled
	var cfg := ConfigFile.new();cfg.load("user://dlz_config.cfg")
	cfg.set_value("audio","music_enabled",enabled);cfg.save("user://dlz_config.cfg")
	if enabled: play_scene(current_scene)
	else: stop()
func _exit_tree() -> void:
	stop()
	stream = null
