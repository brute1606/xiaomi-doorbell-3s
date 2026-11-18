# Replacing the vendor application

The vendor application `doorbell.out` is not required to keep the device
working. This page summarizes what the application actually does, how its
interfaces were reverse engineered, and a working replacement path that keeps
the Wi-Fi module and the control/power firmware untouched.

## Architecture

Two vendor daemons stay in place:

| Component | Role |
|---|---|
| `agent` | JSON-RPC bridge to the control/power firmware over UART; owns the MCU state (events, LED, siren, power) |
| `imp_sync_server` | video/ISP service (kept as-is for now) |

The application connects to `agent` on a local TCP port and uses two
connections:

1. **RPC connection** — handshake (`_internal.helper_ready`, `_internal.hello`)
   and request/response methods (`local.*`, `ext.*`, `_sync.*`).
2. **Event connection** — the agent pushes device events here
   (`ext.wifi_cmd`, `ext.soc_cmd`, cloud `get_properties`, …).

On the RPC/event channels the application sends and receives small frames in
hex form, e.g. `{"method":"ext.wifi_cmd","params":{"wifi_cmd":"7b0809050000007f"}}`.
The first byte after `7b` is the frame length and the last byte is an XOR
checksum.

## Events

The two most important event frames observed on a live device:

| Frame | Meaning |
|---|---|
| `7b0809 04 …` | doorbell button pressed |
| `7b0809 05 …` | PIR motion started |
| `7b0809 02 …` | PIR motion ended |
| `7b0809 80 …` | tamper (removal) button |
| `7b0488f7` | command sent back to play the doorbell chime |

A replacement daemon that accepts the event connection, watches for `7b0809…`
and sends `7b0488f7` back rings the chime exactly like the stock firmware.

## Autonomous sleep and wake

Sleep is not a single command. The vendor application performs a short
sequence of frames when it decides to sleep:

```
7b059c01e3
7b059400ea
7b058700f9
7b058903f4
7b059801e7
```

After that sequence the control firmware powers the SoC off while keeping the
wake sources armed. Pressing the doorbell button powers the SoC back on; the
device boots, the daemon starts and rings the chime again. Replaying the same
sequence from a replacement daemon gives an equivalent sleep/wake cycle
(verified on hardware).

Notes:

- Sending only the `local.lowpower_set` RPC request does **not** start the
  sleep sequence.
- The sleep frames above were captured from the vendor application; the
  control firmware stays on its own firmware.
- An idle timeout in the replacement daemon (e.g. 150 s, reset by button/PIR
  events) is enough to reproduce the stock behaviour. Do not patch
  `fj_system_soc_powerOff` in the vendor binary: the patch breaks wake
  sources and the button stops waking the device.

## Events and notifications

The PIR sensor only reports events after the factory initialization frames
(`SetTrigger`, `PIRInterval`, `PIRSetSensitivity`) are sent to the control
firmware on startup — a replacement daemon must repeat them.



The replacement daemon also pushes each event as a single line to the local hub
(`<topic> <json>`); a tiny hub-side relay publishes it to MQTT, so Home
Assistant automations can react to rings, motion and tamper events. The device
itself does not need a direct route to the MQTT broker.

## Home Assistant integration

Events are relayed over MQTT to Home Assistant and exposed as MQTT event
entities (`event_type` payload). An existing Node-RED voice-announcement flow
built for the vendor integration is reused: the new entities were added to the
same state triggers, so button presses, tamper and motion keep the original
scenario. Note that the Home Assistant MQTT event platform expects the payload
`{"event_type": "<type>"}`.

## Watchdog

The vendor application is the watchdog owner. In a replacement image either
the daemon itself owns `/dev/watchdog` or a small feeder does it while the
daemon refreshes a keepalive file. Without a feeder the SoC resets after the
hardware timeout.

## Control channel stays independent

Our `poller`/`logs` scripts run from `rcS` and do not depend on the
application, so the command channel and the log stream keep working in both
modes. This makes it possible to switch between the vendor application and a
replacement daemon with a single config flag and to roll back remotely.

## Pre-flash gate

Before flashing any region, run the sandbox gate (see
[docs/07-sandbox-qemu.md](07-sandbox-qemu.md)). A good gate checks:

- region size, header and tail padding;
- LZO compression and cpio trailer;
- required files (`rcS`, network config, daemon, scripts);
- **shell syntax of `rcS`** (a broken `rcS` leaves the device without network
  and without a shell — recoverable only with a programmer);
- presence of the application start line and a single poller;
- boot in QEMU: kernel starts, application/daemon starts, no panic.

## Current status (v0.5.0)

| Feature | State |
|---|---|
| Vendor application removed | working (not in the image) |
| Control channel (outbound), logs, OTA | working, optional |
| Local doorbell chime without vendor app | working |
| Autonomous sleep and button wake without vendor app | working |
| Sleep control from Home Assistant | working (`doorbell3s/sleep/set`) |
| PIR motion events | working (factory init frames required) |
| Tamper (removal) button | working (event published) |
| Battery level and charging | working (from control-firmware telemetry) |
| Ring LED (white/orange) | working (`doorbell3s/led/set`) |
| IR-cut filter | working (`doorbell3s/ircut/set`; ~150 ms GPIO sequence) |
| Tamper siren (chime loop) | working (`doorbell3s/siren/set`, 30 s) |
| "On base" state | working (`doorbell3s/on_base`) |
| MQTT / Home Assistant integration | working, direct connection to any broker |
| Video / RTSP | not implemented (`imp_sync_server` kept, no client) |

The replacement daemon opens the same local JSON-RPC connection the vendor
application used, replays the control-firmware initialization frames, publishes
events and retained states over MQTT and accepts commands. See
[docs/15-mqtt-home-assistant.md](15-mqtt-home-assistant.md) for the topic map
and Home Assistant examples.

### Notes

- Sleep is initiated by the daemon after an idle period (default 150 s). The
  wake sources stay armed: the button, the PIR sensor and the tamper switch wake
  the SoC, which boots and rings the chime. `/config/no_sleep` disables sleep
  entirely, and the `sleep` MQTT switch toggles it remotely.
- The LED is driven through GPIO: the white and the orange ring segments are
  separate lines. Both can be switched independently at the MQTT level by using
  the raw command channel if needed.
- The IR-cut filter is driven by a three-line GPIO sequence copied from the
  vendor binary; the filter clicks audibly when it switches.
- Battery telemetry comes from the control firmware (level and charging flag);
  values are published only when the charging state is known.
- If the broker is on a different L2 segment than the doorbell, add a static ARP
  entry for the doorbell on its gateway. A sleeping Wi-Fi station may not answer
  on-demand ARP; this caused multi-second stalls during development and was
  fixed network-side.
