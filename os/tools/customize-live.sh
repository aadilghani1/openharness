#!/bin/bash
set -euo pipefail
echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen
locale-gen
echo 'LANG=en_US.UTF-8' > /etc/locale.conf
echo programmer-live > /etc/hostname
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
useradd -m -G wheel,video,audio -s /bin/bash programmer
passwd -d programmer
mkdir -p /etc/sudoers.d /home/programmer/Projects /etc/systemd/system/getty@tty1.service.d
echo 'programmer ALL=(ALL:ALL) NOPASSWD: ALL' > /etc/sudoers.d/10-live
chmod 440 /etc/sudoers.d/10-live
chown programmer:programmer /home/programmer/Projects
systemctl enable NetworkManager systemd-resolved systemd-timesyncd getty@tty1.service
systemctl --global enable harness-daemon.service
loginctl enable-linger programmer || mkdir -p /var/lib/systemd/linger
touch /var/lib/systemd/linger/programmer
# Agent auth and browser downloads never block boot. No SSH listener by default.
systemctl disable NetworkManager-wait-online.service || true
systemctl mask systemd-networkd.service systemd-networkd-wait-online.service
ln -sf /usr/lib/systemd/system/multi-user.target /etc/systemd/system/default.target
printf '[Service]\nExecStart=\nExecStart=-/usr/bin/agetty --autologin programmer --noclear %%I $TERM\n' > /etc/systemd/system/getty@tty1.service.d/autologin.conf
# A serial console is useful for recovering a live USB; never carried into the install.
mkdir -p /etc/systemd/system/serial-getty@ttyS0.service.d
printf '[Service]\nExecStart=\nExecStart=-/usr/bin/agetty --autologin root --noclear %%I 115200\n' > /etc/systemd/system/serial-getty@ttyS0.service.d/live.conf
systemctl enable serial-getty@ttyS0.service
pacman -Q > /usr/share/harness-os/packages.txt
rm -rf /var/cache/pacman/pkg/* /root/.cache
