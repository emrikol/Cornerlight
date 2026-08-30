#!/bin/zsh
set -euo pipefail

if (( $# != 3 )); then
    print -u2 -- "Usage: $0 SPOTLIGHT.mov LAUNCH.mov OUTPUT_DIRECTORY"
    print -u2 -- "Optional: CORNERLIGHT_NATIVE_OFFSET, CORNERLIGHT_ACTUAL_OFFSET, CORNERLIGHT_MOVIE_CROP, CORNERLIGHT_SAMPLE_TIMES"
    exit 2
fi

NATIVE_MOVIE="$1"
ACTUAL_MOVIE="$2"
OUTPUT_DIRECTORY="$3"
NATIVE_OFFSET="${CORNERLIGHT_NATIVE_OFFSET:-0}"
ACTUAL_OFFSET="${CORNERLIGHT_ACTUAL_OFFSET:-0}"
CROP="${CORNERLIGHT_MOVIE_CROP:-}"
SAMPLE_TIMES="${CORNERLIGHT_SAMPLE_TIMES:-0,0.016667,0.033333,0.05,0.066667,0.1,0.15,0.2,0.28,0.4}"
FFMPEG="${CORNERLIGHT_FFMPEG:-$(command -v ffmpeg)}"
FFPROBE="${CORNERLIGHT_FFPROBE:-$(command -v ffprobe)}"
MAGICK="${CORNERLIGHT_MAGICK:-$(command -v magick)}"

[[ -f "$NATIVE_MOVIE" ]] || { print -u2 -- "Missing Spotlight movie: $NATIVE_MOVIE"; exit 2; }
[[ -f "$ACTUAL_MOVIE" ]] || { print -u2 -- "Missing Cornerlight movie: $ACTUAL_MOVIE"; exit 2; }
[[ -n "$FFMPEG" && -n "$FFPROBE" && -n "$MAGICK" ]] || {
    print -u2 -- "ffmpeg, ffprobe, and ImageMagick are required"
    exit 2
}

mkdir -p "$OUTPUT_DIRECTORY/native" "$OUTPUT_DIRECTORY/actual" "$OUTPUT_DIRECTORY/diff"
$FFPROBE -v error -select_streams v:0 \
    -show_entries stream=width,height,r_frame_rate,avg_frame_rate,nb_frames,duration \
    -of default=noprint_wrappers=1 "$NATIVE_MOVIE" > "$OUTPUT_DIRECTORY/native-metadata.txt"
$FFPROBE -v error -select_streams v:0 \
    -show_entries stream=width,height,r_frame_rate,avg_frame_rate,nb_frames,duration \
    -of default=noprint_wrappers=1 "$ACTUAL_MOVIE" > "$OUTPUT_DIRECTORY/actual-metadata.txt"

print -- 'relative_time,native_time,actual_time,normalized_rmse' > "$OUTPUT_DIRECTORY/frames.csv"
INDEX=0
for RELATIVE_TIME in ${(s:,:)SAMPLE_TIMES}; do
    NATIVE_TIME="$(awk -v offset="$NATIVE_OFFSET" -v relative="$RELATIVE_TIME" 'BEGIN { printf "%.6f", offset + relative }')"
    ACTUAL_TIME="$(awk -v offset="$ACTUAL_OFFSET" -v relative="$RELATIVE_TIME" 'BEGIN { printf "%.6f", offset + relative }')"
    NATIVE_FRAME="$OUTPUT_DIRECTORY/native/$(printf '%03d' "$INDEX").png"
    ACTUAL_FRAME="$OUTPUT_DIRECTORY/actual/$(printf '%03d' "$INDEX").png"
    DIFF_FRAME="$OUTPUT_DIRECTORY/diff/$(printf '%03d' "$INDEX").png"

    FILTER_ARGUMENTS=()
    [[ -z "$CROP" ]] || FILTER_ARGUMENTS=(-vf "crop=$CROP")
    $FFMPEG -v error -ss "$NATIVE_TIME" -i "$NATIVE_MOVIE" \
        $FILTER_ARGUMENTS -frames:v 1 -compression_level 9 -y "$NATIVE_FRAME"
    $FFMPEG -v error -ss "$ACTUAL_TIME" -i "$ACTUAL_MOVIE" \
        $FILTER_ARGUMENTS -frames:v 1 -compression_level 9 -y "$ACTUAL_FRAME"

    NATIVE_SIZE="$($MAGICK identify -format '%wx%h' "$NATIVE_FRAME")"
    ACTUAL_SIZE="$($MAGICK identify -format '%wx%h' "$ACTUAL_FRAME")"
    NORMALIZED_RMSE="geometry-mismatch:$NATIVE_SIZE:$ACTUAL_SIZE"
    if [[ "$NATIVE_SIZE" == "$ACTUAL_SIZE" ]]; then
        METRIC="$($MAGICK compare -metric RMSE "$NATIVE_FRAME" "$ACTUAL_FRAME" null: 2>&1 || true)"
        NORMALIZED_RMSE="$(print -r -- "$METRIC" | sed -n 's/.*(\([^)]*\)).*/\1/p')"
        $MAGICK compare -compose src -highlight-color '#ff2d55' \
            -lowlight-color '#00000000' "$NATIVE_FRAME" "$ACTUAL_FRAME" "$DIFF_FRAME" \
            2>/dev/null || true
    fi
    print -- "$RELATIVE_TIME,$NATIVE_TIME,$ACTUAL_TIME,$NORMALIZED_RMSE" \
        >> "$OUTPUT_DIRECTORY/frames.csv"
    (( INDEX += 1 ))
done

print -- "Wrote lossless frame samples and pixel deltas to $OUTPUT_DIRECTORY"

