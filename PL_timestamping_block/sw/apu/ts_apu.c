#include "ts_apu.h"

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

/* 1: read GPIO_DATA back so the toggle reaches the PL before ts_toggle() returns. */
#ifndef TS_FLUSH_WRITES
#define TS_FLUSH_WRITES 1
#endif

static volatile uint32_t *gpio;
static size_t gpio_size;
static uint32_t shadow;
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;

static int read_sysfs_hex(const char *path, uint64_t *val)
{
    FILE *f = fopen(path, "r");
    if (!f)
        return -errno;
    int n = fscanf(f, "%" SCNx64, val);
    fclose(f);
    return n == 1 ? 0 : -EINVAL;
}

int ts_uio_map(uint32_t phys, volatile uint32_t **regs, size_t *size)
{
    DIR *dir = opendir("/sys/class/uio");
    if (!dir)
        return -errno;

    int ret = -ENODEV;
    struct dirent *e;
    while ((e = readdir(dir))) {
        if (strncmp(e->d_name, "uio", 3) != 0)
            continue;

        char path[300];
        uint64_t addr, len;
        snprintf(path, sizeof(path), "/sys/class/uio/%s/maps/map0/addr", e->d_name);
        if (read_sysfs_hex(path, &addr) != 0 || addr != phys)
            continue;

        snprintf(path, sizeof(path), "/sys/class/uio/%s/maps/map0/size", e->d_name);
        ret = read_sysfs_hex(path, &len);
        if (ret != 0)
            break;

        snprintf(path, sizeof(path), "/dev/%s", e->d_name);
        int fd = open(path, O_RDWR | O_SYNC);
        if (fd < 0) {
            ret = -errno;
            break;
        }

        /* UIO selects map N with offset N * page size; map0 is offset 0. */
        void *p = mmap(NULL, len, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
        ret = (p == MAP_FAILED) ? -errno : 0;
        close(fd);
        if (ret == 0) {
            *regs = p;
            *size = len;
        }
        break;
    }

    closedir(dir);
    return ret;
}

void ts_uio_unmap(volatile uint32_t *regs, size_t size)
{
    if (regs)
        munmap((void *)regs, size);
}

static void write_data(uint32_t v)
{
    gpio[TS_GPIO_DATA / 4] = v;
#if TS_FLUSH_WRITES
    (void)gpio[TS_GPIO_DATA / 4];
#endif
}

int ts_open(void)
{
    if (gpio)
        return 0;

    int ret = ts_uio_map(TS_GPIO_APU_BASE, &gpio, &gpio_size);
    if (ret != 0)
        return ret;

    /* Adopts the current output levels; writing them here would create edges. */
    pthread_mutex_lock(&lock);
    shadow = gpio[TS_GPIO_DATA / 4] & ((1u << TS_NUM_CH) - 1);
    pthread_mutex_unlock(&lock);
    return 0;
}

void ts_close(void)
{
    ts_uio_unmap(gpio, gpio_size);
    gpio = NULL;
    gpio_size = 0;
}

void ts_toggle(unsigned ch)
{
    if (ch >= TS_NUM_CH || !gpio)
        return;

    /* The write stays inside the lock so a stale shadow can't land after a newer one. */
    pthread_mutex_lock(&lock);
    shadow ^= 1u << ch;
    write_data(shadow);
    pthread_mutex_unlock(&lock);
}

void ts_set(unsigned ch, int level)
{
    if (ch >= TS_NUM_CH || !gpio)
        return;

    pthread_mutex_lock(&lock);
    if (level)
        shadow |= 1u << ch;
    else
        shadow &= ~(1u << ch);
    write_data(shadow);
    pthread_mutex_unlock(&lock);
}

uint32_t ts_counter(void)
{
    return gpio ? gpio[TS_GPIO2_DATA / 4] : 0;
}
