using System.Collections.Concurrent;
using System.Reflection;
using System.Text.Json;
using System.Text.Json.Serialization;
using Jellyfin.Data.Enums;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Entities.Movies;
using MediaBrowser.Controller.Entities.TV;
using MediaBrowser.Controller.Library;
using MediaBrowser.Model.Entities;
using Microsoft.Extensions.Logging;
using Moonfin.Server.Helpers;
using Moonfin.Server.Services;

namespace Moonfin.Server.Kostv;

/// <summary>What TMDB said of a title or a person, kept so it's asked once a month.</summary>
public sealed class KostvTasteEntry
{
    [JsonPropertyName("recs")]
    public List<string> Recs { get; set; } = [];

    [JsonPropertyName("people")]
    public List<KostvTastePerson> People { get; set; } = [];

    /// <summary>For a person: what they made or acted in.</summary>
    [JsonPropertyName("credits")]
    public List<string> Credits { get; set; } = [];

    [JsonPropertyName("cachedAt")]
    public DateTimeOffset CachedAt { get; set; }
}

public sealed class KostvTastePerson
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = string.Empty;

    [JsonPropertyName("name")]
    public string Name { get; set; } = string.Empty;

    [JsonPropertyName("director")]
    public bool Director { get; set; }
}

/// <summary>kOS TV: TMDB's recommendations and credits, on disk.</summary>
public sealed class KostvTasteCache : FileBackedCacheService<KostvTasteEntry>
{
    private static readonly TimeSpan MaxAge = TimeSpan.FromDays(30);

    public KostvTasteCache(ILogger<KostvTasteCache> logger)
        : base(logger, "kostv-home-tmdb.json", "kOS TV home")
    {
    }

    public KostvTasteEntry? Get(string key) =>
        EnsureLoaded().TryGetValue(key, out var entry) && DateTimeOffset.UtcNow - entry.CachedAt < MaxAge ? entry : null;

    // Kos TV: whether anything changed since the file was last written.
    private int _changed;

    public void Set(string key, KostvTasteEntry entry)
    {
        entry.CachedAt = DateTimeOffset.UtcNow;
        EnsureLoaded()[key] = entry;
        Interlocked.Exchange(ref _changed, 1);
    }

    /// <summary>
    /// Kos TV: writes the file only when something was added or forgotten since it was last
    /// written; with everything read from it, there is nothing to write.
    /// </summary>
    public Task FlushIfChangedAsync() =>
        Interlocked.Exchange(ref _changed, 0) == 1 ? FlushAsync() : Task.CompletedTask;

    /// <summary>
    /// Kos TV: forgets what is past its age, so the file doesn't keep growing with every title
    /// anyone ever watched. How many went.
    /// </summary>
    public int Prune()
    {
        var cache = EnsureLoaded();
        var now = DateTimeOffset.UtcNow;
        var removed = 0;
        foreach (var (key, entry) in cache)
        {
            if (now - entry.CachedAt >= MaxAge && cache.TryRemove(key, out _))
            {
                removed++;
            }
        }

        if (removed > 0)
        {
            Interlocked.Exchange(ref _changed, 1);
        }

        return removed;
    }
}

/// <summary>How far someone is with a title of their list.</summary>
public enum KostvListState
{
    ToStart,
    Watching,
    Watched
}

/// <summary>A person's list in its three parts.</summary>
public sealed record KostvMyListSections(
    IReadOnlyList<BaseItem> Watching,
    IReadOnlyList<BaseItem> ToStart,
    IReadOnlyList<BaseItem> Watched);

/// <summary>A person's home page as worked out, with what it was worked out from.</summary>
public sealed record KostvHomePage(
    IReadOnlyList<KostvHomeRow> Rows,
    int Seeds,
    int Library,
    bool Tmdb,
    DateTimeOffset BuiltAt,
    IReadOnlyDictionary<string, Guid> Index,
    string Stamp,
    IReadOnlySet<Guid>? Followed = null,
    bool Partial = false);

/// <summary>
/// kOS TV: works out each person's home page. Reads what they watched from the server's own
/// play history, asks TMDB what people who liked those also liked (kept a month), keeps what is
/// on the home server, not seen and within their limits, and hands it to the engine. A page is
/// kept a while per person, so the apps only fetch.
/// </summary>
public sealed class KostvHomeService
{
    private const int MaxSeeds = 14;
    private const int RecommendationPages = 3;

    // TMDB, or a stand-in for it when the plugin is tried out against a made-up library.
    private static readonly string TmdbUrl =
        (Environment.GetEnvironmentVariable("KOSTV_TMDB_URL") ?? "https://api.themoviedb.org").TrimEnd('/');
    private static readonly TimeSpan PageLife = TimeSpan.FromMinutes(20);

    // With nothing new watched, a page stands this long even when asked to refresh.
    private static readonly TimeSpan StaleLife = TimeSpan.FromHours(6);

    // Kos TV: a page worked out while TMDB didn't answer at all (see KostvHomePage.Partial) only
    // stands this long, so a moment of TMDB being down doesn't cost the afternoon's rows.
    internal static readonly TimeSpan PartialLife = TimeSpan.FromMinutes(3);

    // Kos TV: a TMDB key TMDB turned away (401) isn't tried again for this long.
    private static readonly TimeSpan BadKeyFor = TimeSpan.FromMinutes(10);
    private readonly ConcurrentDictionary<string, DateTime> _badKeyUntil = new(StringComparer.Ordinal);
    private readonly ConcurrentDictionary<string, bool> _badKeyLogged = new(StringComparer.Ordinal);

    private static readonly PropertyInfo? OrderByProperty = typeof(InternalItemsQuery).GetProperty(nameof(InternalItemsQuery.OrderBy));

    private static readonly MethodInfo? GetUserData = typeof(IUserDataManager)
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

    private readonly ILibraryManager _libraryManager;
    private readonly IUserDataManager _userDataManager;
    private readonly IHttpClientFactory _httpClientFactory;
    private readonly MoonfinSettingsService _settings;
    private readonly KostvTasteCache _cache;
    private readonly KostvDismissals _dismissals;
    private readonly KostvMyList _myList;
    private readonly KostvFavoriteDates _favorites;
    private readonly ILogger<KostvHomeService> _logger;

    /// <summary>How many of the titles turned down lately TMDB is asked about, to rank what is like them lower.</summary>
    private const int MaxAvoided = 30;

    /// <summary>An episode added this long ago still counts as new.</summary>
    public static readonly TimeSpan NewEpisodeWindow = TimeSpan.FromDays(14);

    private readonly ConcurrentDictionary<Guid, KostvHomePage> _pages = new();

    // Kos TV: read with every Home, and each a few queries per title: kept for a little while.
    // The list is forgotten whenever it changes.
    private static readonly TimeSpan ListKeptFor = TimeSpan.FromMinutes(1);
    private static readonly TimeSpan RewatchKeptFor = TimeSpan.FromMinutes(10);
    private readonly ConcurrentDictionary<Guid, (DateTime At, KostvMyListSections List)> _lists = new();

    // Kos TV: goes up whenever a person's list changes, so a reading of it that started before
    // isn't kept; changed and kept under the one lock.
    private readonly ConcurrentDictionary<Guid, int> _listVersions = new();
    private readonly object _listLock = new();
    private readonly ConcurrentDictionary<(Guid, int), (DateTime At, IReadOnlyList<BaseItem> Items)> _rewatch = new();
    private readonly ConcurrentDictionary<Guid, Building> _building = new();
    private readonly SemaphoreSlim _tmdbGate = new(4, 4);

    // Kos TV: goes up whenever what a page is worked out from changes under it (what they turn
    // down, their list), so a build that started before isn't kept or joined.
    private readonly ConcurrentDictionary<Guid, int> _versions = new();

    // A page is kept, or its version moved on, one at a time, so neither slips between the other.
    private readonly object _keepLock = new();

    // Kos TV: the TMDB titles Lookup asked the library for and didn't find, per person, so the
    // same ones aren't asked again on every load. Short, so what just arrived still shows soon;
    // forgotten when the page is worked out again.
    private static readonly TimeSpan NotFoundKeptFor = TimeSpan.FromMinutes(3);
    private readonly ConcurrentDictionary<Guid, ConcurrentDictionary<string, DateTime>> _notFound = new();

    // Kos TV: whether the person is behind a series whose new episode «Episodios nuevos» would
    // offer, read for each Home: kept a little while.
    private static readonly TimeSpan BehindKeptFor = TimeSpan.FromMinutes(5);
    private readonly ConcurrentDictionary<(Guid User, Guid Episode), (DateTime At, bool Behind)> _behind = new();

    // The longest a list of episodes of many series is read in one query. When a query comes
    // back this full, what it may have cut off is asked one series at a time.
    private const int BulkLimit = 5000;

    /// <summary>
    /// Kos TV: how many of the latest episodes watched are read to find the last of each series;
    /// the series none of those belong to are asked alone (see <see cref="FirstOfEachSeries"/>).
    /// </summary>
    internal int RecentLimit { get; init; } = 500;

    // Kos TV: ILibraryManager.GetItemIds, bound by reflection so a server without it reads the
    // items instead.
    private static readonly MethodInfo? GetItemIdsMethod = typeof(ILibraryManager)
        .GetMethods()
        .FirstOrDefault(m =>
            m.Name == "GetItemIds" &&
            m.GetParameters() is [{ ParameterType: var type }] &&
            type == typeof(InternalItemsQuery) &&
            typeof(IEnumerable<Guid>).IsAssignableFrom(m.ReturnType));

    /// <summary>A build of a person's page under way, and the version it was started on.</summary>
    private sealed class Building
    {
        public Building(int version) => Version = version;

        public int Version { get; }

        public Lazy<Task<KostvHomePage>> Page { get; set; } = null!;
    }

    public KostvHomeService(
        ILibraryManager libraryManager,
        IUserDataManager userDataManager,
        IHttpClientFactory httpClientFactory,
        MoonfinSettingsService settings,
        KostvTasteCache cache,
        KostvDismissals dismissals,
        KostvMyList myList,
        KostvFavoriteDates favorites,
        ILogger<KostvHomeService> logger)
    {
        _favorites = favorites;
        _dismissals = dismissals;
        _myList = myList;
        _libraryManager = libraryManager;
        _userDataManager = userDataManager;
        _httpClientFactory = httpClientFactory;
        _settings = settings;
        _cache = cache;
        _logger = logger;
    }

    /// <summary>The page of <paramref name="userId"/>, worked out again when it's old or asked to.</summary>
    /// <remarks>Kos TV: with <paramref name="keep"/> (the rows further down, asked for after the
    /// first ones) the page those came from, however old, so the rows don't come from two
    /// different workings out.</remarks>
    public Task<KostvHomePage> GetAsync(Guid userId, object user, bool refresh, bool keep = false)
    {
        if (keep && !refresh && _pages.TryGetValue(userId, out var kept))
        {
            return Task.FromResult(kept);
        }

        if (_pages.TryGetValue(userId, out var page))
        {
            var age = DateTimeOffset.UtcNow - page.BuiltAt;
            // Asked to work it out again: only when the person has watched something since,
            // something arrived or their favourites changed, which a few small queries tell.
            // The apps ask every time Home comes back up. Kos TV: one made without anything
            // from TMDB is worked out again after a few minutes, whatever changed.
            if (IsFresh(page, age, refresh, () => FreshnessStamp(user) == page.Stamp))
            {
                return Task.FromResult(page);
            }
        }

        // Two apps asking at once share the one build. Lazy, and run off this thread, so the
        // entry is in the map before the build can finish and take it out. Kos TV: not one
        // started before what it is worked out from changed (see _versions).
        var version = VersionOf(userId);
        return _building.AddOrUpdate(
            userId,
            _ => NewBuilding(userId, user, version),
            (_, had) => had.Version == version ? had : NewBuilding(userId, user, version)).Page.Value;
    }

    /// <summary>
    /// Kos TV: whether a page <paramref name="age"/> old still stands: up to
    /// <see cref="PageLife"/>, or when asked to <paramref name="refresh"/> up to
    /// <see cref="StaleLife"/> while <paramref name="sameStamp"/> says nothing changed; and
    /// never past <see cref="PartialLife"/> when it was made without anything from TMDB.
    /// </summary>
    internal static bool IsFresh(KostvHomePage page, TimeSpan age, bool refresh, Func<bool> sameStamp)
    {
        if (page.Partial && age >= PartialLife)
        {
            return false;
        }

        return refresh ? age < StaleLife && sameStamp() : age < PageLife;
    }

    private int VersionOf(Guid userId) => _versions.GetValueOrDefault(userId);

    /// <summary>
    /// Kos TV: what the person's page was worked out from has changed (they turned something
    /// down, or their list changed): the page kept goes, and a build under way isn't kept.
    /// </summary>
    private void Invalidate(Guid userId)
    {
        lock (_keepLock)
        {
            _versions.AddOrUpdate(userId, 1, (_, had) => unchecked(had + 1));
            _pages.TryRemove(userId, out _);
        }
    }

    private Building NewBuilding(Guid userId, object user, int version)
    {
        var building = new Building(version);
        building.Page = new Lazy<Task<KostvHomePage>>(() => Task.Run(() => BuildAndKeepAsync(userId, user, building)));
        return building;
    }

    /// <summary>
    /// The last thing the person played and when, the latest arrival they can see and their
    /// favourites: changes when they watch something, something arrives or they mark or unmark
    /// a favourite.
    /// </summary>
    private string FreshnessStamp(object user)
    {
        var last = Query(user, [BaseItemKind.Movie, BaseItemKind.Episode], q => q.IsPlayed = true, 1, ItemSortBy.DatePlayed).FirstOrDefault();
        var history = last == null ? "none" : $"{last.Id:N}:{LastPlayed(user, last)?.Ticks}";
        var newest = Query(user, [BaseItemKind.Movie, BaseItemKind.Series], null, 1, ItemSortBy.DateCreated).FirstOrDefault();
        var favorites = QueryIds(user, [BaseItemKind.Movie, BaseItemKind.Series], q => q.IsFavorite = true, 5000);
        // Which ones, not only how many: the same in any order.
        var sum = 0L;
        foreach (var id in favorites)
        {
            sum += id.GetHashCode();
        }

        return $"{history}|{newest?.Id:N}:{newest?.DateCreated.Ticks}|{favorites.Count}:{sum:X}";
    }

    private async Task<KostvHomePage> BuildAndKeepAsync(Guid userId, object user, Building building)
    {
        try
        {
            var page = await BuildAsync(userId, user).ConfigureAwait(false);
            // Kos TV: not when what it was worked out from changed meanwhile; the next ask
            // works it out again.
            lock (_keepLock)
            {
                if (VersionOf(userId) == building.Version)
                {
                    _pages[userId] = page;
                    _notFound.TryRemove(userId, out _);
                }
            }

            return page;
        }
        finally
        {
            // Only this build's entry: a newer one may have taken its place.
            _building.TryRemove(new KeyValuePair<Guid, Building>(userId, building));
        }
    }

    private async Task<KostvHomePage> BuildAsync(Guid userId, object user)
    {
        var now = DateTimeOffset.UtcNow;
        var stamp = FreshnessStamp(user);
        var (library, items, seen) = ReadLibrary(user);
        var listed = _myList.For(userId);
        var (seeds, followed) = ReadSeeds(user, items, seen, now, listed);
        var dismissed = _dismissals.For(userId);
        var avoid = new List<KostvSeedFacts>();

        var apiKey = await TmdbApiKeys.ResolveAsync(_settings, userId).ConfigureAwait(false);
        var facts = new Dictionary<string, KostvSeedFacts>(StringComparer.Ordinal);
        var credits = new Dictionary<string, IReadOnlyList<string>>(StringComparer.Ordinal);
        var hasKey = !string.IsNullOrWhiteSpace(apiKey);
        if (hasKey)
        {
            var asked = await Task.WhenAll(seeds.Select(async seed => (seed.Key, Entry: await SeedFactsAsync(seed.Key, apiKey!).ConfigureAwait(false)))).ConfigureAwait(false);
            foreach (var (key, entry) in asked)
            {
                if (entry != null)
                {
                    facts[key] = new KostvSeedFacts(
                        entry.Recs,
                        entry.People.Select(p => new KostvPerson(p.Id, p.Name, p.Director)).ToList());
                }
            }

            var people = KostvHomeEngine.PeopleToAsk(seeds, facts);
            var works = await Task.WhenAll(people.Select(async person => (person.Id, Entry: await PersonCreditsAsync(person.Id, apiKey!).ConfigureAwait(false)))).ConfigureAwait(false);
            foreach (var (id, entry) in works)
            {
                if (entry != null)
                {
                    credits[id] = entry.Credits;
                }
            }

            // Kos TV: only what is kept by its TMDB title can be asked about (not what was turned
            // down by the server's own id, having none).
            var avoided = await Task.WhenAll(dismissed.Where(IsTmdbKey).TakeLast(MaxAvoided).Select(key => SeedFactsAsync(key, apiKey!))).ConfigureAwait(false);
            foreach (var entry in avoided)
            {
                if (entry != null)
                {
                    avoid.Add(new KostvSeedFacts(entry.Recs, []));
                }
            }

            _cache.Prune();
            // Kos TV: the file only when something in it changed.
            await _cache.FlushIfChangedAsync().ConfigureAwait(false);
        }

        // Kos TV: with a key and titles to ask about but nothing at all from TMDB (down, slow,
        // turning the key away), the page only stands a few minutes (see PartialLife).
        var partial = hasKey && seeds.Count > 0 && facts.Count == 0;

        // The day, and the person, so two people at home don't get the same shuffle.
        var day = (int)(now.ToUnixTimeSeconds() / 86400) + (userId.GetHashCode() & 0xFFFF);
        // What is on their list they know about already: not offered again. Kos TV: nor the
        // favourites «Volver a ver» offers, or may offer while this page stands, so a title isn't
        // in both.
        var onList = listed.Select(e => e.Key).OfType<string>().Concat(RewatchKeys(userId, user, items, seen, now)).ToList();
        var rows = KostvHomeEngine.Build(seeds, facts, credits, library, day, dismissed, avoid, onList);
        var index = new Dictionary<string, Guid>(StringComparer.Ordinal);
        foreach (var (id, item) in items)
        {
            if (KeyOf(item) is { } key)
            {
                index.TryAdd(key, id);
            }
        }

        return new KostvHomePage(rows, seeds.Count, library.Count, hasKey, now, index, stamp, followed, partial);
    }

    /// <summary>
    /// Notes that the person isn't interested in <paramref name="itemId"/>, a film or series of
    /// the home server, and has their page worked out again without it. Null when it isn't one
    /// of those.
    /// </summary>
    /// <remarks>Kos TV: kept by its TMDB title, so it holds when the file is replaced; one without
    /// a TMDB id is kept by the server's own id instead (<see cref="ItemKey"/>).</remarks>
    public async Task<string?> DismissAsync(Guid userId, Guid itemId, bool undo)
    {
        // Kos TV: only a film or a series is offered, so only one of those can be turned down.
        if (_libraryManager.GetItemById(itemId) is not ({ } item and (Movie or Series)))
        {
            return null;
        }

        var key = KeyOf(item) ?? ItemKey(item.Id);
        bool changed;
        if (undo)
        {
            // Both ways it may have been kept, should it have gained a TMDB id since.
            var byItem = _dismissals.Remove(userId, ItemKey(item.Id));
            changed = _dismissals.Remove(userId, key) | byItem;
        }
        else
        {
            changed = _dismissals.Add(userId, key);
        }

        if (changed)
        {
            await _dismissals.FlushAsync().ConfigureAwait(false);
            Invalidate(userId);
        }

        return key;
    }

    /// <summary>
    /// The home server's items of the titles the person turned down, for the rows the app makes
    /// itself (what is most watched now) to leave out too.
    /// </summary>
    public IReadOnlyList<Guid> Hidden(Guid userId, KostvHomePage page) =>
        _dismissals.For(userId)
            .Select(key => page.Index.TryGetValue(key, out var id) ? id : ItemOfKey(key))
            .Where(id => id != Guid.Empty)
            .Distinct()
            .ToList();

    private const string ItemKeyPrefix = "item:";

    /// <summary>
    /// Kos TV: what a title without a TMDB id is turned down by: the server's own id
    /// ("item:…"). Doesn't hold if the file is replaced, but it does what the person asked.
    /// </summary>
    internal static string ItemKey(Guid itemId) => ItemKeyPrefix + itemId.ToString("N");

    /// <summary>Kos TV: the item of a key made by <see cref="ItemKey"/>, or none.</summary>
    internal static Guid ItemOfKey(string key) =>
        key.StartsWith(ItemKeyPrefix, StringComparison.Ordinal) &&
        Guid.TryParseExact(key.AsSpan(ItemKeyPrefix.Length), "N", out var id)
            ? id
            : Guid.Empty;

    /// <summary>Kos TV: whether a key is a TMDB title ("movie:123", "tv:45").</summary>
    internal static bool IsTmdbKey(string key) =>
        key.Split(':') is [("movie" or "tv"), var number] && long.TryParse(number, out _);

    /// <summary>
    /// New episodes of the series the person follows: not seen, of a favourite series (added in
    /// the last <see cref="KostvFavoritesEngine.NewsWindow"/>) or of one they have watched some of
    /// (the last <see cref="NewEpisodeWindow"/>). One per series, the first of its new ones; the
    /// favourites first, then the rest, each the latest arrival first. Read each time, so an
    /// episode shows as it lands. Also says which of those series are favourites.
    /// </summary>
    /// <remarks>Kos TV: of the regular episodes before the specials, and none of a series the
    /// person is behind on (an episode before it unseen, not new): that isn't news to them, and
    /// it would skip seasons.</remarks>
    public (IReadOnlyList<BaseItem> Episodes, IReadOnlySet<Guid> Favorites) NewEpisodes(Guid userId, object user, KostvHomePage page, int max = 20)
    {
        var followed = page.Followed ?? new HashSet<Guid>();
        var favorites = FavoriteSeries(user);
        if (followed.Count == 0 && favorites.Count == 0)
        {
            return ([], favorites);
        }

        var now = DateTime.UtcNow;
        var since = now - (KostvFavoritesEngine.NewsWindow > NewEpisodeWindow ? KostvFavoritesEngine.NewsWindow : NewEpisodeWindow);
        var bySeries = new Dictionary<Guid, (Episode First, DateTime Latest)>();
        // Kos TV: only the episodes of those series. The newest 500 of the whole server could
        // be all of other series on a server where a lot arrives.
        var ofSeries = followed.Concat(favorites).Distinct().ToArray();
        foreach (var item in Query(user, [BaseItemKind.Episode], q =>
        {
            q.IsPlayed = false;
            q.MinDateCreated = since;
            q.AncestorIds = ofSeries;
        }, 500, ItemSortBy.DateCreated))
        {
            if (item is not Episode { SeriesId: var seriesId } episode)
            {
                continue;
            }

            var favorite = favorites.Contains(seriesId);
            var window = favorite ? KostvFavoritesEngine.NewsWindow : NewEpisodeWindow;
            if ((!favorite && !followed.Contains(seriesId)) || now - episode.DateCreated > window)
            {
                continue;
            }

            if (!bySeries.TryGetValue(seriesId, out var had))
            {
                bySeries[seriesId] = (episode, episode.DateCreated);
                continue;
            }

            var earlier = StoryOrder(episode).CompareTo(StoryOrder(had.First)) < 0;
            bySeries[seriesId] = (earlier ? episode : had.First, had.Latest > episode.DateCreated ? had.Latest : episode.DateCreated);
        }

        foreach (var (key, at) in _behind)
        {
            if (now - at.At >= BehindKeptFor)
            {
                _behind.TryRemove(key, out _);
            }
        }

        var episodes = bySeries
            .OrderByDescending(kv => favorites.Contains(kv.Key))
            .ThenByDescending(kv => kv.Value.Latest)
            .Select(kv => kv.Value.First)
            .Where(episode => !IsBehind(userId, user, episode, now))
            .Take(max)
            .Select(episode => (BaseItem)episode)
            .ToList();
        return (episodes, favorites);
    }

    /// <summary>
    /// Kos TV: where an episode stands in its series, the specials (season 0) after the rest, so
    /// a special is only the first new one when nothing else is new.
    /// </summary>
    internal static (int Special, int Season, int Number) StoryOrder(int? season, int? number) =>
        (season == 0 ? 1 : 0, season ?? 0, number ?? 0);

    private static (int Special, int Season, int Number) StoryOrder(Episode episode) =>
        StoryOrder(episode.ParentIndexNumber, episode.IndexNumber);

    /// <summary>
    /// Kos TV: whether, of the series of <paramref name="first"/>, the person hasn't seen an
    /// episode before it (for a special, any regular one): then they are behind, and the new
    /// one isn't news to them.
    /// </summary>
    internal static bool IsBehind((int Special, int Season, int Number) first, IEnumerable<(int Special, int Season, int Number)> unseen) =>
        unseen.Any(other => first.Special == 1 ? other.Special == 0 || other.CompareTo(first) < 0 : other.Special == 0 && other.CompareTo(first) < 0);

    private bool IsBehind(Guid userId, object user, Episode first, DateTime now)
    {
        var order = StoryOrder(first);
        // Nothing comes before the first episode of the first season.
        if (order is { Special: 0, Season: 1, Number: <= 1 })
        {
            return false;
        }

        if (_behind.TryGetValue((userId, first.Id), out var kept) && now - kept.At < BehindKeptFor)
        {
            return kept.Behind;
        }

        // The unseen ones in the order of the story: the earliest is all that is needed, with
        // room for the specials, which come first.
        var unseen = Query(user, [BaseItemKind.Episode], q =>
            {
                q.IsPlayed = false;
                q.AncestorIds = [first.SeriesId];
            }, 300, ascendingBy: [ItemSortBy.ParentIndexNumber, ItemSortBy.IndexNumber])
            .OfType<Episode>()
            .Where(e => e.Id != first.Id)
            .Select(StoryOrder);
        var behind = IsBehind(order, unseen);
        _behind[(userId, first.Id)] = (now, behind);
        return behind;
    }

    /// <summary>
    /// Kos TV: the film or series on the home server that is the TMDB title <paramref name="key"/>
    /// ("movie:123", "tv:45"), of those the person may see, read from the library itself.
    /// </summary>
    internal BaseItem? FindByKey(string key, object user)
    {
        var parts = key.Split(':');
        if (parts.Length != 2 || !long.TryParse(parts[1], out _))
        {
            return null;
        }

        var kind = parts[0] == "tv" ? BaseItemKind.Series : BaseItemKind.Movie;
        return Query(user, [kind], q => q.HasAnyProviderId = new Dictionary<string, string>
        {
            [MetadataProvider.Tmdb.ToString()] = parts[1],
        }, 1).FirstOrDefault();
    }

    /// <summary>
    /// The films and series on the home server, of those the person may see, that are the TMDB
    /// titles in <paramref name="keys"/> ("movie:123", "tv:45"), in that order. Found through the
    /// index kept with the person's page, so the library isn't read again for each list.
    /// </summary>
    public async Task<IReadOnlyList<(string Key, BaseItem Item)>> FindAsync(Guid userId, object user, IReadOnlyList<string> keys)
    {
        // Kos TV: the page kept, however old. Only its index is read here, and what isn't in it
        // is asked of the library below; working the page out again is for Home's own rows,
        // which decide when it's due.
        var page = await GetAsync(userId, user, refresh: false, keep: true).ConfigureAwait(false);
        var now = DateTime.UtcNow;
        var missing = _notFound.GetOrAdd(userId, _ => new ConcurrentDictionary<string, DateTime>(StringComparer.Ordinal));
        foreach (var (key, at) in missing)
        {
            if (now - at >= NotFoundKeptFor)
            {
                missing.TryRemove(key, out _);
            }
        }

        var found = new List<(string, BaseItem)>();
        foreach (var key in keys.Distinct())
        {
            if (page.Index.TryGetValue(key, out var id) &&
                _libraryManager.GetItemById(id) is { } item &&
                UserReflection.IsVisibleStandaloneTo(item, user))
            {
                found.Add((key, item));
            }
            else if (missing.ContainsKey(key))
            {
                // Kos TV: asked a moment ago and not there (or not for them).
            }
            else if (FindByKey(key, user) is { } fresh && UserReflection.IsVisibleStandaloneTo(fresh, user))
            {
                // Kos TV: arrived (or got a new id) since the index was made: the library
                // itself is asked. With the same check of what the person may see as the rest.
                found.Add((key, fresh));
            }
            else
            {
                missing[key] = now;
            }
        }

        return found;
    }

    // ---------------------------------------------------------------- the server

    /// <summary>Every film and series the person may see, and which of them they have seen.</summary>
    private (List<KostvCandidate> Library, Dictionary<Guid, BaseItem> Items, HashSet<Guid> Seen) ReadLibrary(object user)
    {
        var items = new Dictionary<Guid, BaseItem>();
        var library = new List<KostvCandidate>();

        var seen = new HashSet<Guid>(Query(user, [BaseItemKind.Movie], q => q.IsPlayed = true).Select(i => i.Id));
        // A series counts as seen once any of it has been: it's offered under "carry on", not
        // as something new. Kos TV: one episode read per series, not every episode watched.
        var played = SeriesHaving(user, null, q => q.IsPlayed = true, 20000);
        seen.UnionWith(played.Ids);

        foreach (var item in Query(user, [BaseItemKind.Movie, BaseItemKind.Series], null))
        {
            if (item is Series && played.Has(item))
            {
                seen.Add(item.Id);
            }

            if (!UserReflection.IsVisibleStandaloneTo(item, user))
            {
                continue;
            }

            items[item.Id] = item;
            var key = KeyOf(item);
            if (key == null)
            {
                continue;
            }

            library.Add(new KostvCandidate(
                item.Id.ToString("N"),
                key,
                item is Series,
                seen.Contains(item.Id),
                item.CommunityRating ?? 0,
                item.Genres ?? []));
        }

        return (library, items, seen);
    }

    /// <summary>What the person watched lately and what they marked as favourite, weighed.</summary>
    /// <remarks>Kos TV: <paramref name="seen"/> tells the favourites and titles of their list they
    /// have watched, so only those make a "because you watched" row.</remarks>
    private (List<KostvSeed> Seeds, HashSet<Guid> Followed) ReadSeeds(object user, Dictionary<Guid, BaseItem> items, HashSet<Guid> seen, DateTimeOffset now, IReadOnlyList<KostvMyListEntry> listed)
    {
        var seeds = new Dictionary<string, KostvSeed>(StringComparer.Ordinal);

        void Add(BaseItem item, KostvSeedKind kind, double weight, bool watched)
        {
            var key = KeyOf(item);
            if (key == null)
            {
                return;
            }

            seeds.TryGetValue(key, out var had);
            if (had != null && had.Weight >= weight)
            {
                return;
            }

            // A favourite that weighs more than its watch was still watched.
            watched |= had is { Seen: true } or { Kind: not KostvSeedKind.Liked };
            seeds[key] = new KostvSeed(key, item.Id.ToString("N"), item.Name, item is Series, kind, weight, watched);
        }

        foreach (var movie in Query(user, [BaseItemKind.Movie], q => q.IsPlayed = true, 40, ItemSortBy.DatePlayed))
        {
            Add(movie, KostvSeedKind.Finished, KostvHomeEngine.Recency(DaysSince(LastPlayed(user, movie), now)), true);
        }

        // Episodes come newest first, so the first of each series is its latest.
        var series = new Dictionary<Guid, (DateTime? Last, int Count)>();
        foreach (var episode in Query(user, [BaseItemKind.Episode], q => q.IsPlayed = true, 400, ItemSortBy.DatePlayed))
        {
            if (episode is not Episode { SeriesId: var seriesId } || seriesId == Guid.Empty)
            {
                continue;
            }

            series[seriesId] = series.TryGetValue(seriesId, out var had)
                ? (had.Last, had.Count + 1)
                : (LastPlayed(user, episode), 1);
        }

        // Kos TV: which of them have something left to watch, in one query for all.
        var left = SeriesHaving(user, series.Keys.Where(items.ContainsKey).ToList(), q => q.IsPlayed = false, BulkLimit);
        foreach (var (seriesId, (last, count)) in series)
        {
            if (!items.TryGetValue(seriesId, out var show))
            {
                continue;
            }

            // One episode says little; three, that they are into it.
            var weight = KostvHomeEngine.Recency(DaysSince(last, now)) * Math.Min(1.0, count / 3.0);
            var unwatched = left.Has(show);
            Add(show, unwatched ? KostvSeedKind.Watching : KostvSeedKind.Finished, weight, true);
        }

        foreach (var liked in Query(user, [BaseItemKind.Movie, BaseItemKind.Series], q => q.IsFavorite = true, 30))
        {
            Add(liked, KostvSeedKind.Liked, 0.35, seen.Contains(liked.Id));
        }

        // What they put on their list says as much of their taste as a favourite.
        foreach (var entry in listed.Take(30))
        {
            if (Guid.TryParse(entry.ItemId, out var id) && items.TryGetValue(id, out var wanted))
            {
                Add(wanted, KostvSeedKind.Liked, 0.35, seen.Contains(wanted.Id));
            }
        }

        return (seeds.Values.OrderByDescending(s => s.Weight).Take(MaxSeeds).ToList(), series.Keys.ToHashSet());
    }

    private IEnumerable<BaseItem> Query(
        object user,
        BaseItemKind[] kinds,
        Action<InternalItemsQuery>? filter,
        int? limit = null,
        ItemSortBy? newestBy = null,
        ItemSortBy[]? ascendingBy = null)
    {
        if (MakeQuery(user, kinds, filter, limit, newestBy, ascendingBy) is not { } query)
        {
            return [];
        }

        try
        {
            return _libraryManager.GetItemsResult(query).Items;
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "kOS TV home: a library query failed");
            return [];
        }
    }

    /// <summary>
    /// Kos TV: the ids of what <see cref="Query"/> would read, without reading the items when the
    /// server can say just the ids.
    /// </summary>
    private IReadOnlyList<Guid> QueryIds(object user, BaseItemKind[] kinds, Action<InternalItemsQuery>? filter, int? limit = null)
    {
        if (GetItemIdsMethod != null && MakeQuery(user, kinds, filter, limit, null, null) is { } query)
        {
            try
            {
                if (GetItemIdsMethod.Invoke(_libraryManager, [query]) is IEnumerable<Guid> ids)
                {
                    return ids.ToList();
                }
            }
            catch (Exception ex)
            {
                _logger.LogDebug(ex, "kOS TV home: the ids could not be read alone");
            }
        }

        return Query(user, kinds, filter, limit).Select(i => i.Id).ToList();
    }

    /// <summary>The query for the person, or null when their limits can't be applied.</summary>
    private static InternalItemsQuery? MakeQuery(
        object user,
        BaseItemKind[] kinds,
        Action<InternalItemsQuery>? filter,
        int? limit,
        ItemSortBy? newestBy,
        ItemSortBy[]? ascendingBy)
    {
        var query = new InternalItemsQuery
        {
            IncludeItemTypes = kinds,
            IsVirtualItem = false,
            Recursive = true,
            Limit = limit,
            EnableTotalRecordCount = false
        };
        filter?.Invoke(query);
        if (newestBy.HasValue)
        {
            Order(query, "Descending", newestBy.Value);
        }
        else if (ascendingBy is { Length: > 0 })
        {
            Order(query, "Ascending", ascendingBy);
        }

        // Without the person's limits applied nothing is read, rather than everything.
        return UserReflection.ApplyUser(query, user) ? query : null;
    }

    // The tuple type of OrderBy changed between server versions, so it is built by reflection.
    private static void Order(InternalItemsQuery query, string sortOrder, params ItemSortBy[] sortBy)
    {
        if (OrderByProperty == null)
        {
            return;
        }

        try
        {
            var elementType = OrderByProperty.PropertyType.GetGenericArguments()[0];
            var sortOrderType = elementType.GetGenericArguments()[1];
            var order = Enum.Parse(sortOrderType, sortOrder);
            var array = Array.CreateInstance(elementType, sortBy.Length);
            for (var i = 0; i < sortBy.Length; i++)
            {
                array.SetValue(Activator.CreateInstance(elementType, sortBy[i], order), i);
            }

            OrderByProperty.SetValue(query, array);
        }
        catch
        {
            // Unordered is still right, only less recent first.
        }
    }

    private DateTime? LastPlayed(object user, BaseItem item) => UserDataOf(user, item)?.LastPlayedDate;

    private UserItemData? UserDataOf(object user, BaseItem item)
    {
        try
        {
            return GetUserData?.Invoke(_userDataManager, [user, item]) as UserItemData;
        }
        catch
        {
            return null;
        }
    }

    // ---------------------------------------------------------------- favourites

    /// <summary>The series the person marked as favourite.</summary>
    private HashSet<Guid> FavoriteSeries(object user) =>
        Query(user, [BaseItemKind.Series], q => q.IsFavorite = true)
            .Select(i => i.Id)
            .ToHashSet();

    /// <summary>
    /// The person's favourites of <paramref name="kinds"/>, newest marked first (or the other way
    /// with <paramref name="ascending"/>): <paramref name="limit"/> of them from
    /// <paramref name="start"/>, and how many there are.
    /// </summary>
    public (IReadOnlyList<BaseItem> Items, int Total) FavoritesByAdded(
        Guid userId,
        object user,
        BaseItemKind[] kinds,
        int start,
        int limit,
        bool ascending)
    {
        var all = Query(user, kinds, q => q.IsFavorite = true, 5000)
            .Where(i => UserReflection.IsVisibleStandaloneTo(i, user))
            .ToList();
        var since = _favorites.Since(userId);
        var byId = all.ToDictionary(i => i.Id.ToString("N"), StringComparer.Ordinal);
        var order = KostvFavoritesEngine.ByFavorited(
            all.Select(i =>
            {
                var id = i.Id.ToString("N");
                return new KostvFavoriteEntry(id, since.TryGetValue(id, out var at) ? at : null, i.DateCreated);
            }),
            ascending);
        var page = order.Skip(Math.Max(0, start)).Take(Math.Clamp(limit, 1, 200)).Select(id => byId[id]).ToList();
        SweepFavoriteDates(userId);
        return (page, order.Count);
    }

    // Kos TV: how often what is noted of a person's favourites is checked against the server.
    private static readonly TimeSpan FavoritesSweptEvery = TimeSpan.FromDays(1);
    private readonly ConcurrentDictionary<Guid, DateTime> _favoritesSwept = new();

    /// <summary>
    /// Kos TV: now and then (once a day per person), forgets the dates of favourites that have
    /// been gone from the server a long while (<see cref="KostvFavoriteDates.GoneGrace"/>), so
    /// the file doesn't keep what was deleted long ago.
    /// </summary>
    private void SweepFavoriteDates(Guid userId)
    {
        var now = DateTime.UtcNow;
        if (_favoritesSwept.TryGetValue(userId, out var at) && now - at < FavoritesSweptEvery)
        {
            return;
        }

        _favoritesSwept[userId] = now;
        try
        {
            var gone = _favorites.Noted(userId)
                .Where(id => !Guid.TryParseExact(id, "N", out var guid) || _libraryManager.GetItemById(guid) == null)
                .ToHashSet(StringComparer.Ordinal);
            if (_favorites.Sweep(userId, gone, DateTimeOffset.UtcNow))
            {
                _ = _favorites.FlushAsync();
            }
        }
        catch (Exception ex)
        {
            _logger.LogDebug(ex, "kOS TV: tidying the favourites' dates failed");
        }
    }

    /// <summary>
    /// What arrived lately of the person's favourite series: for each, the first new episode,
    /// how many, whether it opens a new season, and whether it came after they last looked.
    /// </summary>
    public IReadOnlyList<(KostvSeriesNews News, BaseItem Series, BaseItem Episode)> FavoriteNews(Guid userId, object user)
    {
        var favorites = FavoriteSeries(user);
        if (favorites.Count == 0)
        {
            return [];
        }

        var since = DateTime.UtcNow - KostvFavoritesEngine.NewsWindow;
        var episodes = Query(user, [BaseItemKind.Episode], q =>
            {
                q.IsPlayed = false;
                q.MinDateCreated = since;
                // Kos TV: only of the favourite series (see NewEpisodes).
                q.AncestorIds = favorites.ToArray();
            }, 500, ItemSortBy.DateCreated)
            .OfType<Episode>()
            .Where(e => favorites.Contains(e.SeriesId))
            .ToList();
        if (episodes.Count == 0)
        {
            return [];
        }

        // A season counts as new when none of it is older than the window.
        var oldSeasons = new HashSet<string>(StringComparer.Ordinal);
        foreach (var seasonId in episodes.Select(e => e.SeasonId).Where(id => id != Guid.Empty).Distinct())
        {
            var older = Query(user, [BaseItemKind.Episode], q => q.AncestorIds = [seasonId], 400)
                .Any(e => e.DateCreated < since);
            if (older)
            {
                oldSeasons.Add(seasonId.ToString("N"));
            }
        }

        var byId = episodes.ToDictionary(e => e.Id.ToString("N"), StringComparer.Ordinal);
        var news = KostvFavoritesEngine.News(
            episodes.Select(e => new KostvNewEpisode(
                e.Id.ToString("N"),
                e.SeriesId.ToString("N"),
                e.SeasonId.ToString("N"),
                e.ParentIndexNumber ?? 0,
                e.IndexNumber ?? 0,
                e.DateCreated)),
            oldSeasons,
            _favorites.NewsSeenAt(userId));
        var found = new List<(KostvSeriesNews, BaseItem, BaseItem)>();
        foreach (var item in news)
        {
            if (Guid.TryParse(item.SeriesId, out var seriesId) &&
                _libraryManager.GetItemById(seriesId) is { } series &&
                UserReflection.IsVisibleStandaloneTo(series, user) &&
                byId.TryGetValue(item.FirstEpisodeId, out var episode))
            {
                found.Add((item, series, episode));
            }
        }

        return found;
    }

    /// <summary>The person has seen the news of their favourite series.</summary>
    public async Task FavoriteNewsSeenAsync(Guid userId)
    {
        _favorites.NewsSeen(userId, DateTimeOffset.UtcNow);
        await _favorites.FlushAsync().ConfigureAwait(false);
    }

    /// <summary>
    /// Favourite films and series to offer again: watched long ago, or marked and never started.
    /// A different few each day.
    /// </summary>
    public IReadOnlyList<BaseItem> Rewatch(Guid userId, object user, int max = 20)
    {
        var now = DateTime.UtcNow;
        if (_rewatch.TryGetValue((userId, max), out var kept) && now - kept.At < RewatchKeptFor)
        {
            return kept.Items;
        }

        var items = RewatchUncached(userId, user, max);
        _rewatch[(userId, max)] = (now, items);
        return items;
    }

    /// <summary>
    /// Kos TV: the TMDB titles of the favourites not started that «Volver a ver» offers, or will
    /// while a page worked out now stands (<see cref="StaleLife"/>), so the recommendations leave
    /// them out. Those watched long ago it offers are seen, out of them already.
    /// </summary>
    private List<string> RewatchKeys(Guid userId, object user, Dictionary<Guid, BaseItem> items, HashSet<Guid> seen, DateTimeOffset now)
    {
        var since = _favorites.Since(userId);
        var remindBy = now - KostvFavoritesEngine.RemindAfter + StaleLife;
        var keys = new List<string>();
        foreach (var favorite in Query(user, [BaseItemKind.Movie, BaseItemKind.Series], q => q.IsFavorite = true, 2000))
        {
            // Started, as «Volver a ver» tells it: an episode watched, or the film begun.
            if (!items.ContainsKey(favorite.Id) ||
                seen.Contains(favorite.Id) ||
                (favorite is not Series && UserDataOf(user, favorite) is { Played: true } or { PlaybackPositionTicks: > 0 }) ||
                (since.TryGetValue(favorite.Id.ToString("N"), out var at) && at >= remindBy) ||
                KeyOf(favorite) is not { } key)
            {
                continue;
            }

            keys.Add(key);
        }

        return keys;
    }

    private IReadOnlyList<BaseItem> RewatchUncached(Guid userId, object user, int max)
    {
        var since = _favorites.Since(userId);
        var items = Query(user, [BaseItemKind.Movie, BaseItemKind.Series], q => q.IsFavorite = true, 2000)
            .Where(i => UserReflection.IsVisibleStandaloneTo(i, user))
            .ToList();
        // Kos TV: the last episode watched of every favourite series at once, not a query each.
        var lastOf = FirstOfEachSeries(user, items.OfType<Series>().Select(s => s.Id).Distinct().ToArray(), q => q.IsPlayed = true, ItemSortBy.DatePlayed, RecentLimit);
        var candidates = new List<KostvRewatchCandidate>();
        foreach (var item in items)
        {
            var id = item.Id.ToString("N");
            DateTime? lastPlayed;
            bool started;
            if (item is Series)
            {
                var last = lastOf[item.Id];
                lastPlayed = last == null ? null : LastPlayed(user, last);
                started = last != null;
            }
            else
            {
                var data = UserDataOf(user, item);
                lastPlayed = data is { Played: true } ? data.LastPlayedDate : null;
                started = data is { Played: true } or { PlaybackPositionTicks: > 0 };
            }

            candidates.Add(new KostvRewatchCandidate(id, lastPlayed, started, since.TryGetValue(id, out var at) ? at : null));
        }

        var now = DateTimeOffset.UtcNow;
        var day = (int)(now.ToUnixTimeSeconds() / 86400) + (userId.GetHashCode() & 0xFFFF);
        var byId = items.ToDictionary(i => i.Id.ToString("N"), StringComparer.Ordinal);
        return KostvFavoritesEngine.Rewatch(candidates, now, day, max).Select(id => byId[id]).ToList();
    }

    // ---------------------------------------------------------------- my list

    /// <summary>
    /// The film or series <paramref name="itemId"/> stands for on a list: itself, or the series
    /// of an episode or season. Null when it is none of those or the person can't see it.
    /// </summary>
    public BaseItem? ListItemFor(Guid itemId, object user)
    {
        var item = _libraryManager.GetItemById(itemId);
        item = item switch
        {
            Episode { SeriesId: var s } when s != Guid.Empty => _libraryManager.GetItemById(s),
            Season { SeriesId: var s } when s != Guid.Empty => _libraryManager.GetItemById(s),
            _ => item
        };
        return item is Movie or Series && UserReflection.IsVisibleStandaloneTo(item, user) ? item : null;
    }

    /// <summary>
    /// Puts <paramref name="item"/> on the person's list, or with <paramref name="remove"/> takes
    /// it off. <paramref name="arrived"/>: put on by itself, because something they asked for
    /// arrived; only the first time. Whether it is on the list afterwards.
    /// </summary>
    public async Task<bool> SetOnListAsync(Guid userId, BaseItem item, bool remove, bool arrived)
    {
        var id = item.Id.ToString("N");
        var changed = remove
            ? _myList.Remove(userId, [id]) > 0
            : _myList.Add(userId, id, KeyOf(item), arrived);
        if (changed)
        {
            await _myList.FlushAsync().ConfigureAwait(false);
            // What is on the list leaves the recommendations, and the other way round.
            Invalidate(userId);
            ListChanged(userId);
        }

        return _myList.For(userId).Any(e => e.ItemId == id);
    }

    /// <summary>The person's list, in its three parts.</summary>
    /// <remarks>Kos TV: with <paramref name="fresh"/> (the list's own page) read again; Home's row
    /// may use what was read up to a minute ago.</remarks>
    public KostvMyListSections MyList(Guid userId, object user, bool fresh = false)
    {
        var now = DateTime.UtcNow;
        if (!fresh && _lists.TryGetValue(userId, out var kept) && now - kept.At < ListKeptFor)
        {
            return kept.List;
        }

        // Kos TV: not kept when the list changed while it was read, so what was just put on or
        // taken off shows at once (see ListChanged).
        var version = _listVersions.GetValueOrDefault(userId);
        var list = MyListUncached(userId, user);
        lock (_listLock)
        {
            if (_listVersions.GetValueOrDefault(userId) == version)
            {
                _lists[userId] = (now, list);
            }
        }

        return list;
    }

    /// <summary>Kos TV: the person's list changed: what was read of it before isn't kept.</summary>
    private void ListChanged(Guid userId)
    {
        lock (_listLock)
        {
            _listVersions.AddOrUpdate(userId, 1, (_, had) => unchecked(had + 1));
            _lists.TryRemove(userId, out _);
        }
    }

    private KostvMyListSections MyListUncached(Guid userId, object user)
    {
        var watching = new List<(BaseItem Item, DateTime When)>();
        var toStart = new List<BaseItem>();
        var watched = new List<(BaseItem Item, DateTime When)>();
        var gone = new List<string>();
        // Kos TV: what has a TMDB title and isn't on the server now is only missing for a while.
        var missing = new List<string>();
        var present = new List<string>();
        var moved = false;
        var visible = new List<(KostvMyListEntry Entry, BaseItem Item)>();
        foreach (var entry in _myList.For(userId))
        {
            if (!Guid.TryParse(entry.ItemId, out var id) || _libraryManager.GetItemById(id) is not { } item)
            {
                // Kos TV: the server gave the title a new id (renamed, moved, scanned
                // again): found again by its TMDB title, it stays on the list.
                if (entry.Key is { } key && FindByKey(key, user) is { } again &&
                    _myList.Repoint(userId, entry.ItemId, again.Id.ToString("N")))
                {
                    item = again;
                    moved = true;
                }
                else
                {
                    (entry.Key == null ? gone : missing).Add(entry.ItemId);
                    continue;
                }
            }

            present.Add(item.Id.ToString("N"));

            if (UserReflection.IsVisibleStandaloneTo(item, user))
            {
                visible.Add((entry, item));
            }
        }

        // Kos TV: how far they are with all of them at once, not a few queries per series.
        var progress = ProgressOf(user, visible.Select(v => v.Item).ToList());
        foreach (var (entry, item) in visible)
        {
            var (state, when) = progress[item.Id];
            switch (state)
            {
                case KostvListState.Watching:
                    watching.Add((item, when ?? entry.AddedAt.UtcDateTime));
                    break;
                case KostvListState.Watched:
                    watched.Add((item, when ?? entry.AddedAt.UtcDateTime));
                    break;
                default:
                    toStart.Add(item);
                    break;
            }
        }

        // What is no longer on the server leaves the list: at once without a TMDB title to find
        // it again by, after a while with one (a file being replaced comes back with a new id).
        if (gone.Count > 0)
        {
            _myList.Remove(userId, gone);
        }

        var swept = _myList.Sweep(userId, missing, present, DateTimeOffset.UtcNow);
        if (gone.Count > 0 || moved || swept)
        {
            _ = _myList.FlushAsync();
        }

        return new KostvMyListSections(
            watching.OrderByDescending(w => w.When).Select(w => w.Item).ToList(),
            toStart,
            watched.OrderByDescending(w => w.When).Select(w => w.Item).ToList());
    }

    /// <summary>Takes off the person's list everything they have watched; how many went.</summary>
    public async Task<int> ClearWatchedAsync(Guid userId, object user)
    {
        var done = MyListUncached(userId, user).Watched.Select(i => i.Id.ToString("N")).ToList();
        var removed = _myList.Remove(userId, done);
        if (removed > 0)
        {
            await _myList.FlushAsync().ConfigureAwait(false);
            Invalidate(userId);
            ListChanged(userId);
        }

        return removed;
    }

    /// <summary>The ids of what is on the person's list.</summary>
    public IReadOnlyList<string> MyListIds(Guid userId) => _myList.For(userId).Select(e => e.ItemId).ToList();

    /// <summary>
    /// How far the person is with each film or series of their list, and when they last watched
    /// it. A series is watched when nothing of it is left unseen, so a new season brings it back.
    /// </summary>
    /// <remarks>Kos TV: the episodes of all the series are read in three queries, not three per
    /// series.</remarks>
    internal Dictionary<Guid, (KostvListState State, DateTime? When)> ProgressOf(object user, IReadOnlyList<BaseItem> items)
    {
        var progress = new Dictionary<Guid, (KostvListState, DateTime?)>();
        foreach (var item in items.Where(i => i is not Series))
        {
            var data = UserDataOf(user, item);
            progress[item.Id] = data switch
            {
                { Played: true } => (KostvListState.Watched, data.LastPlayedDate),
                { PlaybackPositionTicks: > 0 } => (KostvListState.Watching, data.LastPlayedDate),
                _ => (KostvListState.ToStart, null)
            };
        }

        var series = items.OfType<Series>().Select(s => s.Id).Distinct().ToArray();
        if (series.Length == 0)
        {
            return progress;
        }

        // The last watched and the last part way of each, newest first: the first of each series.
        // Kos TV: of the latest ones only, the rest asked for alone (see FirstOfEachSeries).
        var lastPlayed = FirstOfEachSeries(user, series, q => q.IsPlayed = true, ItemSortBy.DatePlayed, RecentLimit);
        var partway = FirstOfEachSeries(user, series, q => q.IsResumable = true, ItemSortBy.DatePlayed, RecentLimit);
        var started = series.Where(id => lastPlayed[id] != null || partway[id] != null).ToArray();
        // Kos TV: whether any is left, one episode read per series rather than all left.
        var left = SeriesHaving(user, started, q => q.IsPlayed = false, BulkLimit);
        foreach (var id in series)
        {
            if (lastPlayed[id] == null && partway[id] == null)
            {
                progress[id] = (KostvListState.ToStart, null);
                continue;
            }

            var when = new[] { lastPlayed[id], partway[id] }
                .Where(e => e != null)
                .Select(e => LastPlayed(user, e!))
                .Max();
            progress[id] = (Has(left, id) ? KostvListState.Watching : KostvListState.Watched, when);
        }

        return progress;
    }

    /// <summary>
    /// Kos TV: for each of <paramref name="series"/>, the first of its episodes that
    /// <paramref name="filter"/> keeps (newest by <paramref name="newestBy"/>), or null when it
    /// has none. One query for all, of at most <paramref name="limit"/>; if that comes back full,
    /// the series it may have cut off that do have one (<see cref="SeriesHaving"/>) are asked
    /// alone. The same as asking each series alone.
    /// </summary>
    internal Dictionary<Guid, BaseItem?> FirstOfEachSeries(object user, Guid[] series, Action<InternalItemsQuery> filter, ItemSortBy? newestBy, int limit = BulkLimit)
    {
        var first = series.ToDictionary(id => id, _ => (BaseItem?)null);
        if (series.Length == 0)
        {
            return first;
        }

        var read = 0;
        foreach (var item in Query(user, [BaseItemKind.Episode], q =>
            {
                filter(q);
                q.AncestorIds = series;
            }, limit, newestBy))
        {
            read++;
            if (item is Episode { SeriesId: var seriesId } && first.TryGetValue(seriesId, out var had) && had == null)
            {
                first[seriesId] = item;
            }
        }

        if (read >= limit)
        {
            var cutOff = series.Where(id => first[id] == null).ToList();
            var have = SeriesHaving(user, cutOff, filter, BulkLimit);
            foreach (var id in cutOff.Where(id => Has(have, id)))
            {
                first[id] = Query(user, [BaseItemKind.Episode], q =>
                {
                    filter(q);
                    q.AncestorIds = [id];
                }, 1, newestBy).FirstOrDefault();
            }
        }

        return first;
    }

    /// <summary>
    /// Kos TV: the series some episode came from, by id and by the series' presentation key
    /// (one series in two libraries shares it, and its watched state with it).
    /// </summary>
    internal sealed record SeriesMatch(HashSet<Guid> Ids, HashSet<string> Keys)
    {
        public bool Has(BaseItem series) =>
            Ids.Contains(series.Id) ||
            (!string.IsNullOrEmpty(series.PresentationUniqueKey) && Keys.Contains(series.PresentationUniqueKey));
    }

    private bool Has(SeriesMatch match, Guid seriesId) =>
        match.Ids.Contains(seriesId) ||
        (match.Keys.Count > 0 && _libraryManager.GetItemById(seriesId) is { } series && match.Has(series));

    /// <summary>
    /// Kos TV: which of <paramref name="series"/> (every series, when null) have an episode
    /// <paramref name="filter"/> keeps. One episode is read per series, grouped by the series as
    /// the server's own «Next up» does, rather than every episode; only whether there is one is
    /// used, since which one a group gives back isn't fixed. If the answer comes back
    /// <paramref name="limit"/> full (a server that doesn't group), those not found yet are
    /// asked alone, so it is the same as asking each.
    /// </summary>
    internal SeriesMatch SeriesHaving(object user, IReadOnlyCollection<Guid>? series, Action<InternalItemsQuery> filter, int limit)
    {
        var match = new SeriesMatch(new HashSet<Guid>(), new HashSet<string>(StringComparer.Ordinal));
        if (series is { Count: 0 })
        {
            return match;
        }

        var among = series?.ToArray();
        var read = 0;
        foreach (var item in Query(user, [BaseItemKind.Episode], q =>
            {
                filter(q);
                if (among != null)
                {
                    q.AncestorIds = among;
                }

                q.GroupBySeriesPresentationUniqueKey = true;
            }, limit))
        {
            read++;
            if (item is not Episode episode)
            {
                continue;
            }

            if (episode.SeriesId != Guid.Empty)
            {
                match.Ids.Add(episode.SeriesId);
            }

            if (!string.IsNullOrEmpty(episode.SeriesPresentationUniqueKey))
            {
                match.Keys.Add(episode.SeriesPresentationUniqueKey);
            }
        }

        if (read >= limit && among != null)
        {
            foreach (var id in among.Where(id => !Has(match, id)))
            {
                if (QueryIds(user, [BaseItemKind.Episode], q =>
                    {
                        filter(q);
                        q.AncestorIds = [id];
                    }, 1).Count > 0)
                {
                    match.Ids.Add(id);
                }
            }
        }

        return match;
    }

    // Played with no date known: taken as a couple of months ago.
    private static double DaysSince(DateTime? when, DateTimeOffset now) =>
        when.HasValue ? Math.Max(0, (now.UtcDateTime - when.Value.ToUniversalTime()).TotalDays) : 60;

    internal static string? KeyOf(BaseItem item)
    {
        var id = item.GetProviderId(MetadataProvider.Tmdb);
        return string.IsNullOrWhiteSpace(id) || !long.TryParse(id, out var number)
            ? null
            : $"{(item is Series ? "tv" : "movie")}:{number}";
    }

    // ---------------------------------------------------------------- TMDB

    internal async Task<KostvTasteEntry?> SeedFactsAsync(string key, string apiKey)
    {
        if (_cache.Get(key) is { } cached)
        {
            return cached;
        }

        var parts = key.Split(':');
        var (type, id) = (parts[0], parts[1]);
        using var first = await GetAsync($"{TmdbUrl}/3/{type}/{id}?append_to_response=recommendations,credits", apiKey).ConfigureAwait(false);
        if (first == null)
        {
            return null;
        }

        // Kos TV: an answer of an unexpected shape leaves this title out, instead of failing the
        // person's whole Home.
        try
        {
            var entry = ParseSeed(first.RootElement, type);
            for (var page = 2; page <= RecommendationPages; page++)
            {
                using var more = await GetAsync($"{TmdbUrl}/3/{type}/{id}/recommendations?page={page}", apiKey).ConfigureAwait(false);
                if (more == null || !AddRecommendations(entry.Recs, more.RootElement, type))
                {
                    break;
                }
            }

            _cache.Set(key, entry);
            return entry;
        }
        catch (Exception ex) when (ex is InvalidOperationException or FormatException or KeyNotFoundException)
        {
            _logger.LogDebug(ex, "kOS TV home: TMDB's answer for {Key} could not be read", key);
            return null;
        }
    }

    private async Task<KostvTasteEntry?> PersonCreditsAsync(string personId, string apiKey)
    {
        var key = "person:" + personId;
        if (_cache.Get(key) is { } cached)
        {
            return cached;
        }

        using var doc = await GetAsync($"{TmdbUrl}/3/person/{personId}/combined_credits", apiKey).ConfigureAwait(false);
        if (doc == null)
        {
            return null;
        }

        try
        {
            var entry = new KostvTasteEntry { Credits = ParseCredits(doc.RootElement) };
            _cache.Set(key, entry);
            return entry;
        }
        catch (Exception ex) when (ex is InvalidOperationException or FormatException or KeyNotFoundException)
        {
            _logger.LogDebug(ex, "kOS TV home: TMDB's credits of {Key} could not be read", key);
            return null;
        }
    }

    /// <summary>A title's recommendations (first page) and its director or creator and leads.</summary>
    internal static KostvTasteEntry ParseSeed(JsonElement root, string type)
    {
        var entry = new KostvTasteEntry();
        if (root.TryGetProperty("recommendations", out var recommendations))
        {
            AddRecommendations(entry.Recs, recommendations, type);
        }

        void AddPerson(JsonElement person, bool director)
        {
            if (person.TryGetProperty("id", out var id) && id.TryGetInt64(out var number) &&
                person.TryGetProperty("name", out var name) && name.GetString() is { Length: > 0 } text &&
                entry.People.All(p => p.Id != number.ToString()))
            {
                entry.People.Add(new KostvTastePerson { Id = number.ToString(), Name = text, Director = director });
            }
        }

        if (root.TryGetProperty("created_by", out var creators) && creators.ValueKind == JsonValueKind.Array)
        {
            foreach (var creator in creators.EnumerateArray().Take(1))
            {
                AddPerson(creator, true);
            }
        }

        if (root.TryGetProperty("credits", out var credits))
        {
            if (credits.TryGetProperty("crew", out var crew) && crew.ValueKind == JsonValueKind.Array)
            {
                foreach (var member in crew.EnumerateArray()
                    .Where(m => m.TryGetProperty("job", out var job) && job.GetString() == "Director")
                    .Take(1))
                {
                    AddPerson(member, true);
                }
            }

            if (credits.TryGetProperty("cast", out var cast) && cast.ValueKind == JsonValueKind.Array)
            {
                foreach (var member in cast.EnumerateArray().Take(2))
                {
                    AddPerson(member, false);
                }
            }
        }

        return entry;
    }

    /// <summary>Adds a page of recommendations; false when the page had none.</summary>
    internal static bool AddRecommendations(List<string> into, JsonElement page, string type)
    {
        if (!page.TryGetProperty("results", out var results) || results.ValueKind != JsonValueKind.Array)
        {
            return false;
        }

        var any = false;
        foreach (var result in results.EnumerateArray())
        {
            if (!result.TryGetProperty("id", out var id) || !id.TryGetInt64(out var number))
            {
                continue;
            }

            var kind = result.TryGetProperty("media_type", out var media) && media.GetString() is "movie" or "tv"
                ? media.GetString()!
                : type;
            var key = $"{kind}:{number}";
            if (!into.Contains(key))
            {
                into.Add(key);
            }

            any = true;
        }

        return any;
    }

    /// <summary>What a person acted in or directed, the best known first.</summary>
    internal static List<string> ParseCredits(JsonElement root)
    {
        var found = new List<(string Key, double Popularity)>();

        void Add(JsonElement credit)
        {
            if (credit.TryGetProperty("id", out var id) && id.TryGetInt64(out var number) &&
                credit.TryGetProperty("media_type", out var media) && media.GetString() is "movie" or "tv")
            {
                var popularity = credit.TryGetProperty("popularity", out var p) && p.TryGetDouble(out var value) ? value : 0;
                found.Add(($"{media.GetString()}:{number}", popularity));
            }
        }

        if (root.TryGetProperty("cast", out var cast) && cast.ValueKind == JsonValueKind.Array)
        {
            foreach (var credit in cast.EnumerateArray())
            {
                Add(credit);
            }
        }

        if (root.TryGetProperty("crew", out var crew) && crew.ValueKind == JsonValueKind.Array)
        {
            foreach (var credit in crew.EnumerateArray()
                .Where(c => c.TryGetProperty("job", out var job) && job.GetString() == "Director"))
            {
                Add(credit);
            }
        }

        return found.OrderByDescending(f => f.Popularity).Select(f => f.Key).Distinct().ToList();
    }

    /// <summary>Kos TV: whether TMDB turned <paramref name="apiKey"/> away a moment ago.</summary>
    internal bool IsKeyTurnedAway(string apiKey) =>
        _badKeyUntil.TryGetValue(apiKey, out var until) && DateTime.UtcNow < until;

    /// <summary>
    /// Kos TV: TMDB said the key is no good (401): it isn't tried again for <see cref="BadKeyFor"/>,
    /// and the admin is told once (until it works again), not on every request.
    /// </summary>
    internal void KeyTurnedAway(string apiKey)
    {
        _badKeyUntil[apiKey] = DateTime.UtcNow + BadKeyFor;
        if (_badKeyLogged.TryAdd(apiKey, true))
        {
            _logger.LogWarning(
                "kOS TV home: TMDB turned the TMDB key away (401), so the recommendations of Home are left out; it is tried again every {Minutes} minutes. Check the TMDB key on the plugin's settings page",
                (int)BadKeyFor.TotalMinutes);
        }
    }

    /// <summary>Kos TV: TMDB took the key: it is good again, and would be told of again.</summary>
    private void KeyWorks(string apiKey)
    {
        _badKeyUntil.TryRemove(apiKey, out _);
        _badKeyLogged.TryRemove(apiKey, out _);
    }

    private async Task<JsonDocument?> GetAsync(string url, string apiKey)
    {
        // Kos TV: not while TMDB is turning the key away; the page comes out without TMDB and
        // is worked out again soon (see PartialLife).
        if (IsKeyTurnedAway(apiKey))
        {
            return null;
        }

        await _tmdbGate.WaitAsync().ConfigureAwait(false);
        try
        {
            if (IsKeyTurnedAway(apiKey))
            {
                return null;
            }

            var client = _httpClientFactory.CreateClient("MoonfinHttpClient");
            for (var attempt = 0; attempt < 2; attempt++)
            {
                using var request = new HttpRequestMessage(HttpMethod.Get, url);
                TmdbRequestHelper.ApplyAuth(request, apiKey);
                using var response = await client.SendAsync(request).ConfigureAwait(false);
                if ((int)response.StatusCode == 429 && attempt == 0)
                {
                    await Task.Delay(TimeSpan.FromSeconds(2)).ConfigureAwait(false);
                    continue;
                }

                if (response.StatusCode == System.Net.HttpStatusCode.Unauthorized)
                {
                    KeyTurnedAway(apiKey);
                    return null;
                }

                if (!response.IsSuccessStatusCode)
                {
                    _logger.LogDebug("kOS TV home: TMDB answered {Status}", (int)response.StatusCode);
                    return null;
                }

                KeyWorks(apiKey);

                await using var stream = await response.Content.ReadAsStreamAsync().ConfigureAwait(false);
                return await JsonDocument.ParseAsync(stream).ConfigureAwait(false);
            }

            return null;
        }
        catch (Exception ex)
        {
            _logger.LogDebug(ex, "kOS TV home: TMDB could not be reached");
            return null;
        }
        finally
        {
            _tmdbGate.Release();
        }
    }
}
