# Jedinični i integracioni testovi (QtTest) + pokrivenost koda (gcov/lcov)

## Šta se testira

Testira se serverska logika igre **SketchIt** (klase iz `SketchIt/SketchIt/server/`).
Mrežni ulaz (`server.cpp`, `main.cpp`) je izostavljen jer zavisi od `QtZeroConf`
biblioteke i živih soketa, što nije predmet jediničnog testiranja.

Testovi su fizički razdvojeni u dva poddirektorijuma (računaju se kao dva alata):
`tests/unit/` i `tests/integration/`. Podela prati definiciju iz skripte: jedinični test
izoluje jedinicu mockovanjem svih spoljnih zavisnosti (fajl-sistem, mreža, druge klase). Pošto
mock nije korišćen, jedinični su samo jedinice **bez ijedne spoljne zavisnosti**; ostali realno
prelaze granicu pa su integracioni.

### Jedinični testovi — `tests/unit/` (bez spoljnih zavisnosti)
- `tst_points.cpp` — bodovanje runde (`Points`): formula
  `100 + (400*timeLeft/1000)/60` za pogađača, `/3` za crtača; reset pri `initialize()`;
  brisanje igrača; brojač otkrivenih slova. Dokumentuje i bag: bez `initialize()`
  crtač je `nullptr` pa se poeni upisuju pod `nullptr` ključem.
- `tst_hangman.cpp` — maskiranje reči (`Hangman`): format `"_ _ _"`, postepeno
  otkrivanje, kompletiranje. Dokumentuje bag: prazna reč izaziva `size_t` underflow
  u `std::string(w.size()*2-1, ' ')` → `std::length_error`/`std::bad_alloc`.

### Integracioni testovi — `tests/integration/` (prelaze granicu: resurs/fajl-sistem/druga klasa)
- `tst_leaderboard.cpp` — `Leaderboard`: učitavanje seed-a iz Qt resursa, perzistencija
  u JSON, sortiranje opadajuće, cap na top 10, akumulacija postojećeg skora.
- `tst_words.cpp` — `Words`: učitavanje liste reči iz resursa, nasumičan izbor
  zadatog broja distinktnih reči. Dokumentuje bag: `pickWords(count)` ulazi u
  beskonačnu petlju ako `count` > broja reči (232).
- `tst_manager.cpp` — `Manager`: roster igrača (dodavanje, pretraga po nadimku,
  prazna pretraga vraća `nullptr`, stanje igre).

Ukupno: **31 test, svi prolaze.**

## Reprodukcija

```bash
cd unit_tests
QT_PREFIX=/putanja/do/Qt/6.x/gcc_64 ./run.sh
```

`run.sh` radi sledeće:
1. primeni `custom.patch` na submodul (obavezna popravka build-a — vidi koren README),
2. konfiguriše CMake sa instrumentacijom za pokrivenost (`--coverage -O0 -g`),
3. izgradi statičku biblioteku `serverlogic` i 5 QtTest izvršnih fajlova,
4. pokrene sve testove headless (`QT_QPA_PLATFORM=offscreen`) preko CTest-a,
5. prikupi pokrivenost (`lcov`), filtrira na analizirane izvore,
6. ispiše per-fajl rezime iz **gcov-a** i generiše HTML izveštaj.

Rezultati se pišu u `results/`:
- `coverage.summary.txt` — per-fajl rezime (gcov, ground-truth),
- `coverage.server.info` — lcov tracefile (samo analizirani izvori),
- `html/index.html` — pun HTML izveštaj (genhtml).

## Rezultati pokrivenosti

| fajl | linija | izvršeno |
|---|---:|---:|
| points.cpp | 26 | 100.00% |
| hangman.cpp | 20 | 100.00% |
| words.cpp | 25 | 92.00% |
| leaderboard.cpp | 75 | 88.00% |
| manager.cpp | 105 | 33.33% |
| player.cpp | 151 | 17.22% |
| game.cpp | 186 | 0.00% |

Ukupno (genhtml): **32.5% linija (185/569), 45.7% funkcija (32/70).**

**Tumačenje.** Četiri klase pod direktnim testom (`Points`, `Hangman`, `Words`,
`Leaderboard`) imaju 88–100% pokrivenosti. `Manager` ima 33% jer veći deo klase
predstavlja tok igre koji zahteva žive soketa. `Player` (17%) i `Game` (0%) ulaze
u build samo kao link-zavisnosti (`Manager` referencira `Game`, `Game` referencira
`Player`) i dominira ih soket/threading kod koji se ne može izvršiti bez mreže —
van su opsega jediničnog testiranja i tako su i tretirani.

## Napomena o alatima

`lcov --list` u verziji 2.0 prikazuje **pogrešnu** per-fajl stopu za ovaj projekat
(ne slaže se ni sa `gcov`-om ni sa `genhtml` HTML-om koje sam generiše iz istih
podataka). Zato skripta vodi rezime iz `gcov`-a, koji je ground-truth, a `lcov` se
koristi samo za prikupljanje tracefile-a i generisanje HTML-a. Takođe je potreban
`--ignore-errors mismatch,gcov,...` jer `lcov 2.0` inače prekida rad na bezopasnim
upozorenjima iz inline-ovanog `libstdc++` template koda.
