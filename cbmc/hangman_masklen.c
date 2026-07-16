#include <stddef.h>

size_t nondet_size(void);

int main(void)
{
    size_t len = nondet_size();        
    __CPROVER_assume(len <= 256);      

    size_t masked = len * 2 - 1;       

    /* For any non-empty word, 2L-1 is a small sane number. For len == 0 this
     * underflows size_t to SIZE_MAX, which is what makes std::string throw. */
    __CPROVER_assert(masked < 1024, "Hangman masked length must not underflow");

    return 0;
}
