using System.Collections.Concurrent;
using Jellyfin.Data.Enums;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Entities.Audio;
using MediaBrowser.Controller.Library;
using Microsoft.Extensions.Logging;
using Moonfin.Server.Helpers;

namespace Moonfin.Server.Kostv;

/// <summary>kOS TV: a song at home, as a station compares it.</summary>
public sealed record KostvStationHomeSong(Guid Id, string Title, IReadOnlyList<string> Artists, string? Mbid = null, string? Album = null);

/// <summary>kOS TV: what a station needs of the library.</summary>
public interface IKostvStationLibrary
{
    /// <summary>The song <paramref name="id"/> as a seed, when <paramref name="user"/> may see it.</summary>
    KostvStationHomeSong? Seed(object user, Guid id);

    /// <summary>The songs at home of the artist <paramref name="artist"/> (for everyone: who may hear them is seen after).</summary>
    IReadOnlyList<KostvStationHomeSong> SongsBy(string artist);

    /// <summary>The songs <paramref name="ids"/> that <paramref name="user"/> may see, in that order.</summary>
    IReadOnlyList<BaseItem> Visible(object user, IReadOnlyList<Guid> ids);
}

/// <summary>
/// kOS TV: the library for the stations: a song's recording on MusicBrainz is its
/// <c>MusicBrainzTrack</c> (what the server reads of the tags, the recording's id), and each
/// artist's songs are kept 10 minutes (for everyone); who may hear them is seen on each request,
/// with the person's limits (libraries and parental control).
/// </summary>
public sealed class KostvStationLibrary : IKostvStationLibrary
{
    private const int SongsLimit = 3000;
    private const int KeptArtists = 2000;
    private static readonly TimeSpan KeptFor = TimeSpan.FromMinutes(10);

    private readonly ILibraryManager _library;
    private readonly KostvMusicService _music;
    private readonly ILogger _logger;
    private readonly ConcurrentDictionary<string, (DateTimeOffset At, IReadOnlyList<KostvStationHomeSong> Songs)> _byArtist = new(StringComparer.Ordinal);

    public KostvStationLibrary(ILibraryManager library, KostvMusicService music, ILogger logger)
    {
        _library = library;
        _music = music;
        _logger = logger;
    }

    /// <summary>The recording of MusicBrainz of a song at home, when tagged.</summary>
    public static string? MbidOf(BaseItem item)
    {
        var ids = item.ProviderIds;
        if (ids == null)
        {
            return null;
        }

        foreach (var key in new[] { "MusicBrainzTrack", "MusicBrainzRecording" })
        {
            if (ids.TryGetValue(key, out var value) && Guid.TryParse(value, out var mbid))
            {
                return mbid.ToString("D");
            }
        }

        return null;
    }

    public static KostvStationHomeSong? SongOf(BaseItem item)
    {
        if (item is not Audio audio || item.IsVirtualItem || string.IsNullOrWhiteSpace(item.Name))
        {
            return null;
        }

        var artists = (audio.Artists ?? []).Concat(audio.AlbumArtists ?? []).Where(a => !string.IsNullOrWhiteSpace(a)).Distinct(StringComparer.OrdinalIgnoreCase).ToList();
        return artists.Count == 0 ? null : new KostvStationHomeSong(item.Id, item.Name, artists, MbidOf(item), audio.Album);
    }

    public KostvStationHomeSong? Seed(object user, Guid id) =>
        Visible(user, [id]).Select(SongOf).FirstOrDefault(s => s != null);

    public IReadOnlyList<BaseItem> Visible(object user, IReadOnlyList<Guid> ids) =>
        ids.Count == 0 ? [] : _music.Songs(user, ids).Where(item => _music.Sees(item, user)).ToList();

    public IReadOnlyList<KostvStationHomeSong> SongsBy(string artist)
    {
        var key = KostvStationRecipe.Norm(artist);
        if (key.Length == 0)
        {
            return [];
        }

        var now = DateTimeOffset.UtcNow;
        if (_byArtist.TryGetValue(key, out var kept) && now - kept.At < KeptFor)
        {
            return kept.Songs;
        }

        var songs = Read(artist, key);
        if (_byArtist.Count >= KeptArtists)
        {
            _byArtist.Clear();
        }

        _byArtist[key] = (now, songs);
        return songs;
    }

    private IReadOnlyList<KostvStationHomeSong> Read(string artist, string key)
    {
        try
        {
            // Asked by name and by search, as the name may be written otherwise at home
            // («Rosalia», «ROSALÍA»); then only those that are the same, compared.
            // GetItemsResult, the same on every server version (GetItemList isn't).
            var artistIds = new HashSet<Guid>();
            foreach (var query in new[]
            {
                new InternalItemsQuery { IncludeItemTypes = [BaseItemKind.MusicArtist], Name = artist.Trim(), Recursive = true, Limit = 5, EnableTotalRecordCount = false },
                new InternalItemsQuery { IncludeItemTypes = [BaseItemKind.MusicArtist], SearchTerm = artist.Trim(), Recursive = true, Limit = 20, EnableTotalRecordCount = false }
            })
            {
                foreach (var found in _library.GetItemsResult(query).Items ?? [])
                {
                    if (KostvStationRecipe.Norm(found.Name) == key)
                    {
                        artistIds.Add(found.Id);
                    }
                }
            }

            if (artistIds.Count == 0)
            {
                return [];
            }

            var songs = _library.GetItemsResult(new InternalItemsQuery
            {
                IncludeItemTypes = [BaseItemKind.Audio],
                ArtistIds = artistIds.ToArray(),
                IsVirtualItem = false,
                Recursive = true,
                Limit = SongsLimit,
                EnableTotalRecordCount = false
            }).Items ?? [];
            return songs.Select(SongOf).OfType<KostvStationHomeSong>().ToList();
        }
        catch (Exception ex)
        {
            _logger.LogDebug(ex, "kOS TV station: an artist's songs could not be read");
            return [];
        }
    }
}
