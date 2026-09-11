# Valgrind (memcheck)

## Sta i zasto

Valgrind memcheck instrumentise vec iskompajliran binarni fajl (bez ponovne
kompilacije) i prati svaku alokaciju/citanje memorije. Koristi se kao **nezavisna
potvrda** rezultata sanitajzera: ASan i memcheck rade na potpuno razlicite nacine
(kompajlerska instrumentacija vs. dinamicka binarna instrumentacija), pa
poklapanje rezultata povecava poverenje.

## Reprodukcija

```bash
cd valgrind
QT_PREFIX=/putanja/do/Qt/6.x/gcc_64 ./run.sh
```

Skripta pravi cist Debug build (bez pokrivenosti i bez sanitajzera, da bi linijske
informacije bile tacne), pa pokrece svih 5 testova pod `memcheck`-om sa
`--leak-check=full`. Ponovo koristi `tests/CMakeLists.txt`, samo sa
`-DENABLE_COVERAGE=OFF`, jer Valgrindu treba neinstrumentisan binar. Logovi se pisu
u `results/*.memcheck.log`.

`qt.supp` sadrzi **jedno** pravilo i ono je neophodno: bez njega memcheck prijavljuje
`Invalid read of size 16` iz Qt-ovog ibus plagina za metod unosa (Qt cita 16 bajtova
odjednom pri parsiranju imena meta-tipa i prelazi granicu bloka od 42 bajta za jedan
bajt). Nijedan frejm u tom steku nije kod projekta. Posto se plagin ucitava preko
DBus-a nedeterministicki, bez tog pravila `ERROR SUMMARY` varira izmedju pokretanja;
sa njim je stabilno 0 kroz sve prolaze.

## Rezultat

| test | definitely lost | indirectly lost | ERROR SUMMARY |
|---|---|---|---|
| tst_points | 0 | 0 | 0 errors |
| tst_hangman | 0 | 0 | 0 errors |
| tst_leaderboard | 0 | 0 | 0 errors |
| tst_words | 0 | 0 | 0 errors |
| tst_manager | 0 | 0 | 0 errors |

Nema curenja ni nevalidnih pristupa na putanjama koje testovi pokrivaju, sto se
poklapa sa ASan rezultatom.

**Vazna napomena o opsegu.** Klasa `Player` alocira soket na dva mesta:

```cpp
Player::Player(qintptr id, QObject* parent) : QThread(parent), ID(id) {
    socket = new QTcpSocket(this);   // roditelj je this
}
void Player::run() {
    socket = new QTcpSocket();       // bez roditelja
```

Prvi soket ima `this` kao roditelja, pa ga Qt oslobodi kroz parent-child mehanizam
kad `Player` bude unisten; pokazivac `socket` na njega se izgubi, ali memorija ne
curi. Curi **drugi**, onaj alociran u `run()` bez roditelja, jer njega ne poseduje
nijedan objekat.

To curenje **nije** dostupno bez zive mreze: `run()` se izvrsava samo posle
`QThread::start()` i zahteva validan soket deskriptor, pa ga ni Valgrind ni ASan ne
mogu pogoditi iz jedinicnog harnesa. Uhvaceno je statickom analizom, clang-tidy
prijavljuje oba dodeljivanja preko `cppcoreguidelines-owning-memory`:

```
player.cpp:7:5:  assigning newly created 'gsl::owner<>' to non-owner 'QTcpSocket *'
player.cpp:12:5: assigning newly created 'gsl::owner<>' to non-owner 'QTcpSocket *'
```

a `cppcoreguidelines-special-member-functions` dodatno prijavljuje `player.h:12`
(klasa ima destruktor a nema kontrolu kopiranja, krsenje pravila nule/pet). Ovo je
dobar primer komplementarnosti statickih i dinamickih alata: dinamicki alat ne moze
da prijavi gresku na putanji koju ne izvrsi.
