#define _GNU_SOURCE
#include "ts_apu.h"

#include <errno.h>
#include <signal.h>
#include <sched.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#define BUF_WORDS       1024
#define CLK_HZ_NOMINAL  100000000u

/* File layout: this header, then raw 8-byte events (word 0, word 1), little-endian. */
struct ts_log_hdr {
    char     magic[8];
    uint32_t version;
    uint32_t clk_hz;
    uint64_t start_realtime_ns;
    uint64_t start_monotonic_ns;
};
_Static_assert(sizeof(struct ts_log_hdr) == 32, "log header must be 32 bytes");

struct stats {
    uint64_t events;
    uint64_t ovf;
    uint64_t bad_len;
    uint64_t rx_err;
    uint64_t ch[8];
};

static volatile uint32_t *fifo;
static volatile sig_atomic_t running = 1;

#define REG(off) fifo[(off) / 4]

static void on_signal(int sig)
{
    (void)sig;
    running = 0;
}

static uint64_t now_ns(clockid_t clk)
{
    struct timespec ts;
    clock_gettime(clk, &ts);
    return (uint64_t)ts.tv_sec * 1000000000u + (uint64_t)ts.tv_nsec;
}

static void rx_reset(void)
{
    REG(TS_FIFO_RDFR) = TS_FIFO_RESET_KEY;
    REG(TS_FIFO_ISR) = 0xFFFFFFFFu;
}

/* Reads complete packets into buf; returns the number of words stored. */
static size_t drain(uint32_t *buf, struct stats *st)
{
    size_t n = 0;
    uint32_t occ = REG(TS_FIFO_RDFO);

    while (occ > 0 && n + 2 <= BUF_WORDS) {
        uint32_t len = REG(TS_FIFO_RLR) & TS_RLR_LEN_MASK;
        uint32_t words = (len + 3) / 4;

        if (words == 0) {
            st->bad_len++;
            break;
        }
        if (len != TS_EV_BYTES) {
            /* Partial packet from a reset mid-event: discard its words. */
            for (uint32_t i = 0; i < words; i++)
                (void)REG(TS_FIFO_RDFD);
            st->bad_len++;
        } else {
            uint32_t w0 = REG(TS_FIFO_RDFD);
            uint32_t w1 = REG(TS_FIFO_RDFD);
            buf[n++] = w0;
            buf[n++] = w1;

            st->events++;
            st->ovf += TS_EV_OVF(w1);
            for (unsigned b = 0, chg = TS_EV_CHANGE(w1); chg; b++, chg >>= 1)
                st->ch[b] += chg & 1u;
        }
        occ -= (words < occ) ? words : occ;
    }
    return n;
}

static int drain_to_file(FILE *out, struct stats *st)
{
    uint32_t buf[BUF_WORDS];
    size_t n;

    do {
        n = drain(buf, st);
        if (n && fwrite(buf, sizeof(buf[0]), n, out) != n)
            return -1;
    } while (n + 2 > BUF_WORDS);

    return fflush(out) == 0 ? 0 : -1;
}

static int setup_rt(int cpu, int prio)
{
    if (cpu >= 0) {
        cpu_set_t set;
        CPU_ZERO(&set);
        CPU_SET(cpu, &set);
        if (sched_setaffinity(0, sizeof(set), &set) != 0) {
            perror("sched_setaffinity");
            return -1;
        }
    }
    if (prio > 0) {
        struct sched_param sp = { .sched_priority = prio };
        if (sched_setscheduler(0, SCHED_FIFO, &sp) != 0) {
            perror("sched_setscheduler");
            return -1;
        }
        if (mlockall(MCL_CURRENT | MCL_FUTURE) != 0) {
            perror("mlockall");
            return -1;
        }
    }
    return 0;
}

static void usage(const char *prog)
{
    fprintf(stderr,
            "usage: %s [-o file] [-p poll_us] [-t seconds] [-c cpu] [-r rtprio]\n"
            "  -o  output log (default ts.bin)\n"
            "  -p  poll period in us (default 2000)\n"
            "  -t  stop after this many seconds (default 0 = until SIGINT)\n"
            "  -c  pin to this CPU\n"
            "  -r  run SCHED_FIFO at this priority\n",
            prog);
}

int main(int argc, char **argv)
{
    const char *path = "ts.bin";
    long poll_us = 2000;
    long seconds = 0;
    int cpu = -1;
    int prio = 0;
    int opt;

    while ((opt = getopt(argc, argv, "o:p:t:c:r:h")) != -1) {
        switch (opt) {
        case 'o': path = optarg; break;
        case 'p': poll_us = strtol(optarg, NULL, 0); break;
        case 't': seconds = strtol(optarg, NULL, 0); break;
        case 'c': cpu = (int)strtol(optarg, NULL, 0); break;
        case 'r': prio = (int)strtol(optarg, NULL, 0); break;
        default:  usage(argv[0]); return opt == 'h' ? 0 : 2;
        }
    }
    if (poll_us <= 0 || seconds < 0) {
        usage(argv[0]);
        return 2;
    }

    size_t fifo_size;
    int ret = ts_uio_map(TS_FIFO_BASE, &fifo, &fifo_size);
    if (ret != 0) {
        fprintf(stderr, "ts_uio_map(0x%08x): %s\n", TS_FIFO_BASE, strerror(-ret));
        return 1;
    }

    FILE *out = fopen(path, "wb");
    if (!out) {
        perror(path);
        return 1;
    }

    if (setup_rt(cpu, prio) != 0)
        return 1;

    struct sigaction sa = { .sa_handler = on_signal };
    sigaction(SIGINT, &sa, NULL);
    sigaction(SIGTERM, &sa, NULL);

    rx_reset();

    struct ts_log_hdr hdr = {
        .version = 1,
        .clk_hz = CLK_HZ_NOMINAL,
        .start_realtime_ns = now_ns(CLOCK_REALTIME),
        .start_monotonic_ns = now_ns(CLOCK_MONOTONIC),
    };
    memcpy(hdr.magic, "TSLOG", 5);
    if (fwrite(&hdr, sizeof(hdr), 1, out) != 1) {
        perror("write header");
        return 1;
    }

    struct stats st = { 0 };
    uint64_t period_ns = (uint64_t)poll_us * 1000u;
    uint64_t end_ns = seconds ? hdr.start_monotonic_ns + (uint64_t)seconds * 1000000000u : 0;
    struct timespec next;
    clock_gettime(CLOCK_MONOTONIC, &next);

    while (running) {
        if (drain_to_file(out, &st) != 0) {
            perror("write log");
            break;
        }

        uint32_t isr = REG(TS_FIFO_ISR);
        if (isr & TS_ISR_RX_ERR) {
            st.rx_err++;
            rx_reset();
        }

        if (end_ns && now_ns(CLOCK_MONOTONIC) >= end_ns)
            break;

        next.tv_nsec += (long)period_ns;
        while (next.tv_nsec >= 1000000000L) {
            next.tv_nsec -= 1000000000L;
            next.tv_sec++;
        }
        clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &next, NULL);
    }

    drain_to_file(out, &st);
    fclose(out);
    ts_uio_unmap(fifo, fifo_size);

    fprintf(stderr, "events %llu  ovf %llu  bad_len %llu  rx_err %llu\n",
            (unsigned long long)st.events, (unsigned long long)st.ovf,
            (unsigned long long)st.bad_len, (unsigned long long)st.rx_err);
    for (int c = 0; c < 8; c++)
        fprintf(stderr, "  ch%d %llu\n", c, (unsigned long long)st.ch[c]);

    return 0;
}
