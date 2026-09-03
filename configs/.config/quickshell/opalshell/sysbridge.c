/* =============================================================================
 * sysbridge.c — QuickShell System Metrics Bridge
 *
 * Provides lightweight, zero-fork system metric polling by reading
 * /proc and /sys directly. Called from QML via Quickshell.Io.Process
 * as a simple CLI:  ./sysbridge <command>
 *
 * Commands:
 *   cpu          → CPU usage percentage (double, 0–100)
 *   memory       → Memory usage percentage (double, 0–100)
 *   disk [path]  → Disk usage percentage for path (default /)
 *   temp         → CPU temperature in Celsius (double)
 *   battery      → Battery capacity percentage (int, -1 if absent)
 *   batstatus    → Battery status string (Charging/Discharging/Full/…)
 *   brightness   → Brightness percentage (int, 0–100, -1 if absent)
 *   network      → JSON object with type/ifname/ip/ssid/signal/connected/bytes
 *   all          → Single JSON blob aggregating every metric above
 *
 * All JSON string values are properly escaped via json_str() to prevent
 * injection from malicious SSIDs, interface names, etc.
 *
 * Compile:  gcc -O2 -Wall -Wextra -o sysbridge sysbridge.c
 * ============================================================================= */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <dirent.h>
#include <sys/statvfs.h>
#include <glob.h>
#include <ctype.h>
#include <ifaddrs.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <net/if.h>

/* ---------------------------------------------------------------------------
 * § JSON HELPERS
 * -------------------------------------------------------------------------- */

/**
 * json_str — Write a JSON-escaped string (with surrounding quotes) to `f`.
 *
 * Handles NULL (emits ""), and escapes: " \ \n \t \r
 * This is critical for safety: network SSIDs, interface names, and
 * battery status strings can contain arbitrary characters.
 */
static void json_str(FILE *f, const char *s) {
    if (!s) { fprintf(f, "\"\""); return; }
    fputc('"', f);
    for (; *s; s++) {
        switch (*s) {
            case '"':  fprintf(f, "\\\""); break;
            case '\\': fprintf(f, "\\\\"); break;
            case '\n': fprintf(f, "\\n");  break;
            case '\t': fprintf(f, "\\t");  break;
            case '\r': fprintf(f, "\\r");  break;
            default:   fputc(*s, f);
        }
    }
    fputc('"', f);
}

/* ---------------------------------------------------------------------------
 * § CPU USAGE — /proc/stat delta method (10 fields)
 *
 * Reads cumulative CPU jiffies from /proc/stat, computes the delta against
 * the previous sample (persisted in CPU_STATE_FILE), and returns a 0–100%
 * utilisation value. Returns 0.0 on the first call (no previous sample).
 * -------------------------------------------------------------------------- */
#define CPU_STATE_FILE "/tmp/.qs_cpu_state"

static double get_cpu_usage(void) {
    FILE *f = fopen("/proc/stat", "r");
    if (!f) return -1.0;

    unsigned long long user=0, nice=0, system=0, idle=0, iowait=0, irq=0, softirq=0, steal=0, guest=0, guest_nice=0;
    char line[256];
    if (fgets(line, sizeof(line), f)) {
        sscanf(line, "cpu %llu %llu %llu %llu %llu %llu %llu %llu %llu %llu",
               &user, &nice, &system, &idle, &iowait, &irq, &softirq, &steal, &guest, &guest_nice);
    }
    fclose(f);

    unsigned long long idle_all = idle + iowait;
    unsigned long long system_all = system + irq + softirq;
    unsigned long long virt_all = guest + guest_nice;
    unsigned long long total = user + nice + system_all + idle_all + steal + virt_all;

    unsigned long long prev_total = 0, prev_idle = 0;
    FILE *sf = fopen(CPU_STATE_FILE, "r");
    if (sf) {
        fscanf(sf, "%llu %llu", &prev_total, &prev_idle);
        fclose(sf);
    }

    sf = fopen(CPU_STATE_FILE, "w");
    if (sf) {
        fprintf(sf, "%llu %llu", total, idle_all);
        fclose(sf);
    }

    if (prev_total == 0 || total <= prev_total) return 0.0;
    unsigned long long d_total = total - prev_total;
    unsigned long long d_idle  = idle_all - prev_idle;
    if (d_total == 0) return 0.0;

    double usage = (double)(d_total - d_idle) / (double)d_total * 100.0;
    if (usage < 0.0) usage = 0.0;
    if (usage > 100.0) usage = 100.0;
    return usage;
}

/* ---------------------------------------------------------------------------
 * § MEMORY USAGE — /proc/meminfo
 *
 * Parses MemTotal + MemAvailable (or fallback fields) to compute the
 * percentage of RAM currently in use. Returns -1.0 on read failure.
 * -------------------------------------------------------------------------- */
static double get_memory_percent(void) {
    FILE *f = fopen("/proc/meminfo", "r");
    if (!f) return -1.0;

    unsigned long mem_total = 0, mem_available = 0, mem_free = 0, buffers = 0, cached = 0, sreclaimable = 0;
    int has_available = 0;
    char line[256];
    while (fgets(line, sizeof(line), f)) {
        if (strncmp(line, "MemTotal:", 9) == 0) sscanf(line + 9, " %lu", &mem_total);
        else if (strncmp(line, "MemAvailable:", 13) == 0) { sscanf(line + 13, " %lu", &mem_available); has_available = 1; }
        else if (strncmp(line, "MemFree:", 8) == 0) sscanf(line + 8, " %lu", &mem_free);
        else if (strncmp(line, "Buffers:", 8) == 0) sscanf(line + 8, " %lu", &buffers);
        else if (strncmp(line, "Cached:", 7) == 0) sscanf(line + 7, " %lu", &cached);
        else if (strncmp(line, "SReclaimable:", 13) == 0) sscanf(line + 13, " %lu", &sreclaimable);
    }
    fclose(f);

    if (mem_total == 0) return -1.0;
    
    unsigned long avail = has_available ? mem_available : (mem_free + buffers + cached + sreclaimable);
    if (avail > mem_total) avail = mem_total;

    return (double)(mem_total - avail) / (double)mem_total * 100.0;
}

/* ---------------------------------------------------------------------------
 * § BLUETOOTH — bluetoothctl (popen)
 *
 * Uses popen("bluetoothctl ...") to query adapter power state and count
 * connected devices. This is the simplest approach for the summary view;
 * the detailed bt_status.c binary uses D-Bus directly for the full popup.
 * -------------------------------------------------------------------------- */
typedef struct {
    char status[16];        /* "on" or "off"           */
    int connected_devices;  /* number of connected BT devices */
} BluetoothInfo;

static void get_bluetooth_details(BluetoothInfo *bt) {
    strcpy(bt->status, "off");
    bt->connected_devices = 0;

    FILE *p = popen("bluetoothctl show 2>/dev/null", "r");
    if (p) {
        char line[256];
        while (fgets(line, sizeof(line), p)) {
            if (strstr(line, "Powered: yes")) {
                strcpy(bt->status, "on");
                break;
            }
        }
        pclose(p);
    }

    if (strcmp(bt->status, "on") == 0) {
        FILE *c = popen("bluetoothctl devices Connected 2>/dev/null", "r");
        if (c) {
            char line[256];
            while (fgets(line, sizeof(line), c)) {
                if (strncmp(line, "Device", 6) == 0) {
                    bt->connected_devices++;
                }
            }
            pclose(c);
        }
    }
}

/* ---------------------------------------------------------------------------
 * § AUDIO — wpctl (WirePlumber)
 *
 * Queries the default audio sink volume and mute state via popen("wpctl").
 * -------------------------------------------------------------------------- */
typedef struct {
    int volume;  /* 0–100 percentage */
    int muted;   /* 1 = muted, 0 = unmuted */
} AudioInfo;

static void get_audio_details(AudioInfo *audio) {
    audio->volume = 0;
    audio->muted = 0;

    FILE *p = popen("wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null", "r");
    if (p) {
        char line[128];
        if (fgets(line, sizeof(line), p)) {
            float vol = 0;
            if (sscanf(line, "Volume: %f", &vol) == 1) {
                audio->volume = (int)(vol * 100 + 0.5); /* round up slightly for precision */
            }
            if (strstr(line, "MUTED") || strstr(line, "muted")) {
                audio->muted = 1;
            }
        }
        pclose(p);
    }
}

/* ---------------------------------------------------------------------------
 * § DISK USAGE — statvfs(2)
 *
 * Returns percentage of disk used at the given mount path.
 * Uses statvfs for a zero-fork, zero-popen approach.
 * -------------------------------------------------------------------------- */
static double get_disk_percent(const char *path) {
    struct statvfs stat;
    if (statvfs(path, &stat) != 0) return -1.0;

    unsigned long long total = (unsigned long long)stat.f_blocks * stat.f_frsize;
    unsigned long long bfree = (unsigned long long)stat.f_bfree * stat.f_frsize;
    if (total == 0) return 0.0;

    double usage = (double)(total - bfree) / (double)total * 100.0;
    if (usage < 0.0) usage = 0.0;
    if (usage > 100.0) usage = 100.0;
    return usage;
}

/* ---------------------------------------------------------------------------
 * § TEMPERATURE — hwmon coretemp/k10temp/zenpower
 *
 * Scans /sys/class/hwmon for CPU temperature sensors. Prefers coretemp
 * (Intel), k10temp/zenpower (AMD), or thinkpad sensors. Falls back to
 * thermal_zone0 if no hwmon match is found. Returns max reading in °C.
 * -------------------------------------------------------------------------- */
static double get_temperature(void) {
    glob_t g;
    double max_temp = -1.0;
    /* Look in hwmon */
    if (glob("/sys/class/hwmon/hwmon*/temp*_input", 0, NULL, &g) == 0) {
        for (size_t i = 0; i < g.gl_pathc; i++) {
            char name_path[512];
            strncpy(name_path, g.gl_pathv[i], sizeof(name_path) - 1);
            char *last_slash = strrchr(name_path, '/');
            if (last_slash) {
                strcpy(last_slash + 1, "name");
                FILE *nf = fopen(name_path, "r");
                if (nf) {
                    char name[64] = {0};
                    fgets(name, sizeof(name), nf);
                    fclose(nf);
                    if (strstr(name, "coretemp") || strstr(name, "k10temp") || strstr(name, "zenpower") || strstr(name, "thinkpad")) {
                        FILE *tf = fopen(g.gl_pathv[i], "r");
                        if (tf) {
                            int millideg = 0;
                            if (fscanf(tf, "%d", &millideg) == 1) {
                                double t = millideg / 1000.0;
                                if (t > max_temp && t < 150.0) max_temp = t;
                            }
                            fclose(tf);
                        }
                    }
                }
            }
        }
        globfree(&g);
    }
    
    /* Fallback to thermal_zone0 if hwmon failed */
    if (max_temp < 0) {
        FILE *f = fopen("/sys/class/thermal/thermal_zone0/temp", "r");
        if (f) {
            int millideg = 0;
            if (fscanf(f, "%d", &millideg) == 1) {
                max_temp = millideg / 1000.0;
            }
            fclose(f);
        }
    }
    
    return max_temp;
}

/* ---------------------------------------------------------------------------
 * § BATTERY — /sys/class/power_supply/BAT*
 *
 * Reads capacity (0–100%) and status string from the first BAT* sysfs entry.
 * Returns -1 / "Unknown" if no battery is present (e.g. desktop PC).
 * -------------------------------------------------------------------------- */
static const char* find_battery_path(void) {
    static char path[512];
    glob_t g;
    if (glob("/sys/class/power_supply/BAT*", 0, NULL, &g) != 0) {
        globfree(&g);
        return NULL;
    }
    if (g.gl_pathc > 0)
        strncpy(path, g.gl_pathv[0], sizeof(path) - 1);
    else
        path[0] = '\0';
    globfree(&g);
    return path[0] ? path : NULL;
}

static int get_battery_capacity(void) {
    const char *base = find_battery_path();
    if (!base) return -1;

    char fpath[600];
    snprintf(fpath, sizeof(fpath), "%s/capacity", base);
    FILE *f = fopen(fpath, "r");
    if (!f) return -1;

    int cap;
    if (fscanf(f, "%d", &cap) != 1) cap = -1;
    fclose(f);
    return cap;
}

static const char* get_battery_status(void) {
    const char *base = find_battery_path();
    if (!base) return "Unknown";

    char fpath[600];
    snprintf(fpath, sizeof(fpath), "%s/status", base);
    FILE *f = fopen(fpath, "r");
    if (!f) return "Unknown";

    static char status[64];
    if (fgets(status, sizeof(status), f)) {
        /* Trim newline */
        size_t len = strlen(status);
        if (len > 0 && status[len-1] == '\n') status[len-1] = '\0';
    } else {
        strcpy(status, "Unknown");
    }
    fclose(f);
    return status;
}

/* ---------------------------------------------------------------------------
 * § BRIGHTNESS — /sys/class/backlight
 *
 * Reads current and max brightness from the first backlight device,
 * returns a 0–100% value. Returns -1 if no backlight is found (desktop).
 * -------------------------------------------------------------------------- */
static int get_brightness_percent(void) {
    glob_t g;
    if (glob("/sys/class/backlight/*/brightness", 0, NULL, &g) != 0) {
        globfree(&g);
        return -1;
    }
    if (g.gl_pathc == 0) { globfree(&g); return -1; }

    /* Get current brightness */
    FILE *f = fopen(g.gl_pathv[0], "r");
    if (!f) { globfree(&g); return -1; }
    int current;
    if (fscanf(f, "%d", &current) != 1) { fclose(f); globfree(&g); return -1; }
    fclose(f);

    /* Get max brightness — replace "brightness" with "max_brightness" in path */
    char max_path[600];
    strncpy(max_path, g.gl_pathv[0], sizeof(max_path) - 1);
    globfree(&g);

    char *last_slash = strrchr(max_path, '/');
    if (last_slash) strcpy(last_slash + 1, "max_brightness");

    f = fopen(max_path, "r");
    if (!f) return -1;
    int max_val;
    if (fscanf(f, "%d", &max_val) != 1) { fclose(f); return -1; }
    fclose(f);

    if (max_val == 0) return 0;
    return (current * 100) / max_val;
}

/* ---------------------------------------------------------------------------
 * § NETWORK — IP, type, signal, bandwidth via getifaddrs + /proc/net/dev
 *
 * Determines the primary network interface via getifaddrs(), classifies it
 * as wifi/ethernet/vpn by interface name prefix, reads WiFi extras (SSID,
 * signal) via popen("iw"), and computes per-second bandwidth deltas from
 * /proc/net/dev counters persisted in NET_STATE_FILE.
 * -------------------------------------------------------------------------- */
#define NET_STATE_FILE "/tmp/.qs_net_state"

typedef struct {
    char type[32];      /* "wifi", "ethernet", "vpn", or "disconnected" */
    char ifname[32];    /* kernel interface name, e.g. "wlan0", "enp3s0"  */
    char ip[64];        /* IPv4 address string, e.g. "192.168.1.5"       */
    char ssid[128];     /* WiFi SSID (may contain special chars!)         */
    int signal_pct;     /* WiFi signal strength 0–100, 0 for non-wifi    */
    int connected;      /* 1 = has an active IPv4 address, 0 = down      */
    unsigned long long up_bytes_sec;   /* upload bytes/sec   */
    unsigned long long down_bytes_sec; /* download bytes/sec */
} NetworkInfo;

/** Return current wall-clock time in milliseconds (for bandwidth deltas). */
static long long get_current_time_ms(void) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (long long)tv.tv_sec * 1000 + tv.tv_usec / 1000;
}

static void get_network_details(NetworkInfo *net) {
    memset(net, 0, sizeof(NetworkInfo));
    strcpy(net->type, "disconnected");
    strcpy(net->ifname, "");
    strcpy(net->ip, "");
    strcpy(net->ssid, "");
    net->signal_pct = 0;
    net->connected = 0;
    net->up_bytes_sec = 0;
    net->down_bytes_sec = 0;

    struct ifaddrs *ifaddr, *ifa;
    if (getifaddrs(&ifaddr) == -1) return;

    /* 1. Find the primary active interface */
    for (ifa = ifaddr; ifa != NULL; ifa = ifa->ifa_next) {
        if (ifa->ifa_addr == NULL) continue;
        if (ifa->ifa_flags & IFF_LOOPBACK) continue;
        if (!(ifa->ifa_flags & IFF_UP) || !(ifa->ifa_flags & IFF_RUNNING)) continue;
        
        if (ifa->ifa_addr->sa_family == AF_INET) {
            strncpy(net->ifname, ifa->ifa_name, sizeof(net->ifname) - 1);
            struct sockaddr_in *pAddr = (struct sockaddr_in *)ifa->ifa_addr;
            inet_ntop(AF_INET, &pAddr->sin_addr, net->ip, sizeof(net->ip));
            net->connected = 1;
            
            if (strncmp(net->ifname, "w", 1) == 0) strcpy(net->type, "wifi");
            else if (strncmp(net->ifname, "e", 1) == 0) strcpy(net->type, "ethernet");
            else strcpy(net->type, "vpn");
            
            break; // take first valid interface
        }
    }
    freeifaddrs(ifaddr);

    if (!net->connected) return;

    /* 2. WiFi Extras */
    if (strcmp(net->type, "wifi") == 0) {
        char cmd[128];
        snprintf(cmd, sizeof(cmd), "iw dev %s link 2>/dev/null", net->ifname);
        FILE *p = popen(cmd, "r");
        if (p) {
            char line[256];
            while (fgets(line, sizeof(line), p)) {
                if (strstr(line, "SSID: ")) {
                    char *val = strstr(line, "SSID: ") + 6;
                    strncpy(net->ssid, val, sizeof(net->ssid) - 1);
                    size_t len = strlen(net->ssid);
                    if (len > 0 && net->ssid[len-1] == '\n') net->ssid[len-1] = '\0';
                }
                else if (strstr(line, "signal: ")) {
                    int dbm = atoi(strstr(line, "signal: ") + 8);
                    /* Convert dBm to rough percentage. Usually -50 is 100%, -100 is 0% */
                    int pct = (dbm + 100) * 2;
                    if (pct < 0) pct = 0;
                    if (pct > 100) pct = 100;
                    net->signal_pct = pct;
                }
            }
            pclose(p);
        }
    }

    /* 3. Bandwidth Bytes */
    unsigned long long rx = 0, tx = 0;
    FILE *f = fopen("/proc/net/dev", "r");
    if (f) {
        char line[512];
        while (fgets(line, sizeof(line), f)) {
            char iface[32];
            if (sscanf(line, " %31[^:]:", iface) == 1 && strcmp(iface, net->ifname) == 0) {
                char *colon = strchr(line, ':');
                if (colon) {
                    unsigned long long dummy;
                    sscanf(colon + 1, "%llu %llu %llu %llu %llu %llu %llu %llu %llu",
                           &rx, &dummy, &dummy, &dummy, &dummy, &dummy, &dummy, &dummy, &tx);
                }
                break;
            }
        }
        fclose(f);
    }

    /* 4. Bandwidth Deltas */
    long long now = get_current_time_ms();
    FILE *sf = fopen(NET_STATE_FILE, "r");
    if (sf) {
        long long prev_time;
        unsigned long long prev_rx, prev_tx;
        if (fscanf(sf, "%lld %llu %llu", &prev_time, &prev_rx, &prev_tx) == 3) {
            long long time_diff = now - prev_time;
            if (time_diff > 0 && time_diff < 10000) { 
                if (rx >= prev_rx) net->down_bytes_sec = ((rx - prev_rx) * 1000ULL) / time_diff;
                if (tx >= prev_tx) net->up_bytes_sec = ((tx - prev_tx) * 1000ULL) / time_diff;
            }
        }
        fclose(sf);
    }

    sf = fopen(NET_STATE_FILE, "w");
    if (sf) {
        fprintf(sf, "%lld %llu %llu\n", now, rx, tx);
        fclose(sf);
    }
}

/* ---------------------------------------------------------------------------
 * § MAIN — CLI dispatcher
 *
 * Each command prints its result to stdout and exits immediately.
 * The "all" command aggregates every metric into a single JSON object
 * so the QML side only needs one process spawn per polling tick.
 * -------------------------------------------------------------------------- */
int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "Usage: sysbridge <command>\n");
        return 1;
    }

    const char *cmd = argv[1];

    if (strcmp(cmd, "cpu") == 0) {
        printf("%.1f\n", get_cpu_usage());
    }
    else if (strcmp(cmd, "memory") == 0) {
        printf("%.1f\n", get_memory_percent());
    }
    else if (strcmp(cmd, "disk") == 0) {
        const char *path = argc > 2 ? argv[2] : "/";
        printf("%.1f\n", get_disk_percent(path));
    }
    else if (strcmp(cmd, "temp") == 0) {
        printf("%.1f\n", get_temperature());
    }
    else if (strcmp(cmd, "battery") == 0) {
        printf("%d\n", get_battery_capacity());
    }
    else if (strcmp(cmd, "batstatus") == 0) {
        printf("%s\n", get_battery_status());
    }
    else if (strcmp(cmd, "brightness") == 0) {
        printf("%d\n", get_brightness_percent());
    }
    else if (strcmp(cmd, "network") == 0) {
        NetworkInfo net;
        get_network_details(&net);
        /* Use json_str() for all string fields to prevent injection from
         * malicious SSIDs or interface names containing " or \ chars. */
        FILE *out = stdout;
        fprintf(out, "{\"type\":");
        json_str(out, net.type);
        fprintf(out, ",\"ifname\":");
        json_str(out, net.ifname);
        fprintf(out, ",\"ip\":");
        json_str(out, net.ip);
        fprintf(out, ",\"ssid\":");
        json_str(out, net.ssid);
        fprintf(out, ",\"signal\":%d,\"connected\":%s,\"upBytes\":%llu,\"downBytes\":%llu}\n",
               net.signal_pct, net.connected ? "true" : "false",
               net.up_bytes_sec, net.down_bytes_sec);
    }
    else if (strcmp(cmd, "all") == 0) {
        /* Single call for all metrics — minimizes process spawns from QML.
         * All string values go through json_str() for safety. */
        double cpu  = get_cpu_usage();
        double mem  = get_memory_percent();
        double disk = get_disk_percent("/");
        double temp = get_temperature();
        int bat  = get_battery_capacity();
        const char *bstat = get_battery_status();
        int bright = get_brightness_percent();

        NetworkInfo net;
        get_network_details(&net);

        BluetoothInfo bt;
        get_bluetooth_details(&bt);

        AudioInfo audio;
        get_audio_details(&audio);

        FILE *out = stdout;
        fprintf(out, "{\"cpu\":%.1f,\"memory\":%.1f,\"disk\":%.1f,\"temp\":%.1f,"
               "\"battery\":%d,\"batteryStatus\":", cpu, mem, disk, temp, bat);
        json_str(out, bstat);
        fprintf(out, ",\"brightness\":%d,\"network\":{\"type\":", bright);
        json_str(out, net.type);
        fprintf(out, ",\"ifname\":");
        json_str(out, net.ifname);
        fprintf(out, ",\"ip\":");
        json_str(out, net.ip);
        fprintf(out, ",\"ssid\":");
        json_str(out, net.ssid);
        fprintf(out, ",\"signal\":%d,\"connected\":%s,\"upBytes\":%llu,\"downBytes\":%llu},"
               "\"bluetooth\":{\"status\":",
               net.signal_pct, net.connected ? "true" : "false",
               net.up_bytes_sec, net.down_bytes_sec);
        json_str(out, bt.status);
        fprintf(out, ",\"connected\":%d},"
               "\"audio\":{\"volume\":%d,\"muted\":%s}}\n",
               bt.connected_devices, audio.volume,
               audio.muted ? "true" : "false");
    }
    else {
        fprintf(stderr, "Unknown command: %s\n", cmd);
        return 1;
    }

    return 0;
}
