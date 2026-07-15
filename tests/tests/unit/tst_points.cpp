/*
 * What: Unit tests for the Points scoring class (SketchIt server).
 * Why:  Points computes per-round scores; its integer arithmetic and map handling
 *       are pure logic, ideal for white-box unit testing.
 * How:  QtTest. Players are constructed only as map keys (no networking is started).
 */
#include <QtTest>
#include "points.h"
#include "player.h"

class TestPoints : public QObject
{
    Q_OBJECT

    // Build a non-running Player usable purely as a QMap key / nickname holder.
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

// initialize() must zero every player's round result and set the drawer.
void TestPoints::initializeResetsAllScores()
{
    Player* a = mkPlayer("a");
    Player* b = mkPlayer("b");
    Points p({a, b});

    p.newCorrectGuess(a, 60000); // dirty the map first
    p.initialize(a);

    auto r = p.getRoundResults();
    QCOMPARE(r.value(a), 0);
    QCOMPARE(r.value(b), 0);
}

// guesserPoints = 100 + (400*timeLeft/1000)/60 ; drawerPoints = guesserPoints/3.
// timeLeft = 60000 ms -> guesser 500, drawer 166 (integer division).
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

// newRevealedLetter() returns a post-increment counter, reset by initialize().
void TestPoints::revealedLetterIncrementsFromZero()
{
    Player* a = mkPlayer("a");
    Points p({a});
    p.initialize(a);

    QCOMPARE(p.newRevealedLetter(), 0);
    QCOMPARE(p.newRevealedLetter(), 1);
    QCOMPARE(p.newRevealedLetter(), 2);
}

// FINDING (documented): without initialize(), drawer is nullptr, so a correct guess
// silently inserts a nullptr key into the results map instead of crediting a drawer.
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
