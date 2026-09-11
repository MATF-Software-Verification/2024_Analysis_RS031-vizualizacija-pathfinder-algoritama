# cppcheck (staticka analiza toka podataka)

## Sta i zasto

`cppcheck` cita izvorni kod i trazi greske **bez prevodjenja i bez izvrsavanja**.
Sopstveni parser napravi AST, pa nad njim izvrsi skup provera ("checkers"), od kojih
je na ovom projektu aktivno **161 od 592**.

Kljucna razlika od kompajlerskih upozorenja je **value-flow analiza**: cppcheck prati
moguce vrednosti promenljivih kroz grane, pa nalazi null-dereference, prekoracenje
granica i neinicijalizovane promenljive i na putanjama koje ni jedan test ne pokrene.
Cena su lazno pozitivni nalazi (vidi sekciju na kraju) i to sto ne razume sablone i
makroe kao pravi kompajler.
    
Verzija koriscena u analizi: **Cppcheck 2.13.0**.

## Reprodukcija

```bash
cd cppcheck
./run.sh
```

## Rezultat: 15 nalaza (12 style, 3 performance, 0 error, 0 warning)

| id | severity | broj | lokacije |
|---|---|---:|---|
| `noExplicitConstructor` | style | 3 | `player.h:16`, `points.h:10`, `words.h:16` |
| `constVariablePointer` | style | 2 | `points.cpp:5`, `game.cpp:182` |
| `constVariableReference` | style | 2 | `player.cpp:101`, `player.cpp:102` |
| `unusedFunction` | style | 2 | `player.cpp:10`, `server.cpp:39` |
| `constParameterPointer` | style | 1 | `points.cpp:22` |
| `shadowVariable` | style | 1 | `player.cpp:122` |
| `useStlAlgorithm` | style | 1 | `manager.cpp:53` |
| `passedByValue` | performance | 2 | `points.cpp:3`, `manager.cpp:51` |
| `passedByValueCallback` | performance | 1 | `manager.cpp:139` |

Nula nalaza kategorije `error` i `warning` je sam po sebi rezultat: cppcheck nije nasao
ni jedan ocigledan obrazac curenja memorije, prekoracenja granica ili upotrebe
neinicijalizovane promenljive.

## Najvazniji nalazi

### 1. `player.cpp:101-102`: cppcheck je pogodio liniju, ali promasio bug

```cpp
const QString& message = QString::fromUtf8(payload);
QString& sender = message.split("/")[0];          // linija 101
QString& messageContent = message.split("/")[1];  // linija 102
```

cppcheck ovo prijavljuje kao `style/constVariableReference` ("moze biti referenca na
const"). Stvarni problem je ozbiljniji: **obe reference vise u vazduhu.**

`message.split("/")` vraca **privremeni** `QStringList`. Produzenje zivotnog veka
(*lifetime extension*) vazi samo kada se referenca vezuje **direktno** za privremeni
objekat; ovde se vezuje za podobjekat dobijen kroz poziv funkcije (`operator[]`), pa
pravilo ne vazi. Privremena lista se unistava na kraju iskaza, a `sender` i
`messageContent` posle toga pokazuju na unisten `QString`.

Reprodukovano na izolovanom primeru sa `-fsanitize=address`:

```
ERROR: AddressSanitizer: heap-use-after-free on address 0x506000000040
READ of size 8 at 0x506000000040 thread T0
    #0 QString::size() const  qstring.h:241
    #1 QDebug::operator<<(QString const&)  qdebug.h:147
    #2 main  t.cpp:7
```

U samom projektu se **UB ne izvrsava**, jer se ni `sender` ni `messageContent` nikada
ne citaju: `emit messageReceived(message, this)` prosledjuje `message`, a ne njih. Dakle
to je mrtav kod sa latentnim UB-om: prvi put kad neko doda upotrebu tih promenljivih,
dobija `heap-use-after-free`.

Ovaj nalaz je i **ilustracija ogranicenja alata**: cppcheck je oznacio tacnu liniju, ali
je klasifikovao kao stilsku sitnicu umesto kao gresku zivotnog veka.

### 2. `player.cpp:122`: `shadowVariable`

```cpp
if (message.split('/')[0] == "SET_NICKNAME") {
    QStringList parts = message.split('/');
    QString nickname = parts[1];   // zaklanja clan Player::nickname (player.h:50)
    setNickname(nickname);
}
```

Lokalna promenljiva ima isto ime kao clan klase. Ovde je posledica bezopasna, jer se
odmah poziva `setNickname()` koji upisuje u clan. Ali obrazac je opasan: dovoljno je da
neko obrise poziv `setNickname()` i kod deluje kao da postavlja nadimak, a u stvari
puni lokalnu promenljivu koja umire na kraju bloka.

### 3. `noExplicitConstructor` (3x): rizik implicitne konverzije

`Points(QList<Player*> players)`, `Player(qintptr id, QObject* parent = nullptr)` i
`Words(QObject* parent = nullptr)` su konstruktori upotrebljivi sa jednim argumentom, a
nisu `explicit`. Zato kompajler dozvoljava tihu konverziju: funkcija koja prima `Points`
prihvatice i goli `QList<Player*>`. Kod `Player`-a je gore jer je prvi parametar
`qintptr` (celobrojni tip), pa se svaki `int` implicitno konvertuje u `Player`.

### 4. `passedByValue` (`points.cpp:3`, `manager.cpp:51`)

`Points::Points(QList<Player*> players)` i `Manager::getPlayerByNick(QString nickname)`
primaju Qt kontejner/string **po vrednosti**. Qt tipovi koriste copy-on-write, pa je
kopija jeftina (samo inkrement brojaca referenci), ali nije besplatna: atomicna operacija
nad brojacem po pozivu. `const&` je ispravan potpis.

## Lazno pozitivni nalazi i ogranicenja

`unusedFunction` na `player.cpp:10` (`Player::run()`) i `server.cpp:39`
(`Server::incomingConnection()`) su **lazno pozitivni**. Oba su `override` virtuelnih
metoda koje Qt framework poziva interno: `run()` pokrece `QThread::start()`, a
`incomingConnection()` poziva `QTcpServer` pri novoj konekciji. cppcheck ih ne vidi
pozvane jer ne postoji nijedan direktan poziv u analiziranom kodu.

Za uporedjivanje, `clang-tidy` ih ispravno prepoznaje kroz hijerarhiju nasledjivanja i
ne prijavljuje kao nekoriscene (vidi `clang-tidy/RunningTests.md`). To je konkretan
primer zasto se dva staticka analizatora koriste zajedno, a ne jedan.

Dodatno ogranicenje: posto Qt hederi nisu dati alatu, cppcheck ne zna prave potpise Qt
metoda i moze propustiti nalaze koji zavise od njih. Nalaz iz sekcije 1 je upravo takav
slucaj.

## Zakljucak

- Nula `error` i `warning` nalaza: nema ociglednih obrazaca curenja, prekoracenja granica
  ili neinicijalizovanih promenljivih.
- 15 nalaza tipa `style`/`performance`, od kojih su tri sadrzinski vazna:
  latentni `heap-use-after-free` (`player.cpp:101-102`), zaklanjanje clana
  (`player.cpp:122`) i neeksplicitni konstruktori na tri klase.
- Dva nalaza (`unusedFunction`) su lazno pozitivna zbog Qt virtuelnih poziva.
- Alat je dao najveci doprinos tamo gde dinamicki alati ne dosezu: `server.cpp`,
  `main.cpp` i `game.cpp` (0% pokrivenosti testovima) su ipak staticki analizirani.
