# `video-for-dj-mix.sh`

Lay a DJ mix over a film: **1080p** output tuned for **fast** video encodes (lower VideoToolbox bitrate / higher libx264 CRF by default — picture quality is not the goal; hosts re-encode anyway), **fade-in** on the picture, thin semi-transparent **grey scope line** along the bottom (`showwaves`), and **stereo AAC ~320 kb/s** in the MP4 (mono mixes are duplicated L/R so the encoder stays **stereo**).

## Requirements

- `ffmpeg`, `ffprobe`, and `bc` on your `PATH`.

## Usage

```bash
./video-for-dj-mix.sh <video_file> <audio_file>
```

Output path is the audio path with extension **`.mp4`**. The MP4 **`title`** metadata is set from the **mix filename** (without extension), not from the film file.

## Behavior

1. **Effective mix length** — By default runs a **full-file** `silencedetect` pass (slow on long mixes). Set **`DJMIX_SKIP_SILENCE_DETECT=1`** to use **ffprobe** duration only (faster; may keep trailing silence in the timeline).

2. **Trim intro/outro** — By default **2 minutes (120 s)** are skipped at the **start** and **end** of the source video (to reduce baked-in titles). Only the middle segment is used for duration math and for encoding. Override with environment variables (see below); use **`0`** to keep the full film.

3. **Full HD** — Video is scaled and padded to **1920×1080** (`force_original_aspect_ratio=decrease`).

4. **Fades** — **5 s** fade-in from black at the start of the picture, and **5 s** fade-out to black at the end when the trimmed segment is longer than **10 s** (otherwise only the fade-in is applied so the two fades do not overlap). The rewind tail uses the same **5 s** fade-out on the reversed segment.

5. **Output not longer than the mix** — The final mux uses **`-shortest`** so the file does not run past the mix.

6. **Mix shorter than the trimmed film** — One encode: only the **first *N* seconds** of the trimmed picture are used, where *N* is the mix length (picture is cut to match audio).

7. **Mix longer than the trimmed film** — Same **rewind** idea as `master`: full trimmed film with fade-in, then a **reversed** segment of the end of the film with a short fade-out, concatenated, then scope overlay and audio.

## Environment variables

| Variable | Meaning |
|----------|---------|
| `DJMIX_TRIM_HEAD_SEC` | Seconds to skip after the start of the source video (default **120**). Set **`0`** to disable. |
| `DJMIX_TRIM_TAIL_SEC` | Seconds to skip before the end of the source video (default **120**). Set **`0`** to disable. |
| `DJMIX_SKIP_SILENCE_DETECT` | Set **`1`** to skip the silence scan and use full **ffprobe** mix length (faster). |
| `DJMIX_NO_HWDEC` | Set **`1`** to disable **`-hwaccel auto`** on video decode if filters misbehave. |
| `DJMIX_VT_BV` | VideoToolbox average bitrate (default **`4500k`**; lower = faster/rougher). |
| `DJMIX_X264_CRF` | libx264 CRF when VideoToolbox is unavailable (default **`45`**; higher = faster/rougher). |

Example: no trimming, only middle of defaults turned off:

```bash
DJMIX_TRIM_HEAD_SEC=0 DJMIX_TRIM_TAIL_SEC=0 ./video-for-dj-mix.sh film.mp4 mix.mp3
```

## Temporary files (rewind path)

You may see `movie_fadein.mp4`, `last_part.mp4`, `reversed_part_fade.mp4`, and `video_only.mp4` during a run; they are removed on success. If a run fails, delete leftovers manually if you do not need them.
