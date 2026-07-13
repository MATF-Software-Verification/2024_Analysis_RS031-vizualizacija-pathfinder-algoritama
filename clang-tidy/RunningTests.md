# clang-tidy (statički lint)

## Šta i zašto

clang-tidy analizira C++ izvorni kod kroz Clangov AST (apstraktno sintaksno stablo) i
prijavljuje kršenja stilskih pravila, loše idiome i potencijalne bagove — bez izvršavanja
koda. Komplementaran je sa cppcheck-om: oslanja se na dublje razumevanje C++ semantike i
modernih idioma (C++17/20), dok cppcheck bolje prati tok podataka unutar funkcija.

## Reprodukcija

```bash
cd clang-tidy
./run.sh
```

Skripta generiše `compile_commands.json` (preko `-DCMAKE_EXPORT_COMPILE_COMMANDS=ON`),
gradi `serverlogic_autogen` target (Qt MOC), a zatim pokreće `clang-tidy` nad svakim od
9 serverskih `.cpp` fajlova sa skupom provera:

```
clang-analyzer-*, bugprone-*, cppcoreguidelines-*, modernize-*, performance-*, misc-*
```

Isključeni su samo `modernize-use-trailing-return-type`, `cppcoreguidelines-avoid-magic-numbers`
i `modernize-use-auto` (preterano restriktivni za ovaj stil koda).

Rezultati se upisuju u `results/clang-tidy.log`, grupisani po fajlu.

## Rezultat — 185 upozorenja u 7 fajlova

| Check | Broj | Opis |
|-------|-----:|------|
| `misc-include-cleaner` | 57 | Header koji se koristi nije direktno uključen (transitivni include) |
| `misc-const-correctness` | 37 | Promenljive/parametri koji se ne menjaju nisu `const` |
| `non-private-member-variables` | 24 | Javni memberi klase (`ID`, `socket`, `isReady`, ...) |
| `modernize-use-nodiscard` | 13 | Getter funkcije bez `[[nodiscard]]` atributa |
| `cppcoreguidelines-special-member-functions` | 9 | Klase sa destruktorom ali bez kopir/move operacija |
| `modernize-use-override` | 9 | Virtual metode bez `override` ključne reči |
| `cppcoreguidelines-owning-memory` | 7 | Sirovi pokazivači bez vlasništva (`new` bez `unique_ptr`) |
| `performance-enum-size` | 5 | `enum` koristi `unsigned int` umesto manjeg tipa |
| `performance-unnecessary-value-param` | 4 | Parametri koji bi trebalo da budu `const&` |
| ostalo | 20 | `narrowing-conversions`, `init-variables`, `prefer-member-initializer`, ... |

## Najvažniji nalazi

### `cppcoreguidelines-special-member-functions` + `owning-memory` na `Player`, `Game`, `Manager`

Ovo je **strukturni defekt**, ne samo stilska napomena. Klase poseduju sirove pokazivače:

- `Player` — `QTcpSocket* socket` (alociran u konstruktoru i ponovo u `run()` — prvi se gubi)
- `Game` — `Hangman*` i `QTimer*` bez kontrole kopiranja
- `Manager` — agregira `Player` objekte

Kršenje C++ pravila nule/pet: ako klasa ima destruktor, mora imati i kopir konstruktor,
kopir operator dodele, move konstruktor i move operator dodele — ili ih eksplicitno zabraniti.
Bez toga je kopiranje klase undefined behavior (double free / dangling pointer).

### `non-private-member-variables` (24×)

`Player::socket`, `Player::ID`, `Player::isReady`, `Player::characterDrawing` su `public` —
direktno su dostupni svim pozivačima bez enkapsulacije. Menjanje internog stanja bez gettera
otežava invarijante i testabilnost.

### `misc-include-cleaner` (57×)

Najveća kategorija po broju, ali najmanje kritična — Qt headers se međusobno include-uju,
pa kod funkcioniše bez direktnih include-ova. Ipak, to pravi krhku zavisnost od internog
uređivanja Qt headerima.

## Ograničenje opsega

clang-tidy prijavljuje upozorenja za virtual metode (`run()`, `incomingConnection()`) koje
Qt framework poziva interno. Za razliku od cppcheck-a koji ih označava kao nekorišćene,
clang-tidy ih ispravno prepoznaje kroz nasleđivanje i ne prijavljuje kao `unusedFunction`.
