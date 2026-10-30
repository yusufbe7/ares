# Kampaniya: dunyo xaritasi (Total War uslubida)

## O'yin oqimi
1. **Davlat tanlash** (o'yin ochilganda birinchi ekran, `ui/screens/country_select.gd`).
   - Chapda qidiruv va 189 davlat ro'yxati: bayroq, nom, kuch (0–100; polklar va YaIM dan).
   - O'rtada dunyo xaritasi: bosilgan joydagi davlat tanlanadi, uning hududlari va blokdoshlari yoritiladi.
   - Tablar: Umumiy (avtomatik tavsif, qo'shnilar), Statistika, Blok. Boshqaruv tabi "Tez orada".
   - Sozlamalar: o'yin rejimi (Standart / Hukmronlik), qiyinlik, Ironman, "Boshida bloklar yo'q".
   - G'alaba shartlari oldindan yoziladi. Tugmalar: O'yindan chiqish / Tasodifiy / START.
   - Tanlov `user://campaign_setup.json` da saqlanadi.
2. **Bosh menyu** (`res://ui/main.tscn`). CAMPAIGN → missiyalar va saqlangan o'yinlar. Kichik dunyo xaritasini bossangiz, kampaniya o'sha joyda ochiladi.
3. **Dunyo xaritasi** (`res://campaign/campaign_map.tscn`) tanlangan davlat bilan ochiladi. Urush e'lon qiling va hujum qiling (pastda).
4. **Hujum → 3D jang → natija** xaritaga qaytadi.

Xaritani alohida sinash uchun `campaign_map.tscn` ni oching va **F6** ni bosing.

## Xarita
- **Butun dunyo.** Uzunlik −180…180°, kenglik −58…84°, rasm o'lchami 4320×1704 (5 yoy daqiqa). Unda 1640 hudud va 189 davlat bor.
- **Ko'rinish real.** Rang NASA Blue Marble sun'iy yo'ldosh rasmidan, relyef soyasi NOAA ETOPO 2022 balandligidan olingan. Okean tungi va qorong'i, ustida sekin bulutlar suzadi. Davlat rangi faqat yengil tus beradi: chegaralar aniq, rang xira.
- **Ma'lumot manbalari:** Natural Earth 10m admin-0 va admin-1 (chegaralar, viloyatlar), populated places (shaharlar, poytaxtlar, aholi). Hammasi public domain.
- **Poytaxt hududlari** poytaxt shahri nomi bilan ataladi: Paris, Tashkent, Berlin va hokazo.
- **Yaqinlashish.**
  - Istalgan joyni **ikki marta bosing**: kamera o'sha joyga uchib boradi va yaqinlashadi. Dengizni **bir marta** bosish ham yetarli.
  - G'ildirak sichqoncha turgan joy tomonga yaqinlashtiradi. Eng yaqin masofa 3 (avval 8 edi).
  - Yaqinda yer yuqori aniqlikdagi sun'iy yo'ldosh rasmidan chiziladi (`map/satellite_hd.jpg`, 16384 piksel, NASA Blue Marble 21600 manbasidan, `tools/make_satellite_hd.py`).
  - Qirg'oq chizig'i silliqlangan, pikselli zinapoya ko'rinmaydi.
- **Okean.** "Free Ocean simulation - Tiled" modelining animatsiyasidan olingan (the9thearl, CC BY 4.0). 159 MB lik GLB o'yinga qo'yilmagan, uning to'lqin animatsiyasi `tools/bake_ocean.py` bilan teksturaga pishirilgan:
  - `map/ocean_disp.png`: 125 kadrli 3D to'lqin siljishi;
  - `map/ocean_normal.png`: normal va to'lqin cho'qqisidagi ko'pik;
  - `map/ocean_color.jpg`: GLB'dagi suv rangi;
  - `data/ocean.json`: parametrlar.

  Uzoqdan okean tungi xarita uslubida ko'rinadi. Yaqinlashganda haqiqiy to'lqinlar paydo bo'ladi: ikki qatlam, takror naqsh ko'rinmaydi. Qo'shimcha ravishda to'lqin cho'qqisida ko'pik, sayoz suvda feruza rang (ETOPO chuqurligidan), quyosh yaltirashi va osmon aksi bor. Kamera masofasi 45 dan kichik bo'lganda kamera ostida 3D to'lqin qatlami (`campaign/map/ocean_near.gd`) suv yuzasini haqiqatan ko'tarib-tushiradi.

## Ekran (rasmdagidek)
| Joy | Nima |
|---|---|
| Yuqori chap | O'yin nomi (`data/game.json`: title / subtitle / logo, almashtiriladi) |
| Chap menyu | CAMPAIGN, WORLD MAP (pastki panellarni yig'adi), OPERATIONS (RTS jang), ARMORY, GARAGE, SOLDIER CUSTOMIZATION, SETTINGS, EXIT. BASE MANAGEMENT va RESEARCH "Tez orada" |
| Yuqori markaz | Tablar: WORLD MAP, ECONOMY (ishlaydi), DIPLOMACY (urush/tinchlik jadvali), TACTICAL VIEW va FACTIONS ("Tez orada") |
| Yuqori o'ng | O'yinchi: avatar, ism, daraja, XP; CREDITS (davlat oltini), SUPPLY, UNITS (qo'shinlar soni), xabarlar, sozlamalar |
| O'ng | GLOBAL TENSION va tanlangan hudud yoki davlat ma'lumoti |
| Pastda | CURRENT CAMPAIGN, MISSION, SELECT FACTION, MAP OPTIONS. "Hide panels" tugmasi bilan yig'iladi |

Hamma uslub bitta Theme'da (`ui/theme/main_theme.tres`), hamma matn `tr()` / `Loc.t()` orqali `data/lang/*.json` dan olinadi. Asosiy til ingliz, qo'shimcha o'zbek va rus. Til Settings > Language da tanlanadi.

## Mexanika
- **Davlat tanlash.** SELECT FACTION to'rida 8 ta yirik davlat va CUSTOM bor (xaritadan istalgan davlatni bosish). Ro'yxat `data/factions.json` da. Tanlanganda kamera o'sha davlatga siljiydi, uning hududlari ajralib turadi, STARTING UNITS qatori chiqadi: piyoda, BTR, tank, aviatsiya, vertolyot. Bular davlatning haqiqiy polklari soni × tarkib ulushi × `units_per_regiment` dan hisoblanadi.
- **MAP VIEW:**
  - Political: davlat ranglari;
  - Terrain: tabiiy rang, siyosiy qoplama juda xira;
  - Resource: hudud resursi va miqdori bo'yicha rang.
  - Almashish shader parametri bilan bo'ladi, qayta yuklanmaydi.
- **MAP OPTIONS:** Borders, Resources (ikonkalar), Military Bases, Supply Routes, Conflicts, Ally Territories, Sea lanes. Har biri darhol ishlaydi.
- **GLOBAL TENSION.** Bloklar `data/blocs.json` da (NATO, CSTO, CHINA, qolganlari OTHERS). Formula:
  `ulush = 0.5 · (blok hududlari / jami hududlar) + 0.5 · (blok polklari / jami polklar)`.
  Og'irliklar `data/rules.json` → `tension_weights` da. Ulush har yurish va har hudud bosib olinganda qayta hisoblanadi.
- **Diplomatiya.** Hamma davlat tinchlikda boshlaydi. Urushda bo'lmagan davlatga hujum qilib bo'lmaydi: hudud panelida yoki DIPLOMACY tabida "Declare war" tugmasi bor. Bir blokdagilar ittifoqchi, ularga urush e'lon qilib bo'lmaydi. Botlar o'zidan 1,5 baravar zaif qo'shnisiga 12% ehtimol bilan urush e'lon qiladi (`rules.json`).
- **Dengiz yo'llari.** Suv orqali 320 km gacha bo'lgan sohil juftliklari `data/neighbors.json` da `"sea"` ro'yxatida turadi. Ularni `tools/build_campaign_map.py` hisoblaydi. Dengizdan o'tish qo'shinni yana bir yurish band qiladi. Shu yo'l bilan Sitsiliya, Kipr, Britaniya va boshqa orollarga borish mumkin.
- **Ta'minot.** Yo'l bazadan yoki poytaxtdan qo'shingacha o'z va ittifoqchi hududlar orqali qidiriladi (BFS). Xaritada punktir chiziq ko'rinadi, ustida quruqlikda yuk mashinasi, dengizda kema yuradi. Yo'l uzilsa, chiziq qizil bo'ladi, samolyot belgisi chiqadi va qo'shin kuchi −30% kamayadi (`unsupplied_penalty`).
- **Ziddiyatlar.** So'nggi 3 yurishdagi jang log'idan olingan joylarda qizil pulsatsiyalanuvchi belgi chiqadi.
- **Harbiy bazalar** `data/bases.json` da: boshida har poytaxtda bittadan.
- **Iqtisod.**
  - Oltin = har hudud uchun 5 + YaIM (million $) × 0.00004.
  - Supply = resurs hosili − har polk uchun 1.
  - ECONOMY tabida har yurish tarixi va grafik bor.
- **Missiyalar** `data/missions/*.tres` da. Maqsad hudud qoida bilan topiladi ("eng boy dushman qo'shnisi", "eng yaqin dushman poytaxti"), shuning uchun istalgan davlat bilan ishlaydi. OBJECTIVES holati haqiqiy egalik va janglardan tekshiriladi. Missiya tanlanganda kamera maqsadga boradi. START MISSION yonidagi qo'shin bilan avto-jangni boshlaydi.
- **Qo'shin belgilari.** O'zingizniki doira, dushmanniki qalqon shaklida, rangi davlat rangida, cheti qalin. Uzoqda yaqin belgilar "x5" bo'lib birlashadi. Panel ostiga tushgan belgi va yozuv chizilmaydi.
- **Saqlash.** Avto-saqlash va 3 ta slot bor (`user://`).

## Hujum (8 qadam)
1. **Hududni tanlash.** Dushman hududi panelida egasi, aholi, mudofaa, garnizon, resurs va tartibsizlik ko'rinadi. Urushda bo'lsangiz **ATTACK** tugmasi chiqadi. Qo'shinni tanlab dushman hududini o'ng tugma bilan bossangiz ham bo'ladi.
2. **Tekshiruvlar** (hujum rejasi oynasi, `ui/campaign/attack_plan.gd`):
   - urush holati;
   - yo'l: quruqlik chegarasi, dengiz yo'li yoki samolyot masofasi;
   - transport: yaqinda harbiy port yoki qo'shin turgan joyda aviabaza;
   - ta'minot va yoqilg'i: har polk uchun quruqlik 1, dengiz 2, havo 4.
3. **Reja.**
   - Usul: **quruqlik** (asosiy), **dengiz desanti**, **havo desanti** (eng ko'pi 4 polk, 1500 km gacha).
   - Polklar soni (qolgani joyida qoladi).
   - Harakat: tez yoki to'liq animatsiya. Jang: 3D yoki avto-hisoblash.
4. **Harakat.** Xaritada yo'l chizig'i va tank / kema / samolyot belgisi yuradi, himoyachi ogohlantiriladi. Botlar o'yinchiga hujumni **bir yurish oldin** e'lon qiladi. Yetib kelganda "3D da himoya qilish" yoki "Avto-hisoblash" so'raladi.
5. **Jang maydoni** hududga qarab yaratiladi (`battle/battle_gen.gd`, `data/battle_biomes.json`): cho'l, shahar, tog', o'rmon, qirg'oq (GLB okeani bilan), qish, mo''tadil. Biom kenglik, balandlik, aholi zichligi, sohil va resursdan aniqlanadi. Seed hudud va yurishdan olinadi, ya'ni bir hudud doim bir xil.
6. **Jang.**
   - Yuklash ekrani o'rniga intro (`battle/battle_intro.gd`): kamera maydonni aylanadi, F-117 lar uchib o'tadi, Mi-24 qo'nadi, T-72 va Humvee kirib keladi.
   - Vazifa yozuvi va ikki tomon kuchlari ko'rsatiladi, keyin JANGNI BOSHLASH yoki AVTO-HISOBLASH.
   - Jang paytida tepada kuch nisbati, ta'minot va nuqtalar nazorati turadi.
   - 1 polk = 10 askar. Juda katta janglar 320 askargacha masshtablanadi.
7. **Natija.** Qolgan askarlar polklarga aylanadi, yo'qotishlar xabarda ko'rsatiladi (`battle/battle_bridge.gd`). Kampaniya jangdan oldin avto-saqlanadi va natija qo'llanadi.
8. **Xarita yangilanadi.** Hudud rangi o'zgaradi, bazalar va resurslar yangi egaga o'tadi.

## Bosib olingandan keyin (`campaign/logic/occupation.gd`, `rules.json` → `occupation`)
- **Tartibsizlik.** Yangi hududda 60%. Har yurish 8 ga kamayadi va daromadni kamaytiradi. 45% dan yuqori, qo'shin yo'q bo'lsa qo'zg'olon chiqishi mumkin: hudud eski egasiga qaytadi.
- **Bazalar.** Aerodrom, port yoki ombor qo'lga olinsa xabar chiqadi.
- **Poytaxt olinsa – kapitulyatsiya.**
  - Tinchlik tuziladi, 30% oltin tovon to'lanadi.
  - Poytaxt eng katta qolgan hududga ko'chadi. Asl poytaxt qaytarib olinsa, poytaxt yana o'sha yerga qaytadi.
  - Barcha hududlarni olish davlatni avtomatik yo'q qilmaydi.
  - O'yinchining poytaxti olinsa – mag'lubiyat.
- **Diplomatiya.**
  - Hujumga uchragan davlatning blokdoshlari urushga kiradi.
  - O'yinchi poytaxt olsa, boshqa bloklar 5 yurishga sanksiya qo'yadi (daromad −15%).
  - Umumiy dushmani bor, blokka kirmagan davlat ittifoq taklif qiladi.
- **G'alaba** (tablar ostida ko'rinadi):
  - Standart: dunyoning 20% i yoki 3 ta kapitulyatsiya;
  - Hukmronlik: 50%.

## Fayllar
- `campaign/campaign_map.gd`: sahna, qatlamlar.
- `campaign/logic/`: o'yin mantig'i, UI'siz ishlaydi:
  - `rules.gd` (jang, `conquer`, `apply_setup`), `turns.gd` (yurish, iqtisod, botlar, e'lon qilingan hujumlar);
  - `war_ops.gd` (hujum rejasi, biom), `occupation.gd` (bosib olingandan keyin);
  - `diplomacy.gd`, `supply.gd`, `tension.gd`;
  - `missions.gd`, `campaign_save.gd`.
- `campaign/map/`: relyef (`map_terrain.gd`, `campaign_terrain.gdshader`), yozuvlar (`map_labels.gd`, polylabel usuli), qatlamlar (`layers_overlay.gd`), bulutlar.
- `ui/campaign/`: panellar. Ular bir-biriga EventBus (`autoload/event_bus.gd`) orqali ulanadi. `attack_plan.gd` – hujum oynasi, `country_info.gd` – davlat tanlash ma'lumoti.
- `campaign/ops_runner.gd`: xaritadagi hujum animatsiyasi.
- `battle/`: jang maydoni generatori (`battle_gen.gd`, `battle_layout.gd`), qirg'oq dengizi (`battle_water.gd`), intro, kampaniya ko'prigi.

## Sinash
```
godot --headless --path . -s res://tests/test_campaign.gd   # 32 tekshiruv
godot --headless --path . -s res://tests/test_menu.gd       # davlat tanlash va bosh menyu oqimi
godot --headless --path . -s res://tests/test_war_ops.gd    # hujum usullari, biomlar, natijani qo'llash
godot --headless --path . -s res://tests/test_battlegen.gd  # 7 biom maydoni (vaqt o'lchanadi)
godot --headless --path . -s res://tests/test_flow.gd       # to'liq oqim: davlat -> hujum -> 3D jang -> natija
godot --headless --path . -s res://tests/sim_campaign.gd    # 40 yurish simulyatsiyasi
```

## Ma'lumotni qayta yasash
1. ETOPO 2022 (60″) va NASA Blue Marble rasmini yuklab oling.
2. Natural Earth 10m geojson fayllarini yuklab oling: admin-0, admin-1, populated places, lakes.
3. Quyidagi buyruqni ishga tushiring:
   `python tools/build_campaign_map.py <etopo> <bluemarble> <natural_earth_papka> <godot_loyiha>`

Mavjud ma'lumotdagi poytaxt nomlarini qayta yasamasdan tuzatish uchun: `python tools/name_capitals.py <natural_earth_papka>`.

## Hali yo'q
- TACTICAL VIEW va FACTIONS tablari; to'liq diplomatiya: shartnomalar va ittifoq tuzish.
- Base Management va Research bo'limlari.
- 3D jangda havo / dengiz desanti alohida sahna emas: bir xil maydon, qo'shin kirish nuqtasidan kiradi.
- Davlat boshqaruvi (tuzum) ma'lumoti yo'q, shuning uchun tab "Tez orada".
- Fog of war.
