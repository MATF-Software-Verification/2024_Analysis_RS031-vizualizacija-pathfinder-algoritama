# Jedinicni i integracioni testovi (QtTest) + pokrivenost koda (gcov/lcov)

## Sta se testira

Testira se serverska logika igre **SketchIt** (klase iz `SketchIt/SketchIt/server/`).
Mrezni ulaz (`server.cpp`, `main.cpp`) je izostavljen jer zavisi od `QtZeroConf`
biblioteke i zivih soketa, sto nije predmet jedinicnog testiranja.

Testovi su fizicki razdvojeni u dva poddirektorijuma (racunaju se kao dva alata):
`tests/unit/` i `tests/integration/`. Posto mock nije koriscen, jedinicni su samo
jedinice **bez ijedne spoljne zavisnosti**; ostali prelaze granicu pa su integracioni.

### Jedinicni testovi, `tests/unit/`
- `tst_points.cpp`: bodovanje runde (`Points`): formula
  `100 + (400*timeLeft/1000)/60` za pogadjaca, `/3` za osobu koja crta; reset pri `initialize()`;
  brisanje igraca; brojac otkrivenih slova. Dokumentuje i bag: bez `initialize()`
  osoba koja crta je `nullptr` pa se poeni upisuju pod `nullptr` kljucem.
- `tst_hangman.cpp`: maskiranje reci (`Hangman`): format `"_ _ _"`, postepeno
  otkrivanje, kompletiranje. Dokumentuje bag: prazna rec izaziva `size_t` underflow
  u `std::string(w.size()*2-1, ' ')` -> `std::length_error`/`std::bad_alloc`.

### Integracioni testovi, `tests/integration/` (prelaze granicu: resurs/fajl-sistem/druga klasa)
- `tst_leaderboard.cpp`: `Leaderboard`: ucitavanje seed-a iz Qt resursa, perzistencija
  u JSON, sortiranje opadajuce, cap na top 10, akumulacija postojeceg skora.
- `tst_words.cpp`: `Words`: ucitavanje liste reci iz resursa, nasumican izbor
  zadatog broja distinktnih reci. Dokumentuje bag: `pickWords(count)` ulazi u
  beskonacnu petlju ako `count` > broja reci (232).
- `tst_manager.cpp`: `Manager`: roster igraca (dodavanje, pretraga po nadimku,
  prazna pretraga vraca `nullptr`, stanje igre).

Ukupno: **21 test, svi prolaze.**

## Reprodukcija

```bash
cd tests
QT_PREFIX=/putanja/do/Qt/6.x/gcc_64 ./run.sh
```

`run.sh` radi sledece:
1. konfigurise CMake sa instrumentacijom za pokrivenost (`--coverage -O0 -g`),
2. izgradi staticku biblioteku `serverlogic` i 5 QtTest izvrsnih fajlova,
3. pokrene sve testove headless (`QT_QPA_PLATFORM=offscreen`) preko CTest-a,
3. prikupi pokrivenost (`lcov`), filtrira na analizirane izvore,
4. ispise per-fajl rezime iz **gcov-a** i generise HTML izvestaj.

Rezultati se pisu u `results/`:
- `coverage.summary.txt`: per-fajl rezime (gcov, ground-truth),
- `coverage.server.info`: lcov tracefile (samo analizirani izvori),
- `html/index.html`: pun HTML izvestaj (genhtml).

## Rezultati pokrivenosti

| fajl | linija | izvrseno |
|---|---:|---:|
| points.cpp | 26 | 100.00% |
| hangman.cpp | 20 | 100.00% |
| words.cpp | 25 | 92.00% |
| leaderboard.cpp | 75 | 88.00% |
| manager.cpp | 105 | 33.33% |
| player.cpp | 151 | 17.22% |
| game.cpp | 186 | 0.00% |

Ukupno (genhtml): **32.5% linija (185/569), 45.7% funkcija (32/70).**

**Tumacenje.** Cetiri klase pod direktnim testom (`Points`, `Hangman`, `Words`,
`Leaderboard`) imaju 88-100% pokrivenosti. `Manager` ima 33% jer veci deo klase
predstavlja tok igre koji zahteva zive sokete. `Player` (17%) i `Game` (0%) ulaze
u build samo kao link-zavisnosti (`Manager` referencira `Game`, `Game` referencira
`Player`) i dominira ih soket/threading kod koji se ne moze izvrsiti bez mreze.

## Napomena o alatima

`lcov --list` u verziji 2.0 prikazuje **pogresnu** per-fajl stopu za ovaj projekat
(ne slaze se ni sa `gcov`-om ni sa `genhtml` HTML-om koje sam generise iz istih
podataka). Zato skripta vodi rezime iz `gcov`-a, koji je ground-truth, a `lcov` se
koristi samo za prikupljanje tracefile-a i generisanje HTML-a.
