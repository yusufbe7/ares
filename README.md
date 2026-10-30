# Europe Front RTS (Godot 4.7)

Qishki qishloqdagi jang (videodagidek). Askarlar, insurgentlar, tanklar, vertolyot va ularning animatsiyalari
`battlefield_rts` o'yinidan olingan. Yer, yo'llar, daraxtlar va **parchalanadigan uylar** esa `RTS_Battlefield`
(Blender) loyihasidan eksport qilingan.

## Ishga tushirish
Godot 4.7 da `godot_game/project.godot` ni oching va **F5** ni bosing. O'yin **bosh menyudan** boshlanadi (`ui/main.tscn`):
- **Orqada** o'yindagi askar modelingiz (`assets/soldier.glb`) uchta nusxada turadi. Ular lagerda, quyosh botish yorug'ida, o'z idle animatsiyasi bilan. Birinchisi o'yinchining jihozlanishida.
- **Menyu:** CAMPAIGN (dunyo xaritasi, `campaign/README_CAMPAIGN.md`), OPERATIONS (shu qishki jang), ARMORY, GARAGE, SOLDIER CUSTOMIZATION, SETTINGS, EXIT. Esc oldingi ekranga qaytaradi.
- **O'ngda** VEHICLE MARKET: rasmlar o'yindagi 3D modellardan render qilingan (`tools/render_thumbs.gd`, `ui/thumbs/`). Pastda tezkor jihozlanish, LAST MISSION va **DEPLOY TO BATTLEFIELD**.
- **Qurol: AK-47** (MaX3Dd, Sketchfab). Teksturalari 4K dan 2K ga tushirilgan (`tools/shrink_glb.py`, `assets/weapons/ak47.glb`), askar qo'liga moslangan (`assets/weapons/ak47_rifle.tscn`). Menyu, Armory, Customization va jangdagi askarlar shu qurolni ishlatadi.
- **Ma'lumot** `data/` dagi Resource / JSON fayllarida: texnika, qurol, kiyim, operatsiya, missiya, narx. O'yinchi profili `user://profile.save` da.
- **Settings** (`user://settings.cfg`):
  - grafika, ovoz;
  - tugmalarni qayta belgilash. Jangdagi R/Y/U/B/V/G/T/H/F/N va WASD/Q/E shu yerdan o'zgaradi (`ui/settings/keys.gd`);
  - kamera tezligi, til (ingliz / o'zbek / rus), UI o'lchami va shaffofligi, FPS.

## O'yin logikasi (yarim avtomatik)
O'yinchi askarlarni qadamma-qadam yurgizmaydi, faqat maqsad beradi: "u yerga bor", "u nuqtani ol", "otryad chaqir". Askarlar yo'lni, panani, otishni, yashirinishni va yaradorni tashishni o'zlari hal qiladi.

- **A / B / C nuqtalar**: A = Crossroads, B = Village (uylar), C = East Farm. Ko'proq nuqtani ushlab turgan tomon raqibni **qon yo'qotishga (bleeding)** majbur qiladi: har 15 soniyada raqib zaxirasidan farq soniga teng odam kamayadi.
- **Zaxira**: har tomonda 150 kishi. **R** tugmasi xaritaning janubi-g'arbiy chetidan 5 kishilik otryad chaqiradi (25 s kutish). Otryad o'zi eng yaqin olinmagan nuqtaga yo'l oladi.
- **Y**: T-72 tank (120 supply + 3 ekipaj). **U**: artilleriya (40 supply). Snaryadlar tushishidan oldin qizil doira chiqadi va hamma askarlar o'sha zonadan qochadi.
- **B**: radial qurilish menyusi: TRENCH (har metri 1), WIRE (4), CAMO NET (15), MINES (6). Supply vaqt o'tishi bilan keladi, ushlab turilgan har bir nuqta daromadni oshiradi.
- Askarlar tanlangan holda nuqta ichiga o'ng tugma bosilsa, ular nuqtani o'zlari egallaydi: panadan panaga yugurib boradi. Oddiy yerga o'ng tugma bosilsa, o'sha joyga borib turadi.
- **Tugash**: 30 daqiqa o'tganda ko'proq odami qolgan tomon yutadi. Bir tomonning zaxirasi ham, maydondagi odami ham qolmasa, o'yin shu yerda tugaydi.
- **Dushman qo'mondoni** shimoli-sharqdan xuddi shunday o'ynaydi: otryadlar yuboradi, sizning to'planib turgan askarlaringizga artilleriya otadi, tank va FPV dron chaqiradi.

### AI pana tizimi (AI COVER SYSTEM)
- Pana nuqtalari (slot) avtomatik joylashtiriladi: uy devorlari va burchaklari, daraxt tanasi, toshlar, yiqilgan daraxtlar, voronkalar (har yangi portlashda yangisi paydo bo'ladi), xandaqlar, qum qoplari, yongan tanklar va vayronalar. Ularning soni ekranning chap yuqorisida ko'rinadi.
- Har bir nuqta qaysi tomondan himoya qilishini, qanchalik himoya qilishini (to'liq yoki yarim) va band yoki bo'shligini biladi. Askar eng yaxshisini shu formula bilan tanlaydi: **ball = himoya − masofa + dushmanga qarash − band bo'lsa jarima**.
- **Bosim (suppression)**: atrofdan o'q o'tsa yoki yaqinda portlash bo'lsa, askar avval cho'kkalaydi, keyin yotadi va aniqligi pasayadi. Bosim kuchli bo'lsa pana ortidan boshini ko'tarmaydi. Bosim vaqt o'tishi bilan kamayadi.
- **Xandaq**: ichidagi askar 70–80% himoyalangan. Tank xandaqdan o'ta olmaydi, ya'ni xandaq tankka qarshi to'siq ham bo'ladi.
- **Tank zirhi**: oldi qalin, yonlari o'rtacha, orqasi zaif. Mina va granata ham tankka zarar beradi.

## Uylar qanday buziladi
- Har bir uy Blenderda (`house_gen.py`) 300 dan 530 gacha qavariq bo'lakka bo'lingan. Qaysi bo'lak qaysi bo'lakka tayanishi ham Blenderda hisoblanib, `europe/houses/House_XX.json` faylida saqlangan.
- Uy butun turganda u bitta mesh sifatida chiziladi, shuning uchun o'yinni sekinlashtirmaydi.
- Qotib qolmaslik uchun har bir zarbada faqat eng katta 14 ta parcha haqiqiy fizik jism bo'ladi (bir vaqtda ko'pi bilan 60 ta). Ular `BoxShape3D` bilan ishlaydi, bir-biri bilan to'qnashmaydi, faqat yer va devorlarga uriladi va soyasi yo'q. Qolgan parchalar fizikasiz, oddiy skript bilan tushadi va har kadrda 8 tadan bo'lib ozod qilinadi. Yerga tushgan yoki tinchlangan parcha bitta umumiy "vayrona" meshiga qo'shiladi (fizikasi ham, alohida node'i ham qolmaydi).
- Snaryad tushganda yer faqat 37x37 metrli bir bo'lakda qayta quriladi, butun xarita emas.
- Uyning har bir bo'lagining o'z kolayderi bor: snaryad va raketa birinchi uchragan devorda portlaydi.
- Portlash yaqinidagi bo'laklar Jolt fizikasi bilan uchib ketadi, atrofidagi g'isht yoriladi. Poydevor bilan aloqasi uzilgan qism (masalan, tom) og'irlik kuchi bilan qulaydi.
- Portlashda oynalar sinadi, devorlarga kuya o'tiradi va suvoq changi ko'tariladi.
- Devorlarining yarmidan ko'pi yiqilgan uy yonib, qora tutun chiqarib turadi. Uning vayronasidan askarlar o'tishi mumkin.
- Tank daraxtga urilsa yoki yonida portlash bo'lsa, daraxt yiqiladi va yiqilgan tana pana bo'ladi. Katta portlashlar yerda chuqur qoldiradi.

## Boshqaruv
| Tugma | Harakat |
|---|---|
| Chap tugmani bosib sudrash / bosish | Tanlash / otryadni tanlash |
| O'ng tugma (yerga) | Yurish |
| O'ng tugma (dushmanga) | Hujum |
| O'ng tugma (**uyga**) | Tank va Mi-24 shu devorni o'qqa tutadi, piyodalar uy devorlari yonida pana oladi |
| V | Xandaq chizish (askarlar qazishadi) |
| R / Y / U / B | Otryad / tank / artilleriya / qurilish menyusi |
| G / T | Granata / RPG |
| Z / X / C | Yotish / cho'kkalash / turish |
| H / F | To'xtash / kamerani tanlanganlarga olib borish |
| WASD, g'ildirak, Q/E | Kamera |
| N / Esc / F9 | Qish yoki yoz / pauza / qaytadan boshlash |

## Fayllar
- `europe/europe_map.gd`: yer (1025x1025, 600x600 m), teksturalar, qor, daraxtlar, xandaq qazish, chuqurlar.
- `europe/destructible_house.gd`: parchalanadigan uy.
- `europe/terrain.gdshader`, `europe/house.gdshader`: yer va uy materiallari (Poly Haven teksturalari, qor).
- `europe/houses/`, `europe/vegetation/`, `europe/terrain/`: Blenderdan eksport qilingan fayllar.
- `demo/operation.gd`, `demo/operation_hud.gd`: operatsiya (nuqtalar, zaxira, bleeding, dushman qo'mondoni, radial menyu, minalar, artilleriya).
- `addons/rts_fx/cover_system.gd`: AI pana tizimi.
- `demo/`, `addons/rts_fx/`: eski o'yindagi askar, tank, vertolyot, HUD va rejimlar (yangi xaritaga moslangan).
- `tests/sim_operation.gd`, `tests/test_menu.gd`, `tests/test_campaign.gd`: headless sinovlar (`godot --headless --path . -s res://tests/<fayl>`).

Eslatma: CS2 terrorist modeli Valve o'yinidan olingan, uni tijoriy loyihada ishlatib bo'lmaydi.
