/*
 * bt_status.c — Bluetooth status via D-Bus (BlueZ API)
 * Drop-in replacement for bluetooth_panel_logic.sh
 *
 * Provides status polling as well as connect/disconnect actions.
 * Output: JSON object representing BT state and known devices.
 * String fields are safely JSON-escaped via json_str().
 *
 * Compile: gcc -O2 -Wall -Wextra -o bt_status bt_status.c $(pkg-config --cflags --libs dbus-1)
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <ctype.h>
#include <dbus/dbus.h>
#include <unistd.h>

#define MAX_DEVICES 64
#define MAX_CONNECTED 16

typedef struct {
    char path[256];
    char address[24];
    char name[128];
    char icon[64];
    int  connected;
    int  paired;
    int  trusted;
    int  battery;      /* -1 if unavailable */
} BtDevice;

static DBusConnection *conn = NULL;

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

/** Map device icon property or name to a Nerd Font glyph. */

static const char* device_icon(const char *icon_type, const char *name) {
    if (!icon_type) icon_type = "";
    if (!name) name = "";
    
    /* Lowercase comparison helpers */
    char icon_lc[64], name_lc[128];
    int i;
    for (i = 0; icon_type[i] && i < 63; i++) icon_lc[i] = tolower((unsigned char)icon_type[i]);
    icon_lc[i] = 0;
    for (i = 0; name[i] && i < 127; i++) name_lc[i] = tolower((unsigned char)name[i]);
    name_lc[i] = 0;

    /* Priority 1: BlueZ Icon property (authoritative — e.g. "input-mouse") */
    if (strstr(icon_lc, "mouse") || strstr(icon_lc, "input-mouse")) return "󰍽";
    if (strstr(icon_lc, "keyboard") || strstr(icon_lc, "input-keyboard")) return "󰌌";
    if (strstr(icon_lc, "headset") || strstr(icon_lc, "headphone") ||
        strstr(icon_lc, "audio-headset") || strstr(icon_lc, "audio-headphones")) return "󰋋";
    if (strstr(icon_lc, "audio") || strstr(icon_lc, "speaker")) return "󰓃";
    if (strstr(icon_lc, "phone") || strstr(icon_lc, "smartphone")) return "󰏲";
    if (strstr(icon_lc, "computer") || strstr(icon_lc, "laptop")) return "󰌢";
    if (strstr(icon_lc, "video") || strstr(icon_lc, "camera")) return "󰄀";
    if (strstr(icon_lc, "controller") || strstr(icon_lc, "input-gaming")) return "󰊖";

    /* Priority 2: Name-based heuristics (fallback for devices with no Icon) */
    if (strstr(name_lc, "mouse") || strstr(name_lc, "m1")) return "󰍽";
    if (strstr(name_lc, "keyboard") || strstr(name_lc, "kb")) return "󰌌";
    if (strstr(name_lc, "headphone") || strstr(name_lc, "buds") ||
        strstr(name_lc, "pods") || strstr(name_lc, "airdopes") ||
        strstr(name_lc, "boult") || strstr(name_lc, "thunder")) return "󰋋";
    if (strstr(name_lc, "speaker")) return "󰓃";
    if (strstr(name_lc, "phone") || strstr(name_lc, "iphone") ||
        strstr(name_lc, "android")) return "󰏲";
    if (strstr(name_lc, "watch") || strstr(name_lc, "band")) return "󰖉";
    if (strstr(name_lc, "controller") || strstr(name_lc, "gamepad")) return "󰊖";
    return "󰂯";
}

/** bt_hw_present — Check if bluetooth hardware is physically present */
static int bt_hw_present(void) {
    DIR *d = opendir("/sys/class/bluetooth");
    if (!d) return 0;
    struct dirent *e;
    while ((e = readdir(d))) {
        if (strncmp(e->d_name, "hci", 3) == 0) { closedir(d); return 1; }
    }
    closedir(d);
    return 0;
}

/* Get a boolean property from a D-Bus object */
static int get_bool_prop(const char *path, const char *iface, const char *prop) {
    DBusMessage *msg = dbus_message_new_method_call("org.bluez", path,
        "org.freedesktop.DBus.Properties", "Get");
    if (!msg) return 0;
    dbus_message_append_args(msg, DBUS_TYPE_STRING, &iface,
        DBUS_TYPE_STRING, &prop, DBUS_TYPE_INVALID);
    
    DBusError err;
    dbus_error_init(&err);
    DBusMessage *reply = dbus_connection_send_with_reply_and_block(conn, msg, 1000, &err);
    dbus_message_unref(msg);
    if (!reply) { dbus_error_free(&err); return 0; }
    
    DBusMessageIter iter, variant;
    dbus_message_iter_init(reply, &iter);
    if (dbus_message_iter_get_arg_type(&iter) == DBUS_TYPE_VARIANT) {
        dbus_message_iter_recurse(&iter, &variant);
        if (dbus_message_iter_get_arg_type(&variant) == DBUS_TYPE_BOOLEAN) {
            dbus_bool_t val;
            dbus_message_iter_get_basic(&variant, &val);
            dbus_message_unref(reply);
            return val ? 1 : 0;
        }
    }
    dbus_message_unref(reply);
    return 0;
}

/* Get a string property from a D-Bus object */
static int get_str_prop(const char *path, const char *iface, const char *prop, char *buf, int bufsz) {
    buf[0] = 0;
    DBusMessage *msg = dbus_message_new_method_call("org.bluez", path,
        "org.freedesktop.DBus.Properties", "Get");
    if (!msg) return 0;
    dbus_message_append_args(msg, DBUS_TYPE_STRING, &iface,
        DBUS_TYPE_STRING, &prop, DBUS_TYPE_INVALID);
    
    DBusError err;
    dbus_error_init(&err);
    DBusMessage *reply = dbus_connection_send_with_reply_and_block(conn, msg, 1000, &err);
    dbus_message_unref(msg);
    if (!reply) { dbus_error_free(&err); return 0; }
    
    DBusMessageIter iter, variant;
    dbus_message_iter_init(reply, &iter);
    if (dbus_message_iter_get_arg_type(&iter) == DBUS_TYPE_VARIANT) {
        dbus_message_iter_recurse(&iter, &variant);
        if (dbus_message_iter_get_arg_type(&variant) == DBUS_TYPE_STRING) {
            const char *val;
            dbus_message_iter_get_basic(&variant, &val);
            strncpy(buf, val, bufsz - 1);
            buf[bufsz - 1] = 0;
            dbus_message_unref(reply);
            return 1;
        }
    }
    dbus_message_unref(reply);
    return 0;
}

/* Get a byte property (for battery) */
static int get_byte_prop(const char *path, const char *iface, const char *prop) {
    DBusMessage *msg = dbus_message_new_method_call("org.bluez", path,
        "org.freedesktop.DBus.Properties", "Get");
    if (!msg) return -1;
    dbus_message_append_args(msg, DBUS_TYPE_STRING, &iface,
        DBUS_TYPE_STRING, &prop, DBUS_TYPE_INVALID);
    
    DBusError err;
    dbus_error_init(&err);
    DBusMessage *reply = dbus_connection_send_with_reply_and_block(conn, msg, 1000, &err);
    dbus_message_unref(msg);
    if (!reply) { dbus_error_free(&err); return -1; }
    
    DBusMessageIter iter, variant;
    dbus_message_iter_init(reply, &iter);
    if (dbus_message_iter_get_arg_type(&iter) == DBUS_TYPE_VARIANT) {
        dbus_message_iter_recurse(&iter, &variant);
        if (dbus_message_iter_get_arg_type(&variant) == DBUS_TYPE_BYTE) {
            unsigned char val;
            dbus_message_iter_get_basic(&variant, &val);
            dbus_message_unref(reply);
            return (int)val;
        }
    }
    dbus_message_unref(reply);
    return -1;
}

/* Set a boolean property */
static void set_bool_prop(const char *path, const char *iface, const char *prop, int val) {
    DBusMessage *msg = dbus_message_new_method_call("org.bluez", path,
        "org.freedesktop.DBus.Properties", "Set");
    if (!msg) return;
    
    DBusMessageIter args, variant;
    dbus_message_iter_init_append(msg, &args);
    dbus_message_iter_append_basic(&args, DBUS_TYPE_STRING, &iface);
    dbus_message_iter_append_basic(&args, DBUS_TYPE_STRING, &prop);
    dbus_message_iter_open_container(&args, DBUS_TYPE_VARIANT, "b", &variant);
    dbus_bool_t bval = val ? TRUE : FALSE;
    dbus_message_iter_append_basic(&variant, DBUS_TYPE_BOOLEAN, &bval);
    dbus_message_iter_close_container(&args, &variant);
    
    DBusError err;
    dbus_error_init(&err);
    DBusMessage *reply = dbus_connection_send_with_reply_and_block(conn, msg, 2000, &err);
    dbus_message_unref(msg);
    if (reply) dbus_message_unref(reply);
    dbus_error_free(&err);
}

/* Call a void method on a device */
static int call_device_method(const char *path, const char *method) {
    DBusMessage *msg = dbus_message_new_method_call("org.bluez", path,
        "org.bluez.Device1", method);
    if (!msg) return -1;
    
    DBusError err;
    dbus_error_init(&err);
    DBusMessage *reply = dbus_connection_send_with_reply_and_block(conn, msg, 30000, &err);
    dbus_message_unref(msg);
    int rc = 0;
    if (dbus_error_is_set(&err)) { rc = -1; dbus_error_free(&err); }
    if (reply) dbus_message_unref(reply);
    return rc;
}

/* Find adapter path */
static int find_adapter(char *path, int pathsz) {
    /* Use GetManagedObjects to find adapter */
    DBusMessage *msg = dbus_message_new_method_call("org.bluez", "/",
        "org.freedesktop.DBus.ObjectManager", "GetManagedObjects");
    if (!msg) return 0;
    
    DBusError err;
    dbus_error_init(&err);
    DBusMessage *reply = dbus_connection_send_with_reply_and_block(conn, msg, 2000, &err);
    dbus_message_unref(msg);
    if (!reply) { dbus_error_free(&err); return 0; }
    
    /* Iterate dict: path -> dict(iface -> dict(prop -> variant)) */
    DBusMessageIter root, dict_entry;
    dbus_message_iter_init(reply, &root);
    if (dbus_message_iter_get_arg_type(&root) != DBUS_TYPE_ARRAY) {
        dbus_message_unref(reply);
        return 0;
    }
    
    dbus_message_iter_recurse(&root, &dict_entry);
    while (dbus_message_iter_get_arg_type(&dict_entry) == DBUS_TYPE_DICT_ENTRY) {
        DBusMessageIter entry, ifaces;
        dbus_message_iter_recurse(&dict_entry, &entry);
        
        const char *obj_path;
        dbus_message_iter_get_basic(&entry, &obj_path);
        
        /* Check if this object has org.bluez.Adapter1 interface */
        dbus_message_iter_next(&entry);
        dbus_message_iter_recurse(&entry, &ifaces);
        
        while (dbus_message_iter_get_arg_type(&ifaces) == DBUS_TYPE_DICT_ENTRY) {
            DBusMessageIter iface_entry;
            dbus_message_iter_recurse(&ifaces, &iface_entry);
            const char *iface_name;
            dbus_message_iter_get_basic(&iface_entry, &iface_name);
            
            if (strcmp(iface_name, "org.bluez.Adapter1") == 0) {
                strncpy(path, obj_path, pathsz - 1);
                path[pathsz - 1] = 0;
                dbus_message_unref(reply);
                return 1;
            }
            dbus_message_iter_next(&ifaces);
        }
        dbus_message_iter_next(&dict_entry);
    }
    
    dbus_message_unref(reply);
    return 0;
}

/* Enumerate all devices */
static int enumerate_devices(BtDevice *devs, int max_devs) {
    DBusMessage *msg = dbus_message_new_method_call("org.bluez", "/",
        "org.freedesktop.DBus.ObjectManager", "GetManagedObjects");
    if (!msg) return 0;
    
    DBusError err;
    dbus_error_init(&err);
    DBusMessage *reply = dbus_connection_send_with_reply_and_block(conn, msg, 2000, &err);
    dbus_message_unref(msg);
    if (!reply) { dbus_error_free(&err); return 0; }
    
    int count = 0;
    DBusMessageIter root, dict_entry;
    dbus_message_iter_init(reply, &root);
    if (dbus_message_iter_get_arg_type(&root) != DBUS_TYPE_ARRAY) {
        dbus_message_unref(reply);
        return 0;
    }
    
    dbus_message_iter_recurse(&root, &dict_entry);
    while (dbus_message_iter_get_arg_type(&dict_entry) == DBUS_TYPE_DICT_ENTRY && count < max_devs) {
        DBusMessageIter entry, ifaces;
        dbus_message_iter_recurse(&dict_entry, &entry);
        
        const char *obj_path;
        dbus_message_iter_get_basic(&entry, &obj_path);
        
        /* Only look at /org/bluez/hciX/dev_* paths */
        if (strstr(obj_path, "/dev_") == NULL) {
            dbus_message_iter_next(&dict_entry);
            continue;
        }
        
        /* Check if this object has org.bluez.Device1 */
        dbus_message_iter_next(&entry);
        dbus_message_iter_recurse(&entry, &ifaces);
        
        int is_device = 0;
        while (dbus_message_iter_get_arg_type(&ifaces) == DBUS_TYPE_DICT_ENTRY) {
            DBusMessageIter iface_entry;
            dbus_message_iter_recurse(&ifaces, &iface_entry);
            const char *iface_name;
            dbus_message_iter_get_basic(&iface_entry, &iface_name);
            if (strcmp(iface_name, "org.bluez.Device1") == 0) { is_device = 1; break; }
            dbus_message_iter_next(&ifaces);
        }
        
        if (is_device) {
            BtDevice *d = &devs[count];
            strncpy(d->path, obj_path, sizeof(d->path) - 1);
            
            get_str_prop(obj_path, "org.bluez.Device1", "Address", d->address, sizeof(d->address));
            get_str_prop(obj_path, "org.bluez.Device1", "Name", d->name, sizeof(d->name));
            get_str_prop(obj_path, "org.bluez.Device1", "Icon", d->icon, sizeof(d->icon));
            d->connected = get_bool_prop(obj_path, "org.bluez.Device1", "Connected");
            d->paired = get_bool_prop(obj_path, "org.bluez.Device1", "Paired");
            d->trusted = get_bool_prop(obj_path, "org.bluez.Device1", "Trusted");
            
            /* Battery: try org.bluez.Battery1 */
            d->battery = get_byte_prop(obj_path, "org.bluez.Battery1", "Percentage");
            
            /* Filter unnamed devices (spam) */
            if (d->name[0] == 0) {
                dbus_message_iter_next(&dict_entry);
                continue;
            }
            /* Filter unnamed-by-MAC devices */
            if (strcmp(d->name, d->address) == 0 && !d->paired) {
                dbus_message_iter_next(&dict_entry);
                continue;
            }
            /* Also filter MAC-with-dashes */
            char mac_dash[24];
            strncpy(mac_dash, d->address, sizeof(mac_dash));
            for (char *p = mac_dash; *p; p++) if (*p == ':') *p = '-';
            if (strcmp(d->name, mac_dash) == 0 && !d->paired) {
                dbus_message_iter_next(&dict_entry);
                continue;
            }
            
            count++;
        }
        dbus_message_iter_next(&dict_entry);
    }
    
    dbus_message_unref(reply);
    return count;
}

/* Find device path by MAC address */
static int find_device_path(const char *mac, char *path, int pathsz) {
    BtDevice devs[MAX_DEVICES];
    int n = enumerate_devices(devs, MAX_DEVICES);
    for (int i = 0; i < n; i++) {
        if (strcasecmp(devs[i].address, mac) == 0) {
            strncpy(path, devs[i].path, pathsz - 1);
            path[pathsz - 1] = 0;
            return 1;
        }
    }
    return 0;
}

static void do_status(void) {
    if (!bt_hw_present()) {
        puts("{\"present\":false,\"power\":\"off\",\"connected\":[],\"devices\":[]}");
        return;
    }
    
    char adapter_path[256];
    if (!find_adapter(adapter_path, sizeof(adapter_path))) {
        puts("{\"present\":false,\"power\":\"off\",\"connected\":[],\"devices\":[]}");
        return;
    }
    
    int powered = get_bool_prop(adapter_path, "org.bluez.Adapter1", "Powered");
    
    if (!powered) {
        puts("{\"present\":true,\"power\":\"off\",\"connected\":[],\"devices\":[]}");
        return;
    }
    
    BtDevice devs[MAX_DEVICES];
    int n = enumerate_devices(devs, MAX_DEVICES);
    
    FILE *out = stdout;
    fprintf(out, "{\"present\":true,\"power\":\"on\",\"connected\":[");
    
    /* Connected devices */
    int cc = 0;
    for (int i = 0; i < n; i++) {
        if (!devs[i].connected) continue;
        if (cc > 0) fputc(',', out);
        const char *icon = device_icon(devs[i].icon, devs[i].name);
        fprintf(out, "{\"id\":");
        json_str(out, devs[i].address);
        fprintf(out, ",\"name\":");
        json_str(out, devs[i].name);
        fprintf(out, ",\"mac\":");
        json_str(out, devs[i].address);
        fprintf(out, ",\"icon\":");
        json_str(out, icon);
        fprintf(out, ",\"battery\":\"%d\"", devs[i].battery >= 0 ? devs[i].battery : 0);
        fprintf(out, ",\"profile\":\"Connected\"}");
        cc++;
    }
    
    fprintf(out, "],\"devices\":[");
    
    /* Non-connected devices */
    int dc = 0;
    for (int i = 0; i < n; i++) {
        if (devs[i].connected) continue;
        if (dc > 0) fputc(',', out);
        const char *icon = device_icon(devs[i].icon, devs[i].name);
        const char *action = devs[i].paired ? "Connect" : "Pair";
        fprintf(out, "{\"id\":");
        json_str(out, devs[i].address);
        fprintf(out, ",\"name\":");
        json_str(out, devs[i].name);
        fprintf(out, ",\"mac\":");
        json_str(out, devs[i].address);
        fprintf(out, ",\"icon\":");
        json_str(out, icon);
        fprintf(out, ",\"action\":");
        json_str(out, action);
        fprintf(out, "}");
        dc++;
    }
    
    fprintf(out, "]}\n");
}

static void do_toggle(void) {
    char adapter_path[256];
    if (!find_adapter(adapter_path, sizeof(adapter_path))) return;
    int powered = get_bool_prop(adapter_path, "org.bluez.Adapter1", "Powered");
    set_bool_prop(adapter_path, "org.bluez.Adapter1", "Powered", !powered);
    usleep(300000); /* 300ms settle time */
}

static void do_connect(const char *mac) {
    char path[256];
    if (!find_device_path(mac, path, sizeof(path))) {
        fprintf(stderr, "bt_status: device %s not found in BlueZ\n", mac);
        dbus_connection_unref(conn);
        exit(1);
    }
    
    /* Check if already paired */
    int paired = get_bool_prop(path, "org.bluez.Device1", "Paired");
    
    /* If not paired, pair first */
    if (!paired) {
        fprintf(stderr, "bt_status: pairing %s...\n", mac);
        int rc = call_device_method(path, "Pair");
        if (rc != 0) {
            fprintf(stderr, "bt_status: pairing failed for %s\n", mac);
            dbus_connection_unref(conn);
            exit(1);
        }
        /* Wait for pairing to settle */
        usleep(500000);
    }
    
    /* Trust the device */
    set_bool_prop(path, "org.bluez.Device1", "Trusted", 1);
    
    /* Connect */
    fprintf(stderr, "bt_status: connecting %s...\n", mac);
    int rc = call_device_method(path, "Connect");
    if (rc != 0) {
        fprintf(stderr, "bt_status: connect failed for %s, retrying...\n", mac);
        /* Retry once after a small delay (some devices need it) */
        usleep(1000000);
        rc = call_device_method(path, "Connect");
        if (rc != 0) {
            fprintf(stderr, "bt_status: connect retry failed for %s\n", mac);
            dbus_connection_unref(conn);
            exit(1);
        }
    }
    fprintf(stderr, "bt_status: connected %s\n", mac);
    dbus_connection_unref(conn);
    exit(0);
}

static void do_disconnect(const char *mac) {
    char path[256];
    if (!find_device_path(mac, path, sizeof(path))) {
        fprintf(stderr, "Device %s not found\n", mac);
        dbus_connection_unref(conn);
        exit(1);
    }
    call_device_method(path, "Disconnect");
    dbus_connection_unref(conn);
    exit(0);
}

int main(int argc, char **argv) {
    DBusError err;
    dbus_error_init(&err);
    conn = dbus_bus_get(DBUS_BUS_SYSTEM, &err);
    if (!conn) {
        if (argc > 1 && strcmp(argv[1], "--status") == 0)
            puts("{\"present\":false,\"power\":\"off\",\"connected\":[],\"devices\":[]}");
        dbus_error_free(&err);
        return 1;
    }
    
    if (argc < 2 || strcmp(argv[1], "--status") == 0) {
        do_status();
    } else if (strcmp(argv[1], "--toggle") == 0) {
        do_toggle();
    } else if (strcmp(argv[1], "--connect") == 0 && argc >= 3) {
        do_connect(argv[2]);
    } else if (strcmp(argv[1], "--disconnect") == 0 && argc >= 3) {
        do_disconnect(argv[2]);
    } else if (strcmp(argv[1], "--scan") == 0) {
        char adapter_path[256];
        if (find_adapter(adapter_path, sizeof(adapter_path))) {
            /* Start discovery — fire and forget */
            DBusMessage *msg = dbus_message_new_method_call("org.bluez", adapter_path,
                "org.bluez.Adapter1", "StartDiscovery");
            if (msg) {
                DBusError serr;
                dbus_error_init(&serr);
                DBusMessage *reply = dbus_connection_send_with_reply_and_block(conn, msg, 5000, &serr);
                dbus_message_unref(msg);
                if (reply) dbus_message_unref(reply);
                dbus_error_free(&serr);
            }
            /* Run discovery for duration (default 10s) */
            int duration = (argc >= 3) ? atoi(argv[2]) : 10;
            if (duration > 0 && duration <= 60) sleep(duration);
            /* Stop discovery */
            msg = dbus_message_new_method_call("org.bluez", adapter_path,
                "org.bluez.Adapter1", "StopDiscovery");
            if (msg) {
                DBusError serr;
                dbus_error_init(&serr);
                DBusMessage *reply = dbus_connection_send_with_reply_and_block(conn, msg, 5000, &serr);
                dbus_message_unref(msg);
                if (reply) dbus_message_unref(reply);
                dbus_error_free(&serr);
            }
        }
    } else if (strcmp(argv[1], "--scan-stop") == 0) {
        char adapter_path[256];
        if (find_adapter(adapter_path, sizeof(adapter_path))) {
            DBusMessage *msg = dbus_message_new_method_call("org.bluez", adapter_path,
                "org.bluez.Adapter1", "StopDiscovery");
            if (msg) {
                DBusError serr;
                dbus_error_init(&serr);
                DBusMessage *reply = dbus_connection_send_with_reply_and_block(conn, msg, 5000, &serr);
                dbus_message_unref(msg);
                if (reply) dbus_message_unref(reply);
                dbus_error_free(&serr);
            }
        }
    }
    
    dbus_connection_unref(conn);
    return 0;
}
