# Frontline

Real vaqtdagi 3D jang o'yini. Godot 4 da, noldan yozilgan, **hech qanday tashqi
fayl ishlatmaydi** — yer, daryo, ko'prik, uylar, daraxtlar, askarlar va texnika
hammasi kod orqali, seed asosida quriladi.

Shuning uchun butun loyiha **~380 KB**. Model ham, tekstura ham yuklab olish
kerak emas.

```
Godot 4.4+ ni oching → project.godot → F5
```

---

## O'yin nima haqida

Xaritani, faslni, ob-havoni va ikkala armiyani o'zingiz tuzasiz, so'ng jangni
boshlaysiz. Jangda askarlarni qadamma-qadam yurgizmaysiz — **maqsad** berasiz,
ular yo'lni, panani, otishni va yotish-turishni o'zlari hal qiladi.

Ikki tomon bor:

| Tomon | Nimasi bor |
|---|---|
| **Armiya** | Miltiqchilar, tankka qarshi guruh, pulemyot, razvedka, BTR, tank, artilleriya, vertolyot |
| **Isyonchilar** | Isyonchi jangchilar, RPG otuvchilar, pulemyot, razvedka, **pikap-texnika**, tank, artilleriya, dron |

Bir xil "30 piyoda, 3 tank, 2 transport" buyrug'i ikki tomonda ikki xil armiya
beradi: armiyada BTR va vertolyot, isyonchilarda pikap va RPG.

---

## Xaritalar

Oltita xarita. Har biri **bir marta** quriladi, fasl esa faqat materiallar,
o'simliklar va ob-havoni almashtiradi — shuning uchun 6 xarita 24 ko'rinishda
o'ynaladi.

| Xarita | Nimasi bor |
|---|---|
| **Village** | Loy va tosh uylar, omborlar, pichan g'aramlari, **tosh quduqlar**, **o'tish joyi bor past devorlar**, **minorali cherkov**, daryo va tosh ko'prik, temir yo'l, simyog'ochlar |
| **Forest** | Qalin o'rmon, yiqilgan tanalar, tor daryo — ko'rish masofasi qisqa |
| **Desert** | Keng ochiq maydon, qumtepalar, **palmalar qatori bilan sug'orish kanali**, uzoq masofa |
| **City** | Yo'l to'ri bo'ylab ko'p qavatli kvartallar, yongan texnika |
| **Mountain** | Qoya tizmalari, tor dovonlar, tog' daryosi |
| **Military Base** | Angarlar, bunkerlar, ombor shtabellari, tekis maydon |

**Daryo haqiqiy to'siq:** suvdan o'tib bo'lmaydi, hujum ko'prikdan o'tishi
kerak. Ko'prik panjaralari pana beradi, ya'ni o'tish joyini ushlab turish
jangning o'zi bo'ladi.

### To'rt fasl

| Fasl | Nomi | Ko'rinishi |
|---|---|---|
| Bahor | **Green Valley** | Yashil o'tloqlar, nam tuproq, yorug' osmon |
| Yoz | **Dustland** | Sarg'aygan quruq yer, changli yo'llar, qattiq quyosh |
| Kuz | **Dead Autumn** | Jigarrang daraxtlar, to'kilgan barglar, loy, tuman |
| Qish | **Frozen Front** | Qor qoplami, **muzlagan daryo**, sovuq ko'k yorug'lik |

Ob-havo ustiga qo'shiladi: ochiq havo, yomg'ir, tuman, qor, kuchli bo'ron.
Yomg'ir va qor zarrachalari kamera ortidan yuradi, bo'ron yorug'likni
pasaytiradi. Har biri ko'rish masofasi, harakat tezligi va otish aniqligiga
ta'sir qiladi — sozlash ekranida foizlari ko'rinib turadi.

---

## G'alaba shartlari

| Shart | Qanday yutiladi |
|---|---|
| **Elimination** | Raqib kuchlarini butunlay yo'q qilish |
| **Capture Point** | A / B / C nuqtalarni egallab turish |
| **Hold Position** | Belgilangan hududni vaqt tugaguncha himoya qilish |
| **Destroy Target** | Raqib shtabini yo'q qilish, o'zingiznikini saqlash |

Ekran tepasida doim shu jangda nima qilish kerakligi va unga qancha qolgani
ko'rinib turadi.

---

## Ekrandagi narsalar

Pastki o'ngda **sektor radari**: butun maydon bir qarashda. O'z askarlaringiz,
ayni paytda ko'rinayotgan dushman, nuqtalar va kameraning qayerga qaraganini
ko'rsatadi. Dushman faqat razvedka ochgan paytda chiqadi, shuning uchun radar
aldamchi ro'yxat emas, haqiqiy ma'lumot bo'ladi. Bosilsa kamera o'sha joyga
uchadi.

Uning yonida **SECTIONS** paneli: har bir guruh nechta jangovar askari
borligini va nechtasi yiqilganini ko'rsatadi (`SECTION 1  6 MEN  +2 DOWN`),
ustiga olib borilsa holati yoziladi — ushlab turibdi, yurmoqda, jangda yoki
qutqarmoqda.

## Boshqaruv

Pastki chapda — videodagi kabi uchta narsa: **MEN** (qancha odam tirik),
**AIR STRIKE** va **NUKE**.

| Tugma | Harakat |
|---|---|
| Chap tugmani sudrash | Tanlash |
| O'ng tugma (yerga) | Yurish |
| O'ng tugma (dushmanga) | Hujum |
| O'ng tugma (binoga) | Texnika binoni o'qqa tutadi, piyoda devor yonida pana oladi |
| O'ng tugma (nuqtaga) | Nuqtani egallash |
| **B** | **Aviazarba** — samolyot o'tib, nishon bo'ylab bomba tashlaydi (75 s) |
| **N** | **Yadro zarbasi** — har tomonga bir marta, hamma narsani tekislaydi |
| 1–5 | Guruhni tanlash. **Ctrl+1–5** — guruh tuzish |
| R / Y / U | Otryad / tank / artilleriya chaqirish |
| V | Xandaq qazish |
| G / T | Granata / RPG |
| Z / X / C | Yotish / cho'kkalash / turish |
| H / F | To'xtash / kamerani tanlanganlarga olib borish |
| M | Razvedka droni |
| WASD, g'ildirak, Q/E | Kamera |
| Esc | Menyuga qaytish |

Barcha tugmalar sozlamalardan qayta belgilanadi. Til: o'zbek / ingliz / rus.

---

## Jang mexanikasi

**Pana tizimi.** Har bir qattiq jism pana nuqtasini e'lon qiladi: devor,
burchak, daraxt, tosh, yiqilgan tana, voronka, xandaq, pichan g'aram, ko'prik
panjarasi, yongan texnika. Askar eng yaxshisini shu formula bilan tanlaydi:

```
ball = himoya − masofa + dushmanga qarash − band bo'lsa jarima
```

**Bosim.** Yaqindan o'q o'tsa yoki portlash bo'lsa, askar cho'kkalaydi, keyin
yotadi, aniqligi pasayadi. Bosim kuchli bo'lsa pana ortidan boshini
ko'tarmaydi.

**Yarador va qutqaruv.** Piyoda askar ko'pincha darhol o'lmaydi — yiqiladi va
qon yo'qota boshlaydi. Panada bo'lgani yiqilish ehtimolini oshiradi. Yaqindagi
hamkasb o'z ishini tashlab, uning oldiga boradi va sudrab o'z chetiga olib
chiqadi. Olib chiqilsa askar yarim kuch bilan safga qaytadi, ulgurilmasa
nobud bo'ladi.

Bu bepul emas: sudrayotgan askar sekin yuradi va o'sha vaqt davomida otmaydi
— bitta yarador uchun ikkita miltiq saf dan chiqadi. Sudrovchi o'ldirilsa,
yarador o'sha joyda qoladi va boshqasi kelishi mumkin. Dushman yiqilgan
askarni o'qqa tutmaydi, shuning uchun qaytib borish mantiqqa ega bo'ladi.

Pastdagi panelda **YARADOR** soni ko'rinadi, natija ekranida esa qutqarilgan
va ulgurilmagan askarlar alohida hisoblanadi.

**Zirh.** Tankning oldi qalin, yoni o'rtacha, orqasi zaif — yon tomondan
aylanib o'tish haqiqiy javob. Pikapni esa oddiy miltiq ham teshadi.

**Parchalanadigan binolar.** Devor ostidagi ustun yo'qolsa tushadi, tom esa
devorlarning 35% dan kami qolganda quladi. Yarmidan ko'pi yiqilgan uy yonadi va
vayronasidan askarlar o'tadi.

**Yer o'zgaradi.** Har portlash chuqur qoldiradi, xandaq yerni kesadi, tank
daraxtni yiqitadi — yiqilgan tana pana bo'ladi.

**Razvedka.** Ko'rilmagan dushman umuman chizilmaydi. Dron zonani ochadi.

**Binoni garnizon qilish.** Piyoda askarlarni tanlab, butun binoga o'ng tugma
bosilsa, ular ichkariga kirib, deraza va tomdan otadi. Devorlar ularni ~86%
himoya qiladi — ochiq maydondagi har qanday panadan kuchliroq. O'rinlar bino
atrofiga teng taqsimlanadi, har uchinchi askar tomga chiqadi, shuning uchun
garnizon har tomonni nazorat qiladi. Bino yarmidan ko'pi buzilsa, ichidagilar
zarar bilan tashqariga otiladi. Mudofaachi bot ham hududdagi binolarga
joylashadi.

**Snaryad izlari.** Har bir snaryad va raketa ortidan tutun donalari qoladi va
asta yo'qoladi. Artilleriya otganda osmonda egri yoylar chiziladi — kamera
shu balandlikda bo'lganda zarba qayerdan qayerga ketayotgani shundan ko'rinadi.

**Radio aloqasi.** Askarlar jang davomida gapiradi: harakatga chiqqanda,
o't ostida qolganda, qotib qolganda, yarador bo'lganda. Tank yoki aviatsiya
chaqirilsa shtab javob beradi, nuqta egallansa xabar beriladi. Har bir gap
pastki chapdagi lentada ismi bilan chiqadi. Bir xil gap qayta-qayta
takrorlanmasligi uchun har turining o'z kutish vaqti bor.

**Texnika ham pana.** Zirhli mashina orqasida turgan askarni korpus himoya
qiladi — pana nuqtalari emas, jonli hisob, chunki texnika yurganda pana ham
u bilan ketadi. Faqat korpus haqiqatan o'q yo'lida bo'lsa ishlaydi.

**Unvon oshadi.** Askar dushmanni yo'q qilgani sari unvoni ko'tariladi:
PVT → PFC → CPL → SGT → 1LT. Har safar lentada ismi bilan e'lon qilinadi.
Tirik qolgan askar shunchaki raqam emas — u sizning tajribali jangchingizga
aylanadi, va uni yo'qotish og'irroq bo'ladi.

**Askarlarning ismi bor.** Har bir piyodada unvon va familiya bor (masalan
`SGT Vance`). Pastki chapdagi lentada kim yarador bo'lgani, kim qutqarilgani
va kim halok bo'lgani ismi bilan yozilib boradi. Bitta askar tanlansa,
panelda uning ismi chiqadi.

---

## Bot

| Daraja | Qaror vaqti | Bosim | Ta'minot | Aniqlik |
|---|---|---|---|---|
| Easy | 6.0 s | past | 0.7x | 0.8x |
| Normal | 4.0 s | o'rta | 1.0x | 1.0x |
| Hard | 2.2 s | yuqori | 1.35x | 1.15x |

Botga bepul zarar berilmaydi — u tezroq qaror qabul qiladi, ko'proq ta'minot
oladi va aniqroq otadi. Bot g'alaba shartiga qarab o'ynaydi: Destroy'da
tanklarni shtabga yuboradi, Hold'da mudofaachi hududga joylashadi.

---

## Jang tugagandan keyin

Kim yutdi va qanday shart bilan; har tomon nechta dushmanni yo'q qildi va
nechta bo'linma, jonli kuch, texnika, aviatsiya yo'qotdi; yetkazilgan zarar;
qolgan zaxira; va **eng samarali texnika** — qaysi tur eng ko'p natija
ko'rsatgani.

---

## Sandbox

Sozlash ekranidagi belgini bossangiz: vaqt yo'q, ta'minot cheksiz, g'olib
e'lon qilinmaydi. Yon paneldan istalgan bo'linmani ikkala tomonga ham
qo'yib, texnikani sinab ko'rasiz.

---

## Fayllar

```
project.godot
core/     autoload: EventBus, Settings, Loc, DB, GameState
data/     units.json (bo'linmalar va tomonlar)
          battle_maps.json (xaritalar, fasllar, ob-havo, g'alaba shartlari, bot)
battle/   relyef va daryo, xarita quruvchi, pana tizimi, parchalanadigan uy,
          shtab nishoni, bo'linmalar, snaryad, direktor, statistika, AI,
          jang sozlagich, kamera, boshqaruv
ui/       sozlash ekrani, jang HUD'i, natija, sozlamalar
tests/    headless sinovlar va jang simulyatsiyasi
```

36 ta fayl, ~6900 qator GDScript.

## Sinovlar

```bash
godot --headless --path . -s res://tests/run_tests.gd
```

```bash
godot --headless --path . -s res://tests/sim_battle.gd
```

Ikkinchisi oltita xaritada jangni grafikasiz o'ynab, balansni chiqaradi.
