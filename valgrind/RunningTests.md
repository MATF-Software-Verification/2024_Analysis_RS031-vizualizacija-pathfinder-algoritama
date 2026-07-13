# Valgrind (memcheck)

## Šta i zašto

Valgrind memcheck instrumentiše već iskompajliran binarni fajl (bez ponovne
kompilacije) i prati svaku alokaciju/čitanje memorije. Koristi se kao **nezavisna
potvrda** rezultata sanitajzera: ASan i memcheck rade na potpuno različite načine
(kompajlerska instrumentacija vs. dinamička binarna instrumentacija), pa
poklapanje rezultata povećava poverenje.

## Reprodukcija

```bash
cd valgrind
QT_PREFIX=/putanja/do/Qt/6.x/gcc_64 ./run.sh
```

Skripta pravi čist Debug build (bez pokrivenosti i bez sanitajzera, da bi linijske
informacije bile tačne), pa pokreće svih 5 testova pod `memcheck`-om sa
`--leak-check=full` i prijavljuje samo **definite/indirect** curenja (akcionabilna);
`qt.supp` priguši šum okvira (Qt singltoni, dlopen plagini, fontconfig).
Logovi se pišu u `results/*.memcheck.log`.

## Rezultat

| test | definitely lost | indirectly lost | ERROR SUMMARY |
|---|---|---|---|
| tst_points | 0 | 0 | 0 errors |
| tst_hangman | 0 | 0 | 0 errors |
| tst_leaderboard | 0 | 0 | 0 errors |
| tst_words | 0 | 0 | 0 errors |
| tst_manager | 0 | 0 | 0 errors |

Nema curenja ni nevalidnih pristupa na putanjama koje testovi pokrivaju —
poklapa se sa ASan rezultatom.

**Važna napomena o opsegu.** Poznato curenje u `Player::run()` (soket se alocira u
konstruktoru *i* ponovo u `run()`, pa se prvi gubi) **nije** dostupno bez žive
mreže/soketa, pa ga ni Valgrind ni ASan ne mogu pogoditi iz jediničnog harnesa.
Taj defekt je uhvaćen statičkom analizom — clang-tidy ga prijavljuje preko provera
`cppcoreguidelines-owning-memory` i `cppcoreguidelines-special-member-functions`
(klasa `Player` poseduje sirov pokazivač na soket a nema kontrolu kopiranja —
kršenje pravila nule/pet). Ovo je dobar primer komplementarnosti statičkih i
dinamičkih alata.
