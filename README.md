# 2026_Analysis_SketchIt

Verifikacija softvera - analiza projekta otvorenog koda: SketchIt

## Autor

- **Ime i prezime:** Jovan Skoric
- **Broj indeksa:** 1030/2024
- Samostalni seminarski rad, kurs *Verifikacija softvera*, MATF.

## Analizirani projekat

**SketchIt** - kopija online multiplayer igre [skribbl.io](https://skribbl.io/), napisana u C++/Qt6.
Igra se sastoji iz **servera** (mrezna logika, bez GUI-ja) i **klijenta** (Qt Widgets GUI).
Svake runde jedan igrac crta zadatu rec, dok ostali pokusavaju da je pogode; bodovanje zavisi
od brzine pogadjanja i kvaliteta crteza.

- **Izvorni kod:** https://gitlab.com/matf-bg-ac-rs/course-rs/projects-2024-2025/SketchIt
- **Analizirana grana:** `main`
- **Hash commit-a:** `1578f98aa3fba5eba5d183c83e048ffdfbc43af0`
- Projekat je referenciran kao **git submodul** u direktorijumu [`SketchIt/`](./SketchIt).

### `custom.patch`

Kod na pinovanom commit-u **se ne prevodi** sa Qt 6.10 - datoteka `SketchIt/server/words.cpp`
(putanja unutar submodula) koristi `QTextStream` bez odgovarajuceg `#include <QTextStream>`
(greska: *variable 'QTextStream in' has incomplete type*). Minimalna izmena potrebna za prevodjenje
data je u [`custom.patch`](./custom.patch) i primenjuje se nad submodulom pre analize:

```bash
git submodule update --init
( cd SketchIt && git apply ../custom.patch )
```

## Fokus analize

Analiza je usmerena na **serversku logiku** (`SketchIt/SketchIt/server/`), jer je samostalna i ne
zavisi od GUI-ja: `points.cpp`, `hangman.cpp`, `words.cpp`, `leaderboard.cpp`, `player.cpp`,
`game.cpp`, `manager.cpp`.

## Korisceni alati i tehnike

Analiza koristi **7 alata/tehnika** (zahtevani minimum je 6). Zahtev da **najmanje dva** alata
nisu radjena na vezbama je ispunjen - dva alata su van vezbi: **cppcheck** i
**AddressSanitizer/UBSan**.

| # | Alat / tehnika | Kategorija | Direktorijum | Na vezbama? |
|---|----------------|------------|--------------|-------------|
| 1 | QtTest - jedinicni testovi | Testiranje | [`tests/`](./tests) | da |
| 2 | QtTest - integracioni testovi | Testiranje | [`tests/`](./tests) | da |
| 3 | clang-tidy | Stilske/lint provere | [`clang-tidy/`](./clang-tidy) | da |
| 4 | Valgrind (memcheck) | Dinamicka analiza memorije | [`valgrind/`](./valgrind) | da |
| 5 | cppcheck | Staticka analiza | [`cppcheck/`](./cppcheck) | **ne** |
| 6 | AddressSanitizer + UndefinedBehaviorSanitizer | Dinamicka instrumentacija | [`sanitizers/`](./sanitizers) | **ne** |
| 7 | CBMC | Ogranicena provera modela | [`cbmc/`](./cbmc) | da |

## Reprodukcija

Preduslovi (Ubuntu 24.04):

```bash
sudo apt-get install -y cppcheck clang clang-tidy valgrind lcov cbmc
# Qt 6.10 instaliran u /home/<user>/Qt/6.10.2/gcc_64
```

Verzije na kojima su rezultati dobijeni: clang/clang-tidy 18, cppcheck 2.13.0, Valgrind 3.22.0,
lcov 2.0, CBMC 5.95.1.

Inicijalizacija:

```bash
git clone --recurse-submodules https://github.com/Skora01/2026_Analysis_SketchIt
cd 2026_Analysis_SketchIt
( cd SketchIt && git apply ../custom.patch )
```

Ako je repozitorijum kloniran bez `--recurse-submodules`, submodul se dovlaci sa
`git submodule update --init` pre primene zakrpe.

Svaki alat ima `run.sh` skriptu u svom direktorijumu i `RunningTests.md` sa detaljima.
Skripte koje grade Qt kod (`tests`, `clang-tidy`, `valgrind`, `sanitizers`) postuju promenljivu
`QT_PREFIX` (podrazumevano `/home/<user>/Qt/6.10.2/gcc_64`); `cppcheck` i `cbmc` ne prevode Qt kod
pa im Qt nije potreban.

```bash
# 1. Testovi + pokrivenost (gcov/lcov)
( cd tests && ./run.sh )                      # 31 test, izvestaj u tests/results/

# 2. clang-tidy (staticki lint; generise compile_commands.json)
( cd clang-tidy && ./run.sh )                 # rezultati u clang-tidy/results/

# 3. Valgrind memcheck
( cd valgrind && ./run.sh )                   # rezultati u valgrind/results/

# 4. cppcheck (staticka analiza)
( cd cppcheck && ./run.sh )                   # rezultati u cppcheck/results/

# 5. AddressSanitizer + UBSan (clang build)
( cd sanitizers && ./run.sh )                 # rezultati u sanitizers/results/

# 6. CBMC ogranicena provera modela
( cd cbmc && ./run.sh )                       # rezultati u cbmc/results/
```

Brojka 31 je ono sto QTest ispisuje u `Totals`; u to su ukljuceni i njegovi sopstveni
`initTestCase`/`cleanupTestCase` slotovi, po dva na svaki izvrsni fajl, pa je autorskih testova 21.

Detaljna uputstva i tumacenje rezultata po alatu nalaze se u `RunningTests.md` svakog
direktorijuma, a objedinjena analiza u [`ProjectAnalysisReport.md`](./ProjectAnalysisReport.md).

## Zakljucci (sazetak)

Verifikacijom je pronadjeno **vise stvarnih defekata**, potvrdjenih sa po nekoliko nezavisnih alata:

1. **`Hangman` - underflow za praznu rec.** Izraz `std::string(w.size()*2-1, ' ')` za `w=""`
   podbacuje `size_t` na `SIZE_MAX`. Nezavisno potvrdjeno UBSan-om (`hangman.cpp:7`) i CBMC-om.
2. **`Words` - moguci duplikati reci.** `pickWords()` deduplira *indekse*, ali `words.txt` ima
   232 linije / 218 jedinstvenih (14 duplikata), pa vracena lista moze imati ponovljene reci.
   Razotkriveno kroz nestabilan test pod drugim kompajlerom; taj test je zbog nestabilnosti
   uklonjen iz svite, pa danasnja svita ovaj defekt vise ne proverava.
3. **`Points` - nevalidovana aritmetika.** Formula je korektna **samo** dok pozivaoci drze
   `timeLeft` u domenu `[0,60000]`; van toga skor izlazi iz opsega / `int` prekoracuje. CBMC
   *dokazuje* korektnost nad legalnim domenom i daje kontraprimer van njega (`timeLeft=-1.6e9`).
4. **`Player` - curenje i krsenje pravila pet.** Konstruktor alocira soket sa roditeljem
   (`new QTcpSocket(this)`), ali ga `run()` preko iste promenljive zameni soketom **bez roditelja**
   (`new QTcpSocket()`) koji vise nema vlasnika i stvarno curi. Klasa uz to poseduje sirov pokazivac
   bez kontrole kopiranja (clang-tidy: `owning-memory`, `special-member-functions`).

Pokrivenost koda testovima: direktno testirane klase 88-100% linija (`points` 100%, `hangman`
100%, `words` 92%, `leaderboard` 88%); ukupno 32.5% jer su `player`/`game` dominantno mrezni kod
van opsega jedinicnog testiranja. Dinamicki alati (ASan, Valgrind) ne prijavljuju curenja na
pokrivenim putanjama. Detaljna analiza i preporuke su u [`ProjectAnalysisReport.md`](./ProjectAnalysisReport.md).
