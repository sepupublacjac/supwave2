import 'song.dart';

class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    required this.description,
    required this.songCount,
    required this.duration,
    this.coverArtId,
    this.songs = const [],
  });

  factory Playlist.fromJson(Map<String, dynamic> json) {
    return Playlist(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? 'Untitled playlist',
      description: (json['comment'] as String?) ?? '',
      songCount: (json['songCount'] as num?)?.toInt() ?? 0,
      duration: Duration(seconds: (json['duration'] as num?)?.toInt() ?? 0),
      coverArtId: json['coverArt'] as String?,
    );
  }

  final String id;
  final String name;
  final String description;
  final int songCount;
  final Duration duration;
  final String? coverArtId;

  /// Populated on demand (the playlist list endpoint only returns
  /// metadata) via [PlaylistsController.loadPlaylistSongs].
  final List<Song> songs;

  Playlist copyWith({List<Song>? songs, int? songCount}) {
    return Playlist(
      id: id,
      name: name,
      description: description,
      songCount: songCount ?? this.songCount,
      duration: duration,
      coverArtId: coverArtId,
      songs: songs ?? this.songs,
    );
  }
}
