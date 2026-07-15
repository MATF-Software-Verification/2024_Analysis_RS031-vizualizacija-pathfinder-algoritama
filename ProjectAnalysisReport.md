# Izveštaj o analizi projekta — SketchIt

Seminarski rad iz predmeta **Verifikacija softvera**, Matematički fakultet, Univerzitet u Beogradu.

- **Autor:** Jovan Škorić, broj indeksa: 1030/2024
- **Analizirani projekat:** SketchIt — C++/Qt6 multiplayer igra crtanja i pogađanja (klon skribbl.io)
- **Izvor:** https://gitlab.com/matf-bg-ac-rs/course-rs/projects-2024-2025/SketchIt
- **Grana:** `main` · **Commit:** `1578f98aa3fba5eba5d183c83e048ffdfbc43af0`
- **Datum:** jun 2026.

---

## 1. Uvod i metodologija

Cilj rada je primena više nezavisnih tehnika verifikacije nad jednim realnim projektom otvorenog
koda i kritičko poređenje onoga što svaka tehnika može (i ne može) da otkrije. Projekat je
uključen kao **git submodul** (`SketchIt/`), čime original ostaje nepromenjen; jedina neophodna
izmena (popravka prevođenja) izolovana je u `custom.patch`.

Analiza je fokusirana na **serversku logiku** (`SketchIt/SketchIt/server/`): `points.cpp`,
`hangman.cpp`, `words.cpp`, `leaderboard.cpp`, `player.cpp`, `manager.cpp`, `game.cpp`. Server je
izabran jer sadrži algoritamsku logiku nezavisnu od GUI-ja, pa je merljiv i testabilan. Mrežni
ulaz (`server.cpp`, `main.cpp`) i `QtZeroConf` zavisnost su van opsega jediničnog testiranja.

Primenjeno je **7 alata/tehnika** (jedinični i integracioni testovi računaju se zasebno), od kojih
su dva van vežbi (cppcheck, ASan/UBSan).
Tehnike su namerno raspoređene po spektru: dinamičko testiranje → statička analiza →
instrumentacija pri izvršavanju → formalna verifikacija. Ista jezgra logike (bodovanje, maskiranje
reči) napadnuta je sa više strana radi unakrsne potvrde nalaza.

### 1.1 `custom.patch` — neophodna popravka prevođenja

Na pinovanom commit-u kod se **ne prevodi** sa Qt 6.10: `server/words.cpp` koristi `QTextStream`
bez `#include <QTextStream>` (greška: *variable 'QTextStream in' has incomplete type*). Zakrpa
dodaje taj jedan include i primenjuje se nad submodulom pre svake analize:

```bash
git submodule update --init
( cd SketchIt && git apply ../custom.patch )
```

---

## 2. Alati, postupak i rezultati

### 2.1 Jedinični i integracioni testovi (QtTest) + pokrivenost (gcov/lcov) — `unit_tests/`

Izgrađena je statička biblioteka `serverlogic` (instrumentisana sa `--coverage`) i pet QtTest
izvršnih fajlova. Testovi se pokreću headless (`QT_QPA_PLATFORM=offscreen`), a resursi (lista reči,
seed leaderboard-a) se registruju kroz `Q_INIT_RESOURCE`.

Podela jedinični/integracioni prati definiciju iz skripte predmeta: jedinični test izoluje
posmatranu jedinicu tako što **mockuje** sve spoljne zavisnosti (standardni ulaz, mreža, baze,
fajl-sistem, kao i komunikaciju sa drugim klasama). U ovom radu mock nije korišćen, pa su jedinični
isključivo testovi jedinica **bez ijedne spoljne zavisnosti** (nema šta da se mockuje); svi ostali u
izvršavanju realno prelaze bar jednu granicu (resurs/fajl-sistem/druga klasa) i time su integracioni.

- **Jedinični (bez spoljnih zavisnosti):** `tst_points` (bodovanje), `tst_hangman` (maskiranje reči)
  — čista aritmetika/string nad primitivima.
- **Integracioni (prelaze granicu bez mocka):** `tst_leaderboard` (čita JSON seed), `tst_words`
  (čita `words.txt`), `tst_manager` (`Manager` + `Player` roster + `Leaderboard` + fajl-sistem).
- **Ukupno: 31 test, svi prolaze.**

**Pokrivenost (ground-truth iz `gcov`):**

| fajl | linija | izvršeno |
|---|---:|---:|
| points.cpp | 26 | 100% |
| hangman.cpp | 20 | 100% |
| words.cpp | 25 | 92% |
| leaderboard.cpp | 75 | 88% |
| manager.cpp | 105 | 33% |
| player.cpp | 151 | 17% |
| game.cpp | 186 | 0% |

Ukupno (genhtml): **32.5% linija (185/569), 45.7% funkcija (32/70)**. Direktno testirane klase
imaju 88–100%; niska ukupna brojka potiče od `player.cpp`/`game.cpp` koji su dominantno
soket/threading kod, povučeni samo kao link-zavisnosti i nedostupni bez žive mreže.

> Napomena o alatu: `lcov --list` (v2.0) prikazuje **pogrešnu** per-fajl stopu za ovaj projekat
> (ne slaže se ni sa `gcov`-om ni sa `genhtml`-om koje sam generiše). Zato je rezime vođen iz
> `gcov`-a. Takođe je nužan `--ignore-errors mismatch,gcov,...` jer `lcov` inače prekida rad na
> bezopasnim upozorenjima iz inline-ovanog `libstdc++` koda.

### 2.2 clang-tidy (statički lint) — `clang-tidy/`

Pokrenut nad `compile_commands.json` (generisanim iz CMake projekta) sa skupom provera
`bugprone-*, cppcoreguidelines-*, modernize-*, performance-*, misc-*`. **185 upozorenja.**
Najznačajnija:

- `cppcoreguidelines-special-member-functions` + `owning-memory` na `Player`/`Game`/`Manager` —
  klase poseduju sirove pokazivače (soket, `Hangman`, `QTimer`) bez kontrole kopiranja
  (kršenje pravila nule/pet) → rizik od dvostrukog oslobađanja / curenja.
- `misc-const-correctness` (37×), `non-private-member-variables` (24×, npr. javni `socket`, `ID`),
  `modernize-use-nodiscard`, `performance-enum-size`, `narrowing-conversions`.

### 2.3 Valgrind memcheck — `valgrind/`

Čist Debug build (bez instrumentacije) pokrenut pod `memcheck --leak-check=full`, sa prikazom samo
akcionabilnih (definite/indirect) curenja i Qt suppression fajlom. **Rezultat: 0 grešaka i 0
curenja** na svim testovima — potvrđuje ASan. Poznato curenje u `Player::run()` nije dostupno bez
mreže pa ga dinamički alati ne mogu pogoditi (hvata ga clang-tidy statički).

### 2.4 cppcheck (statička analiza) — `cppcheck/`

Pokrenut sa `--enable=all --library=qt` (Qt biblioteka je nužna da bi razumeo `Q_OBJECT`/`slots`).
Nalazi su pretežno stilski/performansni: izostanak `explicit` na jednoargumentnim konstruktorima
(`Points`, `Words`, `Player`), `passedByValue` (npr. `QList<Player*> players` po vrednosti),
const-correctness, `useStlAlgorithm`. **Važan zaključak:** cppcheck **ne** otkriva logičke bagove
(underflow u `Hangman`, beskonačnu petlju u `Words`) — za njih su potrebni dinamički/simbolički
alati. Lep primer granica čisto statičke analize.

### 2.5 AddressSanitizer + UBSan — `sanitizers/`

Test-svita je ponovo izgrađena **clang++-om** (zbog `unsigned-integer-overflow`, koji gcc nema) sa
`-fsanitize=address,undefined,unsigned-integer-overflow`. **UBSan je precizno locirao bag:**

```
hangman.cpp:7:50: runtime error: unsigned integer overflow:
    0 - 1 cannot be represented in type 'size_type' (aka 'unsigned long')
```

Bibliotečki šum (Qt `QHash`, libstdc++ `mt19937`) priguše se `ubsan.supp` fajlom, pa izveštaj
ostaje fokusiran na projekat. ASan nije prijavio curenja/UAF na pokrivenim putanjama.

Ovaj build je **usput razotkrio drugi defekat**: test `picksAreDistinct` je pod clang-om pao
(9 jedinstvenih reči od 10). Uzrok nije slučajnost — vidi nalaz 3.2.

### 2.6 CBMC (ograničena provera modela) — `cbmc/`

Isti izrazi, drugi motor (SAT/SMT). Uz ugrađene provere `--signed/unsigned-overflow-check`:

- `hangman_masklen` → `VERIFICATION FAILED`, underflow za `len = 0`.
- `points_domain` → **`VERIFICATION SUCCESSFUL`**: dokazano da nad `[0,60000]` nema prekoračenja i
  da su skorovi u `[100,500]`/`[33,166]` — jača garancija od dva granična jedinična testa.
- `points_overflow` → `VERIFICATION FAILED`, prekoračenje `int`-a za `timeLeft = -1667805263`.

---

## 3. Objedinjeni nalazi

### 3.1 `Hangman` — underflow za praznu reč (potvrđeno 3×)
`std::string(w.size()*2 - 1, ' ')` za `w=""` daje `0*2-1 = SIZE_MAX` → pokušaj ogromne alokacije →
`std::length_error`/`std::bad_alloc`. Bez ikakve provere ulaza. Potvrdili UBSan i CBMC.
**Preporuka:** odbiti praznu reč (`if (w.empty()) throw ...`) ili koristiti `2*w.size()` bez `-1`
uz odgovarajuće indeksiranje.

### 3.2 `Words` — mogući duplikati reči
`pickWords()` deduplira **indekse** (`QSet<int>`), ali `words.txt` ima 232 linije / **218
jedinstvenih (14 duplikata)**, pa dva indeksa mogu dati istu reč → vraćena lista nije nužno
distinktna. Razotkriveno nestabilnim testom pod različitim kompajlerima. **Preporuka:** očistiti
listu od duplikata i/ili deduplirati po vrednosti reči, a ne po indeksu.

### 3.3 `Words` — beskonačna petlja
`while(randomIndices.size() < count)` se nikad ne završava ako je `count > wordList.size()` (232).
Nema gornje granice. **Preporuka:** ograničiti `count` na `min(count, wordList.size())`.

### 3.4 `Points` — nevalidovana aritmetika
Formula je korektna **samo** dok pozivaoci drže `timeLeft ∈ [0,60000]`. CBMC to dokazuje, a oba
formalna alata daju kontraprimere van domena. **Preporuka:** validirati `timeLeft` u samoj
funkciji (clamp ili `assert`) umesto oslanjanja na implicitni ugovor pozivaoca.

### 3.5 `Player` — curenje soketa i kršenje pravila pet
Soket se alocira u konstruktoru i ponovo u `run()` (prvi se gubi); klasa poseduje sirov pokazivač
bez kopir/move kontrole (clang-tidy: `owning-memory`, `special-member-functions`). Takođe
`split("/")[1]` nad neispravnim ulazom izlazi van granica. **Preporuka:** vlasništvo preko
`std::unique_ptr`/Qt parent mehanizma; definisati ili izbrisati kopir operacije; validirati ulaz.

---

## 4. Komplementarnost alata (zaključak metodologije)

| Defekt | testovi | cppcheck | clang-tidy | ASan/UBSan | Valgrind | CBMC |
|---|:--:|:--:|:--:|:--:|:--:|:--:|
| Hangman underflow | dok. | — | — | **✓** | — | **✓** |
| Words duplikati | **✓** | — | — | (povod) | — | — |
| Points van domena | dok. | — | — | — | — | **✓** |
| Player curenje/rule-of-5 | — | — | **✓** | n/d | n/d | — |
| Stil/perf/const | — | **✓** | **✓** | — | — | — |

Ključni zaključak: **nijedan alat sam nije dovoljan.** Statička analiza (cppcheck/clang-tidy) hvata
strukturne i stilske probleme ali promašuje aritmetičke bagove; dinamički alati (ASan/Valgrind)
hvataju samo ono što test-putanje izvrše; formalni alati (CBMC) dokazuju ili obaraju svojstva
nad celim domenom ali zahtevaju izolovane, čiste harnese. Tek njihova kombinacija daje poverenje.

## 5. Zaključak

Projekat SketchIt je funkcionalno solidan, ali sadrži nekoliko stvarnih defekata u serverskoj
logici: underflow za praznu reč u `Hangman`-u, moguće duplikate i potencijalnu beskonačnu petlju u
`Words`-u, nevalidovanu aritmetiku u `Points`-u i kršenje pravila vlasništva u `Player`-u. Svi
ozbiljniji nalazi su **nezavisno potvrđeni sa po nekoliko alata**. Preporučuje se validacija ulaza
na granicama klasa, čišćenje resursa kroz RAII/Qt-parent i proširenje test-svite na mrežni sloj uz
mock soketa.

---
**Autor:** Jovan Škorić · **Predmet:** Verifikacija softvera, MATF · **Datum:** jun 2026.
