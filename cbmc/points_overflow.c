/*
 * What: CBMC harness that exposes the unguarded multiplication in Points scoring.
 * Why:  points.cpp computes `400 * timeLeft` with no validation. CBMC's
 *       --signed-overflow-check proves an int overflow is reachable when timeLeft
 *       is not constrained to its intended [0, 60000] domain.
 * How:  timeLeft is nondeterministic over the full int range (no assume). CBMC
 *       reports the overflow and the assertion violation with a concrete trace.
 */
int nondet_int(void);

int main(void)
{
    int timeLeft = nondet_int();   /* NOTE: no domain assumption — that is the point */

    int guesser = 100 + (400 * timeLeft / 1000) / 60;

    __CPROVER_assert(guesser >= 100 && guesser <= 500,
                     "guesser stays in range without an input contract");
    return 0;
}
