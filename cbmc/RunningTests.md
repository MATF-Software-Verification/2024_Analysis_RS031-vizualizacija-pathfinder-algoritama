# CBMC - ogranicena provera modela (bounded model checking)

## Sta i zasto

CBMC je treca, potpuno drugacija kategorija alata od ostalih u projektu:

| kategorija | alati | sta tvrdi |
|---|---|---|
| staticka analiza | cppcheck, clang-tidy | "ovaj obrazac u kodu lici na gresku" - heuristika |
| dinamicka analiza | valgrind, sanitajzeri | "za ulaze koje sam stvarno pokrenuo nije bilo greske" |
| formalna verifikacija | **CBMC** | "za **sve** ulaze u zadatim granicama svojstvo vazi" - ili evo ulaza koji ga obara |

### Kako radi

1. Petlje se odmotaju do zadate granice (otud "bounded"), a program se prevede u
   oblik gde se svaka promenljiva dodeljuje tacno jednom (SSA).
2. Tako razmotan program postaje jedna propoziciona formula: dodele postaju
   ekvivalencije, grananja implikacije.
3. Toj formuli se pridruzi **negacija** svojstva i sve se preda SAT/SMT
   resavacu:
   - **UNSAT** - ne postoji dodela koja krsi svojstvo, dakle dokaz:
     `VERIFICATION SUCCESSFUL`,
   - **SAT** - resavac je nasao dodelu, i ta dodela **jeste** kontraprimer sa
     konkretnim brojevima: `VERIFICATION FAILED`.

Zato izlaz nikad nije "mozda". Ili je dokaz, ili je konkretan ulaz koji obara
tvrdnju.

### Ogranicenje

CBMC je model-checker za **C**, a SketchIt je C++ sa Qt-om. Zato se ne proverava
izvorni kod nego tri mala harnesa u koje je aritmetika prepisana rucno. Dokaz
vazi za **formulu**, a koliko vredi za program zavisi od vernosti prepisivanja.

Utesna okolnost: oba nalaza imaju nezavisnu potvrdu. UBSan je isti
`hangman.cpp:7` underflow nasao dinamicki, nad pravim C++ kodom.

## Reprodukcija

```bash
cd cbmc
./run.sh
```

Skripta proverava tri harnesa, u terminal ispisuje samo
svojstva i presudu, a pune logove sa kontraprimer-tragovima pise u
`results/*.log`.


## Rezultati

### 1. `hangman_masklen.c` - `VERIFICATION FAILED` (pronadjen bag)

Harnes preslikava izraz `len*2 - 1` iz `hangman.cpp:7`, uz ugovor `len <= 256`.

```
[main.overflow.1] line 10 arithmetic overflow on unsigned * in len * (unsigned long int)2: SUCCESS
[main.overflow.2] line 10 arithmetic overflow on unsigned - in len * (unsigned long int)2 - (unsigned long int)1: FAILURE
[main.assertion.1] line 12 Hangman masked length must not underflow: FAILURE
VERIFICATION FAILED
```

Citanje: mnozenje `len * 2` je dokazano bezbedno, ali **oduzimanje** prekoracuje.
Za `len == 0` izraz `0 - 1` se kao `size_t` obrne na `SIZE_MAX`.

Zastavica `--unsigned-overflow-check` je ono sto razdvaja `overflow.2` od
`assertion.1`. Bez nje bi CBMC rekao samo da tvrdnja ne vazi; sa njom kaze i
**zasto** ne vazi.

Kontraprimer je u `results/hangman_masklen.log`, dobijen zastavicom `--trace`:

```
linija 49:  len=0ul
linija 84:  masked=18446744073709551615ul   (SIZE_MAX)
```

To je ista vrednost koju `std::string(masked, ' ')` pokusava da alocira, odakle
`std::length_error` / `std::bad_alloc`.

### 2. `points_domain.c` - `VERIFICATION SUCCESSFUL` (dokaz korektnosti)

Isti izraz kao u `points.cpp`, uz ugovor `timeLeft` u `[0, 60000]`.

```
[main.overflow.1] line 8 arithmetic overflow on signed * in 400 * timeLeft: SUCCESS
[main.overflow.2] line 8 arithmetic overflow on signed + in 100 + ((400 * timeLeft) / 1000) / 60: SUCCESS
[main.assertion.1] line 11 guesser score within [100,500]: SUCCESS
[main.assertion.2] line 12 drawer score within [33,166]: SUCCESS
VERIFICATION SUCCESSFUL
```

Cetiri dokazana svojstva, a ne dva. Zastavica `--signed-overflow-check` ovde
nije kozmetika: u C-u je potpisano prekoracenje **nedefinisano ponasanje**, a
dokaz o vrednosti izraza koji moze da prekoraci je bezvredan. Tek uz
`overflow.1` i `overflow.2` tvrdnja postaje potpuna - izraz je **i definisan i u
opsegu** za svaku vrednost iz domena.

Ovo je jaca garancija od jedinicnih testova u `tests/`, koji proveravaju samo
nekoliko tacaka domena. Ovde je pokriveno svih 60001 mogucih ulaza odjednom.

Ovaj harnes se pokrece **bez** `--trace`: kad je verifikacija uspesna nema
kontraprimera koji bi se ispisao, pa je i log najkraci (36 linija).

### 3. `points_overflow.c` - `VERIFICATION FAILED` (latentni rizik)

Identican izraz, ali **bez** `__CPROVER_assume`.

```
[main.overflow.1] line 7 arithmetic overflow on signed * in 400 * timeLeft: FAILURE
[main.overflow.2] line 7 arithmetic overflow on signed + in 100 + ((400 * timeLeft) / 1000) / 60: SUCCESS
[main.assertion.1] line 9 guesser stays in range without an input contract: FAILURE
VERIFICATION FAILED
```

Kontraprimer u `results/points_overflow.log`:

```
linija 49:  timeLeft=-1667805263
```

`400 * (-1667805263)` daleko prelazi opseg `int`-a. Vrednost je deterministicna -
resavac pretragu vodi istim redosledom, pa se isti broj dobija pri svakom
pokretanju.

## Zakljucak

Poredjenje harnesa 2 i 3 je ceo nalaz: formula u `Points` je **dokazano
korektna**, ali samo pod pretpostavkom koju funkcija nigde ne proverava.
`Points` je bezbedan zato sto ga pozivaoci drze u domenu, ne zato sto se sam
brani. `Hangman` nema nikakvu zastitu od prazne reci.

Oba defekta su nezavisno potvrdjena sanitajzerima (UBSan), sto zatvara rupu koju
nosi prepisivanje C++ koda u C harnese.
