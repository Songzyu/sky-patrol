extends Node2D

const SIZE := Vector2(768, 640)
const INK := Color("#dff8ff")
const DIM := Color("#87aec5")
const CYAN := Color("#54ebff")
const RED := Color("#ff647c")
const GOLD := Color("#ffc56d")
const NAVY := Color("#122942")

enum { TITLE, PLAY, PAUSE, LOST }

var mode := TITLE
var pilot := Vector2(384, 540)
var shots: Array[Vector2] = []
var hostile: Array[Dictionary] = []
var enemies: Array[Dictionary] = []
var sparks: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()
var scenery := RandomNumberGenerator.new()
var terrain: Array[Dictionary] = []
var elapsed := 0.0
var scroll := 0.0
var spawn_in := 0.0
var fire_in := 0.0
var shield := 0.0
var score := 0
var best := 0
var hull := 3
var wave := 1
var wave_flash := 0.0


func _ready() -> void:
	scenery.seed = 46321
	for index in range(44):
		terrain.append({
			"pos": Vector2(scenery.randf_range(12, 756), scenery.randf_range(0, 880)),
			"scale": scenery.randf_range(0.45, 1.35),
			"kind": index % 6
		})
	var save := ConfigFile.new()
	if save.load("user://flight.cfg") == OK:
		best = int(save.get_value("records", "best", 0))


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed or event.echo:
		return
	if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
		if mode == TITLE or mode == LOST:
			start_flight()
		elif mode == PAUSE:
			mode = PLAY
	if event.keycode == KEY_ESCAPE or event.keycode == KEY_P:
		if mode == PLAY:
			mode = PAUSE
		elif mode == PAUSE:
			mode = PLAY


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and mode == PLAY:
		mode = PAUSE


func start_flight() -> void:
	pilot = Vector2(384, 540)
	shots.clear()
	hostile.clear()
	enemies.clear()
	sparks.clear()
	elapsed = 0.0
	spawn_in = 0.55
	fire_in = 0.0
	shield = 0.0
	score = 0
	hull = 3
	wave = 1
	wave_flash = 1.7
	mode = PLAY


func _physics_process(delta: float) -> void:
	if mode != PAUSE:
		scroll = fposmod(scroll + delta * 104.0, 880.0)
		update_sparks(delta)
	if mode == PLAY:
		update_flight(delta)
	queue_redraw()


func update_flight(delta: float) -> void:
	elapsed += delta
	var next_wave := 1 + int(elapsed / 18.0)
	if next_wave != wave:
		wave = next_wave
		wave_flash = 1.8
	wave_flash -= delta
	shield -= delta

	var steering := Vector2(
		float(held(KEY_RIGHT, KEY_D)) - float(held(KEY_LEFT, KEY_A)),
		float(held(KEY_DOWN, KEY_S)) - float(held(KEY_UP, KEY_W))
	)
	pilot += steering.normalized() * 355.0 * delta
	pilot = pilot.clamp(Vector2(23, 91), SIZE - Vector2(23, 24))

	fire_in -= delta
	if Input.is_physical_key_pressed(KEY_SPACE) and fire_in <= 0.0:
		shots.append(pilot + Vector2(-10, -11))
		shots.append(pilot + Vector2(10, -11))
		fire_in = 0.145

	spawn_in -= delta
	if spawn_in <= 0.0:
		spawn_enemy()
		spawn_in = maxf(0.32, 0.94 - (wave - 1) * 0.085)

	for index in range(shots.size() - 1, -1, -1):
		shots[index].y -= 570.0 * delta
		if shots[index].y < -12:
			shots.remove_at(index)

	update_enemies(delta)
	update_hostile(delta)


func held(arrow: Key, letter: Key) -> bool:
	return Input.is_physical_key_pressed(arrow) or Input.is_physical_key_pressed(letter)


func spawn_enemy() -> void:
	var heavy := wave >= 2 and rng.randf() < 0.24
	var lane := rng.randf_range(58, SIZE.x - 58)
	enemies.append({
		"pos": Vector2(lane, -28),
		"lane": lane,
		"phase": rng.randf_range(0.0, TAU),
		"age": 0.0,
		"speed": (72.0 if heavy else 104.0) + minf(85.0, wave * 9.0),
		"hp": 4 if heavy else 2,
		"heavy": heavy,
		"fire": rng.randf_range(0.95, 1.85)
	})


func update_enemies(delta: float) -> void:
	for index in range(enemies.size() - 1, -1, -1):
		var enemy := enemies[index]
		enemy.age += delta
		enemy.pos.y += enemy.speed * delta
		enemy.pos.x = enemy.lane + sin(enemy.age * 2.15 + enemy.phase) * 42.0
		var center: Vector2 = enemy.pos
		var radius := 22.0 if enemy.heavy else 17.0
		if center.y > SIZE.y + 40:
			enemies.remove_at(index)
			continue
		enemy.fire -= delta
		if enemy.fire <= 0.0 and center.y > 70.0 and center.y < pilot.y - 65.0:
			var direction := center.direction_to(pilot)
			hostile.append({"pos": center, "velocity": direction * (182.0 + minf(90.0, wave * 12.0))})
			enemy.fire = rng.randf_range(1.75, 2.6)

		for shot_index in range(shots.size() - 1, -1, -1):
			if shots[shot_index].distance_squared_to(center) <= radius * radius:
				burst(shots[shot_index], GOLD, 3)
				shots.remove_at(shot_index)
				enemy.hp -= 1
				if enemy.hp <= 0:
					break
		if enemy.hp <= 0:
			burst(center, GOLD if enemy.heavy else RED, 19)
			score += 250 if enemy.heavy else 100
			enemies.remove_at(index)
		elif shield <= 0.0 and pilot.distance_to(center) < radius + 11.0:
			burst(center, RED, 12)
			enemies.remove_at(index)
			hit_pilot()
			if mode == LOST:
				return


func update_hostile(delta: float) -> void:
	if mode != PLAY:
		return
	for index in range(hostile.size() - 1, -1, -1):
		var projectile := hostile[index]
		projectile.pos += projectile.velocity * delta
		if not Rect2(Vector2(-20, -20), SIZE + Vector2(40, 40)).has_point(projectile.pos):
			hostile.remove_at(index)
		elif shield <= 0.0 and pilot.distance_squared_to(projectile.pos) < 190.0:
			hostile.remove_at(index)
			hit_pilot()
			if mode == LOST:
				return


func hit_pilot() -> void:
	hull -= 1
	shield = 1.55
	burst(pilot, CYAN, 25)
	if hull == 0:
		mode = LOST
		if score > best:
			best = score
			var save := ConfigFile.new()
			save.set_value("records", "best", best)
			save.save("user://flight.cfg")


func burst(center: Vector2, color: Color, count: int) -> void:
	for index in range(count):
		sparks.append({
			"pos": center,
			"velocity": Vector2.from_angle(rng.randf_range(0, TAU)) * rng.randf_range(24, 166),
			"life": rng.randf_range(0.18, 0.47),
			"color": color
		})


func update_sparks(delta: float) -> void:
	for index in range(sparks.size() - 1, -1, -1):
		var spark := sparks[index]
		spark.pos += spark.velocity * delta
		spark.life -= delta
		if spark.life <= 0.0:
			sparks.remove_at(index)


func _draw() -> void:
	draw_ocean()
	for shot in shots:
		draw_line(shot, shot + Vector2(0, 13), Color(CYAN, 0.22), 8.0, true)
		draw_line(shot, shot + Vector2(0, 10), INK, 2.0, true)
	for enemy in enemies:
		draw_plane(enemy.pos, PI, GOLD if enemy.heavy else RED, 1.25 if enemy.heavy else 0.9)
	for projectile in hostile:
		draw_circle(projectile.pos, 8, Color(RED, 0.23))
		draw_circle(projectile.pos, 4, GOLD)
	for spark in sparks:
		draw_circle(spark.pos, 1.0 + spark.life * 5.0, Color(spark.color, minf(1.0, spark.life * 4.0)))
	if hull > 0 and (shield <= 0.0 or int(shield * 17.0) % 2 == 0):
		draw_plane(pilot, 0.0, CYAN, 1.06)
		if shield > 0.0:
			draw_arc(pilot, 26, 0, TAU, 32, Color(CYAN, 0.55), 2.0, true)
	draw_hud()
	if mode == PLAY and wave_flash > 0.0:
		center_text("WAVE %02d" % wave, 131, 25, Color(CYAN, minf(1.0, wave_flash * 2.0)))
	elif mode != PLAY:
		draw_overlay()


func draw_ocean() -> void:
	draw_rect(Rect2(Vector2.ZERO, SIZE), Color("#0b3049"))
	for index in range(11):
		var y := fposmod(index * 80.0 + scroll, 880.0) - 80.0
		draw_line(Vector2(0, y), Vector2(SIZE.x, y), Color("#15435c"))
	for item in terrain:
		var center := Vector2(item.pos.x, fposmod(item.pos.y + scroll, 880.0) - 120.0)
		var scale_factor: float = item.scale
		if item.kind == 0:
			for layer in range(4):
				var shift := Vector2(layer * 22.0 - 25.0, sin(layer * 1.8) * 13.0) * scale_factor
				draw_circle(center + shift, (34.0 - layer * 3.0) * scale_factor, Color(0.53, 0.82, 0.87, 0.07), true, -1.0, true)
		else:
			var streak := Vector2(32, 0) * scale_factor
			draw_line(center, center + streak, Color(0.43, 0.76, 0.84, 0.19), 1.0, true)
	draw_line(Vector2(13, 60), Vector2(13, SIZE.y), Color(CYAN, 0.16))
	draw_line(Vector2(SIZE.x - 13, 60), Vector2(SIZE.x - 13, SIZE.y), Color(CYAN, 0.16))


func draw_plane(center: Vector2, angle: float, accent: Color, scale_factor: float) -> void:
	draw_set_transform(center + Vector2(5, 8), angle, Vector2.ONE * scale_factor)
	var silhouette := PackedVector2Array([
		Vector2(0, -26), Vector2(7, -8), Vector2(24, 5), Vector2(24, 12),
		Vector2(8, 9), Vector2(9, 19), Vector2(0, 16), Vector2(-9, 19),
		Vector2(-8, 9), Vector2(-24, 12), Vector2(-24, 5), Vector2(-7, -8)
	])
	draw_colored_polygon(silhouette, Color(0.01, 0.05, 0.1, 0.38))
	draw_set_transform(center, angle, Vector2.ONE * scale_factor)
	draw_colored_polygon(silhouette, accent)
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, -20), Vector2(5, 1), Vector2(3, 15), Vector2(-3, 15), Vector2(-5, 1)
	]), INK.lerp(accent, 0.35))
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, -12), Vector2(4, -2), Vector2(0, 4), Vector2(-4, -2)
	]), NAVY)
	var flame := 5.0 + sin(scroll * 0.37) * 2.5
	draw_line(Vector2(0, 17), Vector2(0, 17 + flame), GOLD, 3.0, true)
	draw_set_transform(Vector2.ZERO)


func draw_hud() -> void:
	draw_rect(Rect2(0, 0, SIZE.x, 63), Color("#081826"))
	draw_line(Vector2(0, 62), Vector2(SIZE.x, 62), Color("#317088"), 1.0)
	label("SCORE", Vector2(27, 22), 13, DIM)
	label("%06d" % score, Vector2(27, 48), 23, INK)
	label("BEST", Vector2(161, 22), 13, DIM)
	label("%06d" % maxi(score, best), Vector2(161, 48), 23, INK)
	center_text("WAVE %02d" % wave, 39, 17, CYAN)
	label("HULL", Vector2(597, 37), 13, DIM)
	for index in range(3):
		var cell := Rect2(650 + index * 29, 25, 22, 13)
		draw_rect(cell, CYAN if index < hull else Color("#293f51"))


func draw_overlay() -> void:
	draw_rect(Rect2(0, 63, SIZE.x, SIZE.y - 63), Color(0.015, 0.05, 0.09, 0.62))
	var panel := Rect2(115, 156, 538, 328)
	draw_rect(panel, Color("#0b2034"))
	draw_rect(panel, Color("#2b627a"), false, 1.0)
	draw_rect(Rect2(115, 156, 538, 3), CYAN)
	if mode == TITLE:
		center_text("ARCADE  /  AIR COMBAT", 199, 15, CYAN)
		center_text("SKY PATROL", 275, 64, INK)
		center_text("CLEAR THE SKIES. SURVIVE EACH WAVE.", 318, 17, DIM)
		center_text("ARROWS / WASD   Move      SPACE   Fire      P   Pause", 370, 15, DIM)
		draw_button("ENTER   /   START")
	elif mode == PAUSE:
		center_text("FLIGHT ON HOLD", 207, 15, CYAN)
		center_text("PAUSED", 291, 62, INK)
		center_text("ARROWS / WASD   Move      SPACE   Fire", 353, 16, DIM)
		draw_button("ENTER   /   RESUME")
	else:
		center_text("END OF FLIGHT", 207, 15, RED)
		center_text("GAME OVER", 286, 58, INK)
		center_text("SCORE %06d     BEST %06d" % [score, best], 351, 23, DIM)
		draw_button("ENTER   /   RETRY")


func draw_button(message: String) -> void:
	draw_rect(Rect2(251, 402, 266, 47), CYAN)
	center_text(message, 432, 17, NAVY)


func center_text(message: String, y: float, font_size: int, color: Color) -> void:
	var width := ThemeDB.fallback_font.get_string_size(message, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	label(message, Vector2((SIZE.x - width) / 2.0, y), font_size, color)


func label(message: String, position_on_screen: Vector2, font_size: int, color: Color) -> void:
	draw_string(ThemeDB.fallback_font, position_on_screen, message, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
