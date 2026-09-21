import 'package:supwave_gen2/models/album.dart';
import 'package:supwave_gen2/models/artist.dart';
import 'package:supwave_gen2/models/playlist.dart';
import 'package:supwave_gen2/models/song.dart';
import 'package:supwave_gen2/navidrome/navidrome_repository.dart';

/// In-memory stand-in for a Navidrome server, so widget tests exercise the
/// real UI/state wiring without needing network access.
class FakeNavidromeRepository implements NavidromeRepository {
  FakeNavidromeRepository() {
    _songs = [
      for (var i = 1; i <= 8; i++)
        Song(
          id: 's$i',
          title: 'Song $i',
          artist: i <= 4 ? 'Artist A' : 'Artist B',
          artistId: i <= 4 ? 'ar1' : 'ar2',
          album: i <= 4 ? 'Album A' : 'Album B',
          albumId: i <= 4 ? 'al1' : 'al2',
          duration: Duration(minutes: 3, seconds: i * 7 % 60),
          coverArtId: 'cover-${i <= 4 ? 'al1' : 'al2'}',
          track: i,
          starred: i == 2,
        ),
    ];

    _playlists = [
      Playlist(
        id: 'p1',
        name: 'Chill Vibes',
        description: 'Slow down and breathe',
        songCount: 3,
        duration: const Duration(minutes: 12),
        coverArtId: 'cover-p1',
      ),
      Playlist(
        id: 'p2',
        name: 'Workout',
        description: '',
        songCount: 2,
        duration: const Duration(minutes: 8),
        coverArtId: 'cover-p2',
      ),
    ];

    _playlistSongs = {
      'p1': [_songs[0], _songs[1], _songs[4]],
      'p2': [_songs[2], _songs[5]],
    };
  }

  late List<Song> _songs;
  late List<Playlist> _playlists;
  late Map<String, List<Song>> _playlistSongs;

  @override
  Future<void> ping() async {}

  @override
  Future<DashboardData> getDashboard() async {
    return DashboardData(
      quickPicks: _songs.take(6).toList(),
      recentAlbums: [
        const Album(
          id: 'al1',
          name: 'Album A',
          artist: 'Artist A',
          artistId: 'ar1',
          songCount: 4,
          duration: Duration(minutes: 14),
          coverArtId: 'cover-al1',
        ),
      ],
      frequentAlbums: [
        const Album(
          id: 'al2',
          name: 'Album B',
          artist: 'Artist B',
          artistId: 'ar2',
          songCount: 4,
          duration: Duration(minutes: 15),
          coverArtId: 'cover-al2',
        ),
      ],
      newestAlbums: [
        const Album(
          id: 'al1',
          name: 'Album A',
          artist: 'Artist A',
          artistId: 'ar1',
          songCount: 4,
          duration: Duration(minutes: 14),
          coverArtId: 'cover-al1',
        ),
        const Album(
          id: 'al2',
          name: 'Album B',
          artist: 'Artist B',
          artistId: 'ar2',
          songCount: 4,
          duration: Duration(minutes: 15),
          coverArtId: 'cover-al2',
        ),
      ],
    );
  }

  @override
  Future<List<Playlist>> getPlaylists() async => List.of(_playlists);

  int _nextPlaylistId = 1;

  @override
  Future<Playlist> createPlaylist(String name) async {
    final playlist = Playlist(
      id: 'new-playlist-${_nextPlaylistId++}',
      name: name,
      description: '',
      songCount: 0,
      duration: Duration.zero,
    );
    _playlists = [..._playlists, playlist];
    return playlist;
  }

  @override
  Future<void> deletePlaylist(String playlistId) async {
    _playlists = _playlists.where((p) => p.id != playlistId).toList();
    _playlistSongs.remove(playlistId);
  }

  @override
  Future<List<Song>> getPlaylistSongs(String playlistId) async =>
      List.of(_playlistSongs[playlistId] ?? const []);

  @override
  Future<void> addSongToPlaylist(String playlistId, Song song) async {
    final songs = _playlistSongs.putIfAbsent(playlistId, () => []);
    if (!songs.any((s) => s.id == song.id)) songs.add(song);
  }

  @override
  Future<void> removeSongFromPlaylist(String playlistId, Song song) async {
    _playlistSongs[playlistId]?.removeWhere((s) => s.id == song.id);
  }

  @override
  Future<Artist> getArtistDetail(String artistId) async {
    final albums = artistId == 'ar1'
        ? [
            const Album(
              id: 'al1',
              name: 'Album A',
              artist: 'Artist A',
              artistId: 'ar1',
              songCount: 4,
              duration: Duration(minutes: 14),
              coverArtId: 'cover-al1',
            ),
          ]
        : [
            const Album(
              id: 'al2',
              name: 'Album B',
              artist: 'Artist B',
              artistId: 'ar2',
              songCount: 4,
              duration: Duration(minutes: 15),
              coverArtId: 'cover-al2',
            ),
          ];
    return Artist(
      id: artistId,
      name: artistId == 'ar1' ? 'Artist A' : 'Artist B',
      albumCount: albums.length,
      coverArtId: 'cover-$artistId',
      albums: albums,
    );
  }

  @override
  Future<Album> getAlbumDetail(String albumId) async {
    final songs = _songs.where((s) => s.albumId == albumId).toList();
    return Album(
      id: albumId,
      name: albumId == 'al1' ? 'Album A' : 'Album B',
      artist: albumId == 'al1' ? 'Artist A' : 'Artist B',
      artistId: albumId == 'al1' ? 'ar1' : 'ar2',
      songCount: songs.length,
      duration: songs.fold(Duration.zero, (sum, s) => sum + s.duration),
      coverArtId: 'cover-$albumId',
      songs: songs,
    );
  }

  @override
  Future<List<Song>> getLikedSongs() async => _songs.where((s) => s.starred).toList();

  @override
  Future<void> setStarred(String songId, bool starred) async {
    final index = _songs.indexWhere((s) => s.id == songId);
    if (index == -1) return;
    final s = _songs[index];
    _songs[index] = Song(
      id: s.id,
      title: s.title,
      artist: s.artist,
      artistId: s.artistId,
      album: s.album,
      albumId: s.albumId,
      duration: s.duration,
      coverArtId: s.coverArtId,
      track: s.track,
      starred: starred,
    );
  }

  @override
  Future<int> getTotalSongCount() async => _songs.length;

  @override
  Future<SearchResults> search(String query) async {
    return SearchResults(
      songs: _songs.where((s) => s.title.toLowerCase().contains(query.toLowerCase())).toList(),
      albums: const [],
      artists: const [],
    );
  }

  @override
  String coverArtUrl(String coverArtId, {int size = 300}) => 'https://fake.test/cover/$coverArtId';

  @override
  String streamUrl(String songId) => 'https://fake.test/stream/$songId';
}
