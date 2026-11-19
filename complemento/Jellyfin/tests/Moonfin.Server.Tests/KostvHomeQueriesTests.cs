using System.Net;
using System.Net.Http;
using Jellyfin.Data.Entities;
using Jellyfin.Data.Enums;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Entities.Movies;
using MediaBrowser.Controller.Entities.TV;
using MediaBrowser.Controller.Library;
using MediaBrowser.Model.Entities;
using MediaBrowser.Model.Querying;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using Moonfin.Server.Kostv;
using Moonfin.Server.Services;
using Xunit;

namespace Moonfin.Server.Tests;

/// <summary>
/// kOS TV: the home page's reads of the library come out the same with one episode per series
/// (grouped by the series, as the server's «Next up» does) as asking each series alone, and the
/// smaller fixes around them.
/// </summary>
public sealed class KostvHomeQueriesTests
{
    private sealed class SeenSeries : Series
    {
        public override bool IsVisibleStandalone(User user) => true;
    }

    private sealed class SeenMovie : Movie
    {
        public override bool IsVisibleStandalone(User user) => true;
    }

    /// <summary>A made-up library that answers the queries the home page makes.</summary>
    private sealed class Library
    {
        public List<BaseItem> Items { get; } = [];

        public Dictionary<Guid, UserItemData> Data { get; } = [];

        /// <summary>Whether the server groups by series when asked (an older one wouldn't).</summary>
        public bool Groups { get; set; } = true;

        /// <summary>How many items each query gave back.</summary>
        public List<int> Answers { get; } = [];

        public Action<Guid>? OnGetItem { get; set; }

        public SeenSeries Series(string name, string? key = null)
        {
            var series = new SeenSeries { Id = Guid.NewGuid(), Name = name, PresentationUniqueKey = key ?? name };
            Items.Add(series);
            return series;
        }

        public SeenMovie Movie(string name, string? tmdb = null)
        {
            var movie = new SeenMovie { Id = Guid.NewGuid(), Name = name };
            if (tmdb != null)
            {
                movie.SetProviderId(MetadataProvider.Tmdb, tmdb);
            }

            Items.Add(movie);
            return movie;
        }

        public Episode Episode(Series series, int season, int number, bool played = false, DateTime? lastPlayed = null, long position = 0)
        {
            var episode = new Episode
            {
                Id = Guid.NewGuid(),
                SeriesId = series.Id,
                SeriesPresentationUniqueKey = series.PresentationUniqueKey,
                ParentIndexNumber = season,
                IndexNumber = number,
            };
            Items.Add(episode);
            Data[episode.Id] = new UserItemData { Key = episode.Id.ToString("N"), Played = played, LastPlayedDate = lastPlayed, PlaybackPositionTicks = position };
            return episode;
        }

        public UserItemData DataOf(BaseItem item) =>
            Data.TryGetValue(item.Id, out var data) ? data : new UserItemData { Key = item.Id.ToString("N") };

        private static bool IsKind(BaseItem item, BaseItemKind kind) => kind switch
        {
            BaseItemKind.Episode => item is Episode,
            BaseItemKind.Series => item is Series,
            BaseItemKind.Movie => item is Movie,
            _ => false
        };

        public List<BaseItem> Run(InternalItemsQuery query)
        {
            var found = Items.Where(i => query.IncludeItemTypes.Any(k => IsKind(i, k)));
            if (query.AncestorIds.Length > 0)
            {
                found = found.Where(i => i is Episode e && query.AncestorIds.Contains(e.SeriesId));
            }

            if (query.IsPlayed.HasValue)
            {
                found = found.Where(i => DataOf(i).Played == query.IsPlayed.Value);
            }

            if (query.IsResumable == true)
            {
                found = found.Where(i => DataOf(i).PlaybackPositionTicks > 0);
            }

            if (query.IsFavorite.HasValue)
            {
                found = found.Where(i => DataOf(i).IsFavorite == query.IsFavorite.Value);
            }

            if (query.OrderBy.Any(o => o.OrderBy == ItemSortBy.DatePlayed))
            {
                found = found.OrderByDescending(i => DataOf(i).LastPlayedDate.HasValue).ThenByDescending(i => DataOf(i).LastPlayedDate);
            }

            if (query.GroupBySeriesPresentationUniqueKey && Groups)
            {
                // Which episode stands for its series isn't fixed: the worst one is given.
                found = found.GroupBy(i => (i as Episode)?.SeriesPresentationUniqueKey).Select(g => g.Last());
            }

            var list = found.Take(query.Limit ?? int.MaxValue).ToList();
            Answers.Add(list.Count);
            return list;
        }

        public ILibraryManager Manager() => RecordingHostProxy.Create<ILibraryManager>((method, args) =>
        {
            switch (method.Name)
            {
                case "GetItemsResult":
                    return new QueryResult<BaseItem>(Run((InternalItemsQuery)args![0]!));
                case "GetItemIds":
                    return Run((InternalItemsQuery)args![0]!).Select(i => i.Id).ToList();
                case "GetItemById" when args is [Guid id]:
                    OnGetItem?.Invoke(id);
                    return Items.FirstOrDefault(i => i.Id == id);
                default:
                    throw new NotSupportedException(method.Name);
            }
        });

        public IUserDataManager UserData() => RecordingHostProxy.Create<IUserDataManager>((method, args) =>
            method.Name == "GetUserData" && args is [_, BaseItem item] ? DataOf(item) : null);
    }

    private sealed class CountingLogger<T> : ILogger<T>
    {
        public int Warnings;

        public IDisposable? BeginScope<TState>(TState state) where TState : notnull => null;

        public bool IsEnabled(LogLevel logLevel) => true;

        public void Log<TState>(LogLevel logLevel, EventId eventId, TState state, Exception? exception, Func<TState, Exception?, string> formatter)
        {
            if (logLevel == LogLevel.Warning)
            {
                Interlocked.Increment(ref Warnings);
            }
        }
    }

    private sealed class Answering : HttpMessageHandler
    {
        private readonly HttpStatusCode _status;

        public Answering(HttpStatusCode status) => _status = status;

        public int Requests;

        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Interlocked.Increment(ref Requests);
            return Task.FromResult(new HttpResponseMessage(_status) { Content = new StringContent("{}") });
        }
    }

    private static readonly string Temp = Path.Combine(Path.GetTempPath(), "kostv-home-queries-" + Guid.NewGuid().ToString("N"));

    private static KostvHomeService NewService(
        Library library,
        int recentLimit = 500,
        HttpMessageHandler? http = null,
        ILogger<KostvHomeService>? logger = null,
        KostvMyList? myList = null) =>
        new(
            library.Manager(),
            library.UserData(),
            http == null ? new ThrowingHttpClientFactory() : new FakeHttpClientFactory(http),
            new MoonfinSettingsService(NullLogger<MoonfinSettingsService>.Instance, Temp),
            new KostvTasteCache(NullLogger<KostvTasteCache>.Instance),
            new KostvDismissals(NullLogger<KostvDismissals>.Instance),
            myList ?? new KostvMyList(NullLogger<KostvMyList>.Instance),
            new KostvFavoriteDates(NullLogger<KostvFavoriteDates>.Instance),
            logger ?? NullLogger<KostvHomeService>.Instance)
        {
            RecentLimit = recentLimit
        };

    private static User NewUser() => new("ana", "auth", "reset");

    /// <summary>What the list's progress was before: each series asked alone, all its episodes read.</summary>
    private static (KostvListState State, DateTime? When) AskedAlone(Library library, BaseItem item)
    {
        if (item is not Series series)
        {
            var data = library.DataOf(item);
            return data switch
            {
                { Played: true } => (KostvListState.Watched, data.LastPlayedDate),
                { PlaybackPositionTicks: > 0 } => (KostvListState.Watching, data.LastPlayedDate),
                _ => (KostvListState.ToStart, null)
            };
        }

        var episodes = library.Items.OfType<Episode>().Where(e => e.SeriesId == series.Id).ToList();
        var played = episodes.Where(e => library.DataOf(e).Played).ToList();
        var partway = episodes.Where(e => library.DataOf(e).PlaybackPositionTicks > 0).ToList();
        if (played.Count == 0 && partway.Count == 0)
        {
            return (KostvListState.ToStart, null);
        }

        DateTime? Latest(List<Episode> of) => of
            .OrderByDescending(e => library.DataOf(e).LastPlayedDate.HasValue)
            .ThenByDescending(e => library.DataOf(e).LastPlayedDate)
            .Select(e => library.DataOf(e).LastPlayedDate)
            .FirstOrDefault();

        var when = new[] { played.Count > 0 ? Latest(played) : null, partway.Count > 0 ? Latest(partway) : null }.Max();
        var left = episodes.Any(e => !library.DataOf(e).Played);
        return (left ? KostvListState.Watching : KostvListState.Watched, when);
    }

    private static (Library Library, List<BaseItem> Listed) LongSeries()
    {
        var library = new Library();
        var now = DateTime.UtcNow;
        var listed = new List<BaseItem>();

        // Long series watched part way: many seen, many left.
        var anime = library.Series("anime");
        for (var i = 1; i <= 240; i++)
        {
            library.Episode(anime, 1, i, played: i <= 40, lastPlayed: i <= 40 ? now.AddDays(-60 + i) : null);
        }

        // Watched to the end, long ago.
        var done = library.Series("done");
        for (var i = 1; i <= 10; i++)
        {
            library.Episode(done, 1, i, played: true, lastPlayed: now.AddDays(-400 + i));
        }

        // Only one part way.
        var started = library.Series("started");
        library.Episode(started, 1, 1, position: 5000, lastPlayed: now.AddHours(-3));
        library.Episode(started, 1, 2);

        // Played without a date.
        var undated = library.Series("undated");
        library.Episode(undated, 1, 1, played: true);
        library.Episode(undated, 1, 2);

        // Nothing watched.
        var fresh = library.Series("fresh");
        library.Episode(fresh, 1, 1);

        var film = library.Movie("film");
        library.Data[film.Id] = new UserItemData { Key = "film", Played = true, LastPlayedDate = now.AddDays(-2) };

        listed.AddRange([anime, done, started, undated, fresh, film]);
        return (library, listed);
    }

    [Theory]
    [InlineData(500, true)]
    [InlineData(3, true)]
    [InlineData(3, false)]
    public void TheListsProgressIsTheSameAsAskingEachSeriesAlone(int recentLimit, bool groups)
    {
        var (library, listed) = LongSeries();
        library.Groups = groups;
        var service = NewService(library, recentLimit);

        var progress = service.ProgressOf(NewUser(), listed);

        foreach (var item in listed)
        {
            Assert.Equal(AskedAlone(library, item), progress[item.Id]);
        }
    }

    [Fact]
    public void WhatIsLeftOfEachSeriesIsReadOneEpisodePerSeries()
    {
        var (library, listed) = LongSeries();
        var service = NewService(library);

        service.ProgressOf(NewUser(), listed);

        // The 200 episodes left of the long one are never read: one episode per series at most
        // for what is left, and the latest watched for the rest.
        var series = listed.OfType<Series>().Count();
        Assert.All(library.Answers, count => Assert.True(count <= 51, $"a query read {count}"));
        Assert.Contains(library.Answers, count => count <= series);
    }

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public void WhichSeriesHaveSomethingIsTheSameGroupedOrNot(bool groups)
    {
        var (library, listed) = LongSeries();
        library.Groups = groups;
        var service = NewService(library);
        var series = listed.OfType<Series>().ToList();

        var left = service.SeriesHaving(NewUser(), series.Select(s => s.Id).ToList(), q => q.IsPlayed = false, 2);
        var played = service.SeriesHaving(NewUser(), null, q => q.IsPlayed = true, 20000);

        foreach (var show in series)
        {
            var episodes = library.Items.OfType<Episode>().Where(e => e.SeriesId == show.Id).ToList();
            Assert.Equal(episodes.Any(e => !library.DataOf(e).Played), left.Has(show));
            Assert.Equal(episodes.Any(e => library.DataOf(e).Played), played.Has(show));
        }
    }

    [Fact]
    public void ASeriesInTwoLibrariesCountsAsWatchedInBoth()
    {
        var library = new Library();
        var one = library.Series("one", key: "shared");
        var other = library.Series("other", key: "shared");
        library.Episode(one, 1, 1, played: true, lastPlayed: DateTime.UtcNow);
        var service = NewService(library);

        var played = service.SeriesHaving(NewUser(), null, q => q.IsPlayed = true, 20000);

        Assert.True(played.Has(one));
        Assert.True(played.Has(other));
    }

    [Theory]
    [InlineData(500)]
    [InlineData(2)]
    public void RewatchOffersTheSameAsAskingEachFavouriteAlone(int recentLimit)
    {
        var library = new Library();
        var now = DateTime.UtcNow;
        var favourites = new List<Series>();
        for (var i = 0; i < 6; i++)
        {
            var series = library.Series("fav" + i);
            favourites.Add(series);
            library.Data[series.Id] = new UserItemData { Key = series.Name, IsFavorite = true };
        }

        // Watched long ago (offered), lately (not), never started (offered), only marked played
        // without a date (started, not offered), and two more watched long ago.
        library.Episode(favourites[0], 1, 1, played: true, lastPlayed: now.AddDays(-300));
        library.Episode(favourites[0], 1, 2, played: true, lastPlayed: now.AddDays(-250));
        library.Episode(favourites[1], 1, 1, played: true, lastPlayed: now.AddDays(-400));
        library.Episode(favourites[1], 1, 2, played: true, lastPlayed: now.AddDays(-5));
        library.Episode(favourites[2], 1, 1);
        library.Episode(favourites[3], 1, 1, played: true);
        library.Episode(favourites[4], 1, 1, played: true, lastPlayed: now.AddDays(-200));
        library.Episode(favourites[5], 1, 1, played: true, lastPlayed: now.AddDays(-190));
        var userId = Guid.NewGuid();
        var service = NewService(library, recentLimit);

        var offered = service.Rewatch(userId, NewUser()).Select(i => i.Id).ToHashSet();

        Assert.Equal(new[] { favourites[0], favourites[2], favourites[4], favourites[5] }.Select(s => s.Id).ToHashSet(), offered);
    }

    [Fact]
    public void APageMadeWithoutTmdbOnlyStandsAFewMinutes()
    {
        var page = new KostvHomePage([], 3, 10, true, DateTimeOffset.UtcNow, new Dictionary<string, Guid>(), "s", null, Partial: true);
        var full = page with { Partial = false };
        var old = KostvHomeService.PartialLife + TimeSpan.FromSeconds(1);

        Assert.True(KostvHomeService.IsFresh(page, TimeSpan.FromMinutes(1), refresh: true, () => true));
        Assert.False(KostvHomeService.IsFresh(page, old, refresh: true, () => true));
        Assert.False(KostvHomeService.IsFresh(page, old, refresh: false, () => true));
        // Made with TMDB: as before.
        Assert.True(KostvHomeService.IsFresh(full, old, refresh: true, () => true));
        Assert.True(KostvHomeService.IsFresh(full, old, refresh: false, () => true));
        Assert.False(KostvHomeService.IsFresh(full, old, refresh: true, () => false));
        Assert.False(KostvHomeService.IsFresh(full, TimeSpan.FromMinutes(21), refresh: false, () => true));
    }

    [Fact]
    public async Task AKeyTmdbTurnsAwayIsNotTriedAgainForAWhileAndToldOnce()
    {
        var http = new Answering(HttpStatusCode.Unauthorized);
        var logger = new CountingLogger<KostvHomeService>();
        var service = NewService(new Library(), http: http, logger: logger);
        var key = "bad-" + Guid.NewGuid().ToString("N");

        Assert.Null(await service.SeedFactsAsync("movie:" + Random.Shared.Next(1, int.MaxValue), key));
        Assert.Null(await service.SeedFactsAsync("movie:" + Random.Shared.Next(1, int.MaxValue), key));

        Assert.Equal(1, http.Requests);
        Assert.Equal(1, logger.Warnings);
        Assert.True(service.IsKeyTurnedAway(key));

        // Still turned away when tried again later: not told again.
        service.KeyTurnedAway(key);
        Assert.Equal(1, logger.Warnings);
    }

    [Fact]
    public async Task NotInterestedWorksForATitleWithoutTmdb()
    {
        var library = new Library();
        var withTmdb = library.Movie("with", tmdb: "77");
        var without = library.Movie("without");
        var userId = Guid.NewGuid();
        var service = NewService(library);

        Assert.Equal("movie:77", await service.DismissAsync(userId, withTmdb.Id, undo: false));
        Assert.Equal(KostvHomeService.ItemKey(without.Id), await service.DismissAsync(userId, without.Id, undo: false));

        var page = new KostvHomePage([], 0, 0, false, DateTimeOffset.UtcNow, new Dictionary<string, Guid> { ["movie:77"] = withTmdb.Id }, "s");
        Assert.Equal(new[] { withTmdb.Id, without.Id }, service.Hidden(userId, page));

        await service.DismissAsync(userId, without.Id, undo: true);
        Assert.Equal(new[] { withTmdb.Id }, service.Hidden(userId, page));
    }

    [Theory]
    [InlineData("movie:12", true)]
    [InlineData("tv:3", true)]
    [InlineData("person:3", false)]
    [InlineData("item:0123456789abcdef0123456789abcdef", false)]
    [InlineData("movie:x", false)]
    public void OnlyTmdbTitlesAreAskedOfTmdb(string key, bool tmdb)
    {
        Assert.Equal(tmdb, KostvHomeService.IsTmdbKey(key));
    }

    [Fact]
    public async Task WhatIsPutOnTheListWhileItIsReadShowsAtOnce()
    {
        var library = new Library();
        var first = library.Movie("first", tmdb: "1");
        var second = library.Movie("second", tmdb: "2");
        var userId = Guid.NewGuid();
        var myList = new KostvMyList(NullLogger<KostvMyList>.Instance);
        var service = NewService(library, myList: myList);
        await service.SetOnListAsync(userId, first, remove: false, arrived: false);

        // Another device puts the second one on while Home is reading the list.
        var once = 0;
        library.OnGetItem = _ =>
        {
            if (Interlocked.Exchange(ref once, 1) == 0)
            {
                service.SetOnListAsync(userId, second, remove: false, arrived: false).GetAwaiter().GetResult();
            }
        };
        service.MyList(userId, NewUser());
        library.OnGetItem = null;

        // The reading that started before isn't kept: the next one has it.
        var list = service.MyList(userId, NewUser());
        Assert.Contains(list.ToStart, i => i.Id == second.Id);
    }

    [Fact]
    public async Task TheTmdbFileIsOnlyWrittenWhenSomethingChanged()
    {
        var cache = new KostvTasteCache(NullLogger<KostvTasteCache>.Instance);
        var path = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Jellyfin", "plugins", "Moonfin", "kostv-home-tmdb.json");

        cache.Set("test:" + Guid.NewGuid().ToString("N"), new KostvTasteEntry());
        await cache.FlushIfChangedAsync();
        var written = File.GetLastWriteTimeUtc(path);

        cache.Prune();
        await Task.Delay(20);
        await cache.FlushIfChangedAsync();

        Assert.Equal(written, File.GetLastWriteTimeUtc(path));
    }
}
