#!/usr/bin/env python3
import subprocess
import time
import os

logos = [
    "Adelie", "aerOS", "Aeon", "AerynOS", "AerynOS_old", "Afterglow", "aix", "Almalinux",
    "Alpine", "Alpine2", "Alpine_small", "alpine2_small", "alpine3_small", "Alter", "ALTLinux",
    "Amazon", "amzn", "Amiga", "AmogOS", "Anarchy", "android", "android_small", "anduinos",
    "Antergos", "antiX", "AnushOS", "aoscosretro", "aoscosretro_small", "aoscos", "aoscos_old",
    "Aperture", "Apple", "Apple_small", "Apricity", "ArchBox", "Archcraft", "Archcraft2",
    "arch", "arch2", "arch3", "arch_small", "arch_old", "ARCHlabs", "ArchStrike", "Arkane",
    "Armbian", "Armbian2", "artix", "artix_small", "artix2_small", "arco", "arco_small", "arse",
    "Arya", "asahi", "asahi2", "aster", "AsteroidOS", "astOS", "Astra", "Ataraxia", "AthenaOS",
    "AthenaOS_old", "Aurora", "AxOS", "Azos", "bedrock", "bedrock_small", "BigLinux", "Bitrig",
    "Blackarch", "BlackMesa", "BlackPanther", "BLAG", "BlankOn", "BlueLight", "Bodhi", "Bonsai",
    "Bredos", "BSD", "BunsenLabs", "CachyOS", "CachyOS_small", "Calculate", "Calinix",
    "Calinix_small", "Carbs", "CBL-Mariner", "Cel", "Center", "CentOS", "CentOS_small", "Cereus",
    "Chakra", "ChaletOS", "Chapeau", "Chimera", "ChonkySealOS", "Chrom", "Cleanjaro",
    "Cleanjaro_small", "clearlinux", "ClearOS", "Clover", "Cobalt", "Codex Linux", "Condres",
    "ContainerLinux", "common-torizon", "Cosmic", "CRUX", "CRUX_small", "Crystal", "Cucumber",
    "CuerdOS", "CutefishOS", "CuteOS", "CyberOS", "cycledream", "dahliaOS", "DarkOS", "Debian",
    "Debian_small", "Deepin", "DesaOS", "Devuan", "Devuan_small", "DietPi", "DracOS",
    "DragonFly", "DragonFly_small", "DragonFly_old", "DraugerOS", "Droidian", "elbrus",
    "Elementary", "Elementary_small", "Elive", "Emmabuntus", "Emperor", "EncryptOS",
    "EndeavourOS", "EndeavourOS_small", "Endless", "Enso", "EshanizedOS", "EuroLinux",
    "EvolutionOS", "EvolutionOS_small", "EvolutionOS_old", "eweOS", "Exherbo", "Exodia",
    "Fastfetch", "Fedora", "fedora-asahi-remix", "Fedora_small", "Fedora2_small", "Fedora_old",
    "Fedora-Silverblue", "Fedora-Kinoite", "Fedora-Sericea", "Fedora-CoreOS", "FemboyOS",
    "Feren", "filotimo", "Finnix", "Floflis", "Freebsd", "freebsd_small", "FreeMiNT",
    "Frugalware", "Funtoo", "Furreto", "GalliumOS", "Garuda", "GarudaDragon", "Garuda_small",
    "Gentoo", "Gentoo_small", "GhostBSD", "GhostFreak", "Glaucus", "gNewSense", "GNOME", "GNU",
    "GoboLinux", "GoldenDog Linux", "GrapheneOS", "Grombyang", "Guix", "Guix_small", "GXDE",
    "Haiku", "Haiku2", "Haiku_small", "HamoniKR", "HarDClanZ", "HardenedBSD", "HarmonyOS",
    "Hash", "HeliumOS", "hce", "Huayra", "Hybrid", "HydroOS", "hypros", "Hyperbola",
    "Hyperbola_small", "Iglunix", "InstantOS", "Interix", "IRIX", "Ironclad", "Itc",
    "januslinux", "Kaisen", "Kali", "Kali_small", "kalpa-desktop", "KaOS", "KernelOS",
    "kdelinux", "KDE Neon", "Kibojoe", "KISS", "kiss2", "Kogaion", "Korora", "KrassOS",
    "KSLinux", "Kubuntu", "Kylin", "LainOS", "langitketujuh", "Laxeros", "LEDE", "LibreELEC",
    "Lilidog", "Lingmo", "Linspire", "Linux", "LinuxFromScratch", "Linux_small", "LinuxLite",
    "LinuxLite_small", "linuxmint", "linuxmint_small", "linuxmint2", "linuxmint_old",
    "Live Raizo", "LliureX", "LMDE", "locos", "lubuntu", "Lunar", "Macaroni", "macOS",
    "macOS_small", "macOS2", "macOS2_small", "macOS3", "MainsailOS", "MainsailOS_small",
    "Mageia", "Mageia_small", "Magix", "MagpieOS", "mandriva", "manjaro", "manjaro_small",
    "MassOS", "MatuusOS", "MaUI", "Mauna", "Meowix", "Mer", "MidnightBSD", "MidOS", "MidOS_old",
    "Minimal_System", "Minix", "miraclelinux", "MOS", "Msys2", "MX", "MX_small", "MX2", "Namib",
    "Nekos", "Neptune", "NetRunner", "nexalinux", "Nitrux", "NixOS", "NixOS_small", "nixos_old",
    "nixos_old_small", "NetBSD", "NetBSD2", "NetBSD_small", "nobara", "nomadbsd", "NurOS",
    "Nurunner", "NuTyX", "NetHydra", "Obarun", "OBRevenge", "ObsidianOS", "OmniOS", "openkylin",
    "openbsd", "openbsd_small", "OpenEuler", "OpenIndiana", "OpenMamba", "OpenStage", "opensuse",
    "opensuse_small", "opensuse-microos", "opensuse-leap", "opensuse-leap_old",
    "opensuse-tumbleweed", "opensuse-tumbleweed_small", "opensuse-tumbleweed_old",
    "opensuse-tumbleweed2", "opensuse-slowroll", "openmandriva", "openwrt", "OPNsense", "oracle",
    "orchid", "orchid_small", "Oreon", "OS2Warp", "OS Elbrus", "OSMC", "OSX", "OSX_small",
    "PacBSD", "Panwah", "parabola", "parabola_small", "Parch", "Pardus", "Parrot", "Parsix",
    "PCBSD", "PCLinuxOS", "PearOS", "Pengwin", "Pentoo", "Peppermint", "Peropesis", "PhyOS",
    "PikaOS", "PisiLinux", "PNM Linux", "pop", "pop_small", "Porteus", "PostMarketOS",
    "PostMarketOS_small", "Proxmox", "PuffOS", "Puppy", "PureOS", "PureOS_small", "PrismLinux",
    "PrismLinux_small", "qts", "Q4OS", "Qubes", "Qubyt", "Quibian", "Quirinux", "Radix",
    "raspbian", "raspbian_small", "RavynOS", "RebornOS", "RebornOS_small", "RedCore", "rhel",
    "rhel_small", "rhel_old", "RedOS", "RedOS_small", "redstar", "Refracta", "Regata",
    "Regolith", "RhaymOS", "rocky", "rocky_small", "rosa", "Rhino Linux", "RengeOS", "Sabayon",
    "Sabotage", "Sailfish", "SalentOS", "Salient OS", "Salix", "SambaBOX", "Sasanqua",
    "Scientific", "secureblue", "Serpent OS", "semc", "Septor", "Serene", "SharkLinux",
    "ShastraOS", "Shebang", "Siduction", "SkiffOS", "SleeperOS", "SleeperOS_small", "Slitaz",
    "SpoinkOS", "Slackel", "Slackware", "Slackware_small", "SmartOS", "SnigdhaOS", "Soda",
    "Source Mage", "solaris", "solaris_small", "Solus", "Sparky", "Star", "Stock Linux",
    "SteamOS", "SteamDeck", "SteamDeck_small", "SteamDeckOled", "Sulin", "SummitOS", "suse",
    "suse_small", "Swagarch", "T2", "T2_small", "Tails", "Tatra", "TeArch", "TempleOS",
    "TileOS", "Torizon OS", "Trisquel", "TrueNAS-Scale", "Tuxedo OS", "Twister", "UBLinux",
    "UBLinux_small", "ubuntu", "ubuntu_small", "ubuntu_old", "ubuntu_old2", "ubuntu_old2_small",
    "ubuntu budgie", "ubuntu cinnamon", "ubuntu gnome", "ubuntu kylin", "ubuntu mate",
    "ubuntu kde", "ubuntu studio", "ubuntu sway", "ubuntu touch", "ubuntu unity", "Ultramarine",
    "Ultramarine_small", "Unifi", "Univalent", "Univention", "UOS", "UrukOS", "uwuntu",
    "Valhalla", "vanilla", "vanilla2", "vanilla_small", "Venom", "Venom_small", "VincentOS",
    "Vnux", "Vzlinux", "void", "void_small", "void2", "void2_small", "WiiLinuxNgx",
    "Windows Server 2025", "Windows 11", "Windows 11_small", "Windows 8", "Windows", "Windows 95",
    "WolfOS", "XCP-ng", "Xenia", "Xenia_old", "XeroArch", "Xferience", "Xubuntu", "Xray_OS",
    "Xinux", "YiffOS", "Zorin", "zos", "Zraxyl",
]

DELAY = 1  # seconds between logos

total = len(logos)

for i, logo in enumerate(logos, start=1):
    os.system("clear")
    print(f"[ {i} / {total} ]  {logo}\n")
    subprocess.run(
        ["fastfetch", "--logo", logo, "--logo-padding-top", "1"],
        stderr=subprocess.DEVNULL
    )
    time.sleep(DELAY)

os.system("clear")
print(f"Done! All {total} logos shown.")
