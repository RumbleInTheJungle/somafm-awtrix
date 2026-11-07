# Notice: SomaFM's streams and data

**Unofficial hobby project, not affiliated with or endorsed by SomaFM but used with their permission.**

SomaFM gave this project permission by email in November 2026.

## SomaFM is not a free data feed

SomaFM's streams and JSON files are not free to use in radio apps, games or other software. Read the [SomaFM Terms of Service](https://somafm.com/contact/tos.html) first, and ask SomaFM before you build on them.

SomaFM is listener-supported. Third-party apps cost them real money in bandwidth and especially music royalties, and going over certain listener numbers moves them to much higher commercial royalty rates.

## If you fork or reuse this code

- **The permission doesn't come with the code.** It was given to this project. A fork or a derived app needs its own permission from SomaFM.
- **The MIT licence covers this project's code only.** It gives you no rights to SomaFM's streams, `channels.json`, name, channel names and descriptions, logos or other content.
- **Change the User-Agent.** Set `sf.USER_AGENT` in `scripts/somafm.be` and `UA` in `tools/` to your own project's name and address, so SomaFM can tell your project apart from this one.

## Logos

SomaFM's logos and channel logos are copyrighted by SomaFM. They allowed this project to convert them for this radio app. Any other use requires permission from SomaFM. The logos are not in this repository.

The colour bar for each channel is picked automatically from the main colour of its logo.

## User-Agent

SomaFM asked this project to identify itself, so it doesn't get blocked by mistake.

| Request | User-Agent |
|---|---|
| `channels.json` from the clock, only when **Update channel list** is used | `somafm-awtrix/2.1 (+https://github.com/RumbleInTheJungle/somafm-awtrix)` |
| `channels.json` and logos from `tools/` | `somafm-awtrix-tools/2.0 (+https://github.com/RumbleInTheJungle/somafm-awtrix)` |
| `.pls` playlists and audio streams | `AWTRIX-NG`, set by the firmware (measured on firmware 1.2.3) |

AWTRIX-NG's documentation has no option for setting the User-Agent of a radio stream from a script, so the streams can't carry this project's name for now.
