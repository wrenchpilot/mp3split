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
    local track_number=$1
    local stem=$2
    local candidate
    local suffix=2

    printf -v candidate '%02d - %s.mp3' "$track_number" "$stem"

    while [[ -e $candidate ]] || output_path_reserved "$candidate"; do
        printf -v candidate '%02d - %s-%d.mp3' "$track_number" "$stem" "$suffix"
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

duration_ms=$(timestamp_to_milliseconds "$duration")

start_times=()
output_paths=()
planned_outputs=()

line_number=0
previous_ms=-1
while IFS= read -r raw_line || [[ -n $raw_line ]]; do
    ((line_number += 1))

    line=$(trim_whitespace "$raw_line")

    if [[ -z $line || ${line:0:1} == '#' ]]; then
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
    next_output_path "$(( ${#start_times[@]} + 1 ))" "$sanitized_title"

    start_times+=("$timestamp")
    output_paths+=("$next_output_path_result")
done < "$timestamp_file"

(( ${#start_times[@]} > 0 )) || die "Timestamp file did not contain any valid entries: $timestamp_file"

for i in "${!start_times[@]}"; do
    next_index=$((i + 1))

    if (( next_index < ${#start_times[@]} )); then
        end_time=${start_times[next_index]}
    else
        end_time=$duration
    fi

    printf 'Writing %s\n' "${output_paths[i]}"
    ffmpeg -n -ss "${start_times[i]}" -to "$end_time" -i "$audio_file" -c copy "${output_paths[i]}"
done
