#include <QtTest>
#include <stdexcept>
#include "hangman.h"

class TestHangman : public QObject
{
    Q_OBJECT
private slots:
    void maskedFormatForMultiChar();
    void singleCharWord();
    void revealAllCompletes();
    void emptyWordIsRejectedOrCrashes();
};

void TestHangman::maskedFormatForMultiChar()
{
    Hangman h("cat", 1);
    QCOMPARE(QString::fromStdString(h.getRevealedWord()), QString("_ _ _"));
    QVERIFY(!h.isComplete());
}

void TestHangman::singleCharWord()
{
    Hangman h("a", 1);
    QCOMPARE(QString::fromStdString(h.getRevealedWord()), QString("_"));
    h.revealNextLetter();
    QCOMPARE(QString::fromStdString(h.getRevealedWord()), QString("a"));
    QVERIFY(h.isComplete());
}

void TestHangman::revealAllCompletes()
{
    const std::string word = "cat";
    Hangman h(word, 1);
    for (size_t i = 0; i < word.size(); ++i)
        h.revealNextLetter();

    QVERIFY(h.isComplete());
    const std::string revealed = h.getRevealedWord();
    //na parnim pozicijama su prava slova
    for (size_t i = 0; i < word.size(); ++i)
        QCOMPARE(revealed[i * 2], word[i]);
}

// za praznu rec dovodi do potkoracenja (0*2 - 1)
void TestHangman::emptyWordIsRejectedOrCrashes()
{
    bool threw = false;
    try {
        Hangman h("", 1);
        (void)h;
    } catch (const std::length_error&) {
        threw = true;
    } catch (const std::bad_alloc&) {
        threw = true;
    }
    QVERIFY2(threw,
             "Hangman(\"\") underflows size in std::string(w.size()*2-1, ' '); "
             "an empty word must be rejected before reaching this class");
}

QTEST_MAIN(TestHangman)
#include "tst_hangman.moc"
