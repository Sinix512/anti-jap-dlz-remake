extends RefCounted
# Test-player economy only, with real finite warehouse stock and real prices.
# Fixed experiment: at most one spare bird-gun sale and three local red dates.
static func snapshot(gs,member:Dictionary) -> Dictionary:
	return {"money":gs.money,"items":gs.items.duplicate(true),"slots":member.get("item_slots",[]).duplicate()}
static func provision(gs) -> Dictionary:
	var member:Dictionary=gs.person(8)
	var before:=snapshot(gs,member)
	var out:Dictionary={"complete":false,"transactions":[],"before":before,"after":before.duplicate(true),"reason":""}
	var stock:Array=gs.town(gs.current_town).get("shops",{}).get("zahuo",[])
	if not stock.any(func(it):return int(it.index)==5):out.reason="current town does not sell red dates";return out
	if member.is_empty() or int(member.get("faction",-1))!=0 or member.get("item_slots",[]).count(0)<3:
		out.reason="Xiao not recruited or fewer than three empty slots";return out
	var needed:int=3*int(gs.item(5).price)
	if gs.money<needed:
		var proceeds:int=int(gs.item(89).price)*(7-gs.difficulty)/10
		if gs.item_count(89)<2 or gs.money+proceeds<needed:
			out.reason="insufficient finite funds/spare bird gun";return out
		var sold:Dictionary=gs.sell_item(89);out.transactions.append({"sell":89,"town":gs.current_town,"result":sold})
		if not sold.ok:out.reason="sale refused";out.after=snapshot(gs,member);return out
	for i in range(3):
		var bought:Dictionary=gs.buy_item(5);out.transactions.append({"buy":5,"town":gs.current_town,"result":bought})
		if not bought.ok:out.reason="purchase refused";out.after=snapshot(gs,member);return out
		var carried:Dictionary=gs.give_item(member,5);out.transactions.append({"carry":5,"pid":8,"result":carried})
		if not carried.ok:out.reason="carry refused";out.after=snapshot(gs,member);return out
	out.complete=true;out.after=snapshot(gs,member)
	return out
