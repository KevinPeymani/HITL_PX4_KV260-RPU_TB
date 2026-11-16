#define _GNU_SOURCE
#include "ts_apu.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define NS_PER_TICK 10.0

static uint64_t now_ns(clockid_t clk)
{
    struct timespec ts;
    clock_gettime(clk, &ts);
    return (uint64_t)ts.tv_sec * 1000000000u + (uint64_t)ts.tv_nsec;
}

/* Advances next by period_ns and sleeps until then, so the period doesn't drift. */
static void sleep_until_next(struct timespec *next, uint64_t period_ns)
{
    next->tv_sec += period_ns / 1000000000u;
    next->tv_nsec += period_ns % 1000000000u;
    if (next->tv_nsec >= 1000000000L) {
        next->tv_nsec -= 1000000000L;
        next->tv_sec++;
    }
    clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, next, NULL);
}

static int parse_ch(const char *s, unsigned *ch)
{
    *ch = (unsigned)strtoul(s, NULL, 0);
    if (*ch >= TS_NUM_CH) {
        fprintf(stderr, "channel must be 0..%d\n", TS_NUM_CH - 1);
        return -1;
    }
    return 0;
}

/* Test 3: N toggles at a fixed period; ts_reader + ts_decode check the events. */
static int cmd_toggle(int argc, char **argv)
{
    if (argc != 3) {
        fprintf(stderr, "usage: ts_test toggle <n> <period_us> <ch>\n");
        return 2;
    }
    long n = strtol(argv[0], NULL, 0);
    uint64_t period_ns = strtoull(argv[1], NULL, 0) * 1000u;
    unsigned ch;
    if (n <= 0 || period_ns == 0 || parse_ch(argv[2], &ch) != 0)
        return 2;

    struct timespec next;
    clock_gettime(CLOCK_MONOTONIC, &next);
    for (long i = 0; i < n; i++) {
        sleep_until_next(&next, period_ns);
        ts_toggle(ch);
    }

    printf("toggled ch%u %ld times, period %llu us\n",
           ch, n, (unsigned long long)(period_ns / 1000u));
    return 0;
}

struct clk_sample {
    uint64_t mono;
    uint64_t raw;
    uint64_t ticks;   /* cnt_lo unwrapped to 64 bits */
    uint64_t window;  /* CLOCK_MONOTONIC time spent taking the sample */
};

/* Reads the counter bracketed by both Linux clocks and unwraps it against prev_lo. */
static void clk_sample(struct clk_sample *s, uint32_t *prev_lo, uint64_t *ext)
{
    uint64_t m0 = now_ns(CLOCK_MONOTONIC);
    uint64_t r0 = now_ns(CLOCK_MONOTONIC_RAW);
    uint32_t c = ts_counter();
    uint64_t r1 = now_ns(CLOCK_MONOTONIC_RAW);
    uint64_t m1 = now_ns(CLOCK_MONOTONIC);

    *ext += (uint32_t)(c - *prev_lo);
    *prev_lo = c;

    s->mono = (m0 + m1) / 2;
    s->raw = (r0 + r1) / 2;
    s->ticks = *ext;
    s->window = m1 - m0;
}

/* Test 4: pl_clk0 frequency from counter vs CLOCK_MONOTONIC(_RAW). */
static int cmd_clock(int argc, char **argv)
{
    long seconds = (argc >= 1) ? strtol(argv[0], NULL, 0) : 60;
    if (seconds <= 0) {
        fprintf(stderr, "usage: ts_test clock [seconds]\n");
        return 2;
    }

    uint32_t prev_lo = ts_counter();
    uint64_t ext = prev_lo;
    struct clk_sample first, last;
    clk_sample(&first, &prev_lo, &ext);

    /* One sample per second keeps every gap far below the 42.9 s wrap of cnt_lo. */
    struct timespec next;
    clock_gettime(CLOCK_MONOTONIC, &next);
    for (long i = 0; i < seconds; i++) {
        sleep_until_next(&next, 1000000000u);
        clk_sample(&last, &prev_lo, &ext);
    }

    double ticks = (double)(last.ticks - first.ticks);
    double f_mono = ticks * 1e9 / (double)(last.mono - first.mono);
    double f_raw = ticks * 1e9 / (double)(last.raw - first.raw);
    double err_ppm = (double)(first.window + last.window) / 2.0
                     / (double)(last.mono - first.mono) * 1e6;

    printf("duration      %.3f s, %.0f ticks\n", (last.mono - first.mono) / 1e9, ticks);
    printf("vs MONOTONIC     %.3f Hz  (%+.3f ppm vs 100 MHz)\n", f_mono, (f_mono / 1e8 - 1.0) * 1e6);
    printf("vs MONOTONIC_RAW %.3f Hz  (%+.3f ppm vs 100 MHz)\n", f_raw, (f_raw / 1e8 - 1.0) * 1e6);
    printf("sampling error   +/- %.4f ppm\n", err_ppm);
    return 0;
}

static int cmp_u32(const void *a, const void *b)
{
    uint32_t x = *(const uint32_t *)a, y = *(const uint32_t *)b;
    return (x > y) - (x < y);
}

/* Pops events until one changes bit ch; returns 0 and its ts[31:0], or -1 on timeout. */
static int wait_event(volatile uint32_t *fifo, unsigned ch, uint32_t *ts_lo)
{
    uint64_t deadline = now_ns(CLOCK_MONOTONIC) + 10000000u;

    for (;;) {
        while (fifo[TS_FIFO_RDFO / 4] == 0) {
            if (now_ns(CLOCK_MONOTONIC) > deadline)
                return -1;
        }
        uint32_t len = fifo[TS_FIFO_RLR / 4] & TS_RLR_LEN_MASK;
        if (len != TS_EV_BYTES) {
            for (uint32_t i = 0; i < (len + 3) / 4; i++)
                (void)fifo[TS_FIFO_RDFD / 4];
            continue;
        }
        uint32_t w0 = fifo[TS_FIFO_RDFD / 4];
        uint32_t w1 = fifo[TS_FIFO_RDFD / 4];
        if (TS_EV_CHANGE(w1) & (1u << ch)) {
            *ts_lo = w0;
            return 0;
        }
    }
}

/* Test 5: ticks from a counter read to the edge of the toggle that follows it. */
static int cmd_latency(int argc, char **argv)
{
    if (argc < 3 || argc > 4) {
        fprintf(stderr, "usage: ts_test latency <n> <period_us> <ch> [samples.txt]\n"
                        "       (ts_reader must not be running)\n");
        return 2;
    }
    long n = strtol(argv[0], NULL, 0);
    uint64_t period_ns = strtoull(argv[1], NULL, 0) * 1000u;
    unsigned ch;
    if (n <= 0 || period_ns == 0 || parse_ch(argv[2], &ch) != 0)
        return 2;

    volatile uint32_t *fifo;
    size_t fifo_size;
    int ret = ts_uio_map(TS_FIFO_BASE, &fifo, &fifo_size);
    if (ret != 0) {
        fprintf(stderr, "ts_uio_map(fifo): %s\n", strerror(-ret));
        return 1;
    }
    fifo[TS_FIFO_RDFR / 4] = TS_FIFO_RESET_KEY;
    fifo[TS_FIFO_ISR / 4] = 0xFFFFFFFFu;

    uint32_t *lat = malloc((size_t)n * sizeof(*lat));
    if (!lat) {
        ts_uio_unmap(fifo, fifo_size);
        return 1;
    }

    long timeouts = 0;
    long got = 0;
    struct timespec next;
    clock_gettime(CLOCK_MONOTONIC, &next);
    for (long i = 0; i < n; i++) {
        sleep_until_next(&next, period_ns);
        uint32_t c0 = ts_counter();
        ts_toggle(ch);
        uint32_t ts_lo;
        if (wait_event(fifo, ch, &ts_lo) != 0) {
            timeouts++;
            continue;
        }
        lat[got++] = ts_lo - c0;
    }
    ts_uio_unmap(fifo, fifo_size);

    if (argc == 4) {
        FILE *f = fopen(argv[3], "w");
        if (f) {
            for (long i = 0; i < got; i++)
                fprintf(f, "%u\n", lat[i]);
            fclose(f);
        } else {
            perror(argv[3]);
        }
    }

    if (got == 0) {
        fprintf(stderr, "no events received (%ld timeouts)\n", timeouts);
        free(lat);
        return 1;
    }

    qsort(lat, (size_t)got, sizeof(*lat), cmp_u32);
    double sum = 0;
    for (long i = 0; i < got; i++)
        sum += lat[i];

    printf("samples %ld  timeouts %ld  (ticks / ns)\n", got, timeouts);
    printf("  min    %6u / %8.0f\n", lat[0], lat[0] * NS_PER_TICK);
    printf("  median %6u / %8.0f\n", lat[got / 2], lat[got / 2] * NS_PER_TICK);
    printf("  p99    %6u / %8.0f\n", lat[got * 99 / 100], lat[got * 99 / 100] * NS_PER_TICK);
    printf("  max    %6u / %8.0f\n", lat[got - 1], lat[got - 1] * NS_PER_TICK);
    printf("  mean   %8.1f / %8.0f\n", sum / got, sum / got * NS_PER_TICK);

    free(lat);
    return timeouts ? 1 : 0;
}

static void usage(void)
{
    fprintf(stderr,
            "usage: ts_test toggle  <n> <period_us> <ch>\n"
            "       ts_test clock   [seconds]\n"
            "       ts_test latency <n> <period_us> <ch> [samples.txt]\n");
}

int main(int argc, char **argv)
{
    if (argc < 2) {
        usage();
        return 2;
    }

    int ret = ts_open();
    if (ret != 0) {
        fprintf(stderr, "ts_open: %s\n", strerror(-ret));
        return 1;
    }

    const char *cmd = argv[1];
    if (strcmp(cmd, "toggle") == 0)
        ret = cmd_toggle(argc - 2, argv + 2);
    else if (strcmp(cmd, "clock") == 0)
        ret = cmd_clock(argc - 2, argv + 2);
    else if (strcmp(cmd, "latency") == 0)
        ret = cmd_latency(argc - 2, argv + 2);
    else {
        usage();
        ret = 2;
    }

    ts_close();
    return ret;
}
