# CBMC — ograničena provera modela (bounded model checking)

## Šta i zašto

CBMC iscrpno proverava svojstvo nad **svim** ulazima (u okviru zadatih granica) i
vraća ili dokaz (`VERIFICATION SUCCESSFUL`) ili konkretan kontraprimer-trag.
Koristi SAT/SMT rešavač (MiniSAT) da pretvori program u skup logičkih formula i
proverava da li postoji ulaz koji krši zadato svojstvo.

Pošto se kritična logika SketchIt-a svodi na celobrojnu aritmetiku, prenesena je u
male, Qt-nezavisne harnese koji verno preslikavaju izraze iz izvornog koda
(`hangman.cpp`, `points.cpp`), a `nondet_*` ulazi puštaju CBMC da ispita ceo prostor.

## Reprodukcija

```bash
cd cbmc
./run.sh
```

Skripta proverava tri harnesa i prikazuje kratak summary u terminalu. Puni
kontraprimer-tragovi (sa konkretnim vrednostima promenljivih) čuvaju se u
`results/*.log`.

## Rezultati

### 1. `hangman_masklen.c` — `VERIFICATION FAILED` (pronađen bag)

Izraz `len*2 - 1` (iz `hangman.cpp:7`) za `len == 0` izaziva underflow `size_t`-a.
Terminalni summary:

```
[main.overflow.1] line 18 arithmetic overflow on unsigned * in len * 2: SUCCESS
[main.overflow.2] line 18 arithmetic overflow on unsigned - in len*2 - 1: FAILURE
[main.assertion.1] Hangman masked length must not underflow: FAILURE
```

Puni trag u `results/hangman_masklen.log` pokazuje konkretan kontraprimer:

```
State 14: len=0ul
State 19: masked=18446744073709551615ul   ← SIZE_MAX (underflow)
Violated property: Hangman masked length must not underflow
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

Bez ugovora o ulazu, `400 * timeLeft` prekoračuje `int`. Terminalni summary:

```
[main.overflow.1] line 15 arithmetic overflow on signed * in 400 * timeLeft: FAILURE
[main.assertion.1] guesser stays in range without an input contract: FAILURE
```

Puni trag u `results/points_overflow.log` pokazuje konkretan kontraprimer:

```
State 14: timeLeft=-1667805263
Violated property: arithmetic overflow on signed * in 400 * timeLeft
```

## Zaključak

`Points` je korektan **samo zato što ga pozivaoci slučajno drže u domenu** — nema
validacije unutar same funkcije. `Hangman` nema nikakvu zaštitu od prazne reči.
Oba nalaza su nezavisno potvrđena i sanitajzerima (UBSan).
