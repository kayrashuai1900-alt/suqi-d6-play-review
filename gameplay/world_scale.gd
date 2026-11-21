extends RefCounted
## All coordinates are logical 360×640. Each pair marks floor depth and standing
## body height, calibrated against cars, furniture and doors in each camera.
## Top-down banquet art intentionally keeps a constant scale.
const PERSON_HEIGHT_M := 1.65
const CAR_HEIGHT_M := 1.45
# Visible bounds of the side and three-quarter sprites, excluding transparent padding.
const CAR_BOUNDS := {
	"car_street.png": Rect2(0, 0, 263, 80),
	"g42_rear_r2.png": Rect2(7, 15, 305, 230),
	"g42_front_r2.png": Rect2(6, 15, 308, 230),
}
const PROFILES := {
	"shanghai_street": [310.0, 62.0, 610.0, 96.0],
	# The painted bays are about 134 px wide at the bumper line y=368.
	# An ~94 px rear view at that depth corresponds to an 81 px standing person.
	"shanghai_parking": [274.0, 59.0, 368.0, 81.0, 580.0, 126.0],
	"chengdu": [270.0, 62.0, 560.0, 110.0],
	"wolong": [280.0, 45.0, 365.0, 72.0, 542.0, 112.0],
	"panda_garden": [176.0, 43.0, 360.0, 64.0, 523.0, 88.0],
	"room": [368.0, 185.0, 620.0, 270.0],
	"office": [432.0, 160.0, 610.0, 225.0],
	"pier": [376.0, 115.0, 590.0, 190.0],
	"boat": [430.0, 180.0, 610.0, 256.0],
	"harbor": [430.0, 82.0, 480.0, 96.0, 620.0, 140.0],
	"cabin": [250.0, 78.0, 620.0, 180.0],
	"boarding": [420.0, 78.0, 620.0, 144.0],
	"pool": [290.0, 72.0, 580.0, 165.0],
	"beach": [170.0, 46.0, 310.0, 72.0, 450.0, 95.0, 620.0, 170.0],
	"beach_memory": [430.0, 44.0, 600.0, 128.0],
	"airport_departure": [380.0, 78.0, 590.0, 116.0],
	"airport": [340.0, 75.0, 400.0, 98.0, 615.0, 165.0],
	"banquet": [198.0, 50.0, 600.0, 50.0],
	"disney": [383.0, 48.0, 620.0, 128.0],
	# Tourists and leads share the same paving depth in all three park views.
	"hk_park": [340.0, 77.0, 420.0, 110.0, 590.0, 178.0, 640.0, 193.0],
}

static func profile(scene_id: String, background := "") -> String:
	if scene_id in ["shanghai_street", "shanghai_parking"]: return scene_id
	if "wolong_entrance" in background: return "wolong"
	if "panda_garden" in background: return "panda_garden"
	if "chengdu" in scene_id or "chengdu" in background: return "chengdu"
	if "bg_cbd_office" in background: return "office"
	if "bg_room" in background or "l3_computer" in background: return "room"
	if "bg_pier" in background or "shizuoka_pier" in background: return "pier"
	if "bg_boat" in background or "boat_cabin" in background: return "boat"
	if "bg_wanning" in background: return "pool"
	if "bg_wenchang" in background: return "beach"
	if "bg_departure_pvg" in background: return "airport_departure"
	if "bg_arrival" in background or "arrivals_sunset" in background: return "airport"
	if "bg_disney" in background: return "disney"
	return ""

static func height_at(key: String, floor_y: float, fallback := 128.0) -> float:
	if not PROFILES.has(key): return fallback
	var p: Array = PROFILES[key]
	for i in range(2, p.size(), 2):
		if floor_y <= p[i]:
			return lerpf(p[i - 1], p[i + 1], clampf((floor_y - p[i - 2]) / (p[i] - p[i - 2]), 0.0, 1.0))
	return p.back()

static func walker_multiplier(walker: Dictionary) -> float:
	return float(walker.heightM) / PERSON_HEIGHT_M if walker.has("heightM") else float(walker.get("scale", 0.94))

static func vehicle_height_m(file: String) -> float:
	return CAR_HEIGHT_M if CAR_BOUNDS.has(file.get_file()) else 0.0

static func vehicle_source_rect(file: String) -> Rect2:
	return CAR_BOUNDS.get(file.get_file(), Rect2())

static func pose_ratio(file: String) -> float:
	# Sitting shortens the body on screen; do not stretch a seated image to the
	# full standing height. Source canvas resolution never determines world size.
	return 0.844 if file.get_file().ends_with("_sit.png") else 1.0

static func foot_x(file: String, texture_width: float) -> float:
	return float({"toretto_neutral_r2.png": 505.0, "toretto_gifts_r2.png": 462.5,
		"toretto_back_r2.png": 491.5, "ayu_fish_hold.png":49.0, "ayu_fish_cast.png":64.0, "ayu_fish_reel.png":64.0}.get(file.get_file(), texture_width * 0.5))

static func visible_rect(texture: Texture2D) -> Rect2:
	# Generated transparent PNGs contain almost invisible (alpha < 16/255)
	# pixels outside the figure. Content bounds omit that fringe, not the body.
	var bounds := {"ayu_fish_hold.png":Rect2(12,8,104,192), "ayu_fish_cast.png":Rect2(39,8,51,192), "ayu_fish_reel.png":Rect2(39,8,51,192),
		"toretto_neutral_r2.png": Rect2(299, 61, 412, 1457),
		"toretto_gifts_r2.png": Rect2(251, 66, 546, 1459),
		"toretto_back_r2.png": Rect2(299, 64, 386, 1458),
		"toretto_walk_back.png": Rect2(75, 17, 111, 386),
		"ayu_trip_sit.png": Rect2(295, 276, 382, 1224),
		"toretto_trip_sit.png": Rect2(241, 269, 496, 1137)}
	var file := texture.resource_path.get_file()
	# Cabin atlas regions are already cut to the visible figure.
	if texture is AtlasTexture and file.begins_with("ayu_trip_"):
		return Rect2(Vector2.ZERO, texture.get_size())
	if bounds.has(file):
		return bounds[file]
	return Rect2(texture.get_image().get_used_rect())

static func local_rect(file: String, texture_width: float, used: Rect2, standing_height: float) -> Rect2:
	var height := standing_height * pose_ratio(file)
	var k := height / maxf(used.size.y, 1)
	return Rect2(Vector2((used.position.x - foot_x(file, texture_width)) * k, -height), used.size * k)

static func guest_parts(used: Rect2, standing_height: float, guest: int) -> Array[Rect2]:
	# Head pixels keep their aspect ratio. The village's compact body is extended
	# separately to match the story actors; transparent padding is not anatomy.
	var child := guest in [11,12]
	var height := standing_height * (0.70 if child else 1.0)
	# Neck rows differ by hairstyle and age. A fixed row slices some faces in
	# half, stretching the jaw as though it were part of the torso.
	var neck_rows := [0,33,32,38,32,40,42,32,30,38,35,56,55]
	var source_head := float(neck_rows[clampi(guest,1,12)])-used.position.y
	var head_height := height * (0.23 if child else 0.20)
	var head_width := 64.0 * head_height / source_head
	var body_width := height * 0.54
	return [Rect2(-head_width/2,-height,head_width,head_height),
		Rect2(-body_width/2,-height+head_height,body_width,height-head_height),
		Rect2(0,used.position.y,64,source_head),
		Rect2(0,used.position.y+source_head,64,used.size.y-source_head)]
