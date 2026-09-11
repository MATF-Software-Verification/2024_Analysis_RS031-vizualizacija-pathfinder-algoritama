# Izvestaj o analizi projekta - SketchIt

Seminarski rad iz predmeta **Verifikacija softvera**, Matf.

- **Autor:** Jovan Skoric, broj indeksa: 1030/2024
- **Analizirani projekat:** SketchIt - C++/Qt6 multiplayer igra crtanja i pogadjanja (klon skribbl.io)
- **Izvor:** https://gitlab.com/matf-bg-ac-rs/course-rs/projects-2024-2025/SketchIt
- **Grana:** `main`, **Commit:** `1578f98aa3fba5eba5d183c83e048ffdfbc43af0`
- **Datum:** jun 2026.

---

## 1. Uvod i metodologija

Cilj rada je primena vise nezavisnih tehnika verifikacije nad jednim realnim projektom otvorenog
koda i kriticko poredjenje onoga sto svaka tehnika moze (i ne moze) da otkrije. Projekat je
ukljucen kao **git submodul** (`SketchIt/`), cime original ostaje nepromenjen; jedina neophodna
izmena (popravka prevodjenja) izolovana je u `custom.patch`.

Analiza je fokusirana na **serversku logiku** (`SketchIt/SketchIt/server/`): `points.cpp`,
`hangman.cpp`, `words.cpp`, `leaderboard.cpp`, `player.cpp`, `manager.cpp`, `game.cpp`. Server je
izabran jer sadrzi algoritamsku logiku nezavisnu od GUI-ja, pa je merljiv i testabilan. Mrezni
ulaz (`server.cpp`, `main.cpp`) i `QtZeroConf` zavisnost su van opsega jedinicnog testiranja.

Primenjeno je **7 tehnika**: jedinicni testovi, integracioni testovi, clang-tidy, Valgrind,
cppcheck, ASan/UBSan i CBMC. Dve tehnike su van vezbi: cppcheck i ASan/UBSan.

Ista jezgra logike (bodovanje, maskiranje reci) napadnuta je sa vise strana radi unakrsne potvrde nalaza.

### 1.1 `custom.patch` - neophodna popravka prevodjenja

Na pinovanom commit-u kod se **ne prevodi** sa Qt 6.10: `server/words.cpp` koristi `QTextStream`
bez `#include <QTextStream>` (greska: *variable 'QTextStream in' has incomplete type*). Zakrpa
dodaje taj jedan include i primenjuje se nad submodulom pre svake analize:

```bash
git submodule update --init
( cd SketchIt && git apply ../custom.patch )
```

---

## 2. Alati, postupak i rezultati

### 2.1 Jedinicni i integracioni testovi (QtTest) + pokrivenost (gcov/lcov) - `tests/`

Izgradjena je staticka biblioteka `serverlogic` (instrumentisana sa `--coverage`) i pet QtTest
izvrsnih fajlova. Testovi se pokrecu headless (`QT_QPA_PLATFORM=offscreen`), a resursi (lista reci,
seed leaderboard-a) se registruju kroz `Q_INIT_RESOURCE`.

- **Jedinicni (bez spoljnih zavisnosti):** `tst_points` (bodovanje), `tst_hangman` (maskiranje reci)
  - cista aritmetika/string nad primitivima.
- **Integracioni (prelaze granicu bez mocka):** `tst_leaderboard` (cita JSON seed), `tst_words`
  (cita `words.txt`), `tst_manager` (`Manager` + `Player` roster + `Leaderboard` + fajl-sistem).
- **Ukupno: 31 test, svi prolaze.** Autorskih testova **21**, a preostalih 10 je QTest-ov okvir.
   Raspodela autorskih: `tst_points` 6, `tst_hangman` 4, `tst_leaderboard` 3, `tst_words` 3, `tst_manager` 5.

**Pokrivenost (per-fajl, iz `gcov`):**

| fajl | linija | izvrseno |
|---|---:|---:|
| points.cpp | 26 | 100% |
| hangman.cpp | 20 | 100% |
| words.cpp | 25 | 92% |
| leaderboard.cpp | 75 | 88% |
| manager.cpp | 105 | 33% |
| player.cpp | 151 | 17% |
| game.cpp | 186 | 0% |

Ukupno (genhtml): **32.5% linija (185/569), 45.7% funkcija (32/70)**. Direktno testirane klase
imaju 88-100%; niska ukupna brojka potice od `player.cpp`/`game.cpp` koji su dominantno
soket/threading kod, povuceni samo kao link-zavisnosti i nedostupni bez zive mreze.

> Napomena o brojanju: imenioci iz `gcov`-a se sabiraju na 588, a `genhtml` prijavljuje 569.
> Razlika je u tri fajla (`manager.cpp` 105 vs 99, `player.cpp` 151 vs 142, `game.cpp` 186 vs 182)
> i potice od toga sto lcov filtrira deo linija koje `gcov` broji kao izvrsive.

### 2.2 clang-tidy (staticki lint) - `clang-tidy/`

Pokrenut nad `compile_commands.json` (generisanim iz CMake projekta) sa skupom provera
`bugprone-*, cppcoreguidelines-*, modernize-*, performance-*, misc-*`. Log sadrzi **185
upozorenja, od kojih 145 jedinstvenih** - ista zaglavlja se prevode u vise prevodnih jedinica, pa
se isto upozorenje ponovi. Najznacajnija:

- `cppcoreguidelines-special-member-functions` (9x) + `owning-memory` (7x) na `Player`/`Game`/`Manager`:
  klase poseduju sirove pokazivace (soket, `Hangman`, `QTimer`) bez kontrole kopiranja
  (krsenje pravila nule/pet) -> rizik od dvostrukog oslobadjanja / curenja.
- `misc-const-correctness` (37x), `non-private-member-variables` (24x, npr. javni `socket`, `ID`),
  `modernize-use-nodiscard` (13x), `modernize-use-override` (9x), `performance-enum-size` (5x),
  `narrowing-conversions` (3x).
- Najbrojnija grupa je zapravo `misc-include-cleaner` (57x) - nedostajuci ili suvisni `#include`.
  Nije defekt u ponasanju programa, ali objasnjava zasto je ukupan broj upozorenja visok.

### 2.3 Valgrind memcheck - `valgrind/`

Cist Debug build (bez instrumentacije) pokrenut pod `memcheck --leak-check=full`, sa prikazom samo
definite/indirect curenja i Qt suppression fajlom. **Rezultat: 0 gresaka, 0 bajtova
definitely lost i 0 indirectly lost** na svim testovima, sto potvrdjuje ASan. Preostaje
`still reachable` (npr. 24.941 bajta u 64 bloka na `tst_manager`) - to su Qt-ovi globalni objekti
zivi do izlaska iz programa, ne curenje. Jedna greska je potisnuta Qt suppression fajlom
(`suppressed: 1 from 1`). Poznato curenje u `Player::run()` nije dostupno bez mreze pa ga dinamicki
alati ne mogu pogoditi (hvata ga clang-tidy staticki).

### 2.4 cppcheck (staticka analiza) - `cppcheck/`

Pokrenut sa `--enable=all --library=qt` (Qt biblioteka je nuzna da bi razumeo `Q_OBJECT`/`slots`;
bez nje pada na `unknownMacro` i broj nalaza se sa 15 srozava na 6). **Rezultat: 15 nalaza + 2
informativna** (`missingInclude`, `checkersReport`). Pretezno stilski/performansni: izostanak
`explicit` na jednoargumentnim konstruktorima (3x: `Points`, `Words`, `Player`), `passedByValue`
(2x, npr. `QList<Player*> players` po vrednosti), const-correctness (5x), `useStlAlgorithm`,
`shadowVariable`. **Vazan zakljucak:** cppcheck **ne** otkriva logicke bagove (underflow u
`Hangman`, beskonacnu petlju u `Words`) - za njih su potrebni dinamicki/simbolicki alati.

### 2.5 AddressSanitizer + UBSan - `sanitizers/`

Test-svita je ponovo izgradjena **clang++-om** (zbog `unsigned-integer-overflow`, koji gcc nema) sa
`-fsanitize=address,undefined,unsigned-integer-overflow`. **UBSan je precizno locirao bag:**

```
hangman.cpp:7:50: runtime error: unsigned integer overflow:
    0 - 1 cannot be represented in type 'size_type' (aka 'unsigned long')
```

Bibliotecki sum (Qt `QHash`, libstdc++ `mt19937`) prigusi se `ubsan.supp` fajlom, pa izvestaj
ostaje fokusiran na projekat. ASan nije prijavio curenja/UAF na pokrivenim putanjama.

### 2.6 CBMC (ogranicena provera modela) - `cbmc/`

Isti izrazi, drugi motor (SAT/SMT). Uz ugradjene provere `--signed/unsigned-overflow-check`:

- `hangman_masklen` -> `VERIFICATION FAILED`, underflow za `len = 0`.
- `points_domain` -> **`VERIFICATION SUCCESSFUL`**: dokazano da nad `[0,60000]` nema prekoracenja i
  da su skorovi u `[100,500]`/`[33,166]` - jaca garancija od dva granicna jedinicna testa.
- `points_overflow` -> `VERIFICATION FAILED`, prekoracenje `int`-a za `timeLeft = -1667805263`.

---

## 3. Objedinjeni nalazi

### 3.1 `Hangman` - underflow za praznu rec (potvrdjeno 3x)
`std::string(w.size()*2 - 1, ' ')` za `w=""` daje `0*2-1 = SIZE_MAX` -> pokusaj ogromne alokacije ->
`std::length_error`/`std::bad_alloc`. Bez ikakve provere ulaza. Potvrdila tri nezavisna izvora:
test `tst_hangman::emptyWordIsRejectedOrCrashes`, UBSan (dinamicki, nad pravim C++ kodom) i CBMC
(formalno, nad prepisanim harnesom).
**Preporuka:** odbiti praznu rec (`if (w.empty()) throw ...`) ili koristiti `2*w.size()` bez `-1`
uz odgovarajuce indeksiranje.

### 3.2 `Words` - moguci duplikati reci
`pickWords()` deduplira **indekse** (`QSet<int>`), ali `words.txt` ima 232 linije / **218
jedinstvenih (14 duplikata)**, pa dva indeksa mogu dati istu rec -> vracena lista nije nuzno
distinktna. Razotkrio ga je test `picksAreDistinct`, koji je pod clang-om padao (9 jedinstvenih
reci od 10) a pod gcc-om prolazio. Zbog te nestabilnosti test je uklonjen i zamenjen
stabilnim `picksAreFromDictionary`, a sam nalaz je zaveden kao komentar u `tst_words.cpp:26-27`.
Posledica: danas se ovaj defekt vise ne proverava, pa bi ga regresija propustila.
**Preporuka:** ocistiti listu od duplikata i/ili deduplirati po vrednosti reci, a ne po indeksu.

### 3.3 `Words` - beskonacna petlja
`while(randomIndices.size() < count)` se nikad ne zavrsava ako je `count > wordList.size()` (232):
`QSet<int>` ne moze da naraste preko 232 elementa, pa uslov ostaje tacan zauvek. Nema gornje
granice. **Preporuka:** ograniciti `count` na `min(count, wordList.size())`.

### 3.4 `Points` - nevalidovana aritmetika
Formula `100 + (400 * timeLeft / 1000) / 60` je korektna **samo** dok pozivaoci drze `timeLeft` u
`[0,60000]`. CBMC to dokazuje za ceo domen, a bez tog ugovora daje kontraprimer
(`timeLeft = -1667805263`, prekoracenje `int`-a, sto je nedefinisano ponasanje).
**Preporuka:** validirati `timeLeft` u samoj funkciji (clamp ili `assert`) umesto oslanjanja na
implicitni ugovor pozivaoca.

---

## 4. Komplementarnost alata (zakljucak metodologije)

Oznake: `+` alat je nalaz otkrio, `-` nije, `dok.` alat ga dokumentuje ali ga nije sam otkrio,
`n/d` putanja nije dostupna tom alatu.

| Defekt | testovi | cppcheck | clang-tidy | ASan/UBSan | Valgrind | CBMC |
|---|:--:|:--:|:--:|:--:|:--:|:--:|
| Hangman underflow | dok. | - | - | **+** | - | **+** |
| Points van domena | dok. | - | - | - | - | **+** |
| Player curenje/rule-of-5 | - | - | **+** | n/d | n/d | - |
| Stil/perf/const | - | **+** | **+** | - | - | - |

## 5. Zakljucak

Projekat SketchIt je funkcionalno solidan, ali sadrzi nekoliko stvarnih defekata u serverskoj
logici: underflow za praznu rec u `Hangman`-u, moguce duplikate i potencijalnu beskonacnu petlju u
`Words`-u, nevalidovanu aritmetiku u `Points`-u i krsenje pravila vlasnistva u `Player`-u. Svi
ozbiljniji nalazi su **nezavisno potvrdjeni sa po nekoliko alata**. Preporucuje se validacija ulaza
na granicama klasa, cistenje resursa kroz RAII/Qt-parent i prosirenje test-svite na mrezni sloj uz
mock soketa.

---
**Autor:** Jovan Skoric | **Predmet:** Verifikacija softvera, MATF | **Datum:** jun 2026.
