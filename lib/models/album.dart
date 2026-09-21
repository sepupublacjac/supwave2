import 'song.dart';

class Album {
  const Album({
    required this.id,
    required this.name,
    required this.artist,
    required this.artistId,
    required this.songCount,
    required this.duration,
    this.year,
    this.coverArtId,
    this.songs = const [],
  });

  factory Album.fromJson(Map<String, dynamic> json) {
    return Album(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? 'Untitled album',
      artist: (json['artist'] as String?) ?? 'Unknown artist',
      artistId: (json['artistId'] as String?) ?? '',
      songCount: (json['songCount'] as num?)?.toInt() ?? 0,
      duration: Duration(seconds: (json['duration'] as num?)?.toInt() ?? 0),
      year: (json['year'] as num?)?.toInt(),
      coverArtId: json['coverArt'] as String?,
    );
  }

  final String id;
  final String name;
  final String artist;
  final String artistId;
  final int songCount;
  final Duration duration;
  final int? year;
  final String? coverArtId;
  final List<Song> songs;
}
