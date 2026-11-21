# Video over RTSP

The custom image keeps the vendor media service `imp_sync_server` (it owns the
ISP and the H.265 encoder) but does **not** ship the vendor application
`doorbell.out`. Instead, a small static daemon `/usr/bin/doorbell_rtsp` talks to
`imp_sync_server` over the same System V IPC protocol the vendor client used and
re-serves the encoded stream over RTSP. No transcoding is involved: the device
only copies the encoded H.265 frames.

## Streams

| Path | Source | Codec / size / rate | Purpose |
|---|---|---|---|
| `/main` | encoder channel 1 | H.265, 2048×1536, 15 fps | recording and live view |
| `/sub` | encoder channel 2 | H.265, 512×384, 15 fps | general low-bandwidth stream |
| `/detect` | encoder channel 2, key frames only | H.265, 512×384, about 1 fps | motion/person detection on a weak CPU |

- The RTSP server listens on **TCP port 554** and also supports RTP over UDP,
  but TCP is recommended: on a lossy Wi-Fi link TCP recovers from packet loss
  better than UDP for this device.
- There is no authentication: expose the stream only inside your own LAN.
- Each stream can be consumed by several clients, but the doorbell has a single
  Wi-Fi uplink; keep the number of simultaneous consumers at the minimum (for
  example one recorder and one detector).

`/detect` sends only IRAP (key) frames, so a detection client decodes a small
fraction of the frames. The daemon asks the encoder for an IDR when a key frame
is overdue, so the detection rate does not depend on the encoder GOP length.

## Example: Frigate camera

```yaml
cameras:
  doorbell:
    enabled: true
    ffmpeg:
      inputs:
        - path: rtsp://192.0.2.20:554/main
          roles: [record]
        - path: rtsp://192.0.2.20:554/detect
          roles: [detect]
    detect:
      width: 512
      height: 384
      fps: 2
    record:
      enabled: true
```

`record` uses stream copy, so the recording keeps the full 3 MP stream without
decoding it. `detect` consumes the light key-frame stream.

## Quick checks

```sh
# what the stream is
ffprobe -v error -rtsp_transport tcp -select_streams v \
  -show_entries stream=codec_name,width,height,r_frame_rate \
  -of default=nw=1 rtsp://192.0.2.20:554/main

# decode a few seconds
ffmpeg -v error -rtsp_transport tcp -i rtsp://192.0.2.20:554/main -t 5 -f null -
```

## Limitations

- H.265 only: the encoder outputs HEVC, and browsers that cannot decode H.265
  will need a transcoding restreamer (for example go2rtc) for live view.
- No RTCP and no encryption: RTSP over plain TCP/UDP inside the LAN.
- Weak Wi-Fi (metal door, distant access point) causes stream stalls; the
  daemon reconnects, but no software can compensate for a poor radio link.
- The daemon only works together with the vendor `imp_sync_server`; it does not
  replace the ISP/encoder stack.

## Low-latency live view (WebRTC)

The RTSP server is the only video source on the device; any restreamer can sit
in front of it. A common setup is a go2rtc instance that pulls one of the
RTSP paths and republishes it as a WebRTC stream:

- use `/sub` (512×384) for interactive live view — it is much lighter for the
  battery-powered device and its Wi-Fi link, while `/main` stays reserved for
  full-quality recording;
- point the camera/NVR integration at the go2rtc stream name; WebRTC playback
  in a browser then avoids the multi-second segment latency of HLS.

The device itself does not transcode; every consumer pulls an encoded stream
directly from the encoder.
