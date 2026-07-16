int nondet_int(void);

int main(void)
{
    int timeLeft = nondet_int();  

    int guesser = 100 + (400 * timeLeft / 1000) / 60;

    __CPROVER_assert(guesser >= 100 && guesser <= 500,
                     "guesser stays in range without an input contract");
    return 0;
}
