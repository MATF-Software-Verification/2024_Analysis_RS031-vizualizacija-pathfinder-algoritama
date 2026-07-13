/*
 * What: Unit tests for the Hangman word-reveal class (SketchIt server).
 * Why:  Hangman builds the masked-word string and reveals letters one by one;
 *       its index/size arithmetic is a prime target for boundary testing.
 * How:  QtTest. Pure std::string logic, no Qt event loop required.
 */
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
    void emptyWordIsRejectedOrCrashes(); // documents the size_t underflow bug
};

// "cat" (len 3) -> revealed length 2*3-1 = 5, underscores at even positions: "_ _ _".
void TestHangman::maskedFormatForMultiChar()
{
    Hangman h("cat", 1);
    QCOMPARE(QString::fromStdString(h.getRevealedWord()), QString("_ _ _"));
    QVERIFY(!h.isComplete());
}

// Single character: length 2*1-1 = 1 -> "_". Revealing once exposes the letter.
void TestHangman::singleCharWord()
{
    Hangman h("a", 1);
    QCOMPARE(QString::fromStdString(h.getRevealedWord()), QString("_"));
    h.revealNextLetter();
    QCOMPARE(QString::fromStdString(h.getRevealedWord()), QString("a"));
    QVERIFY(h.isComplete());
}

// After revealing word.size() letters, every original letter is exposed and the
// game reports completion.
void TestHangman::revealAllCompletes()
{
    const std::string word = "cat";
    Hangman h(word, 1);
    for (size_t i = 0; i < word.size(); ++i)
        h.revealNextLetter();

    QVERIFY(h.isComplete());
    const std::string revealed = h.getRevealedWord();
    // Even positions hold the original letters, odd positions are separators.
    for (size_t i = 0; i < word.size(); ++i)
        QCOMPARE(revealed[i * 2], word[i]);
}

// FINDING: the constructor computes `w.size() * 2 - 1` as the masked length.
// For an empty word this underflows size_t to a huge value, so std::string throws
// std::length_error (or std::bad_alloc). The constructor performs no guard.
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
