/*
 * What: CBMC harness for the Hangman masked-length computation.
 * Why:  Bounded model checking proves (or refutes) the size arithmetic from
 *       hangman.cpp:7 `std::string(w.size()*2 - 1, ' ')` for ALL word lengths at
 *       once, rather than the single cases a unit test can try.
 * How:  word length is nondeterministic; CBMC's --unsigned-overflow-check flags the
 *       size_t underflow, and the assertion fails for len == 0.
 */
#include <stddef.h>

size_t nondet_size(void);

int main(void)
{
    size_t len = nondet_size();        /* length of the word given to Hangman() */
    __CPROVER_assume(len <= 256);      /* a plausible word length */

    size_t masked = len * 2 - 1;       /* the exact expression under test */

    /* For any non-empty word, 2L-1 is a small sane number. For len == 0 this
     * underflows size_t to SIZE_MAX, which is what makes std::string throw. */
    __CPROVER_assert(masked < 1024, "Hangman masked length must not underflow");

    return 0;
}
