# Changelog — November 2026

This page summarises the changes made after the v0.6.0 release. Firmware
images are published as GitHub Releases assets; only the rootfs region is
shared (see [README](../README.md)).

## Reliable event delivery

The daemon talks to the local media/control agent over a small JSON bus. That
bus has a single *downstream* slot: only one connected client is selected to
receive MCU frames (button, PIR, tamper). A client registered with
`_internal.helper_ready` becomes the receiver, and the selection can be taken
over by another client — for example a short-lived probe or the media server
after a reconnect.

The daemon now:

- re-sends its registration (`_internal.helper_ready` and `_internal.hello`)
  every 30 seconds so it keeps the downstream slot;
- reopens the event socket automatically if it was closed;
- restarts itself after three consecutive idle periods (no downstream traffic
  for 90 seconds), which recovers a wedged bus without a reboot.

Result: button notifications are delivered continuously, including after
Wi-Fi drops and reconnects.

## Clock synchronisation (SNTP)

The device has no battery-backed RTC, so the clock started at the Unix epoch
after every boot. The daemon now sends a minimal SNTP request (UDP port 123)
to the configured gateway at start-up and every 30 minutes, and calls
`settimeofday()`. The on-screen timestamp and the NVR recordings now carry the
correct date and time.

## First-run provisioning over USB

A new helper (`provserv`) implements a two-stage fallback:

- if `/config/wifi.env` does **not** exist (fresh or reset device), the USB port
  comes up as an **Ethernet gadget** (`cdc_ether`, static address on the USB interface,
  documentation example `192.0.2.2/24`) and serves a minimal web page on port 80 with fields for
  Wi-Fi (SSID/password) and MQTT (host/port/user/password/discovery prefix);
- otherwise the USB port keeps the established **serial console shell**.

Saving the form writes `/config/wifi.env` and `/config/mqtt.env`, applies the
Wi-Fi credentials and restarts the daemon. Missing form fields are merged with
the existing configuration, so a partial update never wipes credentials.

## USB gadget switch

The MQTT switch `doorbell3s/usbgadget` enables and disables the USB serial
console shell remotely. Turning it off unloads the serial function and
disconnects the UDC; turning it on reloads it.

## Day/night (IR) mode

Night mode is not only the IR-cut filter: the image signal processor must also
switch to its monochrome running mode, otherwise IR illumination produces a
magenta-tinted colour image.

The vendor application did this by sending an ISP running-mode message to the
media server before moving the filter. The custom daemon now does the same:
`ircut on` sends ISP running mode 1 (night, monochrome) and moves the filter,
`ircut off` sends running mode 0 (day, colour) and restores the filter.
Verification on real frames: night mode gives R = G = B, day mode restores
colour.

## Build and flashing notes

- The image build scripts now compile the daemon from source; earlier they
  could silently package a stale prebuilt binary.
- A build-time QEMU sandbox and static checks still gate every image.
- When both A and B slots hold the same verified image, B is a safe rollback
  target. Writing B is a deliberate, separately authorised operation followed
  by a read-back checksum comparison.
