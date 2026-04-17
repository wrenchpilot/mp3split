#!/usr/bin/env bash
# mp3split.sh
# Based on Reddit comment by https://old.reddit.com/user/bayarookie:
# https://old.reddit.com/r/ffmpeg/comments/jn6sny/split_audio_file_into_smaller_file_based_on/gb0mumn/

set -euo pipefail

shopt -s extglob

usage() {
    printf 'Usage: %s TIMESTAMP_FILE MP3_FILE\n' "$(basename "$0")" >&2
}

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

trim_whitespace() {
    local value=$1

    value=${value##+([[:space:]])}
    value=${value%%+([[:space:]])}

    printf '%s\n' "$value"
}

is_valid_timestamp() {
    local timestamp=$1
    local first second third

    [[ $timestamp =~ ^[0-9]+:[0-9]{2}(:[0-9]{2})?(\.[0-9]+)?$ ]] || return 1

    IFS=':' read -r first second third <<< "$timestamp"

    if [[ -n ${third:-} ]]; then
        (( 10#$second <= 59 )) || return 1
        second=${third%%.*}
    else
        second=${second%%.*}
    fi

    (( 10#$second <= 59 ))
}

timestamp_to_milliseconds() {
    local timestamp=$1
    local first second third
    local hours=0
    local minutes
    local seconds
    local whole_seconds
    local fraction=

    IFS=':' read -r first second third <<< "$timestamp"

    if [[ -n ${third:-} ]]; then
        hours=$first
        minutes=$second
        seconds=$third
    else
        minutes=$first
        seconds=$second
    fi

    whole_seconds=${seconds%%.*}
    if [[ $seconds == *.* ]]; then
        fraction=${seconds#*.}
    fi

    fraction=${fraction:0:3}
    while ((${#fraction} < 3)); do
        fraction="${fraction}0"
    done

    printf '%s\n' "$(( ((10#$hours * 60 + 10#$minutes) * 60 + 10#$whole_seconds) * 1000 + 10#$fraction ))"
}

sanitize_output_name() {
    local title=$1

    title=$(printf '%s' "$title" | LC_ALL=C sed -E 's#[/\\]#-#g; s/[[:cntrl:]]//g; s/[<>:"|?*]/_/g; s/[[:space:]]+/ /g')
    title=$(trim_whitespace "$title")

    while [[ $title == .* ]]; do
        title=${title#.}
    done

    title=$(trim_whitespace "$title")

    if [[ -z $title ]]; then
        title='track'
    fi

    printf '%s\n' "$title"
}

output_path_reserved() {
    local candidate=$1
    local reserved

    if ((${#planned_outputs[@]} == 0)); then
        return 1
    fi

    for reserved in "${planned_outputs[@]}"; do
        if [[ $reserved == "$candidate" ]]; then
            return 0
        fi
    done

    return 1
}

next_output_path() {
    local base_dir=$1
    local track_number=$2
    local stem=$3
    local candidate
    local suffix=2

    printf -v candidate '%s/%02d - %s.mp3' "$base_dir" "$track_number" "$stem"

    while [[ -e $candidate ]] || output_path_reserved "$candidate"; do
        printf -v candidate '%s/%02d - %s-%d.mp3' "$base_dir" "$track_number" "$stem" "$suffix"
        ((suffix++))
    done

    planned_outputs+=("$candidate")
    next_output_path_result=$candidate
}

if [[ $# -ne 2 ]]; then
    usage
    exit 1
fi

timestamp_file=$1
audio_file=$2

[[ -r $timestamp_file ]] || die "Timestamp file is not readable: $timestamp_file"
[[ -r $audio_file ]] || die "Audio file is not readable: $audio_file"

require_command ffmpeg
require_command ffprobe

duration=$(
    ffprobe \
        -v error \
        -sexagesimal \
        -show_entries format=duration \
        -of default=noprint_wrappers=1:nokey=1 \
        -- "$audio_file"
) || die "Unable to read audio duration with ffprobe: $audio_file"

duration=$(trim_whitespace "$duration")
[[ -n $duration ]] || die "ffprobe returned an empty duration for: $audio_file"
is_valid_timestamp "$duration" || die "ffprobe returned an invalid duration: $duration"

attached_picture_stream=$(
    ffprobe \
        -v error \
        -select_streams v \
        -show_entries stream=index:stream_disposition=attached_pic \
        -of csv=p=0 \
        -- "$audio_file" |
    awk -F',' '$2 == 1 { print $1; exit }'
) || die "Unable to inspect album art streams with ffprobe: $audio_file"

duration_ms=$(timestamp_to_milliseconds "$duration")

start_times=()
track_titles=()
sanitized_titles=()
output_paths=()
planned_outputs=()
artist_name=
album_title=
year_value=

line_number=0
previous_ms=-1
while IFS= read -r raw_line || [[ -n $raw_line ]]; do
    ((line_number += 1))

    line=$(trim_whitespace "$raw_line")

    if [[ -z $line ]]; then
        continue
    fi

    if [[ ${line:0:1} == '#' ]]; then
        comment_text=$(trim_whitespace "${line#\#}")

        if [[ -n $comment_text ]]; then
            if [[ $comment_text =~ ^([^:]+):[[:space:]]*(.+)$ ]]; then
                metadata_key=$(trim_whitespace "${BASH_REMATCH[1]}")
                metadata_value=$(trim_whitespace "${BASH_REMATCH[2]}")
                metadata_key=$(printf '%s' "$metadata_key" | tr '[:lower:]' '[:upper:]')

                case "$metadata_key" in
                    ARTIST)
                        artist_name=$metadata_value
                        ;;
                    ALBUM)
                        album_title=$metadata_value
                        ;;
                    YEAR)
                        year_value=$metadata_value
                        ;;
                esac
            fi
        fi

        continue
    fi

    if [[ ! $line =~ ^([^[:space:]]+)[[:space:]]+(.+)$ ]]; then
        die "Invalid timestamp entry on line $line_number: $raw_line"
    fi

    timestamp=${BASH_REMATCH[1]}
    title=$(trim_whitespace "${BASH_REMATCH[2]}")

    is_valid_timestamp "$timestamp" || die "Invalid timestamp on line $line_number: $timestamp"
    [[ -n $title ]] || die "Missing output title on line $line_number"

    current_ms=$(timestamp_to_milliseconds "$timestamp")

    (( current_ms < duration_ms )) || die "Timestamp on line $line_number is not before the audio duration ($duration): $timestamp"
    (( current_ms > previous_ms )) || die "Timestamp on line $line_number is not greater than the previous timestamp: $timestamp"

    previous_ms=$current_ms
    sanitized_title=$(sanitize_output_name "$title")

    start_times+=("$timestamp")
    track_titles+=("$title")
    sanitized_titles+=("$sanitized_title")
done < "$timestamp_file"

(( ${#start_times[@]} > 0 )) || die "Timestamp file did not contain any valid entries: $timestamp_file"

track_total=${#start_times[@]}

artist_dir=$(sanitize_output_name "${artist_name:-Unknown Artist}")
album_dir=$(sanitize_output_name "${album_title:-Unknown Album}")
if [[ -n ${year_value:-} ]]; then
    album_dir="${album_dir} (${year_value})"
fi

output_dir="${artist_dir}/${album_dir}"
mkdir -p -- "$output_dir"

for i in "${!sanitized_titles[@]}"; do
    next_output_path "$output_dir" "$((i + 1))" "${sanitized_titles[i]}"
    output_paths+=("$next_output_path_result")
done

for i in "${!start_times[@]}"; do
    next_index=$((i + 1))
    track_number=$((i + 1))

    if (( next_index < ${#start_times[@]} )); then
        end_time=${start_times[next_index]}
    else
        end_time=$duration
    fi

    printf 'Writing %s\n' "${output_paths[i]}"
    ffmpeg_cmd=(
        ffmpeg
        -n
        -ss "${start_times[i]}"
        -to "$end_time"
        -i "$audio_file"
        -map 0:a
        -map_chapters -1
        -c copy
        -id3v2_version 3
        -write_id3v1 1
        -map_metadata 0
        -metadata "title=${track_titles[i]}"
        -metadata "track=${track_number}/${track_total}"
    )

    if [[ -n ${attached_picture_stream:-} ]]; then
        ffmpeg_cmd+=(
            -map "0:${attached_picture_stream}"
            -disposition:v:0 attached_pic
        )
    fi

    if [[ -n ${album_title:-} ]]; then
        ffmpeg_cmd+=(-metadata "album=$album_title")
    fi

    if [[ -n ${artist_name:-} ]]; then
        ffmpeg_cmd+=(-metadata "artist=$artist_name")
    fi

    if [[ -n ${year_value:-} ]]; then
        ffmpeg_cmd+=(
            -metadata "date=$year_value"
            -metadata "year=$year_value"
        )
    fi

    ffmpeg_cmd+=("${output_paths[i]}")
    "${ffmpeg_cmd[@]}"
done
