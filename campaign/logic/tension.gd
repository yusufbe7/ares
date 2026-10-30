## Global Tension: har bir blokning dunyodagi ulushi.
##   ulush(blok) = w_p * (blok hududlari / jami hududlar) + w_r * (blok polklari / jami polklar)
## w_p, w_r: rules.json -> tension_weights (standart 0.5 / 0.5). Blokka kirmaganlar "Others".
## Kuch chizig'i (bar) ikki eng katta blok ulushidan: chap blok / o'ng blok.
class_name CampaignTension
extends RefCounted


## Natija: [{id, name, color, share (0..1), provinces, regiments}], ulush bo'yicha emas, blocs.json tartibida.
static func compute(data: CampaignData) -> Array:
	var w: Dictionary = data.rule("tension_weights", {"provinces": 0.5, "regiments": 0.5})
	var wp := float(w.get("provinces", 0.5))
	var wr := float(w.get("regiments", 0.5))
	var rows := {}
	var order := []
	for b in data.blocs:
		rows[b.id] = {"id": b.id, "name": b.name, "color": Color.html(b.get("color", "#888888")), "provinces": 0, "regiments": 0}
		order.append(b.id)
	var oid: String = data.others.get("id", "others")
	rows[oid] = {"id": oid, "name": data.others.get("name", "OTHERS"), "color": Color.html(data.others.get("color", "#888888")),
		"provinces": 0, "regiments": 0}
	order.append(oid)
	var tp := 0
	var tr_ := 0
	for p in data.provinces.values():
		if p.owner == 0:
			continue
		var b := data.bloc_of(p.owner)
		rows[b if rows.has(b) else oid].provinces += 1
		tp += 1
	for a in data.armies:
		var b := data.bloc_of(a.owner)
		rows[b if rows.has(b) else oid].regiments += a.size
		tr_ += a.size
	var out := []
	for id in order:
		var r: Dictionary = rows[id]
		r.share = wp * (float(r.provinces) / maxf(tp, 1)) + wr * (float(r.regiments) / maxf(tr_, 1))
		out.append(r)
	return out
