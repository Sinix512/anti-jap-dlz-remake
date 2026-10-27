extends SceneTree
const Policy=preload("res://tests/helpers/LateEscortPolicy.gd")
var checks:=0
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("LATE_ESCORT_FAIL "+label)
func person(slot:int,x:int,y:int) -> Dictionary:
	return {"slot":slot,"x":x,"y":y,"hp":60,"max_hp":90,"alive":true,"control":true,"auto":false,"side":"player"}
func run() -> void:
	var actor:=person(8,5,5);var ally:=person(1,5,10);var previous:Dictionary={}
	var before:=[actor.duplicate(true),ally.duplicate(true),previous.duplicate(true)]
	var p:=Policy.decide(9,actor,[ally],previous)
	check(not p.active and not p.withdraw and not p.done,"all early-cover turns untouched even at threshold")
	actor.hp=61;p=Policy.decide(10,actor,[ally])
	check(not p.active and not p.withdraw,"one HP above two-thirds threshold does not activate")
	actor.hp=60;p=Policy.decide(10,actor,[ally])
	check(p.active and p.withdraw and p.goal==Vector2i(5,10) and p.support_slot==1,"exact threshold and T10 activate one real-support intention")
	actor.hp=90;p=Policy.decide(11,actor,[ally],p)
	check(p.active and p.withdraw,"healing before rendezvous does not cause oscillation")
	ally.y=9;p=Policy.decide(11,actor,[ally],p)
	check(p.distance==4 and p.withdraw and not p.done,"distance four is not rendezvous")
	ally.y=8;p=Policy.decide(12,actor,[ally],p)
	check(p.distance==3 and p.done and not p.active and not p.withdraw,"exact distance three resumes old planner in this turn")
	actor.hp=1;ally.y=12;p=Policy.decide(13,actor,[ally],p)
	check(p.done and not p.withdraw,"completed stage never reactivates even at one HP")
	var low:=person(2,5,10);var high:=person(4,10,5)
	p=Policy.decide(10,actor,[high,low])
	check(p.support_slot==2 and p.goal==Vector2i(5,10),"nearest tie uses lower slot regardless of input order")
	low.x=5;low.y=11;p=Policy.decide(10,actor,[low,high])
	check(p.support_slot==4,"closer support wins over lower slot")
	var dead:=person(0,5,6);dead.alive=false
	var auto:=person(1,5,6);auto.auto=true
	var uncontrollable:=person(3,5,6);uncontrollable.control=false
	var enemy:=person(4,5,6);enemy.side="enemy"
	var officer:=person(7,5,6);var negative:=person(-1,5,6)
	p=Policy.decide(10,actor,[dead,auto,uncontrollable,enemy,officer,negative,high])
	check(p.support_slot==4 and p.distance==5,"only living controllable non-auto main support slots zero through six qualify")
	p=Policy.decide(10,actor,[])
	check(p.active and p.withdraw and p.goal==Vector2i(5,5) and p.support_slot==-1,"no visible support means wait intention, never imaginary target")
	actor.hp=60;ally.y=10
	p=Policy.decide(10,actor,[ally],previous)
	check(before==[actor,ally,previous],"source actors/allies/previous stage remain unchanged")
	print("LATE_ESCORT_POLICY checks=",checks," failures=",failures)
	quit(1 if failures else 0)
