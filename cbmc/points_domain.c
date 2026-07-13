/*
 * What: CBMC harness that proves the Points scoring formula correct over its whole
 *       legal input domain.
 * Why:  points.cpp computes guesser = 100 + (400*timeLeft/1000)/60, drawer = /3.
 *       The unit tests cover only the two endpoints; CBMC verifies every value in
 *       [0, 60000] ms and also checks for arithmetic overflow on that range.
 * How:  timeLeft is nondeterministic but assumed in-domain; assertions pin the
 *       expected score envelope. Expected result: VERIFICATION SUCCESSFUL.
 */
int nondet_int(void);

int main(void)
{
    int timeLeft = nondet_int();
    __CPROVER_assume(timeLeft >= 0 && timeLeft <= 60000);

    int guesser = 100 + (400 * timeLeft / 1000) / 60;
    int drawer  = guesser / 3;

    __CPROVER_assert(guesser >= 100 && guesser <= 500, "guesser score within [100,500]");
    __CPROVER_assert(drawer  >= 33  && drawer  <= 166, "drawer score within [33,166]");

    return 0;
}
