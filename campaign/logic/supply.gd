## Ta'minot yo'llari. Har bir davlat uchun manbalar: poytaxt va harbiy bazalar.
## Yo'l faqat o'z va ittifoqchi hududlar orqali yuradi (quruqlik + dengiz yo'llari).
## Qo'shin turgan hududga yo'l bo'lmasa: ta'minot uzilgan, qo'shin kuchi -X% (rules.json: unsupplied_penalty).
## Chizish uchun yo'l (hududlar ketma-ketligi) saqlanadi; uzilganida eng qisqa (har qanday hudud orqali) yo'l.
class_name CampaignSupply
extends RefCounted

var data: CampaignData
var routes := {}                ## army.id -> {"path": [province ids], "ok": bool, "sea": [bool...]}


func _init(d: CampaignData) -> void:
	data = d


func sources_of(cid: int) -> Array:
	var out := []
	var c: CountryData = data.countries.get(cid)
	if c and data.provinces.has(c.capital) and data.provinces[c.capital].owner == cid:
		out.append(c.capital)
	for b in data.bases:
		var p: ProvinceData = data.provinces.get(b.province)
		if p and p.owner == cid and not (b.province in out):
			out.append(b.province)
	return out


## Ko'p manbali BFS. friendly_only bo'lsa faqat o'z va ittifoqchi hududlar orqali.
func _bfs(cid: int, friendly_only: bool) -> Dictionary:
	var prev := {}
	var queue: Array = []
	for s in sources_of(cid):
		prev[s] = -1
		queue.append(s)
	var head := 0
	while head < queue.size():
		var u: int = queue[head]
		head += 1
		var p: ProvinceData = data.provinces[u]
		for v in p.all_neighbors():
			if prev.has(v) or not data.provinces.has(v):
				continue
			if friendly_only and not data.allied(cid, data.provinces[v].owner):
				continue
			prev[v] = u
			queue.append(v)
	return prev


static func _path(prev: Dictionary, to: int) -> Array:
	var out := []
	var u := to
	while prev.has(u) and u != -1:
		out.push_front(u)
		u = prev[u]
	return out


## Hamma qo'shinlar uchun ta'minotni qayta hisoblaydi.
func update() -> void:
	routes.clear()
	var by_owner := {}
	for a in data.armies:
		by_owner.get_or_add(a.owner, []).append(a)
	for cid in by_owner:
		var ok_prev := _bfs(cid, true)
		var any_prev := {}
		for a in by_owner[cid]:
			var path: Array
			var ok := ok_prev.has(a.province)
			if ok:
				path = _path(ok_prev, a.province)
			else:
				if any_prev.is_empty():
					any_prev = _bfs(cid, false)
				path = _path(any_prev, a.province)
			a.supplied = ok
			var sea := []
			for k in range(1, path.size()):
				sea.append(data.provinces[path[k - 1]].is_sea_link(path[k]))
			routes[a.id] = {"path": path, "ok": ok, "sea": sea}


## Jangdagi kuch koeffitsiyenti.
func factor(a: ArmyData) -> float:
	return 1.0 if a.supplied else 1.0 - float(data.rule("unsupplied_penalty", 0.3))
