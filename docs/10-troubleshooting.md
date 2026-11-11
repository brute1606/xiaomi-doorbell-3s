# Troubleshooting

## The chip is not detected

```
No EEPROM/flash device found
LIBUSB_TRANSFER_TIMED_OUT
config_stream: Failed to write 3 bytes
```

- the board is still powered — disconnect the battery and USB;
- clip contact is bad — reseat it, clean the pins, try another USB port;
- the CH341 kernel module is stuck:

```bash
sudo killall -9 flashrom
sudo modprobe -r spi_ch341; sudo modprobe -r ch341
```

## The device boot-loops after flashing

- The rootfs cpio was built **without root**, so `/dev` nodes are missing; the
  application cannot start and reboots the device. Rebuild the cpio as root.
- The image was compressed with **lzop 1.04** instead of 1.03.
- The rootfs is larger than 5056K compressed — check the length prefix.

## Serial console shows only the banner

- The tag was not flashed: `-i rootfs -i rootfs1` does not touch the tag.
  Flash the tag with `-l tag.layout -i tag`.
- The console patch was applied to only one of the two `CMDL` copies.

## "Reboots every few seconds"

That is usually not a crash: the doorbell is a battery device, and the MCU
powers the SoC off a few seconds after an event-less wake-up. Check the
application log for `send soc power off`. To keep the SoC on, apply the
`fj_system_soc_powerOff` patch and power the device from USB-C.

## The application log is full of `SIOCGIFADDR error`

The application polls network state; with no cloud/P2P session it repeats this
message. It is noisy but harmless.

## Battery drains fast

Expected with the sleep patch: the SoC and the camera are always on. Use USB-C
power; the battery then works as a backup.

## Control channel never connects

Symptom: the poller runs (its messages appear on the console) but the hub sees
no connection, and `nc` reports `failed: Network is unreachable`.

Cause: the Wi-Fi chip keeps its own DHCP lease and cloud session, but the Linux
side of the interface (`bleth0`) is configured by the vendor script
`/usr/bin/sta.sh`, which the daemon runs on an `IP_UPDATE` event. That event may
arrive late or not at all, so `bleth0` has no address and no default route while
the device still answers pings.

Fix: set `STATIC_IP`/`STATIC_MASK`/`STATIC_GW` in `/config/net.env`. The poller
re-applies them before every poll, so a lost address is restored automatically.
Check with `ifconfig bleth0` over the console — the `RUNNING` flag must be
present too; without it the interface has no carrier and nothing will connect.
