import '../models/album.dart';
import '../models/artist.dart';
import '../models/playlist.dart';
import '../models/song.dart';

/// A handful of curated lists for the dashboard, since Subsonic has no
/// single "dashboard" endpoint.
class DashboardData {
  const DashboardData({
    required this.quickPicks,
    required this.recentAlbums,
    required this.frequentAlbums,
    required this.newestAlbums,
  });

  final List<Song> quickPicks;
  final List<Album> recentAlbums;
  final List<Album> frequentAlbums;
  final List<Album> newestAlbums;
}

class SearchResults {
  const SearchResults({
    required this.songs,
    required this.albums,
    required this.artists,
  });

  final List<Song> songs;
  final List<Album> albums;
  final List<Artist> artists;
}

/// Everything the UI needs from a Navidrome server. [NavidromeApiRepository]
/// is the real implementation; tests substitute a fake in-memory one so they
/// don't depend on network access.
abstract class NavidromeRepository {
  Future<void> ping();

  Future<DashboardData> getDashboard();

  Future<List<Playlist>> getPlaylists();
  Future<Playlist> createPlaylist(String name);
  Future<void> deletePlaylist(String playlistId);
  Future<List<Song>> getPlaylistSongs(String playlistId);
  Future<void> addSongToPlaylist(String playlistId, Song song);

  /// Subsonic removes playlist entries by position, not song id, so the
  /// repository resolves the index from a fresh copy of the playlist first.
  Future<void> removeSongFromPlaylist(String playlistId, Song song);

  Future<Artist> getArtistDetail(String artistId);
  Future<Album> getAlbumDetail(String albumId);

  Future<List<Song>> getLikedSongs();
  Future<void> setStarred(String songId, bool starred);

  Future<int> getTotalSongCount();

  Future<SearchResults> search(String query);

  String coverArtUrl(String coverArtId, {int size});
  String streamUrl(String songId);
}
