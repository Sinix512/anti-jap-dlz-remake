extends SceneTree
const State=preload("res://scripts/m2/GameState.gd")
const Town=preload("res://scripts/m4/TownRules.gd")
const Plan=preload("res://tests/helpers/CapturedFoodProvision.gd")
var checks:=0
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("CAPTURED_FOOD_FAIL "+label)
func fixture():
	var gs=State.new();gs.new_game(JSON.parse_string(FileAccess.get_file_as_string("res://data/m2.json")))
	gs.setup_m4(JSON.parse_string(FileAccess.get_file_as_string("res://data/m4.json")))
	var cp:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../out/legal_checkpoint_source248_L06.json"))
	gs.from_dict(cp.state)
	Town.visit_resident(gs,gs.current_town);var command:Dictionary=Town.prepare_command(gs,gs.current_town)
	if not bool(command.get("no_choice",false)):Town.accept_command(gs,gs.current_town,command)
	return gs
func run() -> void:
	check(FileAccess.get_file_as_string("res://../out/legal_checkpoint_source248_L06.json").sha256_text()=="e1335fd354647a60dbbb614f6872bd52ba8c30f471371592a2dca212c994631d","recorded source248 input identity is fixed")
	var gs=fixture();var member:Dictionary=gs.person(8);var before:Dictionary=member.duplicate(true)
	check(gs.money==20 and gs.item_count(89)==3 and member.item_slots==[102,8,8,0,0,0,0,0],"genuine checkpoint and normal command recruit establish expected finite input")
	var plan:=Plan.provision(gs)
	check(plan.complete and plan.transactions.size()==7 and plan.transactions.all(func(t):return t.result.ok),"one sale three buys and three real carries all succeed")
	check(gs.money==110 and gs.item_count(89)==2 and gs.item_count(5)==0,"normal 240 sale minus150 purchases conserves actual money/warehouse")
	check(member.item_slots==[102,8,8,6,6,6,0,0],"only three acquired dates enter ordinary eight-slot bag")
	var after:Dictionary=member.duplicate(true);before.erase("item_slots");after.erase("item_slots")
	check(before==after,"no HP level XP faction skill or other character field is edited")
	check(plan.before.money==20 and plan.after.money==110 and plan.before.items["89"]==3 and plan.after.items["89"]==2,"receipt retains before/after inventory instead of inventing subsidy")
	gs=fixture();member=gs.person(8);gs.data.towns[gs.current_town].shops.zahuo=[]
	var snapshot:=Plan.snapshot(gs,member);plan=Plan.provision(gs)
	check(not plan.complete and plan.transactions.is_empty() and Plan.snapshot(gs,member)==snapshot,"no local catalog refuses before selling anything")
	gs=fixture();member=gs.person(8);gs.items["89"]=1;snapshot=Plan.snapshot(gs,member);plan=Plan.provision(gs)
	check(not plan.complete and plan.transactions.is_empty() and Plan.snapshot(gs,member)==snapshot,"last bird gun is reserved, insufficient spare never sold")
	gs=fixture();member=gs.person(8);member.item_slots=[102,8,8,6,6,6,6,0];snapshot=Plan.snapshot(gs,member);plan=Plan.provision(gs)
	check(not plan.complete and plan.transactions.is_empty() and Plan.snapshot(gs,member)==snapshot,"fewer than three slots refuses before money or stock mutation")
	gs=fixture();member=gs.person(8);gs.money=150;plan=Plan.provision(gs)
	check(plan.complete and gs.money==0 and gs.item_count(89)==3 and plan.transactions.size()==6,"synthetic exact cash fixture buys without unnecessary sale")
	gs=fixture();member=gs.person(8);member.faction=1;snapshot=Plan.snapshot(gs,member);plan=Plan.provision(gs)
	check(not plan.complete and plan.transactions.is_empty() and Plan.snapshot(gs,member)==snapshot,"unrecruited actor cannot receive speculative goods")
	print("CAPTURED_FOOD_PROVISION checks=",checks," failures=",failures)
	quit(1 if failures else 0)
