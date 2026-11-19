# MQTT / Home Assistant interface (v0.6.0)

The custom daemon connects to an MQTT broker directly (no cloud service, no
vendor application). The device is a normal MQTT client with a last-will,
retained state topics and plain commands.

## Automatic discovery

The daemon publishes **MQTT discovery** configs on startup, so Home Assistant
creates the doorbell device and its entities automatically — no YAML needed:

- events: `ring`, `tamper`, `motion`;
- switches: LED, siren, "sleep allowed";
- select: IR-cut (`auto`/`on`/`off`);
- binary sensors: "on base", "charging";
- sensor: battery level.

Discovery configs are retained and published once per boot. The prefix defaults
to `homeassistant` and can be overridden in `/config/mqtt.env`
(`MQTT_DISCOVERY=<prefix>`; an empty value disables discovery). The device
block uses `identifiers: ["doorbell3s"]`; `sw_version` is taken from the
running image.

## Device configuration

The image contains no credentials. Create `/config/mqtt.env` on the device
(0600), for example:

```
MQTT_HOST=192.0.2.10
MQTT_PORT=1883
MQTT_USER=doorbell
MQTT_PASS=change-me
```

`MQTT_HOST` may be a host name. If the file is missing, the daemon still runs
(the control firmware side works: ring, motion, tamper), but nothing is
published or accepted over MQTT.

## Topics

### Events (not retained, one message per event)

| Topic | Payload |
|---|---|
| `doorbell3s/ring` | `{"event_type":"ring","uptime":N}` |
| `doorbell3s/motion` | `{"event_type":"motion","uptime":N}` |
| `doorbell3s/motion_end` | `{"event_type":"motion_end","uptime":N}` |
| `doorbell3s/tamper` | `{"event_type":"tamper","uptime":N}` |

### Retained states

| Topic | Payload |
|---|---|
| `doorbell3s/availability` | `online` / `offline` (last will) |
| `doorbell3s/led` | `{"on":0\|1}` |
| `doorbell3s/ircut` | `{"mode":"auto"\|"on"\|"off"}` |
| `doorbell3s/siren` | `{"armed":0\|1}` |
| `doorbell3s/on_base` | `{"on_base":0\|1}` |
| `doorbell3s/sleep` | `{"enabled":0\|1}` |
| `doorbell3s/battery` | `{"level":N,"charging":0\|1}` |

`availability` is published as a retained last-will (`offline`) so Home
Assistant sees the device as unavailable when the connection drops, and is
refreshed every 60 s while connected.

### Commands

| Topic | Payload | Effect |
|---|---|---|
| `doorbell3s/led/set` | `ON` / `OFF` | white ring LED |
| `doorbell3s/ircut/set` | `auto` / `on` / `off` | IR-cut filter |
| `doorbell3s/siren/set` | `ON` / `OFF` | arm/disarm the tamper alarm (chime loop, 30 s) |
| `doorbell3s/sleep/set` | `ON` / `OFF` | allow / forbid low-power sleep (`ON` = may sleep) |

## Home Assistant YAML

Drop this into your MQTT configuration (a package file is convenient):

```yaml
mqtt:
  event:
    - name: "Doorbell ring"
      unique_id: doorbell3s_ring
      state_topic: "doorbell3s/ring"
      event_types: ["ring"]
    - name: "Doorbell tamper"
      unique_id: doorbell3s_tamper
      state_topic: "doorbell3s/tamper"
      event_types: ["tamper"]
  switch:
    - name: "Doorbell LED"
      unique_id: doorbell3s_led
      state_topic: "doorbell3s/led"
      value_template: "{{ value_json.on }}"
      state_on: "1"
      state_off: "0"
      command_topic: "doorbell3s/led/set"
      payload_on: "ON"
      payload_off: "OFF"
      availability_topic: "doorbell3s/availability"
    - name: "Doorbell siren"
      unique_id: doorbell3s_siren
      state_topic: "doorbell3s/siren"
      value_template: "{{ value_json.armed }}"
      state_on: "1"
      state_off: "0"
      command_topic: "doorbell3s/siren/set"
      payload_on: "ON"
      payload_off: "OFF"
      availability_topic: "doorbell3s/availability"
    - name: "Doorbell sleep allowed"
      unique_id: doorbell3s_sleep
      state_topic: "doorbell3s/sleep"
      value_template: "{{ value_json.enabled }}"
      state_on: "1"
      state_off: "0"
      command_topic: "doorbell3s/sleep/set"
      payload_on: "ON"
      payload_off: "OFF"
      availability_topic: "doorbell3s/availability"
  select:
    - name: "Doorbell IR-cut"
      unique_id: doorbell3s_ircut
      state_topic: "doorbell3s/ircut"
      value_template: "{{ value_json.mode }}"
      command_topic: "doorbell3s/ircut/set"
      options: ["auto", "on", "off"]
      availability_topic: "doorbell3s/availability"
  binary_sensor:
    - name: "Doorbell on base"
      unique_id: doorbell3s_on_base
      state_topic: "doorbell3s/on_base"
      value_template: "{{ value_json.on_base }}"
      payload_on: "1"
      payload_off: "0"
      availability_topic: "doorbell3s/availability"
  sensor:
    - name: "Doorbell battery"
      unique_id: doorbell3s_battery
      state_topic: "doorbell3s/battery"
      value_template: "{{ value_json.level }}"
      unit_of_measurement: "%"
      device_class: battery
      availability_topic: "doorbell3s/availability"
```

Notes:

- the `switch` example above intentionally shows both `state_topic` values and
  command payloads; keep `payload_on`/`payload_off` pairs consistent per entity;
- notifications/automations are user-specific — trigger on the `event` entities
  (`event.doorbell_ring`, `event.doorbell_tamper`) or on raw `doorbell3s/ring`;
- state topics are retained, so a restarting Home Assistant picks the current
  state immediately.

## Verifying from a workstation

```bash
# subscribe to everything with any MQTT client
<client> subscribe --host 192.0.2.10 --topic 'doorbell3s/#' -v

# publish a command
<client> publish --host 192.0.2.10 --topic doorbell3s/led/set --message ON
```

Latency measured on a local network: LED commands 5–50 ms, IR-cut ~200 ms
(150 ms of that is the filter GPIO sequence).

## Troubleshooting

- No states at all: check `/config/mqtt.env` exists and the daemon log
  (`/tmp/doorbeld.log`) contains `MQTT connected <host>:<port>`.
- `availability` shows `offline` while the device is on: an old retained value
  may survive a broker switch; the daemon republishes `online` every 60 s.
- If the broker is on a different L2 segment and commands intermittently stall
  for tens of seconds while events still flow, ask the network administrator
  for a **static ARP entry** for the doorbell on its gateway. A sleeping Wi-Fi
  station may not answer on-demand ARP reliably; this was the root cause of
  multi-second stalls seen during development.
