extends Resource
class_name BakedHeightmap
## External height samples so forest_baked.tscn stays small.


@export var terrain_size: float = 1000.0
@export var height_res: int = 257
@export var heights: PackedFloat32Array = PackedFloat32Array()
