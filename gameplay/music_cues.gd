extends RefCounted

const LOCATION_CUES := {
	"shanghai_parking.png": "shanghai__meeting",
	"group_phone_1109_bg.png": "shanghai__messages",
	"bund_night_g42.png": "shanghai__night",
	"garden_phone.png": "chengdu__phone",
	"bg_cbd_office_r2.png": "call__office",
	"bg_cbd_window_chat_r3.png": "call__office",
	"turtle_boarding.png": "shizuoka__cabin",
	"cabin.png": "shizuoka__cabin",
	"trip_urashima_road.png": "shizuoka__road",
	"bg_onsen_sunset_r3.png": "shizuoka__onsen",
	"registry_door.png": "shizuoka__registration",
	"wanning_stall.png": "hainan__stall",
	"bg_wenchang_memory_r2.png": "hainan__wenchang",
	"bg_departure_pvg.png": "flight",
	"hk_street.png": "hongkong__street",
	"park_toys_r2.png": "hongkong__park",
	"park_garden_r2.png": "hongkong__park",
	"park_castle_r2.png": "hongkong__park",
	"university.png": "hongkong__campus",
}

const GAME_CUES := {
	"shanghai/drive": "shanghai__drive",
	"chengdu/pandas": "chengdu__pandas",
	"call/care": "call__care",
	"call/song": "silence",
	"call/moments": "call__moments",
	"shizuoka/fishing": "shizuoka__fishing",
	"shizuoka/onsen": "shizuoka__onsen",
	"shizuoka/registration": "shizuoka__registration",
	"shizuoka/moments": "shizuoka__moments",
	"hainan/ringtoss": "hainan__ringtoss",
	"hainan/fireworks": "hainan__fireworks",
	"hongkong/offer": "hongkong__offer",
	"hongkong/photo": "hongkong__photo",
}

static func at(shot: Dictionary, index: int) -> String:
	var chapter := str(shot.get("chapterId", ""))
	var scene: Dictionary = shot.get("scene", {})
	var bed := _location_cue(str(scene.get("bg", "")), chapter)
	var beats: Array = scene.get("beats", [])
	for i in range(mini(index + 1, beats.size())):
		var beat: Dictionary = beats[i]
		if beat.has("bg"):
			bed = _location_cue(str(beat.bg), bed)
		if beat.has("music"):
			bed = str(beat.music)
		if i == index and beat.has("game"):
			return str(GAME_CUES.get(chapter + "/" + str(beat.game), bed))
	return bed

static func _location_cue(background: String, fallback: String) -> String:
	return str(LOCATION_CUES.get(background.get_slice("|", 0).get_file(), fallback))
