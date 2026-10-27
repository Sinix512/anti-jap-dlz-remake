extends "res://tests/ForecastCandidateSetTest.gd"
const H2=preload("res://tests/helpers/H2WindowPlanner.gd")
const H1=preload("res://tests/helpers/TacticalForecast.gd")
const Geometry=preload("res://tests/helpers/TacticalPlanner.gd")
func run() -> void:
	data=Codec.integers(JSON.parse_string(FileAccess.get_file_as_string("res://data/m4.json")))
	var risk_live=fixture(8);var risk_actor=risk_live.unit_by_slot(0)
	risk_actor.x=1;risk_actor.y=4;risk_live.unit_by_slot(40).x=5;risk_live.unit_by_slot(40).y=5
	risk_live.unit_by_slot(7).x=1;risk_live.unit_by_slot(7).y=3
	risk_live.unit_by_slot(48).alive=false
	var danger:=Vector2i(5,4);var origin:=Vector2i(risk_actor.x,risk_actor.y)
	var live_before:=state(risk_live)
	var live_risk:int=Geometry.immediate_risk(risk_live,risk_actor,danger)
	check(Geometry.immediate_risk(risk_live,risk_actor,origin)==0 and live_risk>0,"risk counterexample origin safe but candidate in live enemy range")
	check(live_before==state(risk_live),"legacy linear risk restores actor")
	var risk_public=Public.clone_public_board(risk_live);boards.append(risk_public)
	var public_actor=risk_public.unit_by_slot(0);var risk_before:=Public.snapshot(risk_public)
	check(Geometry.immediate_risk(risk_public,public_actor,danger)==0,"counterexample detects stale public occupancy in unwrapped geometry")
	check(H2._immediate_risk(risk_public,public_actor,danger)==live_risk,"H2 local cache-safe risk equals live linear risk")
	check(Public.snapshot(risk_public)==risk_before and risk_public._unit_at(origin)==public_actor and risk_public._unit_at(danger)==null,"H2 risk restores source and both occupancy endpoints")
	var b=fixture(8);var u=b.unit_by_slot(0)
	# Deterministic candidates let exact outer-budget boundaries be asserted.
	for actor in b.units:
		for key in actor.skill_counts:actor.skill_counts[key]=0
	var before:=state(b);var source_mines:Array=b.mines.duplicate(true)
	var generator=Candidates.new();var offered:Dictionary=generator.generate(b,u)
	var baseline:Dictionary={};var best:=-2147483648
	for a in offered.shortlist:
		var forecast:Dictionary=H1.evaluate(b,u.slot,a);var score:int=int(a.utility)-int(forecast.cost)
		if score>best:best=score;baseline=a
	var choice:=H2.choose(b,0,{"first":0})
	check(not choice.conditional_survival and choice.status=="no-witness","zero first budget cannot manufacture survival")
	check(H2.action_key(choice.choice)==H2.action_key(baseline),"fallback is exact original H1 shortlist winner")
	check(choice.totals.actions==0 and choice.totals.candidates==0 and choice.candidates.all(func(c):return c.status=="incomplete"),"zero first budget does not start a tree")
	choice=H2.choose(b,0,{"h1":0})
	check(choice.status=="incomplete" and choice.choice.is_empty() and not choice.conditional_survival,"truncated H1 ranking supplies no fake old-H1 fallback")
	choice=H2.choose(b,0,{"first":2,"candidates":1})
	check(choice.conditional_survival and choice.totals.candidates==1,"one complete witness may be selected with all caps respected")
	check(choice.candidates.size()>=2 and choice.candidates[0].status=="complete" and choice.candidates[1].status=="incomplete","second first-plan cannot reset global second-candidate budget")
	check(choice.totals.branches==1,"unused first tree does not consume extra root")
	choice=H2.choose(b,0,{"first":2,"candidates":2})
	check(choice.conditional_survival and choice.totals.candidates==2 and choice.totals.branches==2,"exact outer budget counts two independent roots and second candidates")
	check(choice.candidates[0].status=="complete" and choice.candidates[1].status=="complete","both first trees complete at exact shared cap")
	var public=Public.clone_public_board(b)
	check(Public.validate_action(public,public.unit_by_slot(0),choice.choice).complete,"selected first command remains legal at live public boundary")
	public.free()
	for limits in [{"actions":0},{"branches":0},{"candidates":0},{"collections":0},{"preflights":0}]:
		choice=H2.choose(b,0,limits)
		check(not choice.conditional_survival and choice.status=="no-witness","missing budget produces only explicitly unsafe-labelled fallback "+str(limits))
		check(choice.candidates.all(func(c):return c.status=="incomplete"),"every unexpanded first candidate recorded "+str(limits))
	choice=H2.choose(b,0,{"first":99,"candidates":999,"branches":99999,"actions":99999,"collections":99999,"preflights":99999})
	check(choice.candidates.size()<=6 and choice.totals.candidates<=24 and choice.totals.branches<=64 and choice.totals.actions<=2048,"caller cannot raise predetermined fixed caps")
	check(choice.generation.collections<=256 and choice.generation.preflights<=1024 and choice.generation.h1<=256,"generation and H1 work also bounded globally")
	check(before==state(b) and source_mines==b.mines and b.rng_state==789123,"all actor decisions leave source units/resources/RNG unchanged")
	b.turn=9;choice=H2.choose(b,0)
	check(choice.status=="invalid" and not choice.conditional_survival,"T9 is outside predeclared window")
	b.turn=1;b.level.index=6;choice=H2.choose(b,0)
	check(choice.status=="invalid" and not choice.conditional_survival,"H2 experiment cannot silently switch to L06")
	for board in boards:board.free()
	boards.clear();await process_frame
	print("H2_WINDOW_PLANNER checks=",checks," failures=",failures)
	quit(1 if failures else 0)
