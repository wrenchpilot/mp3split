#!/usr/bin/env bash
# mp3split.sh
# Based on Reddit comment by https://old.reddit.com/user/bayarookie:
# https://old.reddit.com/r/ffmpeg/comments/jn6sny/split_audio_file_into_smaller_file_based_on/gb0mumn/

if [ $# -eq 0 ]; then
    >&2 echo "Usage: $(basename $0) [TIMESTAMP_FILE] [MP3_FILE]"
    exit 1
fi

duration=$(ffmpeg -i $2 2>&1 | awk '/Duration/ { print substr($2,0,length($2)-1) }')

SSI=()
TOI=()
OUT=()
while IFS= read -r line; do
  SSI+=("${line%% *}")
  TOI+=("${line%% *}")
  OUT+=("${line#* }")
done < $1 # Timestamp file

unset 'TOI[0]'
TO2=()
for i in "${!TOI[@]}"; do
  TO2+=("${TOI[i]}")
done

TO2+=("${duration%%.*}")

for i in "${!OUT[@]}"; do
  ffmpeg -ss "${SSI[i]}" -to "${TO2[i]}" -i $2 -c copy "${OUT[i]}.mp3"
done