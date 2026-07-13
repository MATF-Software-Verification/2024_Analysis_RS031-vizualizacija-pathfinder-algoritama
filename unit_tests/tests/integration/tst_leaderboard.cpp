/*
 * What: Integration tests for Leaderboard (SketchIt server).
 * Why:  Leaderboard crosses several boundaries at once - the filesystem (writable
 *       app-data dir), the bundled Qt resource seed, and JSON (de)serialization -
 *       so it is exercised as an integration test rather than a pure unit test.
 * How:  QStandardPaths test mode redirects writes to a throwaway location; the
 *       seed leaderboard.json is removed before each test so state is deterministic.
 */
#include <QtTest>
#include <QStandardPaths>
#include <QFile>
#include "leaderboard.h"
#include "player.h"

class TestLeaderboard : public QObject
{
    Q_OBJECT

    Player* mkPlayer(const QString& nick)
    {
        Player* p = new Player(0, this);
        p->setNickname(nick);
        return p;
    }

    static QString seedPath()
    {
        return QStandardPaths::writableLocation(QStandardPaths::AppDataLocation)
               + "/leaderboard.json";
    }

private slots:
    void initTestCase();
    void init();
    void seedIsSortedDescendingAndCappedAtTen();
    void updateAddsNewPlayerToTop();
    void updateAccumulatesExistingScore();
};

void TestLeaderboard::initTestCase()
{
    QStandardPaths::setTestModeEnabled(true);
    // Force the resource (compiled into serverlogic) to register so the
    // Leaderboard constructor can copy the seed file out of it.
    Q_INIT_RESOURCE(resources);
}

void TestLeaderboard::init()
{
    // Each test starts from the pristine bundled seed.
    QFile::remove(seedPath());
}

// The bundled seed has 23 players; results must come back sorted by score
// descending and capped to the top 10 (getLeaderboardResults uses mid(0,10)).
void TestLeaderboard::seedIsSortedDescendingAndCappedAtTen()
{
    Leaderboard lb;
    auto results = lb.getLeaderboardResults();

    QCOMPARE(results.size(), 10);
    QCOMPARE(results.first().first, QString("Ognjen")); // highest seed score (101)
    QCOMPARE(results.first().second, 101);
    for (int i = 1; i < results.size(); ++i)
        QVERIFY(results[i - 1].second >= results[i].second);
}

// A brand-new high scorer must appear at the top after an update + reload.
void TestLeaderboard::updateAddsNewPlayerToTop()
{
    {
        Leaderboard writer;
        QMap<Player*, int> round;
        round.insert(mkPlayer("Champion"), 999);
        writer.updateLeaderboard(round); // persists to disk
    }

    Leaderboard reader; // re-reads the persisted file
    auto results = reader.getLeaderboardResults();
    QCOMPARE(results.first().first, QString("Champion"));
    QCOMPARE(results.first().second, 999);
}

// Updating an existing name must add to the stored score, not replace it.
void TestLeaderboard::updateAccumulatesExistingScore()
{
    // "Ognjen" starts at 101 in the seed.
    Leaderboard writer;
    QMap<Player*, int> round;
    round.insert(mkPlayer("Ognjen"), 50);
    writer.updateLeaderboard(round);

    Leaderboard reader;
    auto results = reader.getLeaderboardResults();
    QCOMPARE(results.first().first, QString("Ognjen"));
    QCOMPARE(results.first().second, 151); // 101 + 50
}

QTEST_MAIN(TestLeaderboard)
#include "tst_leaderboard.moc"
