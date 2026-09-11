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
    Q_INIT_RESOURCE(resources);
}

void TestLeaderboard::init()
{
    //Brise prethodni file
    QFile::remove(seedPath());
}

//Vraca prvih 10 po skoru opadajuce
void TestLeaderboard::seedIsSortedDescendingAndCappedAtTen()
{
    Leaderboard lb;
    auto results = lb.getLeaderboardResults();

    QCOMPARE(results.size(), 10);
    QCOMPARE(results.first().first, QString("Ognjen"));
    QCOMPARE(results.first().second, 101);
    for (int i = 1; i < results.size(); ++i)
        QVERIFY(results[i - 1].second >= results[i].second);
}

//sa {} osiguravamo da je pisanje flushovano pre citanja
void TestLeaderboard::updateAddsNewPlayerToTop()
{
    {
        Leaderboard writer;
        QMap<Player*, int> round;
        round.insert(mkPlayer("Champion"), 999);
        writer.updateLeaderboard(round);
    }

    Leaderboard reader; // re-reads the persisted file
    auto results = reader.getLeaderboardResults();
    QCOMPARE(results.first().first, QString("Champion"));
    QCOMPARE(results.first().second, 999);
}

void TestLeaderboard::updateAccumulatesExistingScore()
{
    // Ognjen pocinje sa 101
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
