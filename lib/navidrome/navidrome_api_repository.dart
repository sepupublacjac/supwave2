import '../models/album.dart';
import '../models/artist.dart';
import '../models/playlist.dart';
import '../models/song.dart';
import 'navidrome_repository.dart';
import 'subsonic_client.dart';

class NavidromeApiRepository implements NavidromeRepository {
  NavidromeApiRepository(this._client);

  final SubsonicClient _client;

  List<Song> _songList(Map<String, dynamic>? container, String key) {
    if (container == null) return const [];
    final raw = container[key];
    if (raw is! List) return const [];
    return raw.map((e) => Song.fromJson(e as Map<String, dynamic>)).toList();
  }

  List<Album> _albumList(Map<String, dynamic>? container, String key) {
    if (container == null) return const [];
    final raw = container[key];
    if (raw is! List) return const [];
    return raw.map((e) => Album.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<void> ping() => _client.ping();

  @override
  Future<DashboardData> getDashboard() async {
    final results = await Future.wait([
      _client.get('getRandomSongs.view', {'size': '10'}),
      _client.get('getAlbumList2.view', {'type': 'recent', 'size': '10'}),
      _client.get('getAlbumList2.view', {'type': 'frequent', 'size': '10'}),
      _client.get('getAlbumList2.view', {'type': 'newest', 'size': '10'}),
    ]);

    final randomSongs = results[0]['randomSongs'] as Map<String, dynamic>?;
    final recent = results[1]['albumList2'] as Map<String, dynamic>?;
    final frequent = results[2]['albumList2'] as Map<String, dynamic>?;
    final newest = results[3]['albumList2'] as Map<String, dynamic>?;

    return DashboardData(
      quickPicks: _songList(randomSongs, 'song'),
      recentAlbums: _albumList(recent, 'album'),
      frequentAlbums: _albumList(frequent, 'album'),
      newestAlbums: _albumList(newest, 'album'),
    );
  }

  @override
  Future<List<Playlist>> getPlaylists() async {
    final response = await _client.get('getPlaylists.view');
    final container = response['playlists'] as Map<String, dynamic>?;
    final raw = container?['playlist'];
    if (raw is! List) return const [];
    return raw.map((e) => Playlist.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<Playlist> createPlaylist(String name) async {
    final response = await _client.get('createPlaylist.view', {'name': name});
    final json = response['playlist'] as Map<String, dynamic>;
    return Playlist.fromJson(json);
  }

  @override
  Future<void> deletePlaylist(String playlistId) {
    return _client.get('deletePlaylist.view', {'id': playlistId});
  }

  @override
  Future<List<Song>> getPlaylistSongs(String playlistId) async {
    final response = await _client.get('getPlaylist.view', {'id': playlistId});
    final container = response['playlist'] as Map<String, dynamic>?;
    return _songList(container, 'entry');
  }

  @override
  Future<void> addSongToPlaylist(String playlistId, Song song) {
    return _client.get('updatePlaylist.view', {
      'playlistId': playlistId,
      'songIdToAdd': song.id,
    });
  }

  @override
  Future<void> removeSongFromPlaylist(String playlistId, Song song) async {
    final songs = await getPlaylistSongs(playlistId);
    final index = songs.indexWhere((s) => s.id == song.id);
    if (index == -1) return;
    await _client.get('updatePlaylist.view', {
      'playlistId': playlistId,
      'songIndexToRemove': '$index',
    });
  }

  @override
  Future<Artist> getArtistDetail(String artistId) async {
    final response = await _client.get('getArtist.view', {'id': artistId});
    final json = response['artist'] as Map<String, dynamic>;
    final artist = Artist.fromJson(json);
    final rawAlbums = json['album'];
    final albums = rawAlbums is List
        ? rawAlbums.map((e) => Album.fromJson(e as Map<String, dynamic>)).toList()
        : <Album>[];
    return Artist(
      id: artist.id,
      name: artist.name,
      albumCount: artist.albumCount,
      coverArtId: artist.coverArtId,
      albums: albums,
    );
  }

  @override
  Future<Album> getAlbumDetail(String albumId) async {
    final response = await _client.get('getAlbum.view', {'id': albumId});
    final json = response['album'] as Map<String, dynamic>;
    final album = Album.fromJson(json);
    return Album(
      id: album.id,
      name: album.name,
      artist: album.artist,
      artistId: album.artistId,
      songCount: album.songCount,
      duration: album.duration,
      year: album.year,
      coverArtId: album.coverArtId,
      songs: _songList(json, 'song'),
    );
  }

  @override
  Future<List<Song>> getLikedSongs() async {
    final response = await _client.get('getStarred2.view');
    final container = response['starred2'] as Map<String, dynamic>?;
    return _songList(container, 'song');
  }

  @override
  Future<void> setStarred(String songId, bool starred) {
    return _client.get(starred ? 'star.view' : 'unstar.view', {'id': songId});
  }

  @override
  Future<int> getTotalSongCount() async {
    final response = await _client.get('getScanStatus.view');
    final status = response['scanStatus'] as Map<String, dynamic>?;
    return (status?['count'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<SearchResults> search(String query) async {
    final response = await _client.get('search3.view', {
      'query': query,
      'songCount': '25',
      'albumCount': '15',
      'artistCount': '15',
    });
    final container = response['searchResult3'] as Map<String, dynamic>?;
    final rawArtists = container?['artist'];
    final artists = rawArtists is List
        ? rawArtists.map((e) => Artist.fromJson(e as Map<String, dynamic>)).toList()
        : <Artist>[];
    return SearchResults(
      songs: _songList(container, 'song'),
      albums: _albumList(container, 'album'),
      artists: artists,
    );
  }

  @override
  String coverArtUrl(String coverArtId, {int size = 300}) =>
      _client.coverArtUrl(coverArtId, size: size);

  @override
  String streamUrl(String songId) => _client.streamUrl(songId);
}
