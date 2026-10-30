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

## Bosh menyu

| Rejim | Nima qiladi |
|---|---|
| **CUSTOM BATTLE** | O'zing xohlagan ikkita armiyani tuzib jang qilasan |
| **CAMPAIGN** | Ketma-ket 6 ta missiya, har biri oldingisini yutgach ochiladi |
| **MULTIPLAYER** | Do'stlar bilan onlayn jang va global urush |
| **SANDBOX** | Erkin tajriba: vaqt chegarasiz, ta'minot cheksiz, istalgan texnikani chaqirasan |
| **GLOBAL WAR** | Doimiy dunyo xaritasi, diplomatiya, iqtisod va urushlar |

### CUSTOM BATTLE — jangni o'zing tashkil qilasan

Bitta ekranda hammasi tanlanadi:

- **Xarita** — oltitadan biri.
- **Fasl** — bahor / yoz / kuz / qish.
- **Ob-havo** — ochiq havo, yomg'ir, tuman, qor, kuchli bo'ron. Har birining
  ko'rish, tezlik va aniqlikka ta'siri ro'yxatda ko'rinadi.
- **G'alaba sharti** — to'rttadan biri.
- **TEAM A va TEAM B** — piyoda, tank, transport, artilleriya va aviatsiya
  sonini slayder bilan belgilaysan. Piyoda bloki ichida miltiqchi, tankka
  qarshi, pulemyot va razvedka avtomatik taqsimlanadi — faqat miltiqchi
  qo'shin bo'lmaydi.
- **Bot qiyinligi** — Easy / Normal / Hard.
- **Jang davomiyligi** — 10 / 15 / 30 daqiqa yoki cheksiz.

Pastda jang statistikasi jonli yangilanadi: har jamoaning birliklari soni va
tanlangan sozlamalar qatori.

### CAMPAIGN

Oltita missiya: qishloq, o'rmon, cho'l, tog' dovoni, shahar kvartallari va
harbiy bazaga hujum. Har biri boshqa xarita, fasl, ob-havo va g'alaba shartida.
Yutilgan missiya keyingisini ochadi, natija `user://profile.cfg` da saqlanadi.

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

**Oltita xarita** (`data/battle_maps.json`). Hudud yer turiga qarab global
urushda avtomatik tanlanadi, Custom Battle va Campaign'da esa qo'lda.

| Xarita | Asosiy xususiyati |
|---|---|
| Village | Uylar, devorlar, tor ko'chalar |
| Forest | Qalin daraxtlar, pistirma, ko'rish masofasi qisqa |
| Desert | Keng ochiq maydon, uzoq masofa, pana kam |
| City | Ko'p qavatli binolar, kvartallar, tor o'tish joylari |
| Mountain | Baland-past yerlar, qoyalar, tor dovonlar |
| Military Base | Angarlar, omborlar, bunkerlar, tekis maydon |

### To'rt fasl — bitta geometriya

Har bir xarita **bir marta** quriladi. Fasl faqat materiallar, o'simliklar,
ob-havo va effektlarni almashtiradi — xarita geometriyasi o'zgarmaydi. Shuning
uchun oltita xarita 24 xil ko'rinishda o'ynaladi.

| Fasl | Nomi | Ko'rinishi |
|---|---|---|
| Bahor | **Green Valley** | Yashil o'tloqlar, nam tuproq, yorug' osmon |
| Yoz | **Dustland** | Sarg'aygan quruq yer, changli yo'llar, qattiq quyosh |
| Kuz | **Dead Autumn** | Jigarrang daraxtlar, to'kilgan barglar, loy, tuman |
| Qish | **Frozen Front** | Qor qoplami, muzlagan yo'llar, sovuq ko'k yorug'lik |

Fasl palitrasi yerni, o't va daraxt barglarini, daraxt po'stlog'ini, toshlarni,
yo'llarni, osmonni, quyosh rangi va kuchini, tuman zichligini belgilaydi. Qishda
daraxtlar yalang'ochlanadi va ustiga qor qo'nadi, kuzda yerga barg to'kiladi.
Ob-havo esa ustiga qo'shiladi: yomg'ir va qor zarrachalari kamera ortidan
yuradi, bo'ron yorug'likni pasaytiradi.

### G'alaba shartlari

| Shart | Qanday yutiladi |
|---|---|
| **Elimination** | Raqib jamoasini butunlay yo'q qilish |
| **Capture Point** | A / B / C nazorat nuqtalarini egallab turish |
| **Hold Position** | Belgilangan hududni vaqt tugaguncha himoya qilish |
| **Destroy Target** | Raqibning shtabini yo'q qilish, o'zingiznikini saqlash |

HUD'da har doim shu jangda nima qilish kerakligi va unga qancha qolgani
ko'rinib turadi. Global urushda shart hududning o'ziga qarab tanlanadi:
poytaxt — Destroy, mustahkamlangan hudud — Hold, qolgani — Capture.

### Bot qiyinligi

| Daraja | O'ylash vaqti | Bosim | Ta'minot | Aniqlik |
|---|---|---|---|---|
| Easy | 6.0 s | past | 0.7x | 0.8x |
| Normal | 4.0 s | o'rta | 1.0x | 1.0x |
| Hard | 2.2 s | yuqori | 1.35x | 1.15x |

Qiyinlik botga bepul zarar bermaydi — u tezroq qaror qabul qiladi, ko'proq
ta'minot oladi va aniqroq otadi. Bot g'alaba shartiga qarab o'ynaydi: Destroy'da
tanklarni shtabga yuborib, piyodaning bir qismini o'z shtabini qo'riqlashga
qoldiradi; Hold'da mudofaachi hududga joylashadi, hujumchi esa unga bostirib
kiradi.

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

### Jang tugagandan keyin

Natija ekranida to'liq hisobot chiqadi:

- Kim yutdi va qanday shart bilan.
- Har jamoa nechta dushmanni yo'q qildi va nechta bo'linma yo'qotdi.
- Yo'qotilgan jonli kuch, texnika va aviatsiya alohida.
- Yetkazilgan zarar va qolgan zaxira.
- **Eng samarali texnika** — har jamoada qaysi tur eng ko'p natija ko'rsatgani,
  yo'q qilish, zarar va yo'qotish bo'yicha.
- Barcha bo'linma turlari bo'yicha jadval: nechtasi chiqdi, nechtasini yo'q
  qildi, nechtasi yo'qoldi.

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
  data/        countries.json, units.json, buildings.json,
               battle_maps.json (xaritalar, fasllar, ob-havo, g'alaba
               shartlari, qiyinlik), missions.json (kampaniya)
  world/       global xarita: hudud, davlat, armiya, iqtisod, ta'minot,
               diplomatiya, kengash, AI, fasl, jang ko'prigi
  battle/      3D jang: relyef, xarita quruvchi (6 xarita), pana tizimi,
               parchalanadigan uy, shtab nishoni, bo'linmalar, snaryad,
               direktor (4 g'alaba sharti), statistika, AI qo'mondon,
               jang sozlagich, kamera, boshqaruv
  ui/          ekranlar: menyu, custom battle, kampaniya, lobby,
               davlat tanlash, dunyo, jang, natija, sozlamalar
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
| 5. Oltita xarita, to'rt fasl, 4 g'alaba sharti, kampaniya, sandbox, statistika | Bajarildi |
| 6. Katta yangilanish — dengiz qatlami, yangi texnika, reyting, turnirlar | Keyingi |
