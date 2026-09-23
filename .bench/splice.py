p='planet_terrain.gd'
s=open(p,encoding='utf-8').read()
def cut(s,a,b,new):
    i=s.index(a); j=s.index(b)
    return s[:i]+new+s[j:]
rd=lambda f: open(f,encoding='utf-8').read()
s=cut(s,'## Bakes the heightmap.','## One oval storm',rd('.bench/bake_block.gd'))
s=cut(s,'static func _raw_height(','## Height below which','')
s=cut(s,'## Height below which','## Which face a direction',rd('.bench/level_block.gd'))
s=s.replace('''## Rows of one face baked by a single worker task.
const BAND_ROWS := 16
''','''const BAKE_SHADER: RDShaderFile = preload("res://planet_terrain_bake.glsl")
''')
s=s.replace('''static var _cache: Dictionary = {}
''','''static var _cache: Dictionary = {}

## One GPU bake at a time: each opens its own local RenderingDevice.
static var _gpu_mutex := Mutex.new()
''')
open(p,'w',encoding='utf-8',newline='\n').write(s)
