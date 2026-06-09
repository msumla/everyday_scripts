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
#   DJMIX_REWIND=1|0 — force rewind or single-pass (default: auto from measured durations)
#   DJMIX_AUDIO_LENGTH — override mix length in seconds (bypasses silence detect / ffprobe audio duration)
#   DJMIX_NO_HWDEC=1 — disable -hwaccel auto on video decode
#   DJMIX_FPS — output frame rate (default 25; set 0 or source to keep input fps, e.g. 60)
#   DJMIX_VT_BV / DJMIX_X264_CRF — override video speed/size (default: fast/rough video, audio unchanged)
#   DJMIX_PROGRESS_SEC — update interval in seconds (default 2; one in-place status line)
#   DJMIX_PROGRESS_MULTILINE=1 — print a new line each update instead of overwriting one line

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

# Full HD: scale + letterbox; default 25 fps (much faster than 60 fps sources; fine for YouTube)
OUT_FPS="${DJMIX_FPS:-25}"
VF_SCALE='scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2'
if [ -n "$OUT_FPS" ] && [ "$OUT_FPS" != "0" ] && [ "$(echo "$OUT_FPS > 0" | bc 2>/dev/null)" = "1" ]; then
    VF_FHD="${VF_SCALE},fps=${OUT_FPS}"
else
    VF_FHD="$VF_SCALE"
    OUT_FPS=
fi
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

bc1() { echo "$1" | bc 2>/dev/null | head -1 | tr -d ' \t\r'; }

fmt_dur() {
    local s="${1%%.*}"
    [ -z "$s" ] && s=0
    printf '%dh%02dm%02ds' $((s / 3600)) $(((s % 3600) / 60)) $((s % 60))
}

fmt_size() {
    local b="${1%%.*}"
    [ -z "$b" ] || [ "$b" -lt 0 ] 2>/dev/null && b=0
    if [ "$b" -ge 1073741824 ] 2>/dev/null; then
        printf '%.1f GiB' "$(echo "scale=1; $b / 1073741824" | bc)"
    elif [ "$b" -ge 1048576 ] 2>/dev/null; then
        printf '%.0f MiB' "$(echo "scale=0; $b / 1048576" | bc)"
    elif [ "$b" -ge 1024 ] 2>/dev/null; then
        printf '%.0f KiB' "$(echo "scale=0; $b / 1024" | bc)"
    else
        printf '%s B' "$b"
    fi
}

PROGRESS_FILE=
PROGRESS_START=0
PROGRESS_OUT=
FFMPEG_PID=

_progress_val() {
    local key=$1
    [ -f "$PROGRESS_FILE" ] || return 1
    grep "^${key}=" "$PROGRESS_FILE" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d '\r'
}

# Write status to controlling terminal (required for in-place \r updates).
_pout() {
    if [ -n "${PROGRESS_OUT:-}" ]; then
        printf "$@" >"$PROGRESS_OUT"
    else
        printf "$@"
    fi
}

# 20-char bar from percent (0–100).
_progress_bar() {
    local pct_i=$1 filled i bar=""
    [ -z "$pct_i" ] && pct_i=0
    [ "$(bc1 "$pct_i < 0")" = "1" ] && pct_i=0
    [ "$(bc1 "$pct_i > 100")" = "1" ] && pct_i=100
    filled=$(echo "scale=0; $pct_i * 20 / 100" | bc)
    [ -z "$filled" ] && filled=0
    i=0
    while [ "$i" -lt "$filled" ]; do bar="${bar}="; i=$((i + 1)); done
    [ "$filled" -lt 20 ] && bar="${bar}>"
    i=$((filled + 1))
    while [ "$i" -lt 20 ]; do bar="${bar} "; i=$((i + 1)); done
    printf '[%s]' "$bar"
}

# Third arg: 0 = overwrite same terminal line (default), 1 = print newline.
_print_progress_line() {
    local label=$1 target_sec=$2 nl=${3:-0}
    local out_s out_sec size_b speed out_dur target_dur pct_f pct_i pct_disp
    local now elapsed elapsed_d remain eta_wall eta_d finish_at bar
    out_s=$(_progress_val out_time_us)
    size_b=$(_progress_val total_size)
    speed=$(_progress_val speed)
    [ -z "$out_s" ] && return 1
    out_sec=$(echo "scale=3; $out_s / 1000000" | bc)
    out_dur=$(fmt_dur "$(echo "$out_sec / 1" | bc)")

    _progress_eol() {
        [ "$nl" = "1" ] && _pout '\n'
    }
    _progress_bol() {
        [ "$nl" != "1" ] && _pout '\r\033[K'
    }

    if [ -n "$target_sec" ] && [ "$(bc1 "$target_sec > 0")" = "1" ]; then
        pct_f=$(echo "scale=1; 100 * $out_sec / $target_sec" | bc)
        [ "$(bc1 "$pct_f > 100")" = "1" ] && pct_f=100.0
        pct_i=$(echo "scale=0; $pct_f / 1" | bc)
        target_dur=$(fmt_dur "$target_sec")
        bar=$(_progress_bar "$pct_i")
        pct_disp=$(echo "$pct_f" | awk '{printf "%4.1f", $1+0}')

        elapsed=0
        elapsed_d="0h00m00s"
        eta_d="?"
        finish_at=""
        if [ "${PROGRESS_START:-0}" -gt 0 ] 2>/dev/null; then
            now=$(date +%s)
            elapsed=$((now - PROGRESS_START))
            elapsed_d=$(fmt_dur "$elapsed")
            remain=$(echo "scale=0; $target_sec - $out_sec" | bc)
            [ "$(bc1 "$remain < 0")" = "1" ] && remain=0
            speed_n=$(echo "$speed" | tr -d 'x' | tr -d ' ')
            if [ -n "$speed_n" ] && [ "$(bc1 "$speed_n > 0")" = "1" ] && [ "$(bc1 "$remain > 0")" = "1" ]; then
                eta_wall=$(echo "scale=0; $remain / $speed_n" | bc)
                eta_d=$(fmt_dur "$eta_wall")
                finish_at=$(date -r "$((now + eta_wall))" '+%H:%M' 2>/dev/null || true)
            elif [ "$(bc1 "$pct_f > 0.5")" = "1" ]; then
                eta_wall=$(echo "scale=0; $elapsed * (100 / $pct_f - 1)" | bc)
                eta_d=$(fmt_dur "$eta_wall")
                finish_at=$(date -r "$((now + eta_wall))" '+%H:%M' 2>/dev/null || true)
            fi
        fi

        _progress_bol
        if [ -n "$finish_at" ]; then
            _pout '[%s] vid %s | %s %s%%  time %s / %s  |  elapsed %s  left ~%s (~%s)  |  %s  %s' \
                "$label" "$target_dur" "$bar" "$pct_disp" "$out_dur" "$target_dur" \
                "$elapsed_d" "$eta_d" "$finish_at" "$(fmt_size "${size_b:-0}")" "${speed:-?}"
        else
            _pout '[%s] vid %s | %s %s%%  time %s / %s  |  elapsed %s  left ~%s  |  %s  %s' \
                "$label" "$target_dur" "$bar" "$pct_disp" "$out_dur" "$target_dur" \
                "$elapsed_d" "$eta_d" "$(fmt_size "${size_b:-0}")" "${speed:-?}"
        fi
        _progress_eol
    else
        _progress_bol
        _pout '[%s] time %s  size %s  speed %s' \
            "$label" "$out_dur" "$(fmt_size "${size_b:-0}")" "${speed:-?}"
        _progress_eol
    fi
}

# ffmpeg in background; status loop in foreground (background jobs cannot \r the terminal).
run_ffmpeg() {
    local label=$1 target_sec=$2
    local interval="${DJMIX_PROGRESS_SEC:-2}" nl=0 ec=0
    shift 2
    FFMPEG_PID=
    PROGRESS_START=$(date +%s)
    PROGRESS_FILE=$(mktemp -t djmix_progress.XXXXXX)
    : >"$PROGRESS_FILE"

    if [ "${DJMIX_PROGRESS_MULTILINE:-0}" = "1" ]; then
        nl=1
        PROGRESS_OUT=
    elif [ -w /dev/tty ] 2>/dev/null; then
        PROGRESS_OUT=/dev/tty
    else
        nl=1
        PROGRESS_OUT=
    fi

    ffmpeg "${FF_PRE[@]}" -progress "$PROGRESS_FILE" -nostats -loglevel warning "$@" &
    FFMPEG_PID=$!

    while kill -0 "$FFMPEG_PID" 2>/dev/null; do
        if [ -f "$PROGRESS_FILE" ] && [ "$(_progress_val progress 2>/dev/null)" != "end" ]; then
            _print_progress_line "$label" "$target_sec" "$nl" || true
        fi
        sleep "$interval"
    done
    wait "$FFMPEG_PID" || ec=$?

    if [ -f "$PROGRESS_FILE" ]; then
        _print_progress_line "$label" "$target_sec" 1 || true
    fi
    if [ "${PROGRESS_START:-0}" -gt 0 ] 2>/dev/null; then
        _pout '[%s] finished in %s\n' "$label" "$(fmt_dur "$(($(date +%s) - PROGRESS_START))")"
    else
        _pout '[%s] finished\n' "$label"
    fi

    rm -f "$PROGRESS_FILE"
    PROGRESS_FILE=
    FFMPEG_PID=
    PROGRESS_OUT=
    return "$ec"
}

echo "=== Measuring inputs ==="
VIDEO_LENGTH=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$VIDEO_FILE")
AUDIO_PROBE=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$AUDIO_FILE")
if [ -z "$VIDEO_LENGTH" ] || [ -z "$AUDIO_PROBE" ]; then
    echo "Error: ffprobe could not read duration." >&2
    exit 1
fi
echo "Film (ffprobe):  $(fmt_dur "$VIDEO_LENGTH") (${VIDEO_LENGTH}s)"
echo "Mix file probe:  $(fmt_dur "$AUDIO_PROBE") (${AUDIO_PROBE}s)"

if [ -n "${DJMIX_AUDIO_LENGTH:-}" ]; then
    AUDIO_LENGTH=$DJMIX_AUDIO_LENGTH
    echo "Mix length:      $(fmt_dur "$AUDIO_LENGTH") (${AUDIO_LENGTH}s) [DJMIX_AUDIO_LENGTH]"
elif [ "${DJMIX_SKIP_SILENCE_DETECT:-0}" = "1" ]; then
    AUDIO_LENGTH=$AUDIO_PROBE
    echo "Mix length:      $(fmt_dur "$AUDIO_LENGTH") (${AUDIO_LENGTH}s) [ffprobe; DJMIX_SKIP_SILENCE_DETECT=1]"
else
    echo "Scanning mix for end of program audio (full decode; DJMIX_SKIP_SILENCE_DETECT=1 to skip)..."
    REAL_AUDIO_END=$(ffmpeg -nostdin -hide_banner -loglevel error -i "$AUDIO_FILE" -af silencedetect=n=-50dB:d=1 -f null - 2>&1 | \
                     grep "silence_end" | tail -n1 | awk '{print $5}' || echo "0")
    if [ -z "$REAL_AUDIO_END" ] || [ "$REAL_AUDIO_END" = "0" ]; then
        AUDIO_LENGTH=$AUDIO_PROBE
        echo "Mix length:      $(fmt_dur "$AUDIO_LENGTH") (${AUDIO_LENGTH}s) [ffprobe; no silence_end]"
    else
        AUDIO_LENGTH=$REAL_AUDIO_END
        if [ "$(bc1 "$AUDIO_LENGTH > $AUDIO_PROBE")" = "1" ]; then
            echo "Capping detected mix end to ffprobe duration ($(fmt_dur "$AUDIO_PROBE"))."
            AUDIO_LENGTH=$AUDIO_PROBE
        fi
        echo "Mix length:      $(fmt_dur "$AUDIO_LENGTH") (${AUDIO_LENGTH}s) [silencedetect]"
    fi
fi

EFF_VIDEO_LEN=$(echo "$VIDEO_LENGTH - $TRIM_HEAD - $TRIM_TAIL" | bc)
echo "Trimmed film:    $(fmt_dur "$EFF_VIDEO_LEN") (${EFF_VIDEO_LEN}s) [skip head ${TRIM_HEAD}s + tail ${TRIM_TAIL}s]"

if [ "$(bc1 "$EFF_VIDEO_LEN <= 0")" = "1" ]; then
    echo "Error: trim removes more than video length (head=${TRIM_HEAD}s tail=${TRIM_TAIL}s, duration=${VIDEO_LENGTH}s)." >&2
    exit 1
fi

# --- Choose algorithm from measured lengths (override with DJMIX_REWIND=0|1) ---
REVERSE_LENGTH=$(echo "$AUDIO_LENGTH - $EFF_VIDEO_LEN" | bc)
ALGO=
ALGO_REASON=
case "${DJMIX_REWIND:-}" in
    0)
        ALGO=single
        ALGO_REASON="DJMIX_REWIND=0"
        ;;
    1)
        ALGO=rewind
        ALGO_REASON="DJMIX_REWIND=1"
        ;;
esac
if [ -z "$ALGO" ]; then
    if [ "$(bc1 "$AUDIO_LENGTH <= $EFF_VIDEO_LEN")" = "1" ]; then
        ALGO=single
        ALGO_REASON="mix ($(fmt_dur "$AUDIO_LENGTH")) fits in trimmed film ($(fmt_dur "$EFF_VIDEO_LEN"))"
    elif [ "$(bc1 "$VIDEO_LENGTH >= $AUDIO_LENGTH")" = "1" ]; then
        ALGO=single
        ALGO_REASON="full film ($(fmt_dur "$VIDEO_LENGTH")) is longer than mix ($(fmt_dur "$AUDIO_LENGTH"))"
    else
        ALGO=rewind
        ALGO_REASON="mix ($(fmt_dur "$AUDIO_LENGTH")) exceeds film ($(fmt_dur "$VIDEO_LENGTH")) by $(fmt_dur "$REVERSE_LENGTH") after trim"
    fi
fi

echo "=== Algorithm: ${ALGO} ==="
if [ "$ALGO" = "single" ]; then
    echo "One ffmpeg pass: trimmed film + scope; -shortest ends with mix."
    [ -n "$ALGO_REASON" ] && echo "Because: ${ALGO_REASON}."
elif [ "$ALGO" = "rewind" ]; then
    echo "Multi-pass rewind tail (slow). Override with DJMIX_REWIND=0 to truncate at film end."
    [ -n "$ALGO_REASON" ] && echo "Because: ${ALGO_REASON}."
else
    echo "Error: internal algorithm must be single or rewind." >&2
    exit 1
fi
echo ""

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
WAVE_RATE="${OUT_FPS:-25}"
WAVE_CHAIN="showwaves=s=1920x100:mode=line:rate=${WAVE_RATE}:scale=sqrt:colors=9a9a9a@0.72,format=yuva420p[wave]"
FILTER_FINAL="${TO_STEREO};[a_st]asplit=2[srcw][srcm];[srcw]${WAVE_CHAIN};[0:v]${VF_SINGLE}[vb];[vb][wave]overlay=0:H-h:format=auto,format=yuv420p[outv]"
FILTER_PASS2="${TO_STEREO};[a_st]asplit=2[srcw][srcm];[srcw]${WAVE_CHAIN};[0:v][wave]overlay=0:H-h:format=auto,format=yuv420p[outv]"

CONCAT_LIST=

cleanup() {
    if [ -n "${FFMPEG_PID:-}" ]; then
        kill "$FFMPEG_PID" 2>/dev/null
        wait "$FFMPEG_PID" 2>/dev/null
        FFMPEG_PID=
    fi
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

if [ "$ALGO" = "single" ]; then
    if [ -n "$OUT_FPS" ]; then
        echo "Encoding — output vid $(fmt_dur "$PT_LEN") @ ${OUT_FPS}fps (status every ${DJMIX_PROGRESS_SEC:-2}s)..."
    else
        echo "Encoding — output vid $(fmt_dur "$PT_LEN") @ source fps (status every ${DJMIX_PROGRESS_SEC:-2}s)..."
    fi
    run_ffmpeg "encode" "$PT_LEN" "${DEC_IN[@]}" -ss "$TRIM_HEAD" -t "$PT_LEN" -i "$VIDEO_FILE" \
        -t "$AUDIO_LENGTH" -i "$AUDIO_FILE" \
        -filter_complex "$FILTER_FINAL" \
        -map '[outv]' -map '[srcm]' -shortest \
        "${ENC_V[@]}" "${AAC_OUT[@]}" \
        "${MOOV[@]}" "${META_OUT[@]}" \
        "$OUTPUT_FILE" || { echo "ffmpeg (single pass) failed, exit=$?" >&2; exit 1; }
    echo "Done! Output is in $OUTPUT_FILE"
    exit 0
fi

# Mix longer than trimmed film: rewind tail (master flow)
REVERSE_START=$(echo "$EFF_VIDEO_LEN - $REVERSE_LENGTH" | bc)
REVERSE_START=$(printf '%.3f' "$REVERSE_START")
ABS_TAIL_SS=$(echo "$TRIM_HEAD + $REVERSE_START" | bc)
ABS_TAIL_SS=$(printf '%.3f' "$ABS_TAIL_SS")

echo "Rewind pass 1/4: fade-in film + tail slice (parallel)..."
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
run_ffmpeg "rewind 2/4 reverse" "$REVERSE_LENGTH" -i last_part.mp4 -an \
    -vf "reverse,fade=t=out:st=${FADE_OUT_ST}:d=${FADE_SEC}" \
    "${ENC_V[@]}" reversed_part_fade.mp4 || { echo "ffmpeg (reverse+fade) failed, exit=$?" >&2; exit 1; }

echo "Concatenating and adding audio + scope line..."
CONCAT_LIST=$(mktemp -t djmix_concat.XXXXXX)
{
    printf "file '%s'\n" "$(pwd)/movie_fadein.mp4"
    printf "file '%s'\n" "$(pwd)/reversed_part_fade.mp4"
} > "$CONCAT_LIST"

ffmpeg "${FF_PRE[@]}" -f concat -safe 0 -i "$CONCAT_LIST" -c copy video_only.mp4 || { echo "ffmpeg (concat) failed, exit=$?" >&2; exit 1; }

run_ffmpeg "rewind 4/4 mux" "$AUDIO_LENGTH" "${DEC_IN[@]}" -i video_only.mp4 \
    -t "$AUDIO_LENGTH" -i "$AUDIO_FILE" \
    -filter_complex "$FILTER_PASS2" \
    -map '[outv]' -map '[srcm]' -shortest \
    "${ENC_V[@]}" "${AAC_OUT[@]}" \
    "${MOOV[@]}" "${META_OUT[@]}" \
    "$OUTPUT_FILE" || { echo "ffmpeg (final mux) failed, exit=$?" >&2; exit 1; }

echo "Done! Output is in $OUTPUT_FILE"
exit 0
