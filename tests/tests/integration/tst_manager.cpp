#include <QtTest>
#include <QStandardPaths>
#include "manager.h"
#include "player.h"

class TestManager : public QObject
{
    Q_OBJECT

    Player* mkPlayer(const QString& nick)
    {
        Player* p = new Player(0);
        p->setNickname(nick);
        return p;
    }

private slots:
    void initTestCase();
    void rosterStartsEmpty();
    void addPlayerGrowsRoster();
    void lookupByNickname();
    void lookupMissingReturnsNull();
    void gameNotRunningInitially();
};

void TestManager::initTestCase()
{
    QStandardPaths::setTestModeEnabled(true);
    Q_INIT_RESOURCE(resources);
}

void TestManager::rosterStartsEmpty()
{
    Manager m;
    QCOMPARE(m.numberOfPlayers(), 0);
}

void TestManager::addPlayerGrowsRoster()
{
    Manager m;
    m.addPlayer(mkPlayer("alice"));
    m.addPlayer(mkPlayer("bob"));
    QCOMPARE(m.numberOfPlayers(), 2);
    QCOMPARE(m.getAllPlayers().size(), 2);
}

void TestManager::lookupByNickname()
{
    Manager m;
    Player* alice = mkPlayer("alice");
    m.addPlayer(alice);
    QCOMPARE(m.getPlayerByNick("alice"), alice);
}

void TestManager::lookupMissingReturnsNull()
{
    Manager m;
    m.addPlayer(mkPlayer("alice"));
    QCOMPARE(m.getPlayerByNick("nobody"), nullptr);
}

void TestManager::gameNotRunningInitially()
{
    Manager m;
    QVERIFY(!m.gameIsRunning());
}

QTEST_MAIN(TestManager)
#include "tst_manager.moc"
