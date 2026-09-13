# Testing

## CI (GitHub Actions)

Every push runs:

| Job | Checks |
|-----|--------|
| Shell lint and format | ShellCheck, shfmt, `bash -n` |
| EDID generator | 256-byte output |
| Install smoke test | `tests/smoke-test.sh` in a distro matrix (see below) |

### Smoke matrix (CI)

| Distro | Initramfs backend |
|--------|-------------------|
| Debian trixie | initramfs-tools |
| Ubuntu 24.04 | initramfs-tools |
| Fedora 43 | dracut |
| openSUSE Tumbleweed | dracut |
| Arch Linux | mkinitcpio |

## Local / VM smoke test

`tests/smoke-test.sh` runs a full **install → verify → uninstall → verify** cycle without:

- bootloader changes
- initramfs rebuild
- reboot
- KDE / GPU requirements

Requires root (or sudo) and one supported initramfs backend.

```bash
sudo ./tests/smoke-test.sh
```

Environment overrides (also used internally):

| Variable | Purpose |
|----------|---------|
| `SKIP_BOOTLOADER` | Skip GRUB/Limine/systemd-boot changes |
| `SKIP_INITRAMFS_REBUILD` | Write initramfs config but skip rebuild |
| `SKIP_POWER_MGMT` | Skip KDE power-management tweaks |

## Proxmox lab (PVE)

Use LXC or QEMU VMs to test **distro-specific initramfs paths** — not Moonlight, KMS capture, or display switching (no GPU passthrough on the homelab host).

### Test containers (example)

| CTID | Hostname | Template | Backend exercised |
|------|----------|----------|-------------------|
| 120 | sunshine-debian | Debian 13 | initramfs-tools |
| 121 | sunshine-fedora | Fedora 43 | dracut |

Create once on `pve`:

```bash
pct create 120 local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst \
  --hostname sunshine-debian --memory 1024 --cores 1 \
  --rootfs local:8 --net0 name=eth0,bridge=vmbr0,ip=dhcp \
  --unprivileged 1 --onboot 0

pct create 121 local:vztmpl/fedora-43-default_20260115_amd64.tar.xz \
  --hostname sunshine-fedora --memory 1024 --cores 1 \
  --rootfs local:8 --net0 name=eth0,bridge=vmbr0,ip=dhcp \
  --ostype fedora --unprivileged 1 --onboot 0
```

Run smoke test from your workstation:

```bash
rsync -a --exclude .git ./ pve:/tmp/sunshine-vdisplay/
ssh pve 'tar -C /tmp/sunshine-vdisplay -cf - . | pct exec 120 -- bash -c "mkdir -p /root/sunshine-vdisplay && tar -xf - -C /root/sunshine-vdisplay"'
ssh pve 'pct exec 120 -- bash -lc "apt-get update && apt-get install -y python3 sudo initramfs-tools && /root/sunshine-vdisplay/tests/smoke-test.sh"'
```

Repeat for CT 121 with `dnf install -y python3 sudo dracut`.

Stop containers when idle: `pct stop 120 121`

### What PVE cannot test

- NVIDIA / AMD GPU virtual displays
- Sunshine KMS / NVENC / VAAPI / `hevc_vulkan` encoding
- KDE `kscreen-doctor` display switching during Moonlight sessions
- Bootloader changes that require a real VM boot cycle (use QEMU + reboot for that)

Real streaming validation still needs physical hardware (your CachyOS box or volunteer testers).
