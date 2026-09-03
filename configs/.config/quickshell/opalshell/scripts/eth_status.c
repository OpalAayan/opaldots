/*
 * eth_status.c — Ethernet status via libnm (NetworkManager C API)
 * Drop-in replacement for eth_panel_logic.sh
 *
 * Output: JSON object matching the bash script's format.
 * String fields are safely JSON-escaped via json_str().
 *
 * Compile: gcc -O2 -Wall -Wextra -o eth_status eth_status.c $(pkg-config --cflags --libs libnm)
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <NetworkManager.h>

/**
 * json_str — Write a JSON-escaped string (with surrounding quotes) to `f`.
 * Handles NULL (emits ""), and escapes: " \ \n \t \r
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

/**
 * eth_hw_present — Fast check for ethernet interfaces by scanning /sys/class/net.
 * Looking for interfaces starting with 'e' (like eth0, enp3s0).
 */
static int eth_hw_present(void) {
    DIR *d = opendir("/sys/class/net");
    if (!d) return 0;
    struct dirent *e;
    while ((e = readdir(d))) {
        if (e->d_name[0] == '.') continue;
        if (e->d_name[0] == 'e') { closedir(d); return 1; }
    }
    closedir(d);
    return 0;
}

/** Get the first IPv4 address assigned to an NM device, or NULL if none. */
static const char* get_device_ip(NMDevice *dev) {
    NMIPConfig *ip4 = nm_device_get_ip4_config(dev);
    if (!ip4) return NULL;
    GPtrArray *addrs = nm_ip_config_get_addresses(ip4);
    if (!addrs || addrs->len == 0) return NULL;
    NMIPAddress *a = g_ptr_array_index(addrs, 0);
    return nm_ip_address_get_address(a);
}

int main(void) {
    if (!eth_hw_present()) {
        puts("{\"present\":false,\"power\":\"off\",\"device\":\"\",\"connected\":null}");
        return 0;
    }

    NMClient *client = nm_client_new(NULL, NULL);
    if (!client) {
        puts("{\"present\":false,\"power\":\"off\",\"device\":\"\",\"connected\":null}");
        return 0;
    }

    const GPtrArray *devices = nm_client_get_devices(client);
    NMDeviceEthernet *eth_dev = NULL;
    for (guint i = 0; i < devices->len; i++) {
        NMDevice *d = g_ptr_array_index(devices, i);
        if (NM_IS_DEVICE_ETHERNET(d)) {
            if (!eth_dev) eth_dev = NM_DEVICE_ETHERNET(d);
            NMDeviceState state = nm_device_get_state(d);
            if (state == NM_DEVICE_STATE_ACTIVATED || state == NM_DEVICE_STATE_IP_CONFIG || state == NM_DEVICE_STATE_IP_CHECK) {
                eth_dev = NM_DEVICE_ETHERNET(d);
                break;
            }
        }
    }

    if (!eth_dev) {
        puts("{\"present\":false,\"power\":\"off\",\"device\":\"\",\"connected\":null}");
        g_object_unref(client);
        return 0;
    }

    const char *iface = nm_device_get_iface(NM_DEVICE(eth_dev));
    NMDeviceState state = nm_device_get_state(NM_DEVICE(eth_dev));

    FILE *out = stdout;

    if (state == NM_DEVICE_STATE_ACTIVATED || state == NM_DEVICE_STATE_IP_CONFIG ||
        state == NM_DEVICE_STATE_IP_CHECK) {
        const char *ip = get_device_ip(NM_DEVICE(eth_dev));

        /* Read speed from sysfs */
        char speed_path[256], speed_str[32] = "Unknown";
        snprintf(speed_path, sizeof(speed_path), "/sys/class/net/%s/speed", iface);
        FILE *sf = fopen(speed_path, "r");
        if (sf) {
            int speed;
            if (fscanf(sf, "%d", &speed) == 1 && speed > 0)
                snprintf(speed_str, sizeof(speed_str), "%d Mbps", speed);
            fclose(sf);
        }

        /* Read MAC from sysfs */
        char mac_path[256], mac[32] = "";
        snprintf(mac_path, sizeof(mac_path), "/sys/class/net/%s/address", iface);
        FILE *mf = fopen(mac_path, "r");
        if (mf) {
            if (fgets(mac, sizeof(mac), mf)) {
                mac[strcspn(mac, "\n")] = 0;
            }
            fclose(mf);
        }

        /* Get active connection name */
        const char *profile = "Wired Connection";
        NMActiveConnection *ac = nm_device_get_active_connection(NM_DEVICE(eth_dev));
        if (ac) {
            const char *cid = nm_active_connection_get_id(ac);
            if (cid && cid[0]) profile = cid;
        }

        fprintf(out, "{\"present\":true,\"power\":\"on\",\"device\":");
        json_str(out, iface);
        fprintf(out, ",\"connected\":{\"id\":");
        json_str(out, iface);
        fprintf(out, ",\"name\":");
        json_str(out, profile);
        fprintf(out, ",\"icon\":\"󰈀\",\"ip\":");
        json_str(out, ip ? ip : "No IP");
        fprintf(out, ",\"speed\":");
        json_str(out, speed_str);
        fprintf(out, ",\"mac\":");
        json_str(out, mac);
        fprintf(out, "}}\n");
    } else {
        fprintf(out, "{\"present\":true,\"power\":\"off\",\"device\":");
        json_str(out, iface);
        fprintf(out, ",\"connected\":null}\n");
    }

    g_object_unref(client);
    return 0;
}
