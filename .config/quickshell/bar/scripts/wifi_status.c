/*
 * wifi_status.c — WiFi status via libnm (NetworkManager C API)
 * Drop-in replacement for wifi_panel_logic.sh
 *
 * Output: JSON object with fields:
 *   present  (bool)   — WiFi hardware detected
 *   power    (string) — "on" or "off"
 *   connected (object|null) — active connection details (ssid, signal, ip, …)
 *   networks (array)  — list of available WiFi networks
 *
 * All string values are JSON-escaped via json_str() to handle SSIDs with
 * special characters safely.
 *
 * Compile: gcc -O2 -Wall -Wextra -o wifi_status wifi_status.c $(pkg-config --cflags --libs libnm)
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <math.h>
#include <NetworkManager.h>

/** Map WiFi signal strength (0–100) to a Nerd Font icon glyph. */
static const char* signal_icon(int signal) {
    if (signal >= 80) return "󰤨";
    if (signal >= 60) return "󰤥";
    if (signal >= 40) return "󰤢";
    if (signal >= 20) return "󰤟";
    return "󰤯";
}

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
 * wifi_hw_present — Check if WiFi hardware exists by looking for
 * /sys/class/net/<iface>/wireless directories (faster than libnm init).
 */
static int wifi_hw_present(void) {
    DIR *d = opendir("/sys/class/net");
    if (!d) return 0;
    struct dirent *e;
    while ((e = readdir(d))) {
        if (e->d_name[0] == '.') continue;
        char path[512];
        snprintf(path, sizeof(path), "/sys/class/net/%s/wireless", e->d_name);
        DIR *w = opendir(path);
        if (w) { closedir(w); closedir(d); return 1; }
    }
    closedir(d);
    return 0;
}

/**
 * security_to_str — Convert WPA/RSN security flags to a human-readable string.
 * Checks RSN (WPA2/WPA3) first, then falls back to WPA1 flags.
 */
static const char* security_to_str(NM80211ApSecurityFlags wpa, NM80211ApSecurityFlags rsn) {
    if (rsn & NM_802_11_AP_SEC_KEY_MGMT_SAE) return "WPA3";
    if (rsn & NM_802_11_AP_SEC_KEY_MGMT_802_1X) return "WPA2 802.1X";
    if (rsn & NM_802_11_AP_SEC_KEY_MGMT_PSK) return "WPA2";
    if (wpa & NM_802_11_AP_SEC_KEY_MGMT_802_1X) return "WPA 802.1X";
    if (wpa & NM_802_11_AP_SEC_KEY_MGMT_PSK) return "WPA";
    if ((wpa & NM_802_11_AP_SEC_PAIR_WEP40) || (wpa & NM_802_11_AP_SEC_PAIR_WEP104)) return "WEP";
    return "Open";
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
    if (!wifi_hw_present()) {
        puts("{\"present\":false,\"power\":\"off\",\"connected\":null,\"networks\":[]}");
        return 0;
    }

    NMClient *client = nm_client_new(NULL, NULL);
    if (!client) {
        puts("{\"present\":false,\"power\":\"off\",\"connected\":null,\"networks\":[]}");
        return 0;
    }

    gboolean wifi_enabled = nm_client_wireless_get_enabled(client);
    if (!wifi_enabled) {
        puts("{\"present\":true,\"power\":\"off\",\"connected\":null,\"networks\":[]}");
        g_object_unref(client);
        return 0;
    }

    /* Find WiFi device */
    const GPtrArray *devices = nm_client_get_devices(client);
    NMDeviceWifi *wifi_dev = NULL;
    for (guint i = 0; i < devices->len; i++) {
        NMDevice *d = g_ptr_array_index(devices, i);
        if (NM_IS_DEVICE_WIFI(d)) { wifi_dev = NM_DEVICE_WIFI(d); break; }
    }

    if (!wifi_dev) {
        puts("{\"present\":true,\"power\":\"on\",\"connected\":null,\"networks\":[]}");
        g_object_unref(client);
        return 0;
    }

    NMAccessPoint *active_ap = nm_device_wifi_get_active_access_point(wifi_dev);
    const char *active_ssid_str = NULL;
    char active_ssid_buf[256] = {0};

    /* Connected network info */
    FILE *out = stdout;
    fprintf(out, "{\"present\":true,\"power\":\"on\",\"connected\":");

    if (active_ap) {
        GBytes *ssid_bytes = nm_access_point_get_ssid(active_ap);
        if (ssid_bytes) {
            gsize len;
            const guint8 *data = g_bytes_get_data(ssid_bytes, &len);
            if (len < sizeof(active_ssid_buf)) {
                memcpy(active_ssid_buf, data, len);
                active_ssid_buf[len] = 0;
                active_ssid_str = active_ssid_buf;
            }
        }
        int signal = (int)nm_access_point_get_strength(active_ap);
        NM80211ApSecurityFlags wpa = nm_access_point_get_wpa_flags(active_ap);
        NM80211ApSecurityFlags rsn = nm_access_point_get_rsn_flags(active_ap);
        const char *sec = security_to_str(wpa, rsn);
        const char *icon = signal_icon(signal);
        const char *ip = get_device_ip(NM_DEVICE(wifi_dev));
        guint32 freq = nm_access_point_get_frequency(active_ap);

        char freq_str[32] = "";
        if (freq > 0) {
            snprintf(freq_str, sizeof(freq_str), "%u MHz", freq);
        }

        fprintf(out, "{\"id\":");
        json_str(out, active_ssid_str);
        fprintf(out, ",\"ssid\":");
        json_str(out, active_ssid_str);
        fprintf(out, ",\"icon\":");
        json_str(out, icon);
        fprintf(out, ",\"signal\":\"%d\"", signal);
        fprintf(out, ",\"security\":");
        json_str(out, sec);
        fprintf(out, ",\"ip\":");
        json_str(out, ip ? ip : "No IP");
        fprintf(out, ",\"freq\":");
        json_str(out, freq_str[0] ? freq_str : "Unknown");
        fprintf(out, "}");
    } else {
        fprintf(out, "null");
    }

    /* Available networks */
    fprintf(out, ",\"networks\":[");
    const GPtrArray *aps = nm_device_wifi_get_access_points(wifi_dev);
    int count = 0;
    /* Track seen SSIDs to deduplicate */
    char seen[64][256];
    int seen_count = 0;

    if (aps) {
        for (guint i = 0; i < aps->len && count < 24; i++) {
            NMAccessPoint *ap = g_ptr_array_index(aps, i);
            GBytes *ssid_bytes = nm_access_point_get_ssid(ap);
            if (!ssid_bytes) continue;

            gsize len;
            const guint8 *data = g_bytes_get_data(ssid_bytes, &len);
            if (len == 0 || len >= 256) continue;

            char ssid[256];
            memcpy(ssid, data, len);
            ssid[len] = 0;

            /* Skip active AP and duplicates */
            if (active_ssid_str && strcmp(ssid, active_ssid_str) == 0) continue;

            int dup = 0;
            for (int j = 0; j < seen_count; j++) {
                if (strcmp(seen[j], ssid) == 0) { dup = 1; break; }
            }
            if (dup) continue;
            if (seen_count < 64) { strcpy(seen[seen_count++], ssid); }

            int signal = (int)nm_access_point_get_strength(ap);
            NM80211ApSecurityFlags wpa = nm_access_point_get_wpa_flags(ap);
            NM80211ApSecurityFlags rsn = nm_access_point_get_rsn_flags(ap);
            const char *sec = security_to_str(wpa, rsn);
            const char *icon = signal_icon(signal);

            if (count > 0) fputc(',', out);
            fprintf(out, "{\"id\":");
            json_str(out, ssid);
            fprintf(out, ",\"ssid\":");
            json_str(out, ssid);
            fprintf(out, ",\"icon\":");
            json_str(out, icon);
            fprintf(out, ",\"signal\":\"%d\"", signal);
            fprintf(out, ",\"security\":");
            json_str(out, sec);
            fprintf(out, "}");
            count++;
        }
    }

    fprintf(out, "]}\n");
    g_object_unref(client);
    return 0;
}
