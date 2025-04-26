#include <stdio.h>
#include <stdlib.h>
#include <math.h>

long long distance(long long x1, long long y1, long long x2, long long y2) {
    return llround(sqrt((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1)));
}

int main(int argc, char* argv[]) {
    if (argc != 5) {
        fprintf(stderr, "Usage: %s x1 y1 x2 y2\n", argv[0]);
        return 1;
    }

    long long x1 = atoll(argv[1]);
    long long y1 = atoll(argv[2]);
    long long x2 = atoll(argv[3]);
    long long y2 = atoll(argv[4]);

    printf("%lld\n", distance(x1, y1, x2, y2));
    return 0;
}

// gcc -odistance distance.c -lm