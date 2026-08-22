class_name VoxelMaterialRegistry
extends RefCounted

enum Id {
	AIR = 0,
	GRASS = 1,
	ROAD = 2,
	PAVEMENT = 3,
	BRICK = 4,
	ROOF = 5,
	DIRT = 6,
	COBBLE = 7,
	FLOOR = 8,
	GLASS = 9,
	WOOD = 10,
	BOARD = 11,
}

const DEFINITIONS := {
	Id.GRASS: {"name": &"grass", "solid": true, "walkable": true, "durability": -1.0, "color": Color("#58764b")},
	Id.ROAD: {"name": &"road", "solid": true, "walkable": true, "durability": -1.0, "color": Color("#30343a")},
	Id.PAVEMENT: {"name": &"pavement", "solid": true, "walkable": true, "durability": -1.0, "color": Color("#8f918c")},
	Id.BRICK: {"name": &"brick", "solid": true, "walkable": false, "durability": 140.0, "minimum_damage_class": 2, "color": Color("#854d42")},
	Id.ROOF: {"name": &"roof", "solid": true, "walkable": false, "durability": 100.0, "minimum_damage_class": 1, "color": Color("#4d5968")},
	Id.DIRT: {"name": &"dirt", "solid": true, "walkable": true, "durability": -1.0, "color": Color("#745d3f")},
	Id.COBBLE: {"name": &"cobble", "solid": true, "walkable": true, "durability": -1.0, "color": Color("#696b68")},
	Id.FLOOR: {"name": &"floor", "solid": true, "walkable": true, "durability": 80.0, "color": Color("#9b8264")},
	Id.GLASS: {"name": &"glass", "solid": true, "walkable": false, "durability": 25.0, "minimum_damage_class": 0, "color": Color("#a8d4e0")},
	Id.WOOD: {"name": &"wood", "solid": true, "walkable": false, "durability": 55.0, "minimum_damage_class": 0, "color": Color("#6b3f24")},
	Id.BOARD: {"name": &"board", "solid": true, "walkable": false, "durability": 55.0, "minimum_damage_class": 0, "color": Color("#8a7351")},
}


static func definition(material_id: int) -> Dictionary:
	return (DEFINITIONS.get(material_id, {}) as Dictionary).duplicate()


static func material_id_for_surface(surface: StringName) -> int:
	match surface:
		&"asphalt": return Id.ROAD
		&"cobble": return Id.COBBLE
		&"grass": return Id.GRASS
		&"dirt": return Id.DIRT
		&"plaza", &"concrete": return Id.PAVEMENT
		_: return Id.GRASS


static func create_render_materials() -> Array[Material]:
	var result: Array[Material] = []
	for material_id in range(1, Id.BOARD + 1):
		var material := StandardMaterial3D.new()
		material.albedo_color = definition(material_id).get("color", Color.MAGENTA)
		material.vertex_color_use_as_albedo = true
		material.roughness = 0.9
		if material_id == Id.GLASS:
			material.emission_enabled = true
			material.emission = Color(0.35, 0.55, 0.62)
			material.emission_energy_multiplier = 0.25
		result.append(material)
	return result
