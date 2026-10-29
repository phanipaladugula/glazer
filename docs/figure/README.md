# README hero figure

`build.mjs` draws Fig 1, "Head direction picks the display", as an isometric bench instrument. A sighting turret on a rotary base stands in for the user's head. Its yaw circle is engraved every 2° and carries two calibration stops: the MacBook at −4° and the LG monitor at +28°. A faint slot marks the hysteresis band around the +12° midpoint. The turret is turned to +27° and its dwell gauge is full, so the monitor's screen is the one lit part and holds the pointer. The MacBook's screen stays dark.

The model values (calibrations, hysteresis, current yaw) are constants at the top of `build.mjs`. Every angle in the drawing and the readout comes from them.

Regenerate both standalone SVGs (`docs/images/hero-light.svg`, `docs/images/hero-dark.svg`) with:

```sh
node docs/figure/build.mjs
```

`kit/` holds `iso-kit.mjs` and `lathe.mjs`, copied unchanged from the Anatomy skill (MIT, see `kit/LICENSE`). The build needs only Node 20+.
