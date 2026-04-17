# mp3split.sh

* Based on Reddit comment by <https://old.reddit.com/user/bayarookie>
* <https://old.reddit.com/r/ffmpeg/comments/jn6sny/split_audio_file_into_smaller_file_based_on/gb0mumn/>

## Usage

```bash
./mp3split.sh TIMESTAMP_FILE MP3_FILE
```

## Timestamp File Format Example

* <https://www.youtube.com/watch?v=uQ681eG8qfQ>

```txt
# ARTIST: Wu-Tang Clan Vs. Beastie Boys
# ALBUM: Wu-Tang Clan Vs. Beastie Boys
# YEAR: 2021
0:00 Ch Check Out Ya Neck
3:21 Da Mystery of Intergalactic Boxing
6:50 Flute Man
8:39 Shame on the Ladies
11:16 Johnny Ryall Ain't Nuthin' To F'Wit'
14:25 Ricky's Shimmy
16:48 Liquid Swords Do It
20:08 Movin' Method Man's Body
22:49 C.R.E.A.M. Comes Around
26:16 Sneaking Guillotines Out The Hospital
28:40 So You Want To Bring The Ruckus
32:05 Get The 7th Chamber Together
35:30 Hold The Iron Mic (Interlude)
36:16 House of Flying Shots
```

Blank lines and lines starting with `#` are ignored. Every other line must use the format:

```txt
TIMESTAMP Track Title
```

Structured metadata headers are supported at the top of the file:

```txt
# ARTIST: Chipmunks on 16 Speed
# ALBUM: Sludge Never Dies
# YEAR: 2021
```

Output files are written into a metadata-based directory tree:

```txt
ARTIST/ALBUM (YEAR)/01 - Track Title.mp3
```

Directory and file names are sanitized for filesystem safety. If multiple tracks sanitize to the same name, the script adds a numeric suffix instead of overwriting an earlier output. Missing `ARTIST` or `ALBUM` headers fall back to `Unknown Artist` and `Unknown Album`.

Each output file keeps the source metadata by default, then overrides:

* `title` with the track title from the timestamp file
* `track` with the generated track number and total, like `1/10`
* `artist`, `album`, and `year` when those headers are present
* embedded album art when the source file contains an attached picture stream

## Requirements

* [ffmpeg](https://ffmpeg.org)
* `ffprobe` (usually installed with ffmpeg)
* [yt-dlp](https://github.com/yt-dlp/yt-dlp) (optional 😎)
