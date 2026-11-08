# Anicca

A Connect IQ watch face for the Garmin fēnix 9 47mm / 51mm (`fenix947mm`, 454 x 454 AMOLED, Connect IQ API 6.0.3 in SDK 9.2.0). *Anicca* is Pali for impermanence: the time is made of saffron points of light that keep arising and passing away, so the face never looks quite the same twice.

## What it shows

1. The time (following the watch's 12 / 24 hour setting), drawn from points of light that appear, drift and fade within a few seconds.
2. The date above it, and the word *anicca* below.
3. A bodhi leaf above the date: glowing once a meditation activity has been recorded today, a faint dotted outline until then. From 20:00, if there is still no sit, the leaf turns ember and pulses and the date reads TIME TO SIT. Watch faces can't vibrate, so set a daily 20:00 alarm on the watch if you want a buzz too.
4. Heart rate (left), the next sunrise or sunset (right) and today's steps (middle) along the bottom.
5. Two arcs of particles: steps toward the daily goal along the bottom edge, and Garmin's move bar (one long and four short segments, ember) along the top edge.
6. Above stress 50 (Garmin's medium and high bands) the points grow restless, a faint ring of points gathers at the edge, and the word becomes *observe the breath*. There is no paced breathing: Anapana observes the natural breath.

In always-on mode only sparse, dim, still dots of the time are drawn (about 1% of the pixels), shifted a few pixels every minute against burn-in.

The animation runs during the watch's high-power window, the ~10 seconds after a wrist raise. Every drawing call is costly on the watch (drawing each point separately ran at 3 frames a second), so the points are drawn in layers: each layer is a two-color bitmap of scattered points that fades by having its palette recolored and is drawn in one call, and a layer that has faded out is redrawn with fresh points (`source/LightLayers.mc`). The date, leaf, readings and tracks are cached in a bitmap that is redrawn only when they change. The number of layers and points per layer are set at the top of `source/AniccaView.mc`; `./build.sh log-on` makes the face log its frame rate after each wrist raise.

## Feasibility probe

`./build.sh probe` builds *Anicca Probe*, a separate watch face for testing on the watch:

- **Meditation detection**: whether `UserProfile.getUserActivityHistory()` has an `Activity.SPORT_MEDITATION` activity started today, when it last checked and how long the call took, and the first two history entries (sport type, start and duration; `*` marks a start time counted from Garmin's 1989 epoch). The answer is cached and refreshed every 5 minutes, as in the face.
- **Particle budget**: after each wrist raise, the time is drawn from 240, 480, 720 and 960 points (4 to 16 layers of 60) for 2.2 seconds each, then the frame rate and milliseconds per frame of each are listed (the timer caps it at 20 fps). The simulator's numbers say nothing about the watch.

## Build

Requires the Connect IQ SDK (installed through Garmin's SDK Manager, with the fēnix 9 47mm device downloaded) and a developer key:

```sh
openssl genrsa -out ~/.garmin/developer_key.pem 4096
openssl pkcs8 -topk8 -inform PEM -outform DER -in ~/.garmin/developer_key.pem -out ~/.garmin/developer_key.der -nocrypt
```

Then:

```sh
./build.sh                  # builds bin/Anicca.prg
./build.sh simulate         # builds and opens it in the simulator
./build.sh probe simulate   # the feasibility probe, bin/AniccaProbe.prg
./build.sh log-on           # on a connected watch: log the frame rate after each wrist raise
./build.sh log              # print that log
```

## Install on the watch

1. On the watch, set Watch Settings > System > Advanced > USB Mode to MTP.
2. Connect the watch by USB and run `./build.sh install` (or `./build.sh probe install`; needs `brew install libmtp`). It copies the `.prg` into `GARMIN/Apps`, replacing the previous version.
3. Eject the watch (or unplug it): the watch installs the new version on disconnect. Then pick "Anicca" (or "Anicca Probe") from the watch face list.

`./build.sh install` stops the macOS camera services (`icdd`, `ptpcamerad`, `mscamerad-xpc`) that grab the watch; macOS restarts them by itself. OpenMTP does not recognize the fēnix 9, which is why the install uses a small libmtp program (`tools/mtp_install.c`).

## Resources

The lettering is [Jost](https://fonts.google.com/specimen/Jost) and [Spectral](https://fonts.google.com/specimen/Spectral) Light Italic (SIL Open Font License, `fonts/OFL-*.txt`). `tools/generate_resources.py` (needs Pillow) renders them to bitmap fonts, samples the time's digits into the point clouds the particles spawn from (`resources/jsonData`), flattens the bodhi leaf and heart into `source/Generated.mc`, and draws the launcher icon. Re-run it after changing sizes or shapes.
