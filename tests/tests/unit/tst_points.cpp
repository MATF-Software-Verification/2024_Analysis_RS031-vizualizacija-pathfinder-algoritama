#include <QtTest>
#include "points.h"
#include "player.h"

class TestPoints : public QObject
{
    Q_OBJECT

    Player* mkPlayer(const QString& nick)
    {
        Player* p = new Player(0, this);
        p->setNickname(nick);
        return p;
    }

private slots:
    void initializeResetsAllScores();
    void correctGuessFullTime();
    void correctGuessZeroTime();
    void erasePlayerRemovesEntry();
    void revealedLetterIncrementsFromZero();
    void drawerKeyWhenUninitialized();
};

void TestPoints::initializeResetsAllScores()
{
    Player* a = mkPlayer("a");
    Player* b = mkPlayer("b");
    Points p({a, b});

    p.newCorrectGuess(a, 60000);
    p.initialize(a);

    auto r = p.getRoundResults();
    QCOMPARE(r.value(a), 0);
    QCOMPARE(r.value(b), 0);
}

//guesser = max poena 500
//drawer trecina of guessera
void TestPoints::correctGuessFullTime()
{
    Player* drawer = mkPlayer("drawer");
    Player* guesser = mkPlayer("guesser");
    Points p({drawer, guesser});
    p.initialize(drawer);

    p.newCorrectGuess(guesser, 60000);

    auto r = p.getRoundResults();
    QCOMPARE(r.value(guesser), 500);
    QCOMPARE(r.value(drawer), 166);
}

// timeLeft = 0 -> guesser 100, drawer 33.
void TestPoints::correctGuessZeroTime()
{
    Player* drawer = mkPlayer("drawer");
    Player* guesser = mkPlayer("guesser");
    Points p({drawer, guesser});
    p.initialize(drawer);

    p.newCorrectGuess(guesser, 0);

    auto r = p.getRoundResults();
    QCOMPARE(r.value(guesser), 100);
    QCOMPARE(r.value(drawer), 33);
}

void TestPoints::erasePlayerRemovesEntry()
{
    Player* a = mkPlayer("a");
    Player* b = mkPlayer("b");
    Points p({a, b});

    QVERIFY(p.erasePlayer(a));            // present -> removed
    QVERIFY(!p.erasePlayer(a));           // already gone -> false
    QVERIFY(!p.getRoundResults().contains(a));
    QVERIFY(p.getRoundResults().contains(b));
}

// newRevealedLetter() vraca post-inkrement
void TestPoints::revealedLetterIncrementsFromZero()
{
    Player* a = mkPlayer("a");
    Points p({a});
    p.initialize(a);

    QCOMPARE(p.newRevealedLetter(), 0);
    QCOMPARE(p.newRevealedLetter(), 1);
    QCOMPARE(p.newRevealedLetter(), 2);
}

// Bez initialize() dodavanje poena ce dodati poene nullptr
void TestPoints::drawerKeyWhenUninitialized()
{
    Player* guesser = mkPlayer("guesser");
    Points p({guesser});
    // No initialize() call -> drawer == nullptr.

    p.newCorrectGuess(guesser, 60000);

    auto r = p.getRoundResults();
    QVERIFY2(r.contains(nullptr),
             "drawer is nullptr when initialize() was not called; points are lost to a null key");
}

QTEST_MAIN(TestPoints)
#include "tst_points.moc"
