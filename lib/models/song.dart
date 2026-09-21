/// A single track backed by a real Navidrome/Subsonic `child` entry.
class Song {
  const Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.artistId,
    required this.album,
    required this.albumId,
    required this.duration,
    this.coverArtId,
    this.track,
    this.starred = false,
  });

  factory Song.fromJson(Map<String, dynamic> json) {
    return Song(
      id: json['id'] as String,
      title: (json['title'] as String?) ?? 'Unknown title',
      artist: (json['artist'] as String?) ?? 'Unknown artist',
      artistId: (json['artistId'] as String?) ?? '',
      album: (json['album'] as String?) ?? 'Unknown album',
      albumId: (json['albumId'] as String?) ?? '',
      duration: Duration(seconds: (json['duration'] as num?)?.toInt() ?? 0),
      coverArtId: json['coverArt'] as String?,
      track: (json['track'] as num?)?.toInt(),
      starred: json['starred'] != null,
    );
  }

  final String id;
  final String title;
  final String artist;
  final String artistId;
  final String album;
  final String albumId;
  final Duration duration;
  final String? coverArtId;
  final int? track;

  /// Whether the server reported this track as starred/favorited, as of
  /// the last fetch. [PlayerController] tracks live toggles on top of this
  /// baseline so the UI updates instantly without a round trip.
  final bool starred;

  /// Same shape [fromJson] expects, so `Song.fromJson(song.toJson())`
  /// round-trips - used to persist the playback queue locally (not sent to
  /// the server), see `PlayerSessionStore`.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'artistId': artistId,
      'album': album,
      'albumId': albumId,
      'duration': duration.inSeconds,
      if (coverArtId != null) 'coverArt': coverArtId,
      if (track != null) 'track': track,
      if (starred) 'starred': true,
    };
  }

  String get durationLabel {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
