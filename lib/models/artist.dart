import 'album.dart';

class Artist {
  const Artist({
    required this.id,
    required this.name,
    required this.albumCount,
    this.coverArtId,
    this.albums = const [],
  });

  factory Artist.fromJson(Map<String, dynamic> json) {
    return Artist(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? 'Unknown artist',
      albumCount: (json['albumCount'] as num?)?.toInt() ?? 0,
      coverArtId: json['coverArt'] as String?,
    );
  }

  final String id;
  final String name;
  final int albumCount;
  final String? coverArtId;

  /// Populated by [NavidromeRepository.getArtistDetail].
  final List<Album> albums;
}
