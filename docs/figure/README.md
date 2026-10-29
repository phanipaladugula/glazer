# README hero figure

`build.mjs` draws Fig 1, "Head direction picks the display", as an isometric bench instrument. A sighting turret on a rotary base stands in for the user's head. Its yaw circle is engraved every 2° and carries two calibration stops: the MacBook at −4° and the LG monitor at +28°. A faint slot marks the hysteresis band around the +12° midpoint. The turret is turned to +27° and its dwell gauge is full, so the monitor's screen is the one lit part and holds the pointer. The MacBook's screen stays dark.

The model values (calibrations, hysteresis, current yaw) are constants at the top of `build.mjs`. Every angle in the drawing and the readout comes from them.

Regenerate both standalone SVGs (`docs/images/hero-light.svg`, `docs/images/hero-dark.svg`) with:

```sh
node docs/figure/build.mjs
```

## Animated version

`animate.mjs` renders the same figure as a 7.6 s loop at 20 fps. It writes `docs/images/hero-light.gif` and `docs/images/hero-dark.gif`. The story runs on the constants in `build.mjs`:
1. The head faces the MacBook at −4°.
2. It glances past the hysteresis band and comes back before the 0.5 s dwell fills, so nothing switches.
3. It turns to +27°. The dwell gauge fills, and only then does the lit screen and pointer move to the LG.
4. It turns back, and the MacBook relights after the dwell.

```sh
node docs/figure/animate.mjs        # add --fps 15 for smaller files, --keep to keep the frames
```

The animation needs Node 22+ (it uses the built-in WebSocket), Chrome or Chromium to rasterise the frames over the DevTools protocol (set `CHROME_PATH` to use another browser), and ffmpeg (set `FFMPEG` to use another binary). It installs no npm packages.

`kit/` holds `iso-kit.mjs` and `lathe.mjs`, copied unchanged from the Anatomy skill (MIT, see `kit/LICENSE`). The build needs only Node 20+.
