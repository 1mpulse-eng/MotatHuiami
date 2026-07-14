extends Node
# FlowManager.gd — Project Settings → Autoload

signal stage_changed(new_stage: int, old_stage: int)
signal flow_reset

# Пороги в убийствах для каждой стадии. Индекс массива = номер стадии.
const STAGE_THRESHOLDS := [0, 3, 6, 9, 15]

var kill_count: int = 0
var current_stage: int = 0

func register_kill():
	kill_count += 1
	_recompute_stage()

func _recompute_stage():
	var new_stage = 0
	for i in STAGE_THRESHOLDS.size():
		if kill_count >= STAGE_THRESHOLDS[i]:
			new_stage = i
	if new_stage != current_stage:
		var old_stage = current_stage
		current_stage = new_stage
		stage_changed.emit(current_stage, old_stage)

func reset_flow():
	if current_stage == 0 and kill_count == 0:
		return
	kill_count = 0
	current_stage = 0
	flow_reset.emit()
