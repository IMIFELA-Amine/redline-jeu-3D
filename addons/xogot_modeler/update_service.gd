@tool
extends Node

## Update checks are independent of the native bridge, including expired betas.

signal changed

const API_URL := "https://api.xogot.com/api/CheckExtensionVersion"
const DOWNLOAD_URL := "https://xogot.com/modeler-xplat"
const CHECK_INTERVAL := 24 * 60 * 60
const ADDON_PATH := "res://addons/xogot_modeler/"

var version := ""
var build_info: Dictionary = {}
var release_info: Dictionary = {}
var status := "Not checked yet."
var checking := false
var automatic := true
var installation_warning := ""
var _request: HTTPRequest
var _cache := ConfigFile.new()
var _cache_path := ""
var _active := true


## startup_check: whether an automatic check may run now. The development
## tools pass false so that tests don't reach the update server.
func setup(cache_path := "", startup_check := true) -> void:
	var config := ConfigFile.new()
	if config.load(ADDON_PATH + "plugin.cfg") == OK:
		version = str(config.get_value("plugin", "version", ""))
	if FileAccess.file_exists(ADDON_PATH + "build_info.json"):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ADDON_PATH + "build_info.json"))
		if parsed is Dictionary:
			build_info = parsed
	_cache_path = cache_path
	if _cache_path.is_empty():
		_cache_path = EditorInterface.get_editor_paths().get_config_dir().path_join("xogot_modeler_updates.cfg")
	_cache.load(_cache_path)
	automatic = bool(_cache.get_value("updates", "automatic", true))
	_request = HTTPRequest.new()
	_request.timeout = 10.0
	_request.body_size_limit = 64 * 1024
	add_child(_request)
	_request.request_completed.connect(_completed)
	var cached: Variant = _cache.get_value("updates", "response", {})
	if cached is Dictionary and _cache.get_value("updates", "identity", "") == _identity():
		accept_response(cached, false)
	if automatic and startup_check:
		check.call_deferred(false)


func verify_installation(beta: Dictionary) -> bool:
	if beta.get("version", "") != version or (not build_info.is_empty() and (build_info.get("version") != version or beta.get("build_id", "") != build_info.get("buildID", ""))):
		installation_warning = "The Modeler scripts and native library are from different builds. Close Godot and reinstall the complete beta package."
		changed.emit()
		return false
	return true


func set_automatic(enabled: bool) -> void:
	automatic = enabled
	_cache.set_value("updates", "automatic", enabled)
	_save_cache()
	changed.emit()


func check(manual := true) -> void:
	if not _active or checking or not is_instance_valid(_request):
		return
	var now := int(Time.get_unix_time_from_system())
	var last := int(_cache.get_value("updates", "last_attempt", 0))
	if not manual and (not automatic or (_cache.get_value("updates", "attempt_identity", "") == _identity() and last <= now and now - last < CHECK_INTERVAL)):
		return
	var settings := EditorInterface.get_editor_settings()
	if settings.has_setting("network/connection/network_mode") and settings.get_setting("network/connection/network_mode") == 0:
		status = "Godot is offline. Enable online access in Editor Settings to check for beta updates."
		changed.emit()
		return
	if version.is_empty():
		status = "Cannot read the installed Modeler version. Reinstall the complete beta package."
		changed.emit()
		return
	checking = true
	status = "Checking for beta updates…"
	_cache.set_value("updates", "last_attempt", now)
	_cache.set_value("updates", "attempt_identity", _identity())
	_save_cache()
	changed.emit()
	var engine := Engine.get_version_info()
	var godot_version := "%s.%s.%s" % [engine.major, engine.minor, engine.patch]
	var platform := OS.get_name().to_lower()
	var architecture := Engine.get_architecture_name()
	var url := API_URL + "?extensionType=modeler&channel=beta&version=%s&godotVersion=%s&platform=%s&architecture=%s" % [version.uri_encode(), godot_version.uri_encode(), platform.uri_encode(), architecture.uri_encode()]
	var error := _request.request(url)
	if error != OK:
		_failed("Could not start the update check. Try again later.")


func _completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if not _active:
		return
	checking = false
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_failed("Could not check for updates. Check your connection and try again.")
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary or not accept_response(data):
		_failed("The update server returned an invalid response. Try again later.")


func accept_response(data: Dictionary, persist := true) -> bool:
	if data.get("currentVersion") != version or data.get("channel") != "beta" or not data.get("releaseAvailable") is bool:
		return false
	if data.releaseAvailable:
		for key in ["latestVersion", "description", "downloadUrl", "expiresAt", "minimumGodotVersion", "changelog"]:
			if not data.get(key) is String or data[key].is_empty():
				return false
		if not data.get("isUpToDate") is bool or not data.get("isRequiredUpdate") is bool or data.get("stable") != false:
			return false
		if not _safe_url(data.downloadUrl) or not _safe_url(data.changelog):
			return false
		if not RegEx.create_from_string("^[0-9]+\\.[0-9]+\\.[0-9]+-beta\\.[0-9]+$").search(data.latestVersion) or not RegEx.create_from_string("^[0-9]{4}-[0-9]{2}-[0-9]{2}T00:00:00Z$").search(data.expiresAt):
			return false
		var expiry := Time.get_unix_time_from_datetime_string(data.expiresAt)
		if expiry <= Time.get_unix_time_from_system():
			# An expired advertisement is not worth keeping: the server may
			# have a replacement. Forget it, and when it came from the cache
			# let the automatic check run now instead of waiting out the
			# daily interval, so the status reflects a fresh answer.
			release_info = {}
			status = "The advertised beta has expired. Check the download page for a replacement."
			for key in ["response", "identity"] + ([] if persist else ["last_attempt"]):
				if _cache.has_section_key("updates", key):
					_cache.erase_section_key("updates", key)
			_save_cache()
			changed.emit()
			return true
	release_info = data.duplicate(true)
	if not data.releaseAvailable:
		status = "No compatible, unexpired beta is currently available. Check the download page for news."
	elif data.isUpToDate:
		status = "You have the latest compatible beta."
	else:
		status = "Please update to beta %s." % data.latestVersion if data.isRequiredUpdate else "Beta %s is available." % data.latestVersion
	if persist:
		_cache.set_value("updates", "identity", _identity())
		_cache.set_value("updates", "response", data)
		_cache.set_value("updates", "last_success", int(Time.get_unix_time_from_system()))
		_save_cache()
	changed.emit()
	return true


func _safe_url(url: String) -> bool:
	return url.begins_with("https://") and not url.contains("\n") and not url.contains("\r") and not url.substr(8).get_slice("/", 0).is_empty()


func _identity() -> String:
	var engine := Engine.get_version_info()
	return "%s|%s.%s.%s|%s|%s" % [version, engine.major, engine.minor, engine.patch, OS.get_name(), Engine.get_architecture_name()]


func update_available() -> bool:
	return release_info.get("releaseAvailable", false) and not release_info.get("isUpToDate", true) and Time.get_unix_time_from_datetime_string(release_info.get("expiresAt", "1970-01-01T00:00:00Z")) > Time.get_unix_time_from_system()


func should_notify() -> bool:
	return update_available() and (release_info.get("isRequiredUpdate", false) or _cache.get_value("updates", "dismissed", "") != release_info.get("latestVersion", ""))


func dismiss() -> void:
	_cache.set_value("updates", "dismissed", release_info.get("latestVersion", ""))
	_save_cache()
	changed.emit()


func download_url() -> String:
	return release_info.get("downloadUrl", DOWNLOAD_URL) if update_available() else DOWNLOAD_URL


func _failed(message: String) -> void:
	checking = false
	status = message
	changed.emit()


func _save_cache() -> void:
	if not _cache_path.is_empty():
		_cache.save(_cache_path)


func shutdown() -> void:
	_active = false
	if is_instance_valid(_request):
		_request.cancel_request()
		_request.request_completed.disconnect(_completed)
	checking = false
