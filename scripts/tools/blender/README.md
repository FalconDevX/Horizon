# Deposit models (Blender)

`models/deposits/` is made by these two scripts, run inside Blender 4.3
(through the Blender MCP, or the Scripting tab):

- `respipe.py` - the pipeline: build meshes with bmesh, smart-UV them, bake
  each material's `COLOR` (emission) and `MASK` into one PNG (RGB colour with
  ambient occlusion, alpha = where the type's shine/glow applies), export one
  OBJ per variant (Y up, cluster units: ~1 across, feet a little below 0).
- `deposits.py` - one builder and material list per deposit type.

The materials sample Poly Haven textures (CC0) that must be loaded in the
.blend first, by image name: `rock_surface`, `dark_rock`, `rusty_metal_02`,
`metal_plate_02`, `green_metal_rust`, `bark_willow_02`, `snow_02`,
`white_stucco`, `marble_01`, `rock_08` (1k; `<id>_Diffuse`,
`metal_plate_02_Rough`).

```python
import sys; sys.path.append(r"<repo>/scripts/tools/blender")
import deposits
deposits.make("gold_ore", 3, 1024)   # -> models/deposits/gold_ore_1..3.obj + gold_ore_albedo.png
```

`respipe.OUT` is where it writes. `resource_deposits.gd` `MODELS` lists the
types and how many variants each has.
