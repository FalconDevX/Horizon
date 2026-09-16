class_name AutopilotController
extends RefCounted

var ship: Node2D
var executor: AutopilotExecutor

var target_planet: ProcPlanet
var active: bool = false

func _init(p_ship: Node2D) -> void:
    ship = p_ship
    executor = AutopilotExecutor.new(ship)

func engage(target: ProcPlanet) -> void:
    target_planet = target
    active = true
    
    # Prowizoryczny manewr testowy dla etapu 2
    var m = Maneuver.new("Test")
    m.trigger_type = Maneuver.TriggerType.IMMEDIATE
    m.delta_v_vector = Vector2(100.0, 0.0)
    m.reference_body = target
    executor.execute(m)

func cancel() -> void:
    active = false
    target_planet = null
    executor.cancel()

func tick(dt: float, universe) -> void:
    if not active:
        return
    executor.tick(dt)
