# CBMC — ograničena provera modela (bounded model checking)

## Šta i zašto

CBMC iscrpno proverava svojstvo nad **svim** ulazima (u okviru zadatih granica) i
vraća ili dokaz (`VERIFICATION SUCCESSFUL`) ili konkretan kontraprimer-trag.
Ovo nije bilo rađeno na vežbama i komplementarno je sa KLEE-om: drugačiji motor
(SAT/SMT ograničena provera nasuprot simboličkom izvršavanju).

Pošto se kritična logika SketchIt-a svodi na celobrojnu aritmetiku, prenesena je u
male, Qt-nezavisne harnese koji verno preslikavaju izraze iz izvornog koda
(`hangman.cpp`, `points.cpp`), a `nondet_*` ulazi puštaju CBMC da ispita ceo prostor.

## Reprodukcija

```bash
cd cbmc
./run.sh
```

Skripta proverava tri harnesa; logovi (sa tragovima) idu u `results/*.log`.

## Rezultati

### 1. `hangman_masklen.c` — `VERIFICATION FAILED` (pronađen bag)
Izraz `len*2 - 1` (iz `hangman.cpp:7`) za `len == 0` izaziva underflow `size_t`-a.
CBMC daje konkretan kontraprimer **`len = 0`**:

```
[main.overflow.2] arithmetic overflow on unsigned - in len*2 - 1: FAILURE
[main.assertion.1] Hangman masked length must not underflow: FAILURE
```

### 2. `points_domain.c` — `VERIFICATION SUCCESSFUL` (dokaz korektnosti)
Za ceo legalni domen `timeLeft ∈ [0, 60000]` CBMC **dokazuje** da:
- nema prekoračenja u `400 * timeLeft` ni u sabiranju,
- skor pogađača ostaje u `[100, 500]`, a crtača u `[33, 166]`.

```
[main.overflow.1] arithmetic overflow on signed * in 400 * timeLeft: SUCCESS
[main.assertion.1] guesser score within [100,500]: SUCCESS
[main.assertion.2] drawer score within [33,166]: SUCCESS
VERIFICATION SUCCESSFUL
```

Ovo je jača garancija od dva jedinična testa (koji proveravaju samo krajeve domena):
formula je dokazano korektna za svaku vrednost u opsegu.

### 3. `points_overflow.c` — `VERIFICATION FAILED` (latentni rizik)
Bez ugovora o ulazu, `400 * timeLeft` prekoračuje `int`. CBMC daje kontraprimer
**`timeLeft = -1667805263`**:

```
[main.overflow.1] arithmetic overflow on signed * in 400 * timeLeft: FAILURE
[main.assertion.1] guesser stays in range without an input contract: FAILURE
```

## Zaključak

`Points` je korektan **samo zato što ga pozivaoci slučajno drže u domenu** — nema
validacije unutar same funkcije. `Hangman` nema nikakvu zaštitu od prazne reči.
Oba nalaza su nezavisno potvrđena i sanitajzerima (UBSan) i KLEE-om.
