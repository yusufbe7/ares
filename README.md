# World Frontier

Global strategiya + real vaqtdagi 3D jang maydoni. Godot 4 da yozilgan, noldan qurilgan.

O'yin ikkita bir-biriga bog'langan qismdan iborat:

1. **GLOBAL MAP** — davlatlar, chegaralar, iqtisodiyot, diplomatiya, ittifoqlar va urushlar.
2. **BATTLEFIELD** — har bir hudud uchun jang shu yerda, 3D maydonda hal bo'ladi.

Jang natijasi dunyo xaritasiga qaytadi: hudud egasi almashadi, armiyalar yo'qotish ko'radi,
charchoq va norozilik o'sadi. Xaritadagi ta'minot, fasl va ob-havo esa jangning o'zini
o'zgartiradi.

Davr — **2041, muqobil tarix**. Davlat nomlari haqiqiy, lekin chegaralar, siyosat va
voqealar o'ylab topilgan; bugungi real mojarolarga aloqasi yo'q.

---

## Ishga tushirish

Godot 4.4 yoki undan yangi versiyada `godot_game/project.godot` ni oching va **F5** bosing.
Hech qanday tashqi fayl, model yoki tekstura kerak emas: butun dunyo, relyef, uylar,
daraxtlar, askarlar va texnika **kod orqali, seed asosida** quriladi. Shuning uchun
bir xil seed hamma o'yinchida bir xil dunyoni beradi.

Headless sinovlar:

```bash
godot --headless --path godot_game -s res://tests/run_tests.gd
```

Jangni grafikasiz, balans uchun, 60 soniya simulyatsiya qilish:

```bash
godot --headless --path godot_game -s res://tests/sim_battle.gd
```

---

## Rejimlar

### GLOBAL WAR
Doimiy dunyo xaritasi. Davlat tanlaysiz, uni rivojlantirasiz, ittifoq tuzasiz,
urush e'lon qilasiz va hududlarni egallaysiz. Bitta davlatni bir nechta o'yinchi
birga boshqarishi mumkin.

### BATTLE ARENA
Alohida 3D jang: teng armiyalar, oldindan belgilangan ta'minot, 15–30 daqiqa.
Dunyo holatiga ta'sir qilmaydi — tezkor PvP yoki AI'ga qarshi o'yin uchun.

---

## Global xarita

Xarita **olti burchakli kataklardan** iborat (48x32). Har bir katak — bitta hudud:
egasi, yer turi, aholisi, binolari, ta'minoti va norozilik darajasi bor. Qo'shnichilik,
chegara, front va ta'minot yo'li shu to'rdan kelib chiqadi.

| Tizim | Qayerda | Nima qiladi |
|---|---|---|
| Iqtisodiyot | `world/economy.gd` | Kunlik daromad, qo'shin xarajati, safarbarlik, urush charchog'i |
| Ta'minot | `world/supply_net.gd` | Poytaxt / harbiy baza / aeroportdan boshlanadigan zanjir. Uzilsa, armiya zaiflashadi |
| Diplomatiya | `world/diplomacy.gd` | Munosabatlar, ittifoqlar (3–10 davlat), urush e'loni, tinchlik shartnomasi, sulh |
| Milliy kengash | `world/war_council.gd` | Urush, tinchlik va katta xarajatlar bo'yicha ovoz berish |
| AI davlatlar | `world/nation_ai.gd` | Quradi, safarbar qiladi, hujum qiladi, sulh so'raydi |
| Fasl va ob-havo | `world/season_cycle.gd` | Yoz/kuz/qish/bahor, yomg'ir, qor, tuman, bo'ron |
| Jang ko'prigi | `world/battle_bridge.gd` | Hududiy to'qnashuvni 3D jangga aylantiradi va natijani qaytaradi |

### Shaharlarni rivojlantirish
Ferma, kon, neft zavodi, elektr stansiya, harbiy zavod, temir yo'l, aeroport,
harbiy baza, radar, mudofaa chizig'i. Har biri daraja oshadi va kunlar bilan quriladi.

---

## Bitta davlat, bir nechta o'yinchi

Bu o'yinning asosiy g'oyalaridan biri: davlatni jamoa boshqaradi, lekin
**hammaning bir vaqtda onlayn bo'lishi shart emas.**

Har bir o'yinchining lavozimi bor:

| Lavozim | Mustaqil sarflay oladigan ulush | Ovoz vazni |
|---|---|---|
| Davlat rahbari | 60% | 2 |
| Qo'mondon | 35% | 1 |
| Ofitser | 15% | 1 |
| Kuzatuvchi | — | 0 |

Qoidalar:

- **Chegaradan oshgan har qanday xarajat** avtomat ravishda kengash ovoziga qo'yiladi.
  Bitta o'yinchi davlat xazinasini o'zboshimchalik bilan bo'shata olmaydi.
- **Urush, tinchlik va ittifoq** har doim ovozga qo'yiladi.
- Har bir ovoz berishning **muddati** bor (standart — 2 kun). Oflayn o'yinchilar
  ovoz bermasa, ular betaraf hisoblanadi va qaror baribir qabul qilinadi.
- Muddat tugaganda hech kim ovoz bermagan bo'lsa: **qo'mondon va rahbar** taklifi
  o'tadi, **ofitser** taklifi bekor bo'ladi.
- Natija aniq bo'lishi bilan ovoz berish muddatidan oldin ham yopiladi.

Davlatda bitta jonli o'yinchi bo'lsa, ovoz berish umuman ochilmaydi — komitet emas.
Hamma o'yinchi chiqib ketsa, davlatni vaqtincha AI boshqaradi.

### Urush boshlash jarayoni
1. O'yinchi diplomatiya panelidan urush taklif qiladi.
2. Kengashda ovoz beriladi (muddat bilan).
3. Ovoz o'tsa, urush e'lon qilinadi va **ikkala tomonning ittifoqdoshlari** ham tortiladi.
4. Armiyalar qarama-qarshi hududda uchrashganda server jang yaratadi.
5. Jangda jonli o'yinchi bo'lsa — 3D maydon ochiladi. Bo'lmasa — avtomatik hal qilinadi.
6. G'olib hududni oladi.

---

## 3D jang maydoni

Uch xil muhit (`data/battle_maps.json`), hudud yer turiga qarab tanlanadi:

| Xarita | Muhit | Jang xususiyati |
|---|---|---|
| Village | Qishloq | Uylar, ko'chalar, zich pana |
| Forest | O'rmon | Tuman, daraxtlar, pistirma, ko'rish masofasi qisqa |
| Desert | Cho'l | Keng ochiq maydon, uzoq masofa, pana kam |

### Bo'linmalar
Piyodalar, tankka qarshi guruh, razvedka, pulemyotchilar, zirhli transport,
asosiy tank, o'ziyurar artilleriya, zenit, hujum vertolyoti, razvedka droni, FPV dron.

### Boshqaruv falsafasi
O'yinchi askarni qadamma-qadam yurgizmaydi. U **maqsad** beradi — "u yerga bor",
"u nuqtani ol", "u uyni o'qqa tut" — askarlar esa yo'lni, panani, otishni va
yotish-turishni o'zlari hal qiladi.

Butun armiyani bitta buyruq bilan boshqarib bo'lmaydi: **1–5 guruh** tuziladi
(Ctrl+raqam) va har biri alohida boshqariladi. O'yin boshida guruhlar o'zi
tuziladi: 1 — piyodalar, 2 — tanklar, 3 — artilleriya, 4 — razvedka, 5 — zaxira.

### AI pana tizimi (`battle/cover_system.gd`)
Har bir qattiq jism pana nuqtalarini e'lon qiladi: uy devorlari va burchaklari,
daraxt tanasi, toshlar, yiqilgan daraxtlar, voronkalar, xandaqlar, qum qoplari,
yongan texnika. Har bir nuqta qaysi tomondan himoya qilishini, qanchalik
himoya qilishini va band yoki bo'shligini biladi.

Askar eng yaxshisini shu formula bilan tanlaydi:

```
ball = himoya − masofa + dushmanga qarash − band bo'lsa jarima
```

**Bosim (suppression):** yaqindan o'q o'tsa yoki portlash bo'lsa, askar avval
cho'kkalaydi, keyin yotadi, aniqligi pasayadi. Bosim kuchli bo'lsa pana ortidan
boshini ko'tarmaydi. Vaqt o'tishi bilan bosim kamayadi.

**Xandaq:** ichidagi askar ~78% himoyalangan.
**Tank zirhi:** oldi qalin, yoni o'rtacha, orqasi zaif — shuning uchun tankni
yon tomondan aylanib o'tish haqiqiy javob bo'ladi.

### Parchalanadigan uylar (`battle/destructible_building.gd`)
- Har bir uy 0.8 m li bo'laklardan iborat qobiq: devorlar, gable tom, mo'ri.
- Uy butun turganda **bitta birlashtirilgan mesh** sifatida chiziladi.
- Zarbada faqat eng katta 14 ta parcha haqiqiy fizik jism bo'ladi (bir vaqtda ko'pi
  bilan 60 ta). Qolganlari bitta multimesh orqali tushadi va yerga tushgach
  umumiy "vayrona" meshiga qo'shiladi — node ham, fizika ham qolmaydi.
- **Qulash mantiqi:** devor bo'lagi ostidagi ustun yo'qolsa tushadi; tom esa
  devorlarning 35% dan kami qolganda butunlay quladi.
- Devorlarning yarmidan ko'pi yiqilgan uy yonadi, qora tutun chiqaradi va
  vayronasidan askarlar o'tadi.
- Snaryad birinchi uchragan devorda portlaydi, portlash yerda chuqur qoldiradi.

### Yer va muhit
- Relyef shovqin (noise) orqali quriladi; har bir portlash **chuqur** qoldiradi,
  xandaq esa yerni kesadi — ikkalasi ham balandlik funksiyasiga kiradi.
- Tank daraxtga urilsa daraxt yiqiladi va yiqilgan tana pana bo'ladi.
- Fasl va ob-havo: qor qoplami, tuman zichligi, quyosh rangi, ko'rish masofasi,
  harakat tezligi va otish aniqligi.

### Jang mantiqi
- **A / B / C nuqtalar.** Ko'proq nuqta ushlagan tomon raqibni qon yo'qotishga
  majbur qiladi: har 15 soniyada farq soniga teng odam zaxiradan kamayadi.
- **Zaxira:** har tomonda bo'linmalar soniga qarab hisoblanadi; har bir o'lim
  zaxiradan ayriladi.
- **Ta'minot** vaqt bilan keladi, ushlab turilgan har bir nuqta daromadni oshiradi.
  Otryad, tank, artilleriya, dron va qurilish shu ta'minotga sotib olinadi.
- **Razvedka:** ko'rilmagan dushman umuman chizilmaydi. Dron butun zonani ochadi.
- **Dushman qo'mondoni** (`battle/battle_ai.gd`) xuddi shu buyruqlar bilan o'ynaydi:
  guruh tuzadi, nuqtalarga yuboradi, to'plangan askarlarga artilleriya otadi,
  tank va FPV dron chaqiradi.

---

## Boshqaruv

| Tugma | Harakat |
|---|---|
| Chap tugma / sudrash | Tanlash |
| O'ng tugma (yerga) | Yurish |
| O'ng tugma (dushmanga) | Hujum |
| O'ng tugma (uyga) | Texnika uyni o'qqa tutadi, piyodalar devor yonida pana oladi |
| O'ng tugma (nuqta ichiga) | Nuqtani egallash |
| 1–5 | Guruhni tanlash. **Ctrl+1–5** — guruh tuzish |
| R / Y / U | Otryad / tank / artilleriya |
| B / V | Qurilish menyusi / xandaq chizish |
| G / T | Granata / RPG |
| Z / X / C | Yotish / cho'kkalash / turish |
| H / F | To'xtash / kamerani tanlanganlarga olib borish |
| N | Razvedka droni |
| WASD, g'ildirak, Q/E | Kamera |
| Esc | Orqaga / chiqish |

Barcha tugmalar **Sozlamalar** dan qayta belgilanadi (`user://settings.cfg`).
Til: o'zbek / ingliz / rus.

---

## Onlayn

Server dunyoni egallaydi, mijozlar buyruq yuboradi — bu ikki o'yinchi ikki xil
dunyo ko'rishining oldini oladi.

- **Lobby:** server ochish / ulanish, o'yinchilar ro'yxati, chat.
- **Dunyo:** barcha o'zgarishlar serverda tekshiriladi va 2 soniyada bir sinxronlanadi.
- **Jang:** simulyatsiya serverda ishlaydi, mijozlarga 10 Hz tezlikda holat yuboriladi.
- O'yinchi uzilganda uning davlatdagi o'rni "oflayn" bo'ladi; hech kim qolmasa,
  davlatni AI oladi.

---

## Fayllar

```
godot_game/
  core/        autoload: EventBus, Settings, Loc, DB, GameState, Net
  data/        countries.json, units.json, buildings.json, battle_maps.json
  world/       global xarita: hudud, davlat, armiya, iqtisod, ta'minot,
               diplomatiya, kengash, AI, fasl, jang ko'prigi
  battle/      3D jang: relyef, pana tizimi, parchalanadigan uy, bo'linmalar,
               snaryad, direktor, AI qo'mondon, kamera, boshqaruv
  ui/          ekranlar: menyu, lobby, davlat tanlash, dunyo, jang, sozlamalar
  tests/       headless sinovlar va jang simulyatsiyasi
```

---

## Rivojlanish bosqichlari

| Bosqich | Holat |
|---|---|
| 1. Jang prototipi — qishloq, 2 jamoa, piyoda va tank, pana, otishma | Bajarildi |
| 2. Onlayn — server/mijoz, lobby, 2–8 o'yinchi, birgalikda boshqarish | Bajarildi |
| 3. Dunyo xaritasi — davlat tanlash, chegaralar, iqtisod, ittifoq, diplomatiya | Bajarildi |
| 4. Global urush — hudud egallash, ta'minot, shahar rivoji, kengash ovozi | Bajarildi |
| 5. Katta yangilanish — yangi texnika, dengiz va aviatsiya qatlami, reyting, turnirlar | Keyingi |
