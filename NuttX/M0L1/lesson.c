#include <stdint.h>

#define UART0_BASE 0xFF000000u
#define UART_SR    (*(volatile uint32_t *)(UART0_BASE + 0x2C))
#define UART_FIFO  (*(volatile uint32_t *)(UART0_BASE + 0x30))
#define SR_TXFULL  (1u << 4)
#define REG32(addr) (*(volatile uint32_t *)(addr))
#define UART_TXEN  0x04
#define UART_TXDIS 0x05

static inline void reg32_modify(uintptr_t addr, uint32_t clear_mask, uint32_t set_mask) 
{
    // Read
    uint32_t read_value = REG32(addr);
    
    // Modify 
    uint32_t cleared_value = read_value & ~clear_mask;
    uint32_t set_value = cleared_value | set_mask;
    
    // Write
    REG32(addr) = set_value;

}

void uart_tx_enable(void)
{
    reg32_modify(UART0_BASE, ((1u << UART_TXEN) | (1u << UART_TXDIS)), ((1u << UART_TXEN) | 0u << (UART_TXDIS)));

}

void putc_polled(char c)
{
    while (UART_SR & SR_TXFULL)
        ;
    UART_FIFO = c;
}

void send_abc(void)
{
    UART_FIFO = 'a';
    UART_FIFO = 'b';
    UART_FIFO = 'c';
}