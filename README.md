# Verifikacija softvera — Analiza projekta otvorenog koda: SketchIt

## Autor

- **Ime i prezime:** Jovan Škorić 
- **Broj indeksa:** 1030/2024
- Samostalni seminarski rad, kurs *Verifikacija softvera*, Matematički fakultet, Univerzitet u Beogradu.

## Analizirani projekat

**SketchIt** — kopija online multiplayer igre [skribbl.io](https://skribbl.io/), napisana u C++/Qt6.
Igra se sastoji iz **servera** (mrežna logika, bez GUI-ja) i **klijenta** (Qt Widgets GUI).
Svake runde jedan igrač crta zadatu reč, dok ostali pokušavaju da je pogode; bodovanje zavisi
od brzine pogađanja i kvaliteta crteža.

- **Izvorni kod:** https://gitlab.com/matf-bg-ac-rs/course-rs/projects-2024-2025/SketchIt
- **Analizirana grana:** `main`
- **Hash commit-a:** `1578f98aa3fba5eba5d183c83e048ffdfbc43af0`
- Projekat je referenciran kao **git submodul** u direktorijumu [`SketchIt/`](./SketchIt).

### `custom.patch`

Kod na pinovanom commit-u **se ne prevodi** sa Qt 6.10 — datoteka `server/words.cpp` koristi
`QTextStream` bez odgovarajućeg `#include <QTextStream>` (greška: *variable 'QTextStream in' has
incomplete type*). Minimalna izmena potrebna za prevođenje data je u [`custom.patch`](./custom.patch)
i primenjuje se nad submodulom pre analize:

```bash
git submodule update --init
cd SketchIt && git apply ../custom.patch && cd ..
```

## Fokus analize

Analiza je usmerena na **serversku logiku** (`SketchIt/server/`), jer je samostalna i ne zavisi od
GUI-ja: `points.cpp`, `hangman.cpp`, `words.cpp`, `leaderboard.cpp`, `player.cpp`, `game.cpp`,
`manager.cpp`.

## Korišćeni alati i tehnike

Analiza koristi **7 alata/tehnika** (zahtevani minimum je 6). Zahtev da **najmanje dva** alata
nisu rađena na vežbama je ispunjen — dva alata su van vežbi: **cppcheck** i
**AddressSanitizer/UBSan**.

| # | Alat / tehnika | Kategorija | Direktorijum | Na vežbama? |
|---|----------------|------------|--------------|-------------|
| 1 | QtTest — jedinični testovi | Testiranje | [`tests/`](./tests) | da |
| 2 | QtTest — integracioni testovi | Testiranje | [`tests/`](./tests) | da |
| 3 | clang-tidy | Stilske/lint provere | [`clang-tidy/`](./clang-tidy) | da |
| 4 | Valgrind (memcheck) | Dinamička analiza memorije | [`valgrind/`](./valgrind) | da |
| 5 | cppcheck | Statička analiza | [`cppcheck/`](./cppcheck) | **ne** |
| 6 | AddressSanitizer + UndefinedBehaviorSanitizer | Dinamička instrumentacija | [`sanitizers/`](./sanitizers) | **ne** |
| 7 | CBMC | Ograničena provera modela | [`cbmc/`](./cbmc) | da |

> Napomena prema pravilima: jedinični i integracioni testovi računaju se kao **dva zasebna alata**
> (stavke 1 i 2), iako dele isti direktorijum; alat za pokrivenost (gcov/lcov) je podrška testiranju
> i ne broji se zasebno. Podela prati definiciju iz skripte: jedinični test izoluje jedinicu tako što
> **mockuje** sve spoljne zavisnosti (fajl-sistem, mreža, druge klase). Pošto u ovom radu ne koristimo
> mock, jedinični su samo testovi jedinica **bez ijedne spoljne zavisnosti** — `tst_points` i
> `tst_hangman` (čista aritmetika/string nad primitivima, nema šta da se mockuje). Ostali testovi u
> izvršavanju stvarno prelaze granicu ka resursu/fajl-sistemu/drugoj klasi bez mocka, pa su po toj
> definiciji **integracioni**: `tst_leaderboard` (čita JSON seed), `tst_words` (čita `words.txt`) i
> `tst_manager` (`Manager` + `Player` roster + `Leaderboard` + fajl-sistem). Korišćen je tačno jedan
> Valgrind alat (memcheck) i tačno jedan alat za stil (clang-tidy).

## Reprodukcija

Preduslovi (Ubuntu 24.04):

```bash
sudo apt-get install -y cppcheck clang clang-tidy clang-format valgrind lcov cbmc
# Qt 6.10 instaliran u /home/<user>/Qt/6.10.2/gcc_64
```

Inicijalizacija:

```bash
git clone --recurse-submodules https://github.com/Skora01/2026_Analysis_SketchIt
cd VS-2
git submodule update --init
( cd SketchIt && git apply ../custom.patch )
```

Svaki alat ima `run.sh` skriptu u svom direktorijumu i `RunningTests.md` sa detaljima.
Sve skripte poštuju `QT_PREFIX` promenljivu (podrazumevano `/home/<user>/Qt/6.10.2/gcc_64`).

```bash
# 1. Testovi + pokrivenost (gcov/lcov)
( cd tests && ./run.sh )                       # 31 test, izveštaj u tests/results/

# 2. clang-tidy (statički lint; generiše compile_commands.json)
( cd clang-tidy && ./run.sh )                 # rezultati u clang-tidy/results/

# 3. Valgrind memcheck
( cd valgrind && ./run.sh )                   # rezultati u valgrind/results/

# 4. cppcheck (statička analiza)
( cd cppcheck && ./run.sh )                   # rezultati u cppcheck/results/

# 5. AddressSanitizer + UBSan (clang build)
( cd sanitizers && ./run.sh )                 # rezultati u sanitizers/results/

# 6. CBMC ograničena provera modela
( cd cbmc && ./run.sh )                       # rezultati u cbmc/results/
```

Detaljna uputstva i tumačenje rezultata po alatu nalaze se u `RunningTests.md` svakog
direktorijuma, a objedinjena analiza u [`ProjectAnalysisReport.md`](./ProjectAnalysisReport.md).

## Zaključci (sažetak)

Verifikacijom je pronađeno **više stvarnih defekata**, potvrđenih sa po nekoliko nezavisnih alata:

1. **`Hangman` — underflow za praznu reč.** Izraz `std::string(w.size()*2-1, ' ')` za `w=""`
   podbacuje `size_t` na `SIZE_MAX`. Nezavisno potvrđeno UBSan-om (`hangman.cpp:7`) i CBMC-om.
2. **`Words` — mogući duplikati reči.** `pickWords()` deduplira *indekse*, ali `words.txt` ima
   232 linije / 218 jedinstvenih (14 duplikata), pa vraćena lista može imati ponovljene reči.
   Razotkriveno kroz nestabilan (flaky) test pod drugim kompajlerom.
3. **`Points` — nevalidovana aritmetika.** Formula je korektna **samo** dok pozivaoci drže
   `timeLeft` u domenu `[0,60000]`; van toga skor izlazi iz opsega / `int` prekoračuje. CBMC
   *dokazuje* korektnost nad legalnim domenom i daje kontraprimer van njega (`timeLeft=-1.6e9`).
4. **`Player` — curenje i kršenje pravila pet.** Soket se alocira u konstruktoru i ponovo u
   `run()`; klasa poseduje sirov pokazivač bez kontrole kopiranja (clang-tidy:
   `owning-memory`, `special-member-functions`).

Pokrivenost koda testovima: direktno testirane klase 88–100% linija (`points` 100%, `hangman`
100%, `words` 92%, `leaderboard` 88%); ukupno 32.5% jer su `player`/`game` dominantno mrežni kod
van opsega jediničnog testiranja. Dinamički alati (ASan, Valgrind) ne prijavljuju curenja na
pokrivenim putanjama. Detaljna analiza i preporuke su u [`ProjectAnalysisReport.md`](./ProjectAnalysisReport.md).
