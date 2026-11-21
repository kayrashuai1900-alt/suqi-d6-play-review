extends RefCounted

const PATH := "user://hongyuan_save.json"
const PENDING_PATH := "user://hongyuan_save.json.tmp"
const WEB_KEY := "hongyuan_save.json"
const BROWSER_KEY := "(document.querySelector('meta[name=hongyuan-audience]')?.content === 'friends' ? 'hongyuan_friends_save.json' : 'hongyuan_save.json')"

static func _save_path() -> String:
	if OS.has_feature("web") and not OS.has_feature("hongyuan_wechat"):
		if str(JavaScriptBridge.eval(BROWSER_KEY, true)) == "hongyuan_friends_save.json":
			return "user://hongyuan_friends_save.json"
	return PATH

## 网址带 ?new=1 时清掉存档从头开始。清完立刻把参数从地址栏去掉，
## 这样刷新页面不会反复清档。只在网页版生效，微信小游戏没有网址。
static func clear_if_requested() -> bool:
	if not OS.has_feature("web") or OS.has_feature("hongyuan_wechat"):
		return false
	var asked := str(JavaScriptBridge.eval(
		"""(function() {
			try {
				var q = new URLSearchParams(location.search);
				if (q.get('new') !== '1') return '';
				localStorage.removeItem(%s);
				q.delete('new');
				var rest = q.toString();
				history.replaceState(null, '', location.pathname + (rest ? '?' + rest : '') + location.hash);
				return '1';
			} catch (_) { return ''; }
		})()""" % BROWSER_KEY, true)) == "1"
	if asked:
		_erase_files()
	return asked

## 清掉本地与浏览器里的爱情篇存档（效果同 ?new=1，但不改地址栏）。
static func clear_save() -> void:
	if OS.has_feature("web") and not OS.has_feature("hongyuan_wechat"):
		JavaScriptBridge.eval(
			"try { localStorage.removeItem(%s); } catch (_) {}" % BROWSER_KEY,
			true
		)
	_erase_files()

static func _erase_files() -> void:
	var path_for_save := _save_path()
	for path in [path_for_save, path_for_save + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if OS.has_feature("web"):
		JavaScriptBridge.force_fs_sync()

static func read() -> Dictionary:
	clear_if_requested()
	var path := _save_path()
	var saved := _decode(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else {}
	if OS.has_feature("web") and OS.has_feature("hongyuan_wechat"):
		var wx := JavaScriptBridge.get_interface("wx")
		var mobile := _decode(str(wx.getStorageSync(WEB_KEY)))
		if int(mobile.get("revision", -1)) > int(saved.get("revision", -1)):
			saved = mobile
	elif OS.has_feature("web"):
		var web_save := _decode(str(JavaScriptBridge.eval(
			"try { localStorage.getItem(%s) || '' } catch (_) { '' }" % BROWSER_KEY,
			true
		)))
		if int(web_save.get("revision", -1)) > int(saved.get("revision", -1)):
			saved = web_save
	return saved

static func has_progress(state: Dictionary) -> bool:
	return int(state.get("version", 0)) == 1 and str(state.get("stepId", "")) != ""

static func write(state: Dictionary) -> bool:
	var revision := int(state.get("revision", 0))
	var contents := JSON.stringify(state)
	var browser_saved := false
	if OS.has_feature("web") and OS.has_feature("hongyuan_wechat"):
		var result := int(JavaScriptBridge.eval(
			"""(function() {
				try {
					var current = JSON.parse(wx.getStorageSync(%s) || 'null');
					if (current && current.version === 1 && current.revision >= %d) return -1;
					wx.setStorageSync(%s, %s);
					return 1;
				} catch (_) { return 0; }
			})()""" % [JSON.stringify(WEB_KEY), revision, JSON.stringify(WEB_KEY), JSON.stringify(contents)], true
		))
		if result == -1:
			return false
		browser_saved = result == 1
	elif OS.has_feature("web"):
		# Browser refresh can precede IndexedDB's async file flush.
		var result := int(JavaScriptBridge.eval(
			"""try {
				const next = %s;
				const key = %s;
				const current = JSON.parse(localStorage.getItem(key) || 'null');
				if (current && current.version === 1 && current.revision >= %d) { -1 }
				else { localStorage.setItem(key, next); 1 }
			} catch (_) { 0 }""" % [JSON.stringify(contents), BROWSER_KEY, revision],
			true
		))
		if result == -1:
			return false
		browser_saved = result == 1

	var path := _save_path()
	var pending_path := path + ".tmp"
	var file := FileAccess.open(pending_path, FileAccess.WRITE)
	if file == null:
		return browser_saved
	var written := file.store_string(contents)
	file.close()
	if not written:
		return browser_saved
	var file_saved := DirAccess.rename_absolute(pending_path, path) == OK
	if file_saved and OS.has_feature("web"):
		JavaScriptBridge.force_fs_sync()
	return file_saved or browser_saved

static func _decode(value: String) -> Dictionary:
	if value.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(value)
	if parsed is Dictionary and int(parsed.get("version", 0)) == 1:
		return parsed
	return {}
