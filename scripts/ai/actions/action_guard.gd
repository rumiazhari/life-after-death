class_name ActionGuard
extends UtilityAction
## Claims one of the settlement's standing GUARD jobs (one per GuardPost,
## created once at scenario setup, max_workers 1) and holds that position.
## Never self-completes -- it scores lower than any real need or threat
## response and simply loses the next reconsideration when something more
## urgent comes up, releasing the post back to AVAILABLE.

const SEARCH_RADIUS := 2000.0

var _job: Job = null

func _init() -> void:
	action_name = &"guard"
	interrupt_cost = 0.05

func can_start(ai: SurvivorAI) -> bool:
	return ai.job_board != null

func score(ai: SurvivorAI) -> float:
	var best: float = 0.0
	for job in ai.job_board.get_available_jobs(&"", ai.survivor.global_position, SEARCH_RADIUS):
		if job.job_type != Job.Type.GUARD:
			continue
		best = maxf(best, _score_job(ai, job))
	return best

func enter(ai: SurvivorAI) -> void:
	var best_job: Job = null
	var best_score: float = -1.0
	for job in ai.job_board.get_available_jobs(&"", ai.survivor.global_position, SEARCH_RADIUS):
		if job.job_type != Job.Type.GUARD:
			continue
		var s: float = _score_job(ai, job)
		if s > best_score:
			best_score = s
			best_job = job
	if best_job and ai.job_board.claim_job(best_job, ai.data.id):
		_job = best_job
		ai.current_job = _job

func tick(ai: SurvivorAI, delta: float) -> bool:
	if _job == null or not _job.is_target_valid():
		return true
	ai.reserved_target_description = "guarding post"
	var arrived: bool = ai.survivor.move_toward_point(_job.target_position, delta)
	if not arrived:
		return false
	if _job.status == Job.Status.RESERVED:
		ai.job_board.start_job(_job)
	ai.survivor.stop_moving(delta)
	return false

func exit(ai: SurvivorAI) -> void:
	if _job:
		ai.job_board.release_survivor(ai.data.id)
	_job = null

func _score_job(ai: SurvivorAI, job: Job) -> float:
	var distance: float = ai.survivor.global_position.distance_to(job.target_position)
	var brave: float = ai.data.personality.get("brave", 0.0)
	var diligent: float = ai.data.personality.get("diligent", 0.0)
	var danger_bonus: float = (ai.settlement.danger_level() / 100.0) * 0.4 if ai.settlement else 0.0
	var benefit: float = (0.2 + brave * 0.15 + diligent * 0.1 + danger_bonus) * UtilityMath.combat_confidence(ai.data)
	var cost: float = UtilityMath.distance_cost(distance, SEARCH_RADIUS)
	return clampf(benefit - cost * 0.3, 0.0, 1.0)
