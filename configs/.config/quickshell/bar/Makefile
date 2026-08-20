# ==============================================================================
# QuickShell Bar — Build System
# Compiles sysbridge.c and standalone network/bluetooth polling backends.
# ==============================================================================

CC      := gcc
CFLAGS  := -O2 -Wall -Wextra -pedantic

# Targets
SYSBRIDGE := sysbridge
ETH       := scripts/eth_status
WIFI      := scripts/wifi_status
BT        := scripts/bt_status

.PHONY: all clean install

all: $(SYSBRIDGE) $(ETH) $(WIFI) $(BT)

$(SYSBRIDGE): sysbridge.c
	$(CC) $(CFLAGS) -o $@ $<

$(ETH): scripts/eth_status.c
	$(CC) $(CFLAGS) -o $@ $< $$(pkg-config --cflags --libs libnm)

$(WIFI): scripts/wifi_status.c
	$(CC) $(CFLAGS) -o $@ $< $$(pkg-config --cflags --libs libnm) -lm

$(BT): scripts/bt_status.c
	$(CC) $(CFLAGS) -o $@ $< $$(pkg-config --cflags --libs dbus-1)

clean:
	rm -f $(SYSBRIDGE) $(ETH) $(WIFI) $(BT)

# Install to ~/.local/bin for system-wide access (optional)
install: $(SYSBRIDGE)
	install -Dm755 $(SYSBRIDGE) $(HOME)/.local/bin/$(SYSBRIDGE)
