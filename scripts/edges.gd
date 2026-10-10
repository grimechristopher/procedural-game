class_name Edges
extends RefCounted

## The dressing on every cliff edge of the terrain, HGSS style: the cliff's
## rock (or earth, on gentle ground) starts on the top surface, in a band
## below a wavy grass edge, then runs down the face; and a soft shadow lies
## on the ground at its foot. The band also shows on cliffs facing away from
## the camera, whose faces are hidden, so drops to the north still read.
##
## It's one mesh laid over the GridMap's blocks, built once per map from
## the heights; the blocks underneath still define where you can walk.

## How far the band reaches in from the edge, in cells: the band tiles'
## bottom five rows (11-15).
const BAND := 5.0 / 16.0
## Faces sit this far in front of the blocks' own sides, and bands this
## far above their tops (a little more per facing, so overlapping bands at
## corners don't flicker).
const FACE_OFFSET := 0.01
const BAND_LIFT := 0.003
const WATER_SURFACE := -0.25
const SHADOW_WIDTH := 0.45
const SHADOW_ALPHA := 0.35

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
		faces.append(_band(s))
		faces.append(_face(s))
		if not s.water and s.o.y > -0.3:
			_shadow(shadow, s)
	var root := Node3D.new()
	root.name = "Edges"
	if faces.is_empty():
		return root
	var mesh := MeshInstance3D.new()
	mesh.name = "Cliffs"
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


## The band along the top of a cliff edge: grass giving way to the cliff's
## rock or earth, which meets the face at the edge.
static func _band(s: Dictionary) -> Array:
	var lift: float = BAND_LIFT * (2.0 + s.o.angle() / PI)
	var inner: Vector2 = -s.o * BAND
	var pts := [_at(s.p0 + inner, s.top + lift), _at(s.p1 + inner, s.top + lift),
		_at(s.p1, s.top + lift), _at(s.p0, s.top + lift)]
	var u0 := _along(s.p0, s.o)
	var u1: float = u0 + s.p0.distance_to(s.p1)
	var tex: int = GridWorld.Tex.CLIFF_TOP if s.tex == GridWorld.Tex.DIRT else GridWorld.Tex.EARTH_TOP
	return [pts, Vector3.UP, tex,
		[Vector2(u0, 1.0 - BAND), Vector2(u1, 1.0 - BAND), Vector2(u1, 0.999), Vector2(u0, 0.999)]]


## The face below the band, a hair in front of the blocks' own side, with
## its tile hanging from the top edge so each block shows one tile.
static func _face(s: Dictionary) -> Array:
	var o: Vector2 = s.o * FACE_OFFSET
	var pts := [_at(s.p0 + o, s.top), _at(s.p1 + o, s.top), _at(s.p1 + o, s.bottom), _at(s.p0 + o, s.bottom)]
	var u0 := _along(s.p0, s.o)
	var length: float = s.p0.distance_to(s.p1)
	var uvs := [Vector2(u0, 0), Vector2(u0 + length, 0),
		Vector2(u0 + length, s.top - s.bottom), Vector2(u0, s.top - s.bottom)]
	return [pts, Vector3(s.o.x, 0, s.o.y), s.tex, uvs]


## A strip of shade on the ground at the foot of a face, fading outward.
static func _shadow(st: SurfaceTool, s: Dictionary) -> void:
	var y: float = s.bottom + 0.004
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


## A point on the edge, in world units.
static func _at(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, y, p.y)


## Where a texture starts along an edge from p, in world units, so
## neighbouring edges' tiles line up.
static func _along(p: Vector2, o: Vector2) -> float:
	if absf(o.y) > 0.9:
		return p.x
	if absf(o.x) > 0.9:
		return p.y
	return 0.0
