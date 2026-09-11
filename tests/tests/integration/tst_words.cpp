#include <QtTest>
#include <QSet>
#include "words.h"

class TestWords : public QObject
{
    Q_OBJECT
private slots:
    void initTestCase();
    void picksRequestedCount();
    void picksAreFromDictionary();
    void defaultPickIsThree();
};

void TestWords::initTestCase()
{
    Q_INIT_RESOURCE(resources);
}

void TestWords::picksRequestedCount()
{
    Words w;
    QCOMPARE(w.pickWords(5).size(), 5);
}

//pickWords() funkcija vraca reci sa razlicitim indeksom a ne razlicite reci
//words.txt ima 232 indeksa od kojih su 14 reci duplikati
void TestWords::picksAreFromDictionary()
{
    Words w;
    QStringList picks = w.pickWords(10);
    QCOMPARE(picks.size(), 10);
    for (const QString& p : picks)
        QVERIFY2(!p.isEmpty(), "pickWords must not return empty strings");
}

void TestWords::defaultPickIsThree()
{
    Words w;
    QCOMPARE(w.pickWords().size(), 3);
}

QTEST_MAIN(TestWords)
#include "tst_words.moc"
