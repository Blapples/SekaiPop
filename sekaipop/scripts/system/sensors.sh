#!/bin/sh

# The reading side of the temperatures and disks in the CPU & RAM card
# (services/SensorsService.qml). Prints one line per thing it could read, and nothing for what it
# could not (a machine with no readable sensor just prints less):
#
#   cpu=62                          degrees C
#   gpu=55
#   disk=/|112000000000|476000000000|/dev/nvme0n1p2   mount point | bytes used | bytes in total | device
#   home=/                          the mount point of the filesystem holding $HOME
#
# CPU: the hwmon chip of an AMD (k10temp, zenpower) or Intel (coretemp) processor, its package /
# Tctl / Tdie reading; failing that the kernel's x86_pkg_temp zone.
# GPU: the hwmon chip of an AMD (amdgpu, radeon) or Nouveau card. NVIDIA's own driver has no
# hwmon chip, and asking nvidia-smi would wake a sleeping GPU on a hybrid laptop, so it is not
# asked.
# Disks: every mounted local disk (a device under /dev), once per mount point: /, /home when it is
# its own mount, a games drive, a USB stick. The mounts that are not storage you would look at
# (/boot, /efi, /var/..., snaps, /run other than /run/media, loop devices, anything under 1 GiB)
# are left out, and / is always there. Mounts of one device (btrfs subvolumes, a bind mount) are
# one disk to the card, which groups them by the device printed last. `home=` says which mount
# $HOME is on, so a home that is just a folder of / still reads "System / Home". df gets three
# seconds: a hung network mount must not hang this (network mounts are not listed anyway).
#
# Only reads sysfs and runs df; changes nothing.

read_first() {
    # the first line of a file, or nothing
    [ -r "$1" ] && head -n 1 "$1" 2>/dev/null
}

cpu=""
gpu=""
for h in /sys/class/hwmon/hwmon*; do
    [ -d "$h" ] || continue
    name=$(read_first "$h/name")
    case "$name" in
        k10temp|zenpower|coretemp)
            [ -n "$cpu" ] && continue
            pick=""
            for l in "$h"/temp*_label; do
                [ -r "$l" ] || continue
                lab=$(read_first "$l")
                case "$lab" in
                    Tctl|Tdie|"Package id 0") pick="${l%_label}_input"; break ;;
                esac
            done
            [ -z "$pick" ] && pick="$h/temp1_input"
            v=$(read_first "$pick")
            case "$v" in ''|*[!0-9]*) ;; *) cpu=$((v / 1000)) ;; esac
            ;;
        amdgpu|radeon|nouveau)
            [ -n "$gpu" ] && continue
            v=$(read_first "$h/temp1_input")
            case "$v" in ''|*[!0-9]*) ;; *) gpu=$((v / 1000)) ;; esac
            ;;
    esac
done

if [ -z "$cpu" ]; then
    for z in /sys/class/thermal/thermal_zone*; do
        [ "$(read_first "$z/type")" = "x86_pkg_temp" ] || continue
        v=$(read_first "$z/temp")
        case "$v" in ''|*[!0-9]*) ;; *) cpu=$((v / 1000)); break ;; esac
    done
fi

[ -n "$cpu" ] && echo "cpu=$cpu"
[ -n "$gpu" ] && echo "gpu=$gpu"

t=""
command -v timeout >/dev/null 2>&1 && t="timeout 3"

# source used avail target (the target may have spaces, so it is what is left after three fields)
$t df -B1 --output=source,used,avail,target 2>/dev/null | awk '
NR == 1 { next }
{
    src = $1; used = $2; avail = $3
    mnt = $0
    for (i = 1; i <= 3; i++) sub(/^[ \t]*[^ \t]+[ \t]+/, "", mnt)
    if (mnt ~ /\|/ || used !~ /^[0-9]+$/ || avail !~ /^[0-9]+$/) next
    total = used + avail
    if (mnt != "/") {
        if (src !~ /^\/dev\// || src ~ /^\/dev\/loop/) next
        if (mnt ~ /^\/(boot|efi|snap|usr|nix|tmp|sys|proc|dev)(\/|$)/) next
        if (mnt ~ /^\/var\// || mnt ~ /^\/\.snapshots/) next
        if (mnt ~ /^\/run\// && mnt !~ /^\/run\/media\//) next
        if (total < 1073741824) next
    }
    printf "disk=%s|%s|%s|%s\n", mnt, used, total, src
}'

h=$($t df --output=target "$HOME" 2>/dev/null | tail -n 1)
[ -n "$h" ] && echo "home=$h"
exit 0
