#ifndef TS_APU_H
#define TS_APU_H

#include <stddef.h>
#include <stdint.h>

#define TS_GPIO_APU_BASE  0xA0010000u
#define TS_FIFO_BASE      0xA0000000u

/* AXI GPIO register offsets (PG144). */
#define TS_GPIO_DATA      0x0
#define TS_GPIO_TRI       0x4
#define TS_GPIO2_DATA     0x8
#define TS_GPIO2_TRI      0xC

/* AXI4-Stream FIFO register offsets (PG080), AXI4-Lite data interface. */
#define TS_FIFO_ISR       0x00
#define TS_FIFO_RDFR      0x18
#define TS_FIFO_RDFO      0x1C
#define TS_FIFO_RDFD      0x20
#define TS_FIFO_RLR       0x24

#define TS_FIFO_RESET_KEY 0xA5
#define TS_ISR_RX_ERR     0xE0000000u  /* RPURE | RPORE | RPUE */
#define TS_RLR_LEN_MASK   0x007FFFFFu

/* Event word 1 fields; word 0 is ts[31:0]. */
#define TS_EV_BYTES       8
#define TS_EV_OVF(w1)     ((w1) >> 31)
#define TS_EV_CHANGE(w1)  (((w1) >> 20) & 0xFFu)

#define TS_NUM_CH         4

enum ts_ch {
    TS_CH_SENSOR_TX = 0,  /* HIL_SENSOR written into RPMsg */
    TS_CH_ACT_RX    = 1,  /* actuator message read from RPMsg */
    TS_CH_SPARE2    = 2,
    TS_CH_SPARE3    = 3,
};

/* Maps the UIO device whose map0 starts at phys; returns 0 or -errno. */
int  ts_uio_map(uint32_t phys, volatile uint32_t **regs, size_t *size);
void ts_uio_unmap(volatile uint32_t *regs, size_t size);

/* Maps gpio_apu and keeps the current output levels; returns 0 or -errno. */
int  ts_open(void);
void ts_close(void);

/* ch must be 0..TS_NUM_CH-1; other values are ignored. */
void ts_toggle(unsigned ch);
void ts_set(unsigned ch, int level);

/* PL counter bits [31:0]; wraps every ~42.9 s. */
uint32_t ts_counter(void);

#endif
