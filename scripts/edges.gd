class_name Edges
extends RefCounted

## The dressing on every cliff edge of the terrain, HGSS style: a rounded
## grass lip bulging over the edge, the face below it (earth on gentle
## ground, where cliffs are half a block, rocky clods where the terrain is
## cliffy and cliffs are whole blocks), and a soft shadow on the ground at
## its foot. Lips sweep round convex corners in a curve, so plateaus read as
## rounded rather than as stacks of cubes.
##
## It's one mesh laid over the GridMap's blocks, built once per map from
## the heights; the blocks underneath still define where you can walk.

## The lip's cross-section, from the top edge outward and down: (how far
## out, how far below the top). Heights are in blocks, out in cells.
const LIP := [
	Vector2(0.0, 0.0), Vector2(0.07, -0.02), Vector2(0.125, -0.06),
	Vector2(0.155, -0.115), Vector2(0.14, -0.165), Vector2(0.085, -0.2), Vector2(0.0, -0.215),
]
## How far along the cross-section each step starts, 0..1, for wrapping
## the lip tile over it.
static var _lip_v := _lip_lengths()

## Half cliffs get a smaller lip, so it doesn't swallow their face.
const HALF_CLIFF_LIP := 0.65

## Faces sit this far in front of the blocks' own sides.
const FACE_OFFSET := 0.01
const WATER_SURFACE := -0.25
const SHADOW_WIDTH := 0.45
## Cliffs facing away from the camera (north) hide their face and foot, so
## their drop is marked by a dark rim along the lip instead.
const RIM_DEPTH := 0.12
const SHADOW_ALPHA := 0.35
## Steps for a lip sweeping round a right-angle corner.
const CORNER_STEPS := 4

const T := GridWorld.Tile
const SOLID_TOPS := [T.FULL, T.FULL_DIRT, T.ROCK, T.HALF]
const WEDGES := [T.WEDGE, T.WEDGE_DIRT, T.HALF_WEDGE, T.UPPER_HALF_WEDGE]
## Pieces at the foot of a face that lean on it and hide it.
const AGAINST := [T.HILL_RAMP, T.HALF_HILL_RAMP, T.UPPER_HALF_HILL_RAMP, T.STAIRS]


## A node holding the edge meshes for the world's current terrain.
static func build(world: GridWorld, heights: PackedInt32Array, terrain: Terrain) -> Node3D:
	var segments := _find_segments(world, heights, terrain)
	var faces := []
	var shadow := SurfaceTool.new()
	shadow.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in segments:
		faces += _lip(s.p0, s.p1, s.o, s.top, _lip_scale(s))
		faces.append(_face(s))
		if s.o.y < -0.3:
			faces.append(_rim(s))
		if not s.water and s.o.y > -0.3:
			_shadow(shadow, s)
	faces += _corners(segments)
	var root := Node3D.new()
	root.name = "Edges"
	if faces.is_empty():
		return root
	var mesh := MeshInstance3D.new()
	mesh.name = "Lips"
	mesh.mesh = world._build_mesh(faces, {}, world.block_material())
	root.add_child(mesh)
	var shadows := MeshInstance3D.new()
	shadows.name = "Shadows"
	shadows.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	shadow.set_material(mat)
	shadows.mesh = shadow.commit()
	root.add_child(shadows)
	return root


## Every exposed edge: { p0, p1 (ends, in cells), o (outward), top, bottom
## (in blocks), tex, water }. Heights come in steps of half a block.
static func _find_segments(world: GridWorld, heights: PackedInt32Array, terrain: Terrain) -> Array:
	var segments := []
	var size := world.map_size
	for z in size.y:
		for x in size.x:
			var c := Vector2i(x, z)
			var h := heights[z * size.x + x]
			if h < 0:
				continue
			var center := Vector2(x + 0.5, z + 0.5)
			var tex: int = GridWorld.Tex.DIRT if terrain.is_cliffy(x, z) else GridWorld.Tex.EARTH_SIDE
			var top_layer := (h - 1) / 2
			var top_item := world.get_cell_item(Vector3i(x, top_layer, z))
			if h > 0 and top_item in WEDGES:
				# The wedge's slanted face runs between the two corners
				# beside its solid one, facing away from it, down to the
				# ground beside it.
				var si := world._corner_dir(c, top_layer)
				var s := Vector2(si)
				var low := heights[z * size.x + x - si.x]
				segments.append({
					p0 = center + Vector2(s.x, -s.y) * 0.5, p1 = center + Vector2(-s.x, s.y) * 0.5,
					o = -s.normalized(), top = h / 2.0, bottom = maxi(low, 0) / 2.0, tex = tex, water = false,
				})
				continue
			if h > 0 and top_item not in SOLID_TOPS:
				continue
			if h == 0 and world.get_cell_item(Vector3i(x, GridWorld.GROUND_LAYER, z)) not in [T.GROUND, T.FLOWERS]:
				continue
			for d in GridWorld.ORTHOGONAL:
				var n := c + d
				if n.x < 0 or n.y < 0 or n.x >= size.x or n.y >= size.y:
					continue
				var hn := heights[n.y * size.x + n.x]
				var water := hn < 0
				if not water and hn >= h:
					continue
				if h == 0 and not water:
					continue
				# A ramp leaning on this face hides it.
				if not water and world.get_cell_item(Vector3i(n.x, hn / 2, n.y)) in AGAINST:
					continue
				var t := Vector2(-d.y, d.x)
				var mid := center + Vector2(d) * 0.5
				segments.append({
					p0 = mid - t * 0.5, p1 = mid + t * 0.5, o = Vector2(d),
					top = h / 2.0, bottom = WATER_SURFACE if water else hn / 2.0, tex = tex, water = water,
				})
	return segments


## The lip along a straight edge: one strip per step of the cross-section,
## grass on top fading to a dark underside by the faces' shading.
static func _lip(p0: Vector2, p1: Vector2, o: Vector2, top: float, scale: float) -> Array:
	var faces := []
	for i in LIP.size() - 1:
		var a: Vector2 = LIP[i] * scale
		var b: Vector2 = LIP[i + 1] * scale
		var pts := [
			_at(p0 + o * a.x, top + a.y), _at(p1 + o * a.x, top + a.y),
			_at(p1 + o * b.x, top + b.y), _at(p0 + o * b.x, top + b.y),
		]
		var u0 := _along(p0, o)
		var u1 := u0 + p0.distance_to(p1)
		faces.append([pts, _normal(o, a, b), GridWorld.Tex.LIP,
			[Vector2(u0, _lip_v[i]), Vector2(u1, _lip_v[i]), Vector2(u1, _lip_v[i + 1]), Vector2(u0, _lip_v[i + 1])]])
	return faces


## The lip swept round a corner at p, from facing o0 to facing o1.
static func _sweep(p: Vector2, o0: Vector2, o1: Vector2, top: float, scale: float) -> Array:
	var faces := []
	var a0 := o0.angle()
	var turn := wrapf(o1.angle() - a0, -PI, PI)
	var steps := maxi(1, roundi(absf(turn) / (PI / 2.0) * CORNER_STEPS))
	for k in steps:
		var u0 := Vector2.from_angle(a0 + turn * k / steps)
		var u1 := Vector2.from_angle(a0 + turn * (k + 1) / steps)
		var mid := (u0 + u1).normalized()
		for i in LIP.size() - 1:
			var a: Vector2 = LIP[i] * scale
			var b: Vector2 = LIP[i + 1] * scale
			var pts := [
				_at(p + u0 * a.x, top + a.y), _at(p + u1 * a.x, top + a.y),
				_at(p + u1 * b.x, top + b.y), _at(p + u0 * b.x, top + b.y),
			]
			var w := 0.25 * (k + 1) / steps
			var uvs := [Vector2(w - 0.25 / steps, _lip_v[i]), Vector2(w, _lip_v[i]),
				Vector2(w, _lip_v[i + 1]), Vector2(w - 0.25 / steps, _lip_v[i + 1])]
			if a.x == 0.0:
				pts.remove_at(1)
				uvs.remove_at(1)
			elif b.x == 0.0:
				pts.remove_at(2)
				uvs.remove_at(2)
			faces.append([pts, _normal(mid, a, b), GridWorld.Tex.LIP, uvs])
	return faces


## Rounds each convex corner where two edges at the same height meet.
static func _corners(segments: Array) -> Array:
	var ends := {}
	for s in segments:
		for p in [s.p0, s.p1]:
			var key := Vector3i(roundi(p.x * 2.0), roundi(p.y * 2.0), roundi(s.top * 2.0))
			if not ends.has(key):
				ends[key] = []
			ends[key].append(s)
	var faces := []
	for key in ends:
		var at: Array = ends[key]
		if at.size() != 2:
			continue
		var a: Dictionary = at[0]
		var b: Dictionary = at[1]
		var p := Vector2(key.x, key.y) / 2.0
		var along_b: Vector2 = (b.p1 if b.p0.is_equal_approx(p) else b.p0) - p
		if a.o.dot(along_b) < -0.01:
			faces += _sweep(p, a.o, b.o, a.top, minf(_lip_scale(a), _lip_scale(b)))
	return faces


## The face under the lip, a hair in front of the blocks' own side, with
## its tile hanging from the top edge so each block shows one tile.
static func _face(s: Dictionary) -> Array:
	var o: Vector2 = s.o * FACE_OFFSET
	var pts := [_at(s.p0 + o, s.top), _at(s.p1 + o, s.top), _at(s.p1 + o, s.bottom), _at(s.p0 + o, s.bottom)]
	var u0 := _along(s.p0, s.o)
	var length: float = s.p0.distance_to(s.p1)
	var uvs := [Vector2(u0, 0), Vector2(u0 + length, 0),
		Vector2(u0 + length, s.top - s.bottom), Vector2(u0, s.top - s.bottom)]
	return [pts, Vector3(s.o.x, 0, s.o.y), s.tex, uvs]


static func _lip_scale(s: Dictionary) -> float:
	return HALF_CLIFF_LIP if s.top - s.bottom <= 0.5 else 1.0


## The dark rim along the far edge of a cliff facing away from the camera:
## a strip hanging just behind the lip, facing back toward the camera, so it
## outlines the drop against the lower ground beyond.
static func _rim(s: Dictionary) -> Array:
	var out: Vector2 = s.o * (LIP[3].x * _lip_scale(s) + FACE_OFFSET)
	var top: float = s.top - 0.02
	var pts := [_at(s.p0 + out, top), _at(s.p1 + out, top),
		_at(s.p1 + out, top - RIM_DEPTH), _at(s.p0 + out, top - RIM_DEPTH)]
	var u0 := _along(s.p0, s.o)
	var u1: float = u0 + s.p0.distance_to(s.p1)
	return [pts, Vector3(-s.o.x, 0, -s.o.y), GridWorld.Tex.LIP,
		[Vector2(u0, 0.8), Vector2(u1, 0.8), Vector2(u1, 0.95), Vector2(u0, 0.95)]]


## A strip of shade on the ground at the foot of a face, fading outward.
static func _shadow(st: SurfaceTool, s: Dictionary) -> void:
	var y: float = (s.bottom + 0.004) * GridWorld.BLOCK_HEIGHT
	var near0 := Vector3(s.p0.x, y, s.p0.y)
	var near1 := Vector3(s.p1.x, y, s.p1.y)
	var out := Vector3(s.o.x, 0, s.o.y) * SHADOW_WIDTH
	var dark := Color(0, 0, 0, SHADOW_ALPHA)
	var clear := Color(0, 0, 0, 0)
	for v in [[near0, dark], [near1, dark], [near1 + out, clear],
			[near0, dark], [near1 + out, clear], [near0 + out, clear]]:
		st.set_color(v[1])
		st.set_normal(Vector3.UP)
		st.add_vertex(v[0])


## A point on the edge, in model units (heights in blocks; _build_mesh
## stretches them to BLOCK_HEIGHT).
static func _at(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, y, p.y)


## Outward normal of the cross-section step a -> b, facing o.
static func _normal(o: Vector2, a: Vector2, b: Vector2) -> Vector3:
	var d := b - a
	return (Vector3(o.x, 0, o.y) * -d.y + Vector3.UP * d.x).normalized()


## Where a texture starts along an edge from p, in world units, so
## neighbouring edges' tiles line up.
static func _along(p: Vector2, o: Vector2) -> float:
	if absf(o.y) > 0.9:
		return p.x
	if absf(o.x) > 0.9:
		return p.y
	return 0.0


## Cumulative length along LIP, as fractions of the whole: 0 at the top
## edge, 1 at the underside.
static func _lip_lengths() -> PackedFloat32Array:
	var lengths := PackedFloat32Array([0.0])
	for i in range(1, LIP.size()):
		var step: Vector2 = LIP[i] - LIP[i - 1]
		# Heights are stretched to BLOCK_HEIGHT on screen.
		lengths.append(lengths[i - 1] + Vector2(step.x, step.y * GridWorld.BLOCK_HEIGHT).length())
	for i in lengths.size():
		lengths[i] /= lengths[lengths.size() - 1]
	return lengths
