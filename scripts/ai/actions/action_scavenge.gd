class_name ActionScavenge
extends UtilityAction
## Claims a SCAVENGE job from the settlement job board (one per
## ScavengePoint, created at scenario setup), walks to it, works it for the
## point's configured duration, and deposits the yield into the survivor's
## carried inventory. Job-board claiming means two survivors scoring this
## action in the same window never converge on the same point.

const SEARCH_RADIUS := 900.0

var _job: Job = null
var _work_timer: float = 0.0

func _init() -> void:
	action_name = &"scavenge"
	interrupt_cost = 0.25

func can_start(ai: SurvivorAI) -> bool:
	return ai.job_board != null

func score(ai: SurvivorAI) -> float:
	var best: float = 0.0
	for job in ai.job_board.get_available_jobs(&"", ai.survivor.global_position, SEARCH_RADIUS):
		if job.job_type != Job.Type.SCAVENGE:
			continue
		var point := job.get_target() as ScavengePoint
		if point == null:
			continue
		var s: float = _score_point(ai, point)
		best = maxf(best, s)
	return best

func enter(ai: SurvivorAI) -> void:
	var best_job: Job = null
	var best_score: float = -1.0
	for job in ai.job_board.get_available_jobs(&"", ai.survivor.global_position, SEARCH_RADIUS):
		if job.job_type != Job.Type.SCAVENGE:
			continue
		var point := job.get_target() as ScavengePoint
		if point == null:
			continue
		var s: float = _score_point(ai, point)
		if s > best_score:
			best_score = s
			best_job = job
	if best_job and ai.job_board.claim_job(best_job, ai.data.id):
		_job = best_job
		ai.current_job = _job
		_work_timer = 0.0

func tick(ai: SurvivorAI, delta: float) -> bool:
	if _job == null or not _job.is_target_valid():
		return true
	var point := _job.get_target() as ScavengePoint
	if point == null or point.is_depleted():
		return true
	ai.reserved_target_description = "scavenging %s" % point.name
	var arrived: bool = ai.survivor.move_toward_point(point.global_position, delta)
	if not arrived:
		return false
	if _job.status == Job.Status.RESERVED:
		ai.job_board.start_job(_job)
	_work_timer += delta
	if _work_timer < point.scavenge_duration:
		return false
	# Atomic: either the capacity-limited amount moves from the point into
	# the survivor's inventory completely, or nothing does -- see
	# ScavengePoint.harvest_into().
	point.harvest_into(ai.survivor.carried_inventory)
	if point.is_depleted():
		ai.job_board.complete_job(_job)
	else:
		# Still has stock -- reopen the job (AVAILABLE again) instead of
		# completing it, so this point gets revisited instead of a single
		# harvest permanently retiring it.
		ai.job_board.release_survivor(ai.data.id)
	_job = null
	return true

func exit(ai: SurvivorAI) -> void:
	if _job:
		ai.job_board.release_survivor(ai.data.id)
	_job = null
	_work_timer = 0.0

func _score_point(ai: SurvivorAI, point: ScavengePoint) -> float:
	var distance: float = ai.survivor.global_position.distance_to(point.global_position)
	var risk: float = UtilityMath.risk_from_danger(point.danger, ai.data.personality.get("brave", 0.0))
	var benefit: float = 0.5 + ai.data.scavenging_skill / 200.0
	var cost: float = UtilityMath.distance_cost(distance, SEARCH_RADIUS)
	return clampf(benefit - risk * 0.5 - cost * 0.4, 0.0, 1.2)
