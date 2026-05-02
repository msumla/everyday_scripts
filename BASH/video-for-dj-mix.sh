#!/bin/bash

# If this file is sourced (". ./script" or "source script"), every "exit" closes that shell
# and can kill the terminal tab — run it as ./script or bash script instead.
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    echo "Do not source this script (exit would close your shell). Run:" >&2
    echo "  ./$(basename "${BASH_SOURCE[0]}") <video_file> <audio_file>" >&2
    return 1 2>/dev/null || exit 1
fi

# Usage: ./video-for-dj-mix.sh <video_file> <audio_file>
# Optional env:
#   DJMIX_TRIM_HEAD_SEC / DJMIX_TRIM_TAIL_SEC (default 120 each; 0 = no trim)
#   DJMIX_SKIP_SILENCE_DETECT=1 — skip full-file silence scan (faster; may leave trailing silence)
#   DJMIX_NO_HWDEC=1 — disable -hwaccel auto on video decode
#   DJMIX_VT_BV / DJMIX_X264_CRF — override video speed/size (default: fast/rough video, audio unchanged)

if [ $# -ne 2 ]; then
    echo "Usage: $0 <video_file> <audio_file>"
    exit 1
fi

VIDEO_FILE=$1
AUDIO_FILE=$2

if [ ! -r "$VIDEO_FILE" ] || [ ! -r "$AUDIO_FILE" ]; then
    echo "Error: video or audio file missing or not readable." >&2
    exit 1
fi

TRIM_HEAD="${DJMIX_TRIM_HEAD_SEC:-120}"
TRIM_TAIL="${DJMIX_TRIM_TAIL_SEC:-120}"

OUTPUT_FILE="${AUDIO_FILE%.*}.mp4"
# MP4 metadata title = mix filename (not the film’s embedded title)
AUDIO_BASE="${AUDIO_FILE##*/}"
TITLE_FROM_AUDIO="${AUDIO_BASE%.*}"
META_OUT=(-map_metadata -1 -metadata "title=${TITLE_FROM_AUDIO}")

# Full HD, fast: scale to 1920×1080 with letterbox/pillarbox
VF_FHD='scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2'
# Fade in from black and fade out to black (same duration at start and end when the clip is long enough)
FADE_SEC=5

# Video: wall-clock over picture quality (YouTube will re-encode anyway). Audio stays high below.
VT_BV_MAIN="${DJMIX_VT_BV:-4500k}"
CRF_FAST="${DJMIX_X264_CRF:-45}"
if ffmpeg -hide_banner -encoders 2>/dev/null | grep -q 'h264_videotoolbox'; then
    ENC_V=(-pix_fmt yuv420p -c:v h264_videotoolbox -b:v "${VT_BV_MAIN}")
else
    ENC_V=(-pix_fmt yuv420p -c:v libx264 -preset ultrafast -tune zerolatency -crf "${CRF_FAST}")
fi

MOOV=(-movflags +faststart)

FF_THREADS=(-threads 0)
DEC_IN=()
if [ -z "${DJMIX_NO_HWDEC:-}" ]; then
    DEC_IN=(-hwaccel auto)
fi
FF_PRE=( -nostdin -hide_banner -y "${FF_THREADS[@]}" )

# AAC stereo ~320k CBR (mono sources duplicated L/R so aac_at keeps 320k; mono-only AAC often caps lower)
if ffmpeg -hide_banner -encoders 2>/dev/null | grep -q 'aac_at'; then
    AAC_OUT=(-ar 44100 -ac 2 -c:a aac_at -aac_at_mode cbr -b:a 320k)
else
    AAC_OUT=(-ar 44100 -ac 2 -c:a aac -b:a 320k)
fi

REAL_AUDIO_END="0"
if [ "${DJMIX_SKIP_SILENCE_DETECT:-0}" = "1" ]; then
    echo "Skipping silence scan (DJMIX_SKIP_SILENCE_DETECT=1); using full mix duration from ffprobe."
else
    echo "Detecting actual audio end (full decode; set DJMIX_SKIP_SILENCE_DETECT=1 to skip)..."
    REAL_AUDIO_END=$(ffmpeg -nostdin -hide_banner -loglevel error -i "$AUDIO_FILE" -af silencedetect=n=-50dB:d=1 -f null - 2>&1 | \
                     grep "silence_end" | tail -n1 | awk '{print $5}' || echo "0")
fi

if [ -z "$REAL_AUDIO_END" ] || [ "$REAL_AUDIO_END" = "0" ]; then
    echo "Using full audio length..."
    AUDIO_LENGTH=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$AUDIO_FILE")
else
    echo "Using detected audio end at: $REAL_AUDIO_END seconds"
    AUDIO_LENGTH=$REAL_AUDIO_END
fi

VIDEO_LENGTH=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$VIDEO_FILE")

if [ -z "$AUDIO_LENGTH" ] || [ -z "$VIDEO_LENGTH" ]; then
    echo "Error: ffprobe could not read duration." >&2
    exit 1
fi

EFF_VIDEO_LEN=$(echo "$VIDEO_LENGTH - $TRIM_HEAD - $TRIM_TAIL" | bc)
bc1() { echo "$1" | bc 2>/dev/null | head -1 | tr -d ' \t\r'; }

if [ "$(bc1 "$EFF_VIDEO_LEN <= 0")" = "1" ]; then
    echo "Error: trim removes more than video length (head=${TRIM_HEAD}s tail=${TRIM_TAIL}s, duration=${VIDEO_LENGTH}s)." >&2
    exit 1
fi

# Picture length for single-pass (and symmetric fades: need duration > 2×FADE_SEC for full in+out)
PT_LEN=$(echo "if ($AUDIO_LENGTH < $EFF_VIDEO_LEN) { $AUDIO_LENGTH } else { $EFF_VIDEO_LEN }" | bc -l)
PT_LEN=$(echo "$PT_LEN" | tr -d ' \n')
if [ -z "$PT_LEN" ] || [ "$(bc1 "$PT_LEN <= 0")" = "1" ]; then
    echo "Error: invalid picture length (audio=${AUDIO_LENGTH}, eff_video=${EFF_VIDEO_LEN})." >&2
    exit 1
fi
TWICE_FADE=$(echo "2 * $FADE_SEC" | bc | tr -d ' \n')
if [ "$(bc1 "$PT_LEN > $TWICE_FADE")" = "1" ]; then
    FOUT_ST=$(echo "$PT_LEN - $FADE_SEC" | bc)
    VF_SINGLE="${VF_FHD},fade=t=in:st=0:d=${FADE_SEC},fade=t=out:st=${FOUT_ST}:d=${FADE_SEC}"
else
    VF_SINGLE="${VF_FHD},fade=t=in:st=0:d=${FADE_SEC}"
fi

# Stereo output: real stereo passes through; mono → duplicate L/R; 3+ ch → fold to stereo
AUDIO_CH=$(ffprobe -v error -select_streams a:0 -show_entries stream=channels -of default=noprint_wrappers=1:nokey=1 "$AUDIO_FILE" 2>/dev/null | head -1)
AUDIO_CH=${AUDIO_CH%%.*}
AUDIO_CH=${AUDIO_CH:-2}
if [ "$AUDIO_CH" = "1" ]; then
    echo "Mix is mono; duplicating to stereo for output."
    TO_STEREO='[1:a]pan=stereo|c0<c0|c1<c0[a_st]'
else
    TO_STEREO='[1:a]aformat=sample_fmts=fltp:channel_layouts=stereo[a_st]'
fi

# Master-style: thin scope line, grey + partial transparency (yuva420p so @ alpha blends in overlay)
# asplit: one branch for showwaves, one for mux — mapping [1:a] while [1:a] feeds filters often fails ffmpeg.
WAVE_CHAIN='showwaves=s=1920x100:mode=line:rate=25:scale=sqrt:colors=9a9a9a@0.72,format=yuva420p[wave]'
FILTER_FINAL="${TO_STEREO};[a_st]asplit=2[srcw][srcm];[srcw]${WAVE_CHAIN};[0:v]${VF_SINGLE}[vb];[vb][wave]overlay=0:H-h:format=auto,format=yuv420p[outv]"
FILTER_PASS2="${TO_STEREO};[a_st]asplit=2[srcw][srcm];[srcw]${WAVE_CHAIN};[0:v][wave]overlay=0:H-h:format=auto,format=yuv420p[outv]"

REVERSE_LENGTH=$(echo "$AUDIO_LENGTH - $EFF_VIDEO_LEN" | bc)
if [ "$(bc1 "$REVERSE_LENGTH > 0")" = "1" ]; then
    NEED_REWIND=1
else
    NEED_REWIND=0
fi

CONCAT_LIST=

cleanup() {
    rm -f movie_fadein.mp4 reversed_part_fade.mp4 video_only.mp4 last_part.mp4 2>/dev/null || true
    if [ -n "${CONCAT_LIST:-}" ]; then
        rm -f "$CONCAT_LIST" 2>/dev/null || true
    fi
}

# Bash 3.2 (macOS): EXIT trap must not clobber the real exit status — save $? then re-exit after cleanup.
_exit_hook() {
    _ec=$?
    cleanup
    trap - EXIT
    exit "$_ec"
}
trap _exit_hook EXIT

if [ "$NEED_REWIND" = "0" ]; then
    echo "Single encode: trimmed film (${PT_LEN}s picture) + scope line; output stops with mix (-shortest)."
    ffmpeg "${FF_PRE[@]}" "${DEC_IN[@]}" -ss "$TRIM_HEAD" -t "$PT_LEN" -i "$VIDEO_FILE" \
        -t "$AUDIO_LENGTH" -i "$AUDIO_FILE" \
        -filter_complex "$FILTER_FINAL" \
        -map '[outv]' -map '[srcm]' -shortest \
        "${ENC_V[@]}" "${AAC_OUT[@]}" \
        "${MOOV[@]}" "${META_OUT[@]}" \
        "$OUTPUT_FILE" || { echo "ffmpeg (single pass) failed, exit=$?" >&2; exit 1; }
    exit 0
fi

# Mix longer than trimmed film: rewind tail (master flow)
REVERSE_START=$(echo "$EFF_VIDEO_LEN - $REVERSE_LENGTH" | bc)
REVERSE_START=$(printf '%.3f' "$REVERSE_START")
ABS_TAIL_SS=$(echo "$TRIM_HEAD + $REVERSE_START" | bc)
ABS_TAIL_SS=$(printf '%.3f' "$ABS_TAIL_SS")

echo "Mix is longer than trimmed film; creating rewind tail (master-style)..."
echo "Creating fade-in + tail slice in parallel..."
ffmpeg "${FF_PRE[@]}" "${DEC_IN[@]}" -ss "$TRIM_HEAD" -t "$EFF_VIDEO_LEN" -i "$VIDEO_FILE" -an \
    -vf "${VF_FHD},fade=t=in:st=0:d=${FADE_SEC}" \
    "${ENC_V[@]}" movie_fadein.mp4 &
PID_FADE=$!
ffmpeg "${FF_PRE[@]}" "${DEC_IN[@]}" -ss "$ABS_TAIL_SS" -t "$REVERSE_LENGTH" -i "$VIDEO_FILE" -an \
    -vf "$VF_FHD" \
    "${ENC_V[@]}" last_part.mp4 &
PID_TAIL=$!
EF=0 ET=0
wait "$PID_FADE" || EF=1
wait "$PID_TAIL" || ET=1
if [ "$EF" -ne 0 ] || [ "$ET" -ne 0 ]; then
    echo "ffmpeg parallel phase failed (fade-in exit=$EF, tail slice exit=$ET)." >&2
    exit 1
fi

FADE_OUT_ST=$(echo "$REVERSE_LENGTH - $FADE_SEC" | bc)
[ "$(bc1 "$FADE_OUT_ST < 0")" = "1" ] && FADE_OUT_ST=0
ffmpeg "${FF_PRE[@]}" -i last_part.mp4 -an \
    -vf "reverse,fade=t=out:st=${FADE_OUT_ST}:d=${FADE_SEC}" \
    "${ENC_V[@]}" reversed_part_fade.mp4 || { echo "ffmpeg (reverse+fade) failed, exit=$?" >&2; exit 1; }

echo "Concatenating and adding audio + scope line..."
CONCAT_LIST=$(mktemp -t djmix_concat.XXXXXX)
{
    printf "file '%s'\n" "$(pwd)/movie_fadein.mp4"
    printf "file '%s'\n" "$(pwd)/reversed_part_fade.mp4"
} > "$CONCAT_LIST"

ffmpeg "${FF_PRE[@]}" -f concat -safe 0 -i "$CONCAT_LIST" -c copy video_only.mp4 || { echo "ffmpeg (concat) failed, exit=$?" >&2; exit 1; }

ffmpeg "${FF_PRE[@]}" "${DEC_IN[@]}" -i video_only.mp4 \
    -t "$AUDIO_LENGTH" -i "$AUDIO_FILE" \
    -filter_complex "$FILTER_PASS2" \
    -map '[outv]' -map '[srcm]' -shortest \
    "${ENC_V[@]}" "${AAC_OUT[@]}" \
    "${MOOV[@]}" "${META_OUT[@]}" \
    "$OUTPUT_FILE" || { echo "ffmpeg (final mux) failed, exit=$?" >&2; exit 1; }

echo "Done! Output is in $OUTPUT_FILE"
exit 0
