# MicFixer

A tiny macOS menu bar app that keeps your Mac's audio input off Bluetooth headsets like AirPods.

When a Mac uses the AirPods microphone, macOS drops the audio going to the AirPods into low-quality "headset" mode. MicFixer watches the default input device and, whenever it switches to a Bluetooth mic, switches it straight back to your built-in microphone (or another mic you pick). Your AirPods keep playing in full quality, and their battery lasts longer.

Native Swift, runs on Apple Silicon and Intel, no Rosetta needed. Inspired by [AirPods Sound Quality Fixer](https://github.com/milgra/airpodssoundqualityfixer).

## Menu

- **Keep Bluetooth mics off**: turn the fix on or off (turn it off when you want to use the AirPods mic for a call)
- **Use this mic instead**: pick which non-Bluetooth mic to switch to (defaults to the built-in mic)
- **Open at Login**: start MicFixer automatically
- **Quit MicFixer**

## Build and install

Requires macOS 13 or later and the Xcode Command Line Tools (`xcode-select --install`).

```sh
git clone https://github.com/wilsonmakchina/MicFixer.git
cd MicFixer
./build.sh
```

This compiles the app, installs it to `/Applications/MicFixer.app`, and launches it. Look for the microphone icon in the menu bar.

## License

MIT
