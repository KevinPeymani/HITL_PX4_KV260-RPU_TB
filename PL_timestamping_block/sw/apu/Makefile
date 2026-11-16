CROSS_COMPILE ?= aarch64-linux-gnu-
CC            := $(CROSS_COMPILE)gcc
CFLAGS        ?= -O2
CFLAGS        += -std=gnu11 -Wall -Wextra
LDLIBS        += -lpthread
BUILD         ?= build

BOARD         ?= petalinux@10.11.0.77
DEST          ?= ts_bench

BINS := $(BUILD)/ts_reader $(BUILD)/ts_test

all: $(BINS)

$(BUILD):
	mkdir -p $@

$(BUILD)/%.o: %.c ts_apu.h | $(BUILD)
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@

$(BUILD)/ts_reader: $(BUILD)/ts_reader.o $(BUILD)/ts_apu.o
	$(CC) $(LDFLAGS) $^ $(LDLIBS) -o $@

$(BUILD)/ts_test: $(BUILD)/ts_test.o $(BUILD)/ts_apu.o
	$(CC) $(LDFLAGS) $^ $(LDLIBS) -o $@

# Copies the binaries to ~/$(DEST) on the board (needs ssh key login).
deploy: all
	ssh $(BOARD) mkdir -p $(DEST)
	scp $(BINS) $(BOARD):$(DEST)/

clean:
	rm -rf $(BUILD)

.PHONY: all deploy clean
