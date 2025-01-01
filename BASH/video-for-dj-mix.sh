#!/bin/bash

# Usage: ./video-for-dj-mix.sh trimmed.mp4 audio.mp3

if [ $# -ne 2 ]; then
    echo "Usage: $0 <video_file> <audio_file>"
    exit 1
fi

VIDEO_FILE=$1
AUDIO_FILE=$2

# Create output filename from audio filename (replacing .mp3 with .mp4)
OUTPUT_FILE="${AUDIO_FILE%.*}.mp4"

# Detect last non-silent part in audio (threshold: -50dB, duration: 1 second)
echo "Detecting actual audio end..."
REAL_AUDIO_END=$(ffmpeg -i "$AUDIO_FILE" -af silencedetect=n=-50dB:d=1 -f null - 2>&1 | \
                 grep "silence_end" | tail -n1 | awk '{print $5}' || echo "0")

if [ -z "$REAL_AUDIO_END" ] || [ "$REAL_AUDIO_END" = "0" ]; then
    echo "Using full audio length..."
    AUDIO_LENGTH=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$AUDIO_FILE")
else
    echo "Using detected audio end at: $REAL_AUDIO_END seconds"
    AUDIO_LENGTH=$REAL_AUDIO_END
fi

VIDEO_LENGTH=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$VIDEO_FILE")

# Calculate reverse start point more precisely
REVERSE_LENGTH=$(echo "$AUDIO_LENGTH - $VIDEO_LENGTH" | bc)
REVERSE_START=$(echo "$VIDEO_LENGTH - $REVERSE_LENGTH" | bc)

# Round to nearest frame for ffmpeg
REVERSE_START=$(printf "%.3f" $REVERSE_START)

# Create fade-in version
echo "Creating fade-in version..."
ffmpeg -y -i "$VIDEO_FILE" -vf "fade=t=in:st=0:d=5" -an -c:v libx264 -preset ultrafast -crf 28 movie_fadein.mp4

# Create reversed ending
echo "Creating reversed ending..."
ffmpeg -y -i "$VIDEO_FILE" -ss $REVERSE_START -t $REVERSE_LENGTH -c:v copy last_part.mp4
ffmpeg -y -i last_part.mp4 -vf "reverse,fade=t=out:st=$(echo "$REVERSE_LENGTH - 5" | bc):d=5" -an -c:v libx264 -preset ultrafast -crf 28 reversed_part_fade.mp4

# Concatenate parts
echo "Concatenating and adding audio/waveform..."
echo "file 'movie_fadein.mp4'" > files.txt
echo "file 'reversed_part_fade.mp4'" >> files.txt
ffmpeg -y -f concat -safe 0 -i files.txt -c copy video_only.mp4 && \
ffmpeg -y -i video_only.mp4 -i "$AUDIO_FILE" -filter_complex "[1:a]showwaves=s=1920x100:mode=line:rate=25:colors=ffffff@0.2[wave];[0:v][wave]overlay=0:H-h:format=auto,format=yuv420p" -c:v libx264 -preset ultrafast -crf 28 -c:a copy "$OUTPUT_FILE"

# Cleanup
rm -f files.txt movie_fadein.mp4 reversed_part_fade.mp4 video_only.mp4 last_part.mp4

echo "Done! Output is in $OUTPUT_FILE"