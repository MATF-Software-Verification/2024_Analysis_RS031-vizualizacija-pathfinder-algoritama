# Sanitajzeri: AddressSanitizer + UndefinedBehaviorSanitizer

## Sta i zasto

Dinamicka analiza tokom izvrsavanja test-svite, kao i Valgrind, ali sa bitno
drugacijom mehanikom:

| | Valgrind | sanitajzeri |
|---|---|---|
| kako radi | prevodi masinski kod u VEX IR i simulira ga | kompajler ubacuje provere u sam kod |
| rekompilacija | nije potrebna | obavezna (`-fsanitize=...`) |
| usporenje | 10-50x | 2-3x |
| vidi | `malloc`/`free` i pristupe adresama | semantiku C++-a (tipove, granice steka i globala) |

Valgrind vidi samo ono sto se vidi iz masinskih instrukcija. Sanitajzeri rade 
pre prevodjenja pa znaju da je jedna promenljiva `int` a druga `size_t`, znaju
gde je granica niza na steku, i znaju koje vrednosti `enum` sme da uzme. 
Tri klase gresaka koje Valgrind ne moze da nadje a sanitajzeri mogu:

- prekoracenje niza na **steku** ili u **globalnoj** promenljivoj (Valgrind prati samo hip),
- potpisano prekoracenje, nevalidan `shift`, nevalidan `enum`, deljenje nulom
  (to nisu greske nad memorijom nego nad jezikom),
- `unsigned` prekoracenje, sto je tacno bag u ovom projektu.

Dva alata u jednom buildu:

- **ASan** hvata use-after-free, prekoracenja na hipu/steku/globalima, dvostruko oslobadjanje.
     U sebi nosi i **LeakSanitizer** za curenja.
- **UBSan** ubacuje proveru ispred sumnjive operacije i zove runtime kad pukne.

## Reprodukcija

```bash
cd sanitizers
QT_PREFIX=/putanja/do/Qt/6.x/gcc_64 ./run.sh
```

Skripta konfigurise `tests` projekat sa sanitajzerskim zastavicama i
pokrivenoscu iskljucenom, izgradi ga i pokrene svih 5 test-izvrsnih fajlova.
Traje oko 10 sekundi.

Izlaz ide u `results/`:

- `run.log` - stdout/stderr svih testova,
- `report.<pid>` - izvestaji sanitajzera. 

Trenutno stanje: **31(21 + 10 od QTest-a) test prolazi, 0 padova, 1 UBSan nalaz, 0 ASan nalaza.**

## Cemu sluzi ubsan.supp

`unsigned` prekoracenje **nije** nedefinisano ponasanje. Standard izricito kaze
da se `unsigned` aritmetika racuna po modulu 2^n. UBSan tu proveru zato ne
ukljucuje podrazumevano, a `run.sh` je dodaje rucno jer se bag u `Hangman`
ispoljava bas u tom obliku.

Cena je sum: svaka biblioteka koja namerno koristi wrap-around pocne da se prijavljuje.

`ubsan.supp` postoji iskljucivo zato sto je ukljucen `unsigned-integer-overflow`.

## Rezultat: pronadjen pravi defekt

UBSan precizno locira bag u `Hangman` konstruktoru:

```
SketchIt/server/hangman.cpp:7:50: runtime error: unsigned integer overflow:
    0 - 1 cannot be represented in type 'size_type' (aka 'unsigned long')
    #0 Hangman::Hangman(...) hangman.cpp:7:50
    #1 TestHangman::emptyWordIsRejectedOrCrashes() tst_hangman.cpp:50:17
```

Izraz `std::string(w.size() * 2 - 1, ' ')` za praznu rec daje `0 * 2 - 1`, sto
se kao `size_t` ne potpise nego obrne na `SIZE_MAX`. Posledica je pokusaj
alokacije ogromnog stringa, dakle `std::length_error` ili `std::bad_alloc`.
Konstruktor nema nikakvu proveru. Prazna rec mora biti odbijena pre nego sto
dospe do ove klase.

Ovo je dinamicki dokaz sa tacnom linijom i stack trace-om, 
a ne upozorenje statickog alata koje tek treba potvrditi.

## Rezultat: ASan bez nalaza

ASan nije prijavio ni curenja ni use-after-free. 

Curenje koje stvarno postoji, u `Player::run()` (soket se alocira dvaput, jednom
u konstruktoru sa roditeljem, pa ponovo bez roditelja), nije dostupno bez zive
mrezne veze pa ga ovaj sloj testova ne dodiruje. Vidi staticke alate i izvestaj.
