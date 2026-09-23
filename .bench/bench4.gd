extends SceneTree

static func work_math(_i: int) -> void:
	var s := 0.0
	for k in 200000:
		s += sin(k * 0.001)

static func work_noise(_i: int) -> void:
	var nz := FastNoiseLite.new()
	nz.fractal_octaves = 8
	for k in 20000:
		nz.get_noise_3d(k * 0.01, 0.3, 0.2)

static func work_noise_v(_i: int) -> void:
	var nz := FastNoiseLite.new()
	nz.fractal_octaves = 8
	for k in 20000:
		nz.get_noise_3dv(Vector3(k * 0.01, 0.3, 0.2))

func run(name: String, c: Callable) -> void:
	var t := Time.get_ticks_msec()
	for i in 4: c.call(i)
	var serial := Time.get_ticks_msec() - t
	t = Time.get_ticks_msec()
	var g := WorkerThreadPool.add_group_task(c, 28, -1, true)
	WorkerThreadPool.wait_for_group_task_completion(g)
	print(name, ": serial x4 ", serial, " ms, parallel x28 ", Time.get_ticks_msec() - t, " ms")

func _init() -> void:
	run("math", work_math)
	run("noise", work_noise)
	run("noise_v", work_noise_v)
	quit()
