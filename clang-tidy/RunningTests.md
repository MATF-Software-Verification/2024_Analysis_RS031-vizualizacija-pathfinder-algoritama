# clang-tidy (staticki lint)

## Sta i zasto

clang-tidy je linter izgradjen nad Clangovim pravim frontend-om. Za razliku od
cppcheck-a, koji ima sopstveni parser, clang-tidy dobija isti AST koji bi dobio i
kompajler, pa zna prava preopterecenja, instancirane sablone, hijerarhiju
nasledjivanja i implicitne konverzije. Cena je sto mu trebaju tacni flagovi
prevodjenja, odakle i potreba za `compile_commands.json`.

Komplementaran je sa cppcheck-om jer su mehanizmi razliciti: cppcheck ima
value-flow analizu unutar funkcije, dok clang-tidy ima semanticke provere nad
punim AST-om. Konkretno, cppcheck je nasao latentni dangling-reference na
`player.cpp:101`, a clang-tidy 7 krsenja vlasnistva nad memorijom
(`cppcoreguidelines-owning-memory`) i 9 krsenja pravila nule/pet, koje cppcheck
nije prijavio.

## Reprodukcija

```bash
cd clang-tidy
QT_PREFIX=/putanja/do/Qt/6.x/gcc_64 ./run.sh
```

Skripta ponovo koristi `tests/CMakeLists.txt` da generise
`compile_commands.json` (`-DCMAKE_EXPORT_COMPILE_COMMANDS=ON`) u odvojenom
`cdb-build/` direktorijumu, izgradi `serverlogic_autogen` target (Qt MOC headeri
moraju postojati pre nego sto clang-tidy parsira TU-ove), a zatim pokrece
`clang-tidy` nad **7** serverskih `.cpp` fajlova. Rezultati idu u
`results/clang-tidy.log`, grupisani po fajlu.

Ukljuceno je 314 provera:

```
clang-analyzer-*, bugprone-*, cppcoreguidelines-*, modernize-*, performance-*, misc-*
```

## Rezultat: 185 upozorenja u 7 fajlova

| Check | Broj | Opis |
|-------|-----:|------|
| `misc-include-cleaner` | 57 | Header koji se koristi nije direktno ukljucen (tranzitivni include) |
| `misc-const-correctness` | 37 | Promenljive/parametri koji se ne menjaju nisu `const` |
| `cppcoreguidelines-non-private-member-variables-in-classes` | 24 | Javni clanovi klase (`ID`, `socket`, `isReady`, ...) |
| `modernize-use-nodiscard` | 13 | Getter funkcije bez `[[nodiscard]]` atributa |
| `cppcoreguidelines-special-member-functions` | 9 | Klase sa destruktorom ali bez kopir/move operacija |
| `cppcoreguidelines-explicit-virtual-functions` | 9 | Virtuelne metode bez `override` (alijas: `modernize-use-override`) |
| `cppcoreguidelines-owning-memory` | 7 | Sirovi pokazivaci bez vlasnistva (`new` bez `unique_ptr`) |
| `performance-enum-size` | 5 | `enum` koristi `unsigned int` umesto manjeg tipa |
| `performance-unnecessary-value-param` | 4 | Parametri koji bi trebalo da budu `const&` |
| ostalo | 20 | `pro-type-const-cast`, `prefer-member-initializer`, `init-variables`, `narrowing-conversions`, ... |

### O broju 185

185 je broj linija sa upozorenjem u logu, ali **jedinstvenih lokacija je 136**.
Razlika su headeri: upozorenje u `.h` fajlu se ponavlja jednom za svaki `.cpp`
koji ga include-uje. Na primer `player.h:27:12` je prijavljeno 5 puta, jer
`player.h` ulazi u 5 prevodilackih jedinica. Oba broja su tacna, samo mere
razlicite stvari (prijavljenih dijagnostika vs. mesta u kodu).

## Najvazniji nalazi

### `cppcoreguidelines-special-member-functions` + `owning-memory` na `Player`, `Game`, `Manager`

Ovo je strukturni defekt, ne stilska napomena. Klase poseduju sirove pokazivace
bez kontrole kopiranja:

- `Player` poseduje `QTcpSocket* socket`
- `Game` poseduje `Hangman*` i `QTimer*`
- `Manager` agregira `Player` objekte

Krsenje pravila nule/pet: ako klasa ima destruktor, mora imati i kopir
konstruktor, kopir operator dodele, move konstruktor i move operator dodele, ili
ih eksplicitno zabraniti. Bez toga je kopiranje instance undefined behavior
(double free ili dangling pointer).

Kod `Player`-a se soket alocira na dva mesta:

```cpp
Player::Player(qintptr id, QObject* parent) : QThread(parent), ID(id) {
    socket = new QTcpSocket(this);   // roditelj je this
}
void Player::run() {
    socket = new QTcpSocket();       // bez roditelja
```

clang-tidy prijavljuje oba dodeljivanja:

```
player.cpp:7:5:  assigning newly created 'gsl::owner<>' to non-owner 'QTcpSocket *'
player.cpp:12:5: assigning newly created 'gsl::owner<>' to non-owner 'QTcpSocket *'
```

Prvi soket ima `this` kao roditelja, pa ga Qt oslobodi kroz parent-child
mehanizam; pokazivac `socket` na njega se izgubi, ali memorija ne curi. Curi
**drugi**, onaj alociran u `run()` bez roditelja, jer njega ne poseduje nijedan
objekat. To curenje nije dostupno bez zive mreze (`run()` se izvrsava samo posle
`QThread::start()`), pa ga ni Valgrind ni ASan ne mogu pogoditi iz jedinicnog
harnesa. Vidi `valgrind/RunningTests.md`.

### `cppcoreguidelines-non-private-member-variables-in-classes` (24x)

`Player::socket`, `Player::ID`, `Player::isReady` i `Player::characterDrawing` su
`public`, dakle direktno dostupni svim pozivacima bez enkapsulacije. Menjanje
internog stanja bez settera otezava odrzavanje invarijanti i testiranje.

### `misc-include-cleaner` (57x)

Najveca kategorija po broju, ali najmanje kriticna. Qt headeri se medjusobno
include-uju, pa kod radi bez direktnih include-ova. Ipak je to krhka zavisnost od
internog uredjenja Qt headera: promena u Qt-u moze da polomi prevodjenje.

## Ogranicenje opsega

clang-tidy analizira **7** fajlova, dok cppcheck analizira **9**. Razlika je
`server.cpp` i `main.cpp`, koji nisu u `SOURCES` ove skripte jer nisu ni u
`tests/CMakeLists.txt`, pa za njih nema unosa u `compile_commands.json`. U logu
se `server.h` i `Server::incomingConnection` pojavljuju 0 puta.

To je konkretan primer zasto se dva statickog analizatora koriste zajedno, ali u
suprotnom smeru od ocekivanog: cppcheck ima **siri opseg** (sam parsira, ne treba
mu build), pa pokriva i `server.cpp`/`main.cpp`. Cena tog opsega je tacnost:
posto cppcheck ne vidi hijerarhiju nasledjivanja, prijavljuje lazno pozitivan
`unusedFunction` za `Server::incomingConnection()` i `Player::run()`, virtuelne
metode koje Qt poziva interno. clang-tidy ih razume kroz nasledjivanje, ali samo
za fajlove koje uopste analizira.
