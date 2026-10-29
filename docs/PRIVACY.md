# Privacy

Glazer uses your camera. You should know exactly what it does with it.

## What Glazer does

- When Glazer is **on**, it reads frames from the camera and measures the position and
  direction of faces in each frame. It keeps only the latest measurement in memory.
- When Glazer is **off**, the camera is off. The green camera light on your Mac tells you
  this independently of Glazer.

## What Glazer never does

- It never records, saves or uploads camera frames or images of any kind.
- It never identifies who you are. It doesn't use face recognition.
- It makes no network requests at all. There is no analytics, no crash reporting and no
  update check.

## What Glazer stores

Glazer stores its settings in your user defaults (`io.github.phanipaladugula.glazer`):
whether it is on, and, once calibration ships, a few head angles for each display. Delete
them with:

```sh
defaults delete io.github.phanipaladugula.glazer
```

## Permissions

| Permission | Why |
|---|---|
| Camera | To see which display you are facing |
| Accessibility (later) | To move keyboard focus to a window on another display |

Glazer asks for each permission only when it first needs it.

## Verifying this

Glazer is open source, so you can check these claims in the code. Camera access lives in
`Sources/GlazerSystem`, and nothing in the package imports networking APIs.
