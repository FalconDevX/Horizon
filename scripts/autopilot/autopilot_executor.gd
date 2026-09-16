class_name AutopilotExecutor
extends RefCounted

enum State { IDLE, WAIT_FOR_WINDOW, ORIENT, BURN, VERIFY, COMPLETE, ERROR }
var state: State = State.IDLE

var current_maneuver: Maneuver
var ship: Node2D

var _burn_start_velocity: Vector2
var _burn_start_remaining_dv: float

func _init(p_ship: Node2D) -> void:
    ship = p_ship

func execute(maneuver: Maneuver) -> void:
    current_maneuver = maneuver
    state = State.WAIT_FOR_WINDOW

func tick(dt: float) -> void:
    if state == State.IDLE or state == State.COMPLETE or state == State.ERROR:
        return
        
    if current_maneuver == null:
        state = State.IDLE
        return
        
    match state:
        State.WAIT_FOR_WINDOW:
            _tick_wait(dt)
        State.ORIENT:
            _tick_orient(dt)
        State.BURN:
            _tick_burn(dt)
        State.VERIFY:
            _tick_verify(dt)

func _tick_wait(dt: float) -> void:
    # Uproszczenie: na razie dzialamy na IMMEDIATE
    if current_maneuver.trigger_type == Maneuver.TriggerType.IMMEDIATE:
        state = State.ORIENT
        return
    # Tutaj w przyszlosci sprawdzanie anamalii, czasu itp.
    state = State.ORIENT

func _tick_orient(dt: float) -> void:
    if current_maneuver.delta_v_vector.length_squared() < 0.01:
        state = State.COMPLETE
        return
        
    var target_angle = current_maneuver.delta_v_vector.angle()
    ship.call("_steer_to", target_angle, dt)
    
    var error = absf(wrapf(ship.rotation - target_angle, -PI, PI))
    if error < 0.05:
        _burn_start_velocity = ship.velocity # Zmienic na orbital frame velocity
        _burn_start_remaining_dv = current_maneuver.delta_v_vector.length()
        state = State.BURN

func _tick_burn(dt: float) -> void:
    var burn_dir = current_maneuver.delta_v_vector.normalized()
    var target_angle = burn_dir.angle()
    ship.call("_steer_to", target_angle, dt)
    
    ship.throttle = 1.0 # W przyszlosci progresywne dlawienie
    
    # Sprawdzamy ile DV juz dostarczono
    var dv_delivered = (ship.velocity - _burn_start_velocity).dot(burn_dir)
    var remaining = _burn_start_remaining_dv - dv_delivered
    current_maneuver.remaining_delta_v = burn_dir * maxf(0.0, remaining)
    
    if remaining <= current_maneuver.tolerance_dv:
        ship.throttle = 0.0
        state = State.VERIFY

func _tick_verify(dt: float) -> void:
    ship.throttle = 0.0
    # Na razie uproszczona weryfikacja
    state = State.COMPLETE

func cancel() -> void:
    current_maneuver = null
    state = State.IDLE
    if is_instance_valid(ship):
        ship.throttle = 0.0
