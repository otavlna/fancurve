# fancurve

**English** · [Čeština](README.cs.md)

A custom temperature-based fan curve for the 14" MacBook Pro with M4 Pro (Mac16,8). Once the CPU passes 90 °C under load it takes over the fans and runs them at full speed from 100 °C, because Apple's default fan control ramps up late and the CPU thermal throttles.

This is not a finished app, just a shell script. It writes to the fans through the `smc` tool bundled with [Stats.app](https://github.com/exelban/stats), runs as a system service (LaunchDaemon) and is controlled with the `fanctl` command.

## Requirements

- A Mac with Apple Silicon (tuned on M4 Pro, Mac16,8)
- Stats.app installed in `/Applications`, with fans set to automatic in Stats
- No other fan control tool running (Macs Fan Control, TG Pro)

On a different model, first check the fan speed range with `/Applications/Stats.app/Contents/Resources/smc fans` and set `MAX_RPM` in `fancurve.sh` to the maximum. `MIN_RPM` is the speed the curve starts at and must not be below the hardware minimum.

## Installation

```sh
git clone https://github.com/otavlna/fancurve.git
cd fancurve
sudo ./fanctl install   # the curve stays off after install
fanctl test             # optional: watch it live in the terminal, Ctrl+C to stop
fanctl on
```

## Usage

For everyday use, `fanctl on` and `fanctl off` are all you need. Commands that change the system ask for your sudo password on their own.

| Command | What it does | Password |
| --- | --- | --- |
| `fanctl on` | Turns the curve on now and after every reboot | yes |
| `fanctl off` | Turns the curve off and hands the fans back to macOS, stays off after reboot | yes |
| `fanctl status` | Shows whether the curve is running and the current speed of both fans | no |
| `fanctl test` | Runs the curve in the terminal, printing every second, Ctrl+C to stop | yes |
| `fanctl install` | One-time installation, the curve is off afterwards | yes |
| `fanctl uninstall` | Removes the service, the script and `fanctl`, fans go back to automatic | yes |
| `fanctl help` | Prints this list | no |

## How the curve works

Below 90 °C macOS controls the fans as usual. At 90 °C the script takes over, starts the fans at 4500 rpm and speeds them up linearly with temperature, reaching full speed at 100 °C.

| CPU temperature | Speed (both fans) | Script variable |
| --- | --- | --- |
| below 90 °C | macOS automatic | — |
| 90 °C | 4500 rpm (`MIN_RPM`) | `T_ON` |
| 95 °C | 6163 rpm | — |
| 100 °C and above | 7826 rpm (`MAX_RPM`) | `T_FULL` |
| drops below 85 °C | back to automatic | `T_OFF` |

- **Hysteresis:** once the script takes over, it hands the fans back to macOS only below 85 °C, not as soon as the temperature drops under 90 °C. Between 85 and 90 °C the fans stay at 4500 rpm. This keeps the fans from flipping back and forth when the temperature hovers around the threshold.
- **Sensor:** the highest reading across the CPU core sensors (SMC keys `Tp*` for performance cores, `Te*` for efficiency cores).
- **Interval:** temperature is read and fan speed set every second (`INTERVAL`).
- **On exit:** the script always calls `smc reset`, so the fans never stay stuck in manual mode.

During normal work and moderate load (below 90 °C) the script does nothing and the fans are as quiet as without it.

## Where things live

After `fanctl install` everything is in these locations. The cloned repo is no longer needed.

| File | Path |
| --- | --- |
| Control command | `/usr/local/bin/fanctl` |
| Curve script | `/usr/local/libexec/fancurve.sh` |
| Service definition | `/Library/LaunchDaemons/io.github.otavlna.fancurve.plist` |
| Error log | `/var/log/fancurve.err` |
| SMC tool (part of Stats) | `/Applications/Stats.app/Contents/Resources/smc` |

The launchd service name is `io.github.otavlna.fancurve`. The curve depends on Stats.app: if you uninstall Stats, it stops working.

## Changing the thresholds

The thresholds are set directly in the script and take effect after restarting the service.

1. Open the script: `sudo nano /usr/local/libexec/fancurve.sh`
2. At the top, change `T_ON` (when the script takes over the fans), `T_FULL` (when they run at full speed) and `T_OFF` (when macOS gets them back). Always keep `T_OFF` a few degrees below `T_ON`.
3. Restart the service: `fanctl off`, then `fanctl on`.
4. Check: `fanctl status`.

To print the whole curve without changing anything, run `fancurve.sh --table`. For a dry run that only shows what the script would set, run `fancurve.sh --dry-run 60` (the number is how long to run, in seconds).

To keep the change in the repo as well, edit `fancurve.sh` here and run `sudo ./fanctl install` and `fanctl on` again.

## Troubleshooting

If the fans behave strangely, this command always hands them back to macOS, even without `fanctl`:

```sh
sudo /Applications/Stats.app/Contents/Resources/smc reset
```

| Symptom | What to do |
| --- | --- |
| Fans run at full speed while idle | `fanctl off`, then `fanctl status`. If they are still in manual mode, run `smc reset` above. |
| `fanctl status` says OFF although it is on | Check `/var/log/fancurve.err`. The most common cause is a missing or updated Stats.app. |
| Fan speed jumps around or is set differently | Make sure Stats does not have the fans in manual mode. They must be on automatic. |
| After installing Macs Fan Control or TG Pro | These have their own fan control and would fight the curve. Use only one of them. |
| `fanctl: command not found` | Not installed, or `/usr/local/bin` is missing from `PATH`. Run `/usr/local/bin/fanctl` directly. |
