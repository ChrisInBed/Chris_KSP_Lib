function engine_stage_check {
	if not stage:ready { return false. }
	local elist to list().
	list engines in elist.
	if elist:length = 0 { return false. }
	for e in elist {
		if e:stage = stage:number { set hasCurStageEngine to true. }
		if e:flameout { return true. }
	}
	if not (defined hasCurStageEngine) { return true. }
	else { unset hasCurStageEngine. }
	return false.
}

function auto_stage {
	set done to false.
	when engine_stage_check() then {
		stage.
		if done { return false. }
		else { return true. }
	}
	// do something
	set done to true.
}