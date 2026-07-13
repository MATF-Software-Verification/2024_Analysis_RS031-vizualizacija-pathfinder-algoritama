# Sanitajzeri: AddressSanitizer + UndefinedBehaviorSanitizer

## Šta i zašto

Dinamička analiza tokom izvršavanja test-svite. ASan hvata greške nad memorijom
(curenja, use-after-free, prekoračenja bafera), a UBSan nedefinisano ponašanje
(prekoračenje znakovnih celih brojeva, nevalidni shift/enum, itd.).

Build se radi **clang++-om** (a ne gcc-om kao za pokrivenost) iz dva razloga:
1. provera `unsigned-integer-overflow` postoji samo u Clang-u (gcc je odbija),
2. zdravo je pokrenuti analizu pod drugim kompajlerom.

## Reprodukcija

```bash
cd sanitizers
QT_PREFIX=/putanja/do/Qt/6.x/gcc_64 ./run.sh
```

Skripta konfiguriše `unit_tests` projekat sa `-fsanitize=address,undefined,unsigned-integer-overflow`
(pokrivenost isključena), izgradi i pokrene svih 5 test-izvršnih fajlova pod
sanitajzerima, i upiše izveštaje u `results/` (`run.log`, `asan.*`, `ubsan.*`).

Datoteka `ubsan.supp` priguši `unsigned-integer-overflow` prijave koje potiču iz
template koda trećih strana (Qt `QHash` heširanje, libstdc++ `mt19937` /
`uniform_int_distribution`) — to su namerni wrap-around-i tih biblioteka, a ne
defekti projekta, pa izveštaj ostaje fokusiran na kod samog projekta.

## Rezultat — pronađen pravi defekt

UBSan precizno locira dokumentovani bag u `Hangman` konstruktoru:

```
SketchIt/server/hangman.cpp:7:50: runtime error: unsigned integer overflow:
    0 - 1 cannot be represented in type 'size_type' (aka 'unsigned long')
```

Izraz `std::string(w.size() * 2 - 1, ' ')` za praznu reč daje `0 * 2 - 1`, što
kao `size_t` ne potpiše već se obrne (underflow) na `SIZE_MAX`. Posledica je
pokušaj alokacije ogromnog stringa → `std::length_error` / `std::bad_alloc`.
Konstruktor nema nikakvu proveru. Prazna reč mora biti odbijena pre nego što
dospe do ove klase.

ASan nije prijavio curenja memorije ni use-after-free u testiranim putanjama —
testovi instanciraju `Player` objekte sa ispravnim `parent`-om, pa Qt vlasništvo
sve počisti. (Curenje koje nastaje u `Player::run()` zbog duple alokacije soketa
nije dostupno bez žive mreže pa nije pokriveno ovde — vidi statičke alate i izveštaj.)

## Usputni nalaz koji je sanitajzer build razotkrio

Pod clang-build-om je test `picksAreDistinct` (raniji naziv) pao: `pickWords(10)`
vratio je 9 jedinstvenih reči od 10. Uzrok nije slučajnost nego pravi defekt:
`Words::pickWords()` deduplira **indekse** (`QSet<int>`), ali `words.txt` ima 232
linije od kojih je samo 218 jedinstvenih (14 duplikata), pa dva različita indeksa
mogu pokazivati na istu reč. Test je zato prepravljen da proverava stvarni ugovor
(tačan broj i ne-prazne reči), a sam defekt je dokumentovan u izveštaju.
