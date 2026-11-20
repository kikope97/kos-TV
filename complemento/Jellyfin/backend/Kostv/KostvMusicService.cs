using System.Collections.Concurrent;
using System.Linq.Expressions;
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Text.Json;
using System.Text.Json.Serialization;
using Jellyfin.Data.Enums;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Entities.Audio;
using MediaBrowser.Controller.Library;
using Microsoft.Extensions.Logging;
using Moonfin.Server.Helpers;

namespace Moonfin.Server.Kostv;

/// <summary>
/// kOS TV: each person's music: their daily mixes, the artists for «Descubrimiento semanal» and
/// the songs for the time of day, read from the library and from what they listened to, and
/// handed to <see cref="KostvMusicEngine"/>. Kept per person for the day (and time of day), in
/// memory and in their folder (so a restart of the server doesn't change them), so every device
/// shows the same all day.
/// </summary>
public sealed class KostvMusicService
{
    // What is read of the library for a person. Generous for a home, and bounded.
    private const int HeardLimit = 5000;
    private const int FavoritesLimit = 2000;
    private const int GenreLimit = 1500;
    private const int ArtistsLimit = 3000;
    private const int PoolGenres = 6;
    private const int PoolArtists = 30;
    private const int SimilarOf = 12;
    private const int SimilarEach = 6;
    private const int IdsChunk = 500;

    // The most songs of a genre (or of some artists) the new ones are drawn from.
    private const int SampleFrom = 50000;

    // An empty answer is worked out again after this, so a person who just started listening
    // doesn't wait for the next day.
    private static readonly TimeSpan EmptyKeptFor = TimeSpan.FromHours(1);
    private static readonly TimeSpan NotReadyKeptFor = TimeSpan.FromMinutes(30);

    private static readonly JsonSerializerOptions DayOptions = new()
    {
        WriteIndented = false,
        Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping
    };

    private static readonly PropertyInfo? OrderByProperty = typeof(InternalItemsQuery).GetProperty(nameof(InternalItemsQuery.OrderBy));

    // The person's data of a song. It takes the User, whose type changed between server
    // versions, so it is bound by reflection, and compiled once: it is asked for thousands of songs.
    private static readonly Func<IUserDataManager, object, BaseItem, UserItemData?>? GetUserData = BindGetUserData();

    private readonly ILibraryManager _library;
    private readonly IUserDataManager _userData;
    private readonly KostvMusicStore _store;
    private readonly ILogger<KostvMusicService> _logger;

    private readonly ConcurrentDictionary<Guid, SemaphoreSlim> _gates = new();

    // What was worked out per person for the day (as in their folder), and what was read of the
    // library to work it out; both under _sync.
    private readonly object _sync = new();
    private readonly Dictionary<Guid, DayResults> _days = new();
    private readonly Dictionary<Guid, Work> _work = new();

    // Goes up each time a person's music is forgotten, so a working out that started before isn't kept.
    private readonly Dictionary<Guid, int> _generations = new();

    /// <summary>The mix of the time of day: which, whether there is enough for it, and its songs.</summary>
    public sealed record KostvMoment(string Slot, bool Ready, IReadOnlyList<Guid> Items);

    /// <summary>What was read of a person to work out their music.</summary>
    private sealed record Taste(
        IReadOnlyList<KostvMusicEvent> Events,
        List<KostvMusicTrack> Tracks,
        KostvMusicProfile Profile);

    /// <summary>Something worked out, when, and whether it came out empty, as kept in the person's folder.</summary>
    private sealed class Kept<T>
    {
        [JsonPropertyName("at")]
        public DateTimeOffset At { get; set; }

        [JsonPropertyName("empty")]
        public bool Empty { get; set; }

        [JsonPropertyName("value")]
        public T Value { get; set; } = default!;
    }

    /// <summary>What was worked out for a person for one music day: overwritten each day.</summary>
    private sealed class DayResults
    {
        [JsonPropertyName("day")]
        public string Day { get; set; } = string.Empty;

        [JsonPropertyName("mixes")]
        public Kept<List<KostvMix>>? Mixes { get; set; }

        [JsonPropertyName("seeds")]
        public Kept<List<string>>? Seeds { get; set; }

        [JsonPropertyName("moments")]
        public Dictionary<string, Kept<KostvMoment>> Moments { get; set; } = new(StringComparer.Ordinal);
    }

    /// <summary>
    /// What was read of the library for a person for the day: their taste, and the songs the new
    /// ones are picked from (of which genres and artists), so the mix of the moment needn't read
    /// it all again. Only in memory.
    /// </summary>
    private sealed class Work
    {
        public required string Day { get; init; }

        public required int Generation { get; init; }

        public required Taste Taste { get; init; }

        public required HashSet<Guid> Known { get; init; }

        public Dictionary<Guid, KostvMusicTrack> Pool { get; } = new();

        public Dictionary<string, IReadOnlyList<string>> Similar { get; } = new(StringComparer.OrdinalIgnoreCase);

        /// <summary>The artists looked for by name, found or not.</summary>
        public HashSet<string> ArtistsLooked { get; } = new(StringComparer.Ordinal);

        public Dictionary<string, BaseItem> Artists { get; } = new(StringComparer.OrdinalIgnoreCase);

        public HashSet<string> SimilarLooked { get; } = new(StringComparer.Ordinal);

        public HashSet<string> Genres { get; } = new(StringComparer.Ordinal);

        public HashSet<Guid> ArtistsRead { get; } = new();

        /// <summary>The songs the daily mixes are made of, once read.</summary>
        public List<KostvMusicTrack>? MixTracks { get; set; }

        public IEnumerable<KostvMusicTrack> Tracks => Taste.Tracks.Concat(Pool.Values);
    }

    public KostvMusicService(
        ILibraryManager library,
        IUserDataManager userData,
        KostvMusicStore store,
        ILogger<KostvMusicService> logger)
    {
        _library = library;
        _userData = userData;
        _store = store;
        _logger = logger;
    }

    public KostvMusicStore Store => _store;

    /// <summary>The music day it is at home (see <see cref="KostvMusicEngine.MusicDay"/>).</summary>
    public string Day => KostvMusicEngine.DayKey(KostvMusicEngine.MusicDay(_store.Now, _store.Zone));

    /// <summary>The ISO week it is at home.</summary>
    public string Week => KostvMusicEngine.WeekOf(_store.Now, _store.Zone);

    /// <summary>The time of day it is at home.</summary>
    public string Slot => KostvMusicEngine.SlotOf(TimeZoneInfo.ConvertTime(_store.Now, _store.Zone).Hour);

    /// <summary>
    /// Forgets what was worked out for <paramref name="userId"/>, in memory and in their folder,
    /// so it is worked out again; one being worked out meanwhile isn't kept.
    /// </summary>
    public void Forget(Guid userId)
    {
        lock (_sync)
        {
            _generations[userId] = _generations.GetValueOrDefault(userId) + 1;
            _days.Remove(userId);
            _work.Remove(userId);
            _store.ForgetDay(userId);
        }
    }

    private int GenerationOf(Guid userId)
    {
        lock (_sync)
        {
            return _generations.GetValueOrDefault(userId);
        }
    }

    // ---------------------------------------------------------------- the day's results

    // Under _sync: what was worked out for the day, from memory or, after a restart, the folder.
    private DayResults DayOfLocked(Guid userId, string day)
    {
        if (_days.TryGetValue(userId, out var known) && known.Day == day)
        {
            return known;
        }

        var stored = ParseDay(_store.DayText(userId));
        var results = stored != null && stored.Day == day ? stored : new DayResults { Day = day };
        _days[userId] = results;
        return results;
    }

    private DayResults? ParseDay(string? text)
    {
        if (string.IsNullOrWhiteSpace(text))
        {
            return null;
        }

        try
        {
            return JsonSerializer.Deserialize<DayResults>(text, DayOptions);
        }
        catch (Exception ex) when (ex is JsonException or NotSupportedException)
        {
            _logger.LogWarning(ex, "kOS TV music: the day's music stored could not be read");
            return null;
        }
    }

    private bool Stands<T>(Kept<T>? kept, TimeSpan emptyFor) =>
        kept != null && (!kept.Empty || _store.Now - kept.At < emptyFor);

    private T? Cached<T>(Guid userId, string day, Func<DayResults, Kept<T>?> pick, TimeSpan emptyFor)
        where T : class
    {
        lock (_sync)
        {
            var kept = pick(DayOfLocked(userId, day));
            return Stands(kept, emptyFor) ? kept!.Value : null;
        }
    }

    /// <summary>Keeps what was worked out, unless the person's music was forgotten meanwhile.</summary>
    private void Save(Guid userId, string day, int generation, Action<DayResults> change)
    {
        lock (_sync)
        {
            if (_generations.GetValueOrDefault(userId) != generation)
            {
                return;
            }

            var results = DayOfLocked(userId, day);
            change(results);
            _store.SetDayText(userId, JsonSerializer.Serialize(results, DayOptions));
        }
    }

    private Kept<T> Keep<T>(T value, bool empty) => new() { At = _store.Now, Empty = empty, Value = value };

    /// <summary>
    /// The genre of today's daily mix <paramref name="mixId"/> of <paramref name="userId"/>, if
    /// it was worked out (it is not worked out for this).
    /// </summary>
    public string? MixGenreOf(Guid userId, string mixId)
    {
        lock (_sync)
        {
            return DayOfLocked(userId, Day).Mixes?.Value?.FirstOrDefault(m => string.Equals(m.Id, mixId, StringComparison.Ordinal))?.Genre;
        }
    }

    // ---------------------------------------------------------------- daily mixes and seeds

    private SemaphoreSlim GateOf(Guid userId) => _gates.GetOrAdd(userId, _ => new SemaphoreSlim(1, 1));

    /// <summary>The daily mixes of <paramref name="userId"/>, the same all day.</summary>
    public async Task<IReadOnlyList<KostvMix>> MixesAsync(Guid userId, object user)
    {
        var day = Day;
        if (Cached(userId, day, r => r.Mixes, EmptyKeptFor) is { } known)
        {
            return known;
        }

        var gate = GateOf(userId);
        await gate.WaitAsync().ConfigureAwait(false);
        try
        {
            if (Cached(userId, day, r => r.Mixes, EmptyKeptFor) is { } again)
            {
                return again;
            }

            var generation = GenerationOf(userId);
            var work = WorkOf(userId, user, day, generation);
            var tracks = MixTracksOf(work, user, userId);
            var mixes = KostvMusicEngine.Mixes(userId, day, tracks, work.Taste.Profile, work.Similar)
                .Select(mix => mix with { ArtistIds = ArtistIdsOf(work, mix.Artists) })
                .ToList();
            var seeds = KostvMusicEngine.Seeds(work.Taste.Profile).ToList();
            Save(userId, day, generation, r =>
            {
                r.Mixes = Keep(mixes, mixes.Count == 0);
                r.Seeds = Keep(seeds, seeds.Count == 0);
            });
            return mixes;
        }
        finally
        {
            gate.Release();
        }
    }

    /// <summary>The artists <paramref name="userId"/> likes most, to ask for songs like theirs.</summary>
    public async Task<IReadOnlyList<string>> SeedsAsync(Guid userId, object user)
    {
        var day = Day;
        if (Cached(userId, day, r => r.Seeds, EmptyKeptFor) is { } known)
        {
            return known;
        }

        var gate = GateOf(userId);
        await gate.WaitAsync().ConfigureAwait(false);
        try
        {
            if (Cached(userId, day, r => r.Seeds, EmptyKeptFor) is { } again)
            {
                return again;
            }

            var generation = GenerationOf(userId);
            var seeds = KostvMusicEngine.Seeds(WorkOf(userId, user, day, generation).Taste.Profile).ToList();
            Save(userId, day, generation, r => r.Seeds = Keep(seeds, seeds.Count == 0));
            return seeds;
        }
        finally
        {
            gate.Release();
        }
    }

    /// <summary>
    /// The mix for the time of day it is, for <paramref name="userId"/>: not ready until they
    /// have listened enough at this time of day, and never while Learn is off.
    /// </summary>
    public async Task<KostvMoment> MomentAsync(Guid userId, object user)
    {
        var day = Day;
        var slot = Slot;
        if (Cached(userId, day, r => r.Moments.GetValueOrDefault(slot), NotReadyKeptFor) is { } known)
        {
            return known;
        }

        var gate = GateOf(userId);
        await gate.WaitAsync().ConfigureAwait(false);
        try
        {
            if (Cached(userId, day, r => r.Moments.GetValueOrDefault(slot), NotReadyKeptFor) is { } again)
            {
                return again;
            }

            var generation = GenerationOf(userId);
            var moment = new KostvMoment(slot, false, []);
            var now = _store.Now;
            var zone = _store.Zone;
            var events = _store.Learns(userId) ? _store.Read(userId, now - KostvMusicEngine.MomentWindow) : [];
            if (KostvMusicEngine.MomentReady(events, slot, now, zone))
            {
                // What was read for the day's mixes, and only what the time of day needs besides.
                var work = WorkOf(userId, user, day, generation);
                MixTracksOf(work, user, userId);
                var slotItems = KostvMusicEngine.SlotListens(events, slot, now, zone)
                    .Where(e => e.Outcome != KostvListenOutcome.Skipped)
                    .ToList();
                var genres = slotItems.SelectMany(e => e.Genres ?? []).GroupBy(KostvMusicEngine.Key).OrderByDescending(g => g.Count()).Take(3).Select(g => g.First()).ToList();
                var artists = slotItems.SelectMany(e => e.Artists ?? []).GroupBy(KostvMusicEngine.Key).OrderByDescending(g => g.Count()).Take(PoolArtists).Select(g => g.First()).ToList();
                Extend(work, user, userId, genres, artists, "moment-" + slot);
                var items = KostvMusicEngine.Moment(userId, day, slot, events, work.Tracks, work.Taste.Profile, now, zone, work.Similar);
                moment = new KostvMoment(slot, items.Count > 0, items);
            }

            Save(userId, day, generation, r => r.Moments[slot] = Keep(moment, !moment.Ready));
            return moment;
        }
        finally
        {
            gate.Release();
        }
    }

    // ---------------------------------------------------------------- reading the library

    /// <summary>What was read of the library for <paramref name="userId"/> today, read now if it wasn't.</summary>
    private Work WorkOf(Guid userId, object user, string day, int generation)
    {
        lock (_sync)
        {
            if (_work.TryGetValue(userId, out var known) && known.Day == day && known.Generation == generation)
            {
                return known;
            }
        }

        var taste = TasteOf(userId, user);
        var work = new Work { Day = day, Generation = generation, Taste = taste, Known = taste.Tracks.Select(t => t.Id).ToHashSet() };
        lock (_sync)
        {
            if (_generations.GetValueOrDefault(userId) == generation)
            {
                _work[userId] = work;
            }
        }

        return work;
    }

    /// <summary>The songs of the daily mixes: the person's, and the new ones of their main genres and artists.</summary>
    private List<KostvMusicTrack> MixTracksOf(Work work, object user, Guid userId)
    {
        if (work.MixTracks == null)
        {
            var genres = work.Taste.Profile.Genres.Take(PoolGenres).Select(g => g.Name).ToList();
            var artists = work.Taste.Profile.Artists.Select(a => a.Name).ToList();
            Extend(work, user, userId, genres, artists, "mix");
            work.MixTracks = work.Tracks.ToList();
        }

        return work.MixTracks;
    }

    /// <summary>
    /// What <paramref name="userId"/> has played (the server's count and last time, their hearts
    /// and, with Learn on, their listens), and what they like of it.
    /// </summary>
    private Taste TasteOf(Guid userId, object user)
    {
        var now = _store.Now;
        var events = _store.Learns(userId) ? _store.Read(userId) : [];
        var listens = KostvMusicEngine.Listens(events, now);

        var items = new Dictionary<Guid, BaseItem>();
        foreach (var item in Query(user, q => q.IsPlayed = true, HeardLimit, newestBy: ItemSortBy.DatePlayed)
            .Concat(Query(user, q => q.IsFavorite = true, FavoritesLimit))
            .Concat(Load(user, listens.Keys.ToList())))
        {
            items.TryAdd(item.Id, item);
        }

        var tracks = items.Values.Select(item => TrackOf(item, UserDataOf(user, item))).ToList();
        return new Taste(events, tracks, KostvMusicEngine.Profile(tracks, listens, now));
    }

    /// <summary>
    /// Adds to the songs to pick the new ones from those not read yet: of
    /// <paramref name="genres"/>, not played; of the person's main <paramref name="artists"/>, not
    /// played; and of the artists the server finds like them (noted by artist), not played. Each
    /// drawn in an order fixed by the person and the day, not the library's.
    /// </summary>
    private void Extend(Work work, object user, Guid userId, IEnumerable<string> genres, IEnumerable<string> artists, string kind)
    {
        void Add(IEnumerable<BaseItem> items)
        {
            foreach (var item in items)
            {
                if (!work.Known.Contains(item.Id) && !work.Pool.ContainsKey(item.Id))
                {
                    work.Pool[item.Id] = TrackOf(item, null);
                }
            }
        }

        foreach (var genre in genres.Where(g => !string.IsNullOrWhiteSpace(g)).Distinct(StringComparer.OrdinalIgnoreCase))
        {
            var key = KostvMusicEngine.Key(genre);
            if (work.Genres.Add(key))
            {
                Add(Sampled(user, userId, work.Day, "genre|" + key, q =>
                {
                    q.Genres = [genre];
                    q.IsPlayed = false;
                }, GenreLimit));
            }
        }

        var names = artists.Where(n => !string.IsNullOrWhiteSpace(n)).Distinct(StringComparer.OrdinalIgnoreCase).Take(PoolArtists).ToList();
        foreach (var (name, artist) in ArtistsByName(names.Where(n => !work.ArtistsLooked.Contains(KostvMusicEngine.Key(n)))))
        {
            work.Artists[name] = artist;
        }

        work.ArtistsLooked.UnionWith(names.Select(KostvMusicEngine.Key));
        var main = names.Select(n => work.Artists.GetValueOrDefault(n)).OfType<BaseItem>().ToList();
        var mainIds = main.Select(a => a.Id).Where(id => !work.ArtistsRead.Contains(id)).Distinct().ToArray();
        if (mainIds.Length > 0)
        {
            work.ArtistsRead.UnionWith(mainIds);
            Add(Sampled(user, userId, work.Day, kind + "|artists", q =>
            {
                q.ArtistIds = mainIds;
                q.IsPlayed = false;
            }, ArtistsLimit));
        }

        var alikeIds = new HashSet<Guid>();
        foreach (var artist in main.Take(SimilarOf))
        {
            if (!work.SimilarLooked.Add(KostvMusicEngine.Key(artist.Name ?? string.Empty)))
            {
                continue;
            }

            var alike = SimilarArtists(artist);
            if (alike.Count > 0)
            {
                work.Similar[artist.Name!] = alike.Select(a => a.Name).ToList();
                alikeIds.UnionWith(alike.Select(a => a.Id));
            }
        }

        alikeIds.ExceptWith(work.ArtistsRead);
        if (alikeIds.Count > 0)
        {
            var ids = alikeIds.ToArray();
            work.ArtistsRead.UnionWith(ids);
            Add(Sampled(user, userId, work.Day, kind + "|alike", q =>
            {
                q.ArtistIds = ids;
                q.IsPlayed = false;
            }, ArtistsLimit));
        }
    }

    /// <summary>The ids of the artists on a mix's cover, found once for the day.</summary>
    private List<Guid> ArtistIdsOf(Work work, IReadOnlyList<string> names)
    {
        var missing = names.Where(n => !work.Artists.ContainsKey(n)).ToList();
        if (missing.Count > 0)
        {
            foreach (var (name, artist) in ArtistsByName(missing))
            {
                work.Artists[name] = artist;
            }
        }

        return names.Select(n => work.Artists.GetValueOrDefault(n)).OfType<BaseItem>().Select(a => a.Id).ToList();
    }

    /// <summary>The artists of a mix's cover, by their ids (or, without them, by name).</summary>
    public IReadOnlyList<BaseItem> CoverArtists(KostvMix mix)
    {
        if (mix.ArtistIds == null)
        {
            var byName = ArtistsByName(mix.Artists);
            return mix.Artists.Select(n => byName.GetValueOrDefault(n)).OfType<BaseItem>().ToList();
        }

        var found = new List<BaseItem>();
        foreach (var id in mix.ArtistIds)
        {
            try
            {
                if (_library.GetItemById(id) is { } artist)
                {
                    found.Add(artist);
                }
            }
            catch (Exception ex)
            {
                _logger.LogDebug(ex, "kOS TV music: an artist could not be read");
            }
        }

        return found;
    }

    /// <summary>The artists of the server with these names, by name. Asked by name, as artists aren't in a library.</summary>
    public Dictionary<string, BaseItem> ArtistsByName(IEnumerable<string> names)
    {
        var found = new Dictionary<string, BaseItem>(StringComparer.OrdinalIgnoreCase);
        foreach (var name in names.Where(n => !string.IsNullOrWhiteSpace(n)).Distinct(StringComparer.OrdinalIgnoreCase))
        {
            try
            {
                // Not GetArtist, which makes the artist when it isn't there.
                var artist = _library.GetItemList(new InternalItemsQuery
                {
                    IncludeItemTypes = [BaseItemKind.MusicArtist],
                    Name = name,
                    Recursive = true,
                    Limit = 1,
                    EnableTotalRecordCount = false
                }).FirstOrDefault();
                if (artist != null)
                {
                    found[name] = artist;
                }
            }
            catch (Exception ex)
            {
                _logger.LogDebug(ex, "kOS TV music: an artist could not be read");
            }
        }

        return found;
    }

    /// <summary>The artists the server finds most like <paramref name="artist"/> (its own similar items).</summary>
    private List<BaseItem> SimilarArtists(BaseItem artist)
    {
        try
        {
            return _library.GetItemList(new InternalItemsQuery
            {
                IncludeItemTypes = [BaseItemKind.MusicArtist],
                SimilarTo = artist,
                ExcludeItemIds = [artist.Id],
                Recursive = true,
                Limit = SimilarEach,
                EnableTotalRecordCount = false
            }).Where(a => !string.IsNullOrWhiteSpace(a.Name)).ToList();
        }
        catch (Exception ex)
        {
            _logger.LogDebug(ex, "kOS TV music: the artists like one could not be read");
            return [];
        }
    }

    /// <summary>
    /// The songs <paramref name="ids"/> within the person's limits, in that order, read at once
    /// (for the cards of a mix).
    /// </summary>
    public IReadOnlyList<BaseItem> Songs(object user, IReadOnlyList<Guid> ids)
    {
        var byId = new Dictionary<Guid, BaseItem>();
        foreach (var item in Load(user, ids))
        {
            byId.TryAdd(item.Id, item);
        }

        return ids.Select(id => byId.GetValueOrDefault(id)).OfType<BaseItem>().ToList();
    }

    private static KostvMusicTrack TrackOf(BaseItem item, UserItemData? data)
    {
        var audio = item as Audio;
        var artists = (audio?.Artists ?? []).Where(a => !string.IsNullOrWhiteSpace(a)).ToList();
        if (artists.Count == 0)
        {
            artists = (audio?.AlbumArtists ?? []).Where(a => !string.IsNullOrWhiteSpace(a)).ToList();
        }

        return new KostvMusicTrack(
            item.Id,
            artists,
            (item.Genres ?? []).Where(g => !string.IsNullOrWhiteSpace(g)).ToList(),
            data?.PlayCount ?? 0,
            data?.LastPlayedDate,
            data?.IsFavorite ?? false);
    }

    private static InternalItemsQuery NewQuery(Action<InternalItemsQuery> filter, int limit)
    {
        var query = new InternalItemsQuery
        {
            IncludeItemTypes = [BaseItemKind.Audio],
            IsVirtualItem = false,
            Recursive = true,
            Limit = limit,
            EnableTotalRecordCount = false
        };
        filter(query);
        return query;
    }

    /// <summary>Songs within the person's limits (libraries and parental rating).</summary>
    private IReadOnlyList<BaseItem> Query(object user, Action<InternalItemsQuery> filter, int limit, ItemSortBy? newestBy = null)
    {
        var query = NewQuery(filter, limit);
        if (newestBy.HasValue)
        {
            Order(query, newestBy.Value);
        }

        // Without the person's limits applied nothing is read, rather than everything.
        if (!UserReflection.ApplyUser(query, user))
        {
            return [];
        }

        try
        {
            return _library.GetItemList(query);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "kOS TV music: a library query failed");
            return [];
        }
    }

    /// <summary>The songs <paramref name="ids"/> within the person's limits, a few hundred per query.</summary>
    private IEnumerable<BaseItem> Load(object user, IReadOnlyList<Guid> ids) =>
        ids.Chunk(IdsChunk).SelectMany(chunk => Query(user, q => q.ItemIds = chunk, chunk.Length));

    /// <summary>
    /// Up to <paramref name="limit"/> songs of <paramref name="filter"/> within the person's
    /// limits, drawn from all of them in an order fixed by the person, the day and
    /// <paramref name="kind"/> (so not always the same first ones of a large library). Only their
    /// ids are read to draw them. A server that can't give ids gives the first ones, as before.
    /// </summary>
    private IEnumerable<BaseItem> Sampled(object user, Guid userId, string day, string kind, Action<InternalItemsQuery> filter, int limit)
    {
        var query = NewQuery(filter, SampleFrom);
        if (!UserReflection.ApplyUser(query, user))
        {
            return [];
        }

        List<Guid> ids;
        try
        {
            ids = ItemIds(query);
        }
        catch (Exception ex)
        {
            _logger.LogDebug(ex, "kOS TV music: the songs' ids could not be read");
            return Query(user, filter, limit);
        }

        return Load(user, KostvMusicEngine.Shuffled(ids, userId, day, kind).Take(limit).ToList());
    }

    // Apart, so a server without it fails only here.
    [MethodImpl(MethodImplOptions.NoInlining)]
    private List<Guid> ItemIds(InternalItemsQuery query) => _library.GetItemIds(query);

    // The tuple type of OrderBy changed between server versions, so it is built by reflection.
    private static void Order(InternalItemsQuery query, ItemSortBy sortBy)
    {
        if (OrderByProperty == null)
        {
            return;
        }

        try
        {
            var elementType = OrderByProperty.PropertyType.GetGenericArguments()[0];
            var sortOrderType = elementType.GetGenericArguments()[1];
            var array = Array.CreateInstance(elementType, 1);
            array.SetValue(Activator.CreateInstance(elementType, sortBy, Enum.Parse(sortOrderType, "Descending")), 0);
            OrderByProperty.SetValue(query, array);
        }
        catch
        {
            // Unordered is still right, only not the latest first.
        }
    }

    private static Func<IUserDataManager, object, BaseItem, UserItemData?>? BindGetUserData()
    {
        var method = typeof(IUserDataManager)
            .GetMethods()
            .FirstOrDefault(m =>
            {
                if (m.Name != "GetUserData")
                {
                    return false;
                }

                var parameters = m.GetParameters();
                return parameters.Length == 2 &&
                    parameters[1].ParameterType == typeof(BaseItem) &&
                    typeof(UserItemData).IsAssignableFrom(m.ReturnType);
            });
        if (method == null)
        {
            return null;
        }

        try
        {
            var manager = Expression.Parameter(typeof(IUserDataManager), "manager");
            var user = Expression.Parameter(typeof(object), "user");
            var item = Expression.Parameter(typeof(BaseItem), "item");
            var call = Expression.Call(manager, method, Expression.Convert(user, method.GetParameters()[0].ParameterType), item);
            return Expression.Lambda<Func<IUserDataManager, object, BaseItem, UserItemData?>>(
                Expression.Convert(call, typeof(UserItemData)), manager, user, item).Compile();
        }
        catch
        {
            return (manager, user, item) => method.Invoke(manager, [user, item]) as UserItemData;
        }
    }

    private UserItemData? UserDataOf(object user, BaseItem item)
    {
        try
        {
            return GetUserData?.Invoke(_userData, user, item);
        }
        catch
        {
            return null;
        }
    }

    /// <summary>The week's list the app stored for <paramref name="userId"/>, or null.</summary>
    public JsonElement? DiscoverySongs(Guid userId) => _store.DiscoveryOf(userId, Week);

    // ---------------------------------------------------------------- what was shown

    private KostvMusicEvent Shown(string surface) =>
        new KostvMusicEvent { Type = KostvMusicEvent.ShownType, Surface = surface }.Stamp(_store.Now, _store.Zone);

    private void NoteShown(Guid userId, string key, string period, KostvMusicEvent entry)
    {
        try
        {
            _store.AppendOnce(userId, key, period, entry);
        }
        catch (Exception ex)
        {
            // Never in the way of showing the music.
            _logger.LogWarning(ex, "kOS TV music: noting what was shown failed");
        }
    }

    /// <summary>Notes, once a music day, the daily mixes <paramref name="userId"/> was shown (ids only).</summary>
    public void NoteShownMixes(Guid userId, IReadOnlyList<KostvShownMix> mixes)
    {
        if (mixes.Count == 0)
        {
            return;
        }

        var entry = Shown(KostvMusicEvent.MixesSurface);
        entry.Mixes = mixes.ToList();
        NoteShown(userId, KostvMusicEvent.MixesSurface, Day, entry);
    }

    /// <summary>Notes, once a music day for each time of day, the mix of the moment <paramref name="userId"/> was shown.</summary>
    public void NoteShownMoment(Guid userId, string slot, IReadOnlyList<Guid> items)
    {
        if (items.Count == 0)
        {
            return;
        }

        var entry = Shown(KostvMusicEvent.MomentSurface);
        entry.Slot = slot;
        entry.Items = items.Select(id => id.ToString("N")).ToList();
        NoteShown(userId, KostvMusicEvent.MomentSurface + ":" + slot, Day, entry);
    }

    /// <summary>
    /// Notes, once a week, the list of «Descubrimiento semanal» stored for <paramref name="userId"/>
    /// for <paramref name="week"/>: the Deezer ids of its songs.
    /// </summary>
    public void NoteShownDiscovery(Guid userId, string week, JsonElement? songs)
    {
        var ids = DeezerIdsOf(songs);
        if (ids.Count == 0)
        {
            return;
        }

        var entry = Shown(KostvMusicEvent.DiscoverySurface);
        entry.Week = week;
        entry.DeezerIds = ids;
        NoteShown(userId, KostvMusicEvent.DiscoverySurface, week, entry);
    }

    /// <summary>The Deezer ids of the songs of a week's list, as Stremfin gives them (<c>deezer_id</c>).</summary>
    internal static List<string> DeezerIdsOf(JsonElement? songs)
    {
        var ids = new List<string>();
        if (songs is not { ValueKind: JsonValueKind.Array } list)
        {
            return ids;
        }

        foreach (var song in list.EnumerateArray().Take(KostvMusicStore.MaxDiscoverySongs))
        {
            if (song.ValueKind != JsonValueKind.Object)
            {
                continue;
            }

            foreach (var property in song.EnumerateObject())
            {
                if (property.Name is "deezer_id" or "deezerId" or "DeezerId")
                {
                    var id = property.Value.ValueKind switch
                    {
                        JsonValueKind.String => property.Value.GetString(),
                        JsonValueKind.Number => property.Value.GetRawText(),
                        _ => null
                    };
                    if (!string.IsNullOrWhiteSpace(id) && id.Length <= 32)
                    {
                        ids.Add(id.Trim());
                    }

                    break;
                }
            }
        }

        return ids;
    }
}
