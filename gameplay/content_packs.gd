extends Node
## Each request owns its progress and errors. A pack is transferred once even
## when a background batch and an imminent scene both need it.
signal progress(detail: Dictionary)
signal blocking_changed(active: bool)
const MANIFEST := "res://hongyuan/content_manifest.json"
const CACHE := "user://hongyuan-packs/"
static var runtime: Node
var cache_root := CACHE
var config: Dictionary = {}
var mounted: Dictionary = {}
var jobs: Dictionary = {}
var last_error := ""
var timeout_seconds := 900.0
var stall_seconds := 45.0 if OS.has_feature("web") else 15.0
var transfer_retries := 1 if OS.has_feature("web") else 0
var requests: Array[Dictionary] = []
var next_id := 0
var prefetch_tickets: Dictionary = {}
var blocking_owners: Dictionary = {}

func set_blocking(owner_id: int, active: bool) -> void:
	var was_blocking := not blocking_owners.is_empty()
	if active: blocking_owners[owner_id] = true
	else: blocking_owners.erase(owner_id)
	if was_blocking != not blocking_owners.is_empty():
		blocking_changed.emit(not blocking_owners.is_empty())

func is_blocking() -> bool:
	return not blocking_owners.is_empty()

const GROUP_TITLES := {"prologue":"序章", "shanghai":"上海", "chengdu":"成都", "call":"来电与心动", "shizuoka":"静冈", "hainan":"海南", "hongkong":"香港", "finale":"写邀请函", "love-core":"共用画面", "love-media":"共用画面", "world":"赴约入口", "world-shared":"赴约共用画面", "world-media":"罗曼山庄", "estate":"罗曼山庄", "village":"裳泓村", "village-entry":"裳泓村入口", "village-home":"村中住处", "village-street":"村中街道", "village-panels":"村中界面", "village-rooms":"村中房间", "village-activities":"村中活动"}

static func group_title(group: String) -> String:
	return str(GROUP_TITLES.get(group, "接下来的回忆"))

static func groups_title(groups: Array) -> String:
	var labels := PackedStringArray()
	for group in groups:
		if str(group) in ["love-core", "love-media"] and groups.size() > 1: continue
		var title := group_title(str(group))
		if not labels.has(title): labels.append(title)
	return "、".join(labels)

func _received(ticket: Dictionary) -> int:
	var received := 0
	for key: String in ticket.entries:
		if mounted.has(key): received += int(ticket.entries[key].bytes)
		elif jobs.has(key): received += clampi(int(jobs[key].received), 0, int(ticket.entries[key].bytes))
	return received


static func service() -> Node:
	if not is_instance_valid(runtime):
		runtime = load("res://hongyuan/content_packs.gd").new()
		runtime.name = "HongyuanContent"
		runtime.configure()
		(Engine.get_main_loop() as SceneTree).root.add_child.call_deferred(runtime)
	return runtime

static func ensure(groups: Array[String]) -> bool:
	var loader := service()
	var ticket: Dictionary = loader.request_groups(groups)
	var ok: bool = await loader.wait_request(ticket)
	loader.last_error = ticket.error
	return ok

static func prefetch(groups: Array[String], retry_failed := false) -> Dictionary:
	return service()._prefetch(groups, retry_failed)

func _prefetch(groups: Array[String], retry_failed: bool) -> Dictionary:
	# Keep a batch's result across scene changes. Mounts are shared with
	# foreground requests, which may already have filled part of this batch.
	var ordered := groups.duplicate()
	ordered.sort()
	var key := JSON.stringify(ordered)
	var previous: Dictionary = prefetch_tickets.get(key, {})
	if previous.is_empty() or (retry_failed and previous.done and not previous.error.is_empty()):
		previous = request_groups(groups, true)
		prefetch_tickets[key] = previous
	return previous

static func route_groups(route: String) -> Array[String]:
	if route == "village":
		if service().has_group("village-entry"):
			return ["world", "world-shared", "village", "village-entry"]
		return ["world", "world-media", "village", "village-media"]
	if service().has_group("world-shared"):
		return ["world", "world-shared", "world-media", "estate"]
	return ["world", "world-media", "estate"]

func configure(manifest: Dictionary = {}) -> void:
	prefetch_tickets.clear()
	config = manifest.duplicate(true)
	if config.is_empty() and FileAccess.file_exists(MANIFEST):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
		if parsed is Dictionary:
			config = parsed
	process_mode = Node.PROCESS_MODE_ALWAYS

func _bridge() -> JavaScriptObject:
	if OS.has_feature("web") and OS.has_feature("hongyuan_wechat"):
		return JavaScriptBridge.get_interface("hongyuanContent")
	return null

func has_group(group: String) -> bool:
	var bridge := _bridge()
	if bridge != null:
		return bool(bridge.local(group)) or int(bridge.count(group)) > 0
	return config.get("groups", {}).has(group)

func _entries_for(groups: Array, ticket: Dictionary) -> Dictionary:
	var entries := {}
	var bridge := _bridge()
	if OS.has_feature("web") and OS.has_feature("hongyuan_wechat"):
		if bridge == null:
			ticket.error = "资源服务尚未连接"
			return entries
		for group in groups:
			var first := -1 if bool(bridge.local(group)) else 0
			var count := int(bridge.count(group))
			if first == count:
				ticket.error = "本版本缺少%s的画面清单，请更新试玩" % group_title(str(group))
				return entries
			for i in range(first, count):
				var key := str(bridge.key(group, i))
				entries[key] = {"group": group, "item": i, "bytes": int(bridge.bytes(group, i)), "wechat": true}
		return entries
	if str(config.get("mode", "bundled")) == "bundled":
		return entries
	for group in groups:
		if not has_group(group):
			ticket.error = "本版本缺少%s的画面清单，请更新试玩" % group_title(str(group))
			return entries
		for entry: Dictionary in config.groups[group]:
			var key := str(entry.get("sha256", ""))
			if key.length() != 64 or not key.is_valid_hex_number(false) or int(entry.get("bytes", 0)) <= 0:
				ticket.error = "资源清单校验失败"
				return entries
			entries[key] = entry.duplicate(true)
			entries[key]["group"] = str(group)
	return entries

func request_groups(groups: Array, background := false) -> Dictionary:
	next_id += 1
	var ticket := {"id": next_id, "background": background, "done": false, "error": "", "entries": {},
		"groups": groups.duplicate(), "failure": {}, "total": 0, "received": 0, "next": "", "state": ""}
	ticket.entries = _entries_for(groups, ticket)
	for item: Dictionary in ticket.entries.values():
		ticket.total += int(item.bytes)
	ticket.received = _received(ticket)
	if not ticket.error.is_empty() or ticket.entries.is_empty():
		ticket.done = true
	else:
		requests.append(ticket)
	return ticket

func wait_request(ticket: Dictionary) -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	while not ticket.done:
		await tree.process_frame
	return ticket.error.is_empty()

func is_ready(groups: Array) -> bool:
	var ticket := {"error": ""}
	var entries := _entries_for(groups, ticket)
	return ticket.error.is_empty() and entries.keys().all(func(key): return mounted.has(key))

func _process(_delta: float) -> void:
	if requests.is_empty():
		return
	for ticket: Dictionary in requests:
		_update_ticket(ticket)
	requests = requests.filter(func(ticket): return not ticket.done)
	# Keep one slot free for an imminent scene. A foreground request joins
	# an existing download before opening a second connection.
	for background in [false, true]:
		if background and requests.any(func(ticket): return not ticket.background):
			continue
		for ticket: Dictionary in requests:
			if ticket.background != background or ticket.next.is_empty() or jobs.has(ticket.next):
				continue
			if jobs.size() >= 2 or jobs.values().any(func(job): return job.background == background):
				break
			var key: String = ticket.next
			var job := {"received": 0, "background": background, "error": ""}
			jobs[key] = job
			_run_transfer.call_deferred(key, ticket.entries[key], job)
			break

func _update_ticket(ticket: Dictionary) -> void:
	var received := 0
	ticket.next = ""
	for key: String in ticket.entries:
		var size := int(ticket.entries[key].bytes)
		if mounted.has(key):
			received += size
		else:
			if ticket.next.is_empty():
				ticket.next = key
			if jobs.has(key):
				received += clampi(int(jobs[key].received), 0, size)
	ticket.done = not ticket.error.is_empty() or ticket.next.is_empty()
	var state := "error" if not ticket.error.is_empty() else ("ready" if ticket.done else "download")
	if state == ticket.state and received == ticket.received:
		return
	ticket.received = received
	ticket.state = state
	progress.emit({"request_id": ticket.id, "state": state, "received": received, "total": ticket.total,
		"error": ticket.error, "background": ticket.background, "groups": ticket.groups,
		"group": str(ticket.entries.get(ticket.next, {}).get("group", "")), "failure": ticket.failure})

func _run_transfer(key: String, entry: Dictionary, job: Dictionary) -> void:
	job["trace"] = {"group":str(entry.get("group", "")), "file":str(entry.get("file", "")), "expected_bytes":int(entry.bytes), "expected_sha256":key, "event":"start"}
	var ok: bool
	if entry.get("wechat", false):
		ok = await _wechat(entry, job)
	else:
		ok = await _download_and_mount(entry, job)
	job.trace["event"] = "ready" if ok else "error"
	job.trace["received"] = int(job.received)
	job.trace["error"] = str(job.error)
	if ok:
		mounted[key] = true
	else:
		# A single diagnostic per failed file; normal downloads stay quiet.
		print("CONTENT_FAILURE ", JSON.stringify(job.trace))
		for ticket: Dictionary in requests:
			if not ticket.done and ticket.entries.has(key):
				ticket.error = job.error if not str(job.error).is_empty() else "资源加载失败，请重试"
				ticket.failure = job.trace.duplicate(true)
	jobs.erase(key)

func _download_and_mount(entry: Dictionary, job: Dictionary) -> bool:
	var hash_value := str(entry.sha256)
	DirAccess.make_dir_recursive_absolute(cache_root)
	var cached := cache_root + hash_value + ".pck"
	if FileAccess.file_exists(cached) and FileAccess.get_sha256(cached) == hash_value:
		if ProjectSettings.load_resource_pack(cached, false):
			job.trace["cache"] = "verified_disk"
			job.trace["verification"] = "sha256_pass"
			job.received = int(entry.bytes)
			return true
	var base := str(config.get("baseUrl", ""))
	if OS.has_feature("web") and not base.is_empty():
		base = str(JavaScriptBridge.eval("new URL(%s, location.href).href" % JSON.stringify(base), true))
	var local_http := bool(config.get("development", false)) and (base.begins_with("http://127.0.0.1:") or base.begins_with("http://localhost:"))
	if not base.begins_with("https://") and not local_http:
		job.error = "章节下载地址尚未配置"
		return false
	var filename := str(entry.get("file", ""))
	if filename.contains("/") or filename.contains("..") or filename.is_empty():
		job.error = "资源文件名无效"
		return false
	if OS.has_feature("web") and bool(JavaScriptBridge.eval("navigator.onLine === false", true)):
		job.error = "网络未连接，请稍后重试"
		return false
	var temporary := cached + ".part"
	job.trace["url"] = base.trim_suffix("/") + "/" + filename
	job.trace["cache"] = "network"
	var response: Array
	for attempt: int in range(transfer_retries + 1):
		job.trace["attempt"] = attempt + 1
		response = await _request_pack(entry, job, temporary)
		if attempt >= transfer_retries or not _transient_error(response):
			break
		DirAccess.remove_absolute(temporary)
		print("CONTENT_RETRY ", JSON.stringify(job.trace))
		await get_tree().create_timer(1.0).timeout
	if response.is_empty() or int(response[0]) != HTTPRequest.RESULT_SUCCESS or int(response[1]) != 200:
		DirAccess.remove_absolute(temporary)
		var code := int(job.trace.get("http_status", 0))
		if job.trace.has("request_error"):
			job.error = "网络未连接，请稍后重试"
		else:
			job.error = "下载暂时中断，请重试" if code == 0 else ("这段内容暂未送达（%d）" % code)
		return false
	job.received = int(entry.bytes)
	if OS.has_feature("web"):
		var writer := FileAccess.open(temporary, FileAccess.WRITE)
		if writer == null:
			job.error = "设备无法保存数据，请检查可用空间"
			return false
		var written := writer.store_buffer(response[2])
		writer.close()
		if not written:
			DirAccess.remove_absolute(temporary)
			job.error = "设备无法保存数据，请检查可用空间"
			return false
	var file := FileAccess.open(temporary, FileAccess.READ)
	var actual_size := file.get_length() if file != null else -1
	if file:
		file.close()
	var actual_hash := FileAccess.get_sha256(temporary)
	job.trace["actual_bytes"] = actual_size
	job.trace["actual_sha256"] = actual_hash
	job.trace["verification"] = "sha256_pass" if actual_size == int(entry.bytes) and actual_hash == hash_value else "sha256_failed"
	if actual_size != int(entry.bytes) or actual_hash != hash_value:
		DirAccess.remove_absolute(temporary)
		job.error = "资源校验失败，请重试"
		return false
	if DirAccess.rename_absolute(temporary, cached) != OK or not ProjectSettings.load_resource_pack(cached, false):
		job.error = "资源保存失败，请检查设备空间后重试"
		return false
	if OS.has_feature("web"):
		JavaScriptBridge.force_fs_sync()
	return true


func _request_pack(entry: Dictionary, job: Dictionary, temporary: String) -> Array:
	job.received = 0
	for key in ["http_status", "http_result", "timeout", "request_error"]:
		job.trace.erase(key)
	var request := HTTPRequest.new()
	request.timeout = timeout_seconds
	request.body_size_limit = int(entry.bytes)
	request.accept_gzip = false
	if not OS.has_feature("web"):
		request.download_file = temporary
	add_child(request)
	var response: Array = []
	request.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray):
		response.append([result, code, body]))
	var error := request.request(str(job.trace.url))
	if error != OK:
		request.queue_free()
		job.trace["request_error"] = error
		return []
	var last_change := Time.get_ticks_msec()
	while response.is_empty():
		var received := request.get_downloaded_bytes()
		if received != job.received:
			job.received = received
			last_change = Time.get_ticks_msec()
		if Time.get_ticks_msec() - last_change > stall_seconds * 1000.0:
			job.trace["timeout"] = "no_progress"
			request.cancel_request()
			break
		await get_tree().process_frame
	request.queue_free()
	if response.is_empty():
		return []
	job.trace["http_status"] = int(response[0][1])
	job.trace["http_result"] = int(response[0][0])
	return response[0]


func _transient_error(response: Array) -> bool:
	if response.is_empty():
		return true
	var code := int(response[1])
	return code in [0, 408, 429] or (code >= 500 and code <= 599)

func _wechat(entry: Dictionary, job: Dictionary) -> bool:
	var bridge := _bridge()
	var result: Array = []
	var callback := JavaScriptBridge.create_callback(func(args: Array):
		result.assign(args if not args.is_empty() else [""]))
	bridge.fetch(entry.group, entry.item, callback)
	while result.is_empty():
		var status: Variant = JSON.parse_string(str(bridge.status(entry.group, entry.item)))
		if status is Dictionary:
			job.trace.merge(status, true)
			job.received = int(status.get("received", 0))
		await get_tree().process_frame
	var final_status: Variant = JSON.parse_string(str(bridge.status(entry.group, entry.item)))
	if final_status is Dictionary: job.trace.merge(final_status, true)
	if str(result[0]).is_empty() or not ProjectSettings.load_resource_pack(result[0], false):
		job.error = "资源下载未完成，请检查网络或设备空间后重试"
		return false
	return true
