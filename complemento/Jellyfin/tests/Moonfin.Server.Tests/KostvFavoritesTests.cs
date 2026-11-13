using Microsoft.Extensions.Logging.Abstractions;
using Moonfin.Server.Kostv;
using Xunit;

namespace Moonfin.Server.Tests;

/// <summary>kOS TV: favourites newest first, the news of favourite series and what to watch again.</summary>
public sealed class KostvFavoritesTests
{
    private static readonly DateTimeOffset Now = new(2026, 11, 13, 12, 0, 0, TimeSpan.Zero);

    [Fact]
    public void AFavouriteIsNotedOnceAndForgottenWhenUnmarked()
    {
        var dates = new KostvFavoriteDates(NullLogger<KostvFavoriteDates>.Instance);
        var ana = Guid.NewGuid();
        var item = Guid.NewGuid();

        Assert.True(dates.Mark(ana, item, true, Now));
        // Saved again for some progress: the first moment stays.
        Assert.False(dates.Mark(ana, item, true, Now.AddDays(1)));
        Assert.Equal(Now, dates.Since(ana)[item.ToString("N")]);

        Assert.True(dates.Mark(ana, item, false, Now));
        Assert.Empty(dates.Since(ana));
        // Unmarking what never was changes nothing.
        Assert.False(dates.Mark(ana, item, false, Now));
        Assert.Empty(dates.Since(Guid.NewGuid()));
    }

    [Fact]
    public void WhenTheNewsWasLastSeenIsKeptPerPerson()
    {
        var dates = new KostvFavoriteDates(NullLogger<KostvFavoriteDates>.Instance);
        var ana = Guid.NewGuid();
        Assert.Null(dates.NewsSeenAt(ana));
        dates.NewsSeen(ana, Now);
        Assert.Equal(Now, dates.NewsSeenAt(ana));
        Assert.Null(dates.NewsSeenAt(Guid.NewGuid()));
    }

    [Fact]
    public void FavouritesGoNewestMarkedFirstThenTheOlderOnesByArrival()
    {
        var order = KostvFavoritesEngine.ByFavorited(
            [
                new("old-a", null, new DateTime(2024, 1, 1)),
                new("marked-1", Now.AddDays(-10), new DateTime(2020, 1, 1)),
                new("old-b", null, new DateTime(2025, 1, 1)),
                new("marked-2", Now.AddDays(-1), new DateTime(2019, 1, 1)),
            ],
            ascending: false);
        Assert.Equal(["marked-2", "marked-1", "old-b", "old-a"], order);

        var reversed = KostvFavoritesEngine.ByFavorited(
            [
                new("a", Now.AddDays(-2), DateTime.MinValue),
                new("b", Now.AddDays(-1), DateTime.MinValue),
            ],
            ascending: true);
        Assert.Equal(["a", "b"], reversed);
    }

    [Fact]
    public void NewsComesPerSeriesTheLatestFirstWithItsFirstNewEpisode()
    {
        var news = KostvFavoritesEngine.News(
            [
                new("e3", "faro", "s2", 2, 3, new DateTime(2026, 11, 10)),
                new("e1", "faro", "s2", 2, 1, new DateTime(2026, 11, 1)),
                new("e2", "faro", "s2", 2, 2, new DateTime(2026, 11, 5)),
                new("x9", "puerto", "p1", 1, 9, new DateTime(2026, 11, 12)),
            ],
            oldSeasons: new HashSet<string> { "p1" },
            seenAt: null);

        Assert.Equal(["puerto", "faro"], news.Select(n => n.SeriesId));
        var faro = news.Single(n => n.SeriesId == "faro");
        Assert.Equal("e1", faro.FirstEpisodeId);
        Assert.Equal(3, faro.Count);
        // None of season 2 is older than the window: a new season.
        Assert.True(faro.NewSeason);
        Assert.Equal(2, faro.Season);
        Assert.False(news.Single(n => n.SeriesId == "puerto").NewSeason);
        Assert.All(news, n => Assert.True(n.Unseen));
    }

    [Fact]
    public void OnlyWhatCameAfterTheLastLookIsUnseen()
    {
        var news = KostvFavoritesEngine.News(
            [
                new("a", "early", "s", 1, 1, new DateTime(2026, 11, 1, 0, 0, 0, DateTimeKind.Utc)),
                new("b", "late", "t", 1, 1, new DateTime(2026, 11, 12, 0, 0, 0, DateTimeKind.Utc)),
            ],
            oldSeasons: new HashSet<string>(),
            seenAt: new DateTimeOffset(2026, 11, 5, 0, 0, 0, TimeSpan.Zero));
        Assert.False(news.Single(n => n.SeriesId == "early").Unseen);
        Assert.True(news.Single(n => n.SeriesId == "late").Unseen);
    }

    [Fact]
    public void WatchAgainWhatWasWatchedLongAgoOrNeverStarted()
    {
        var picked = KostvFavoritesEngine.Rewatch(
            [
                new("long-ago", Now.UtcDateTime.AddDays(-400), true, null),
                new("lately", Now.UtcDateTime.AddDays(-20), true, null),
                new("never-started", null, false, Now.AddDays(-60)),
                new("just-marked", null, false, Now.AddDays(-2)),
                new("half-way", null, true, Now.AddDays(-60)),
            ],
            Now,
            day: 1);
        Assert.Equal(new[] { "long-ago", "never-started" }.Order(), picked.Order());
    }

    [Fact]
    public void WatchAgainChangesFromDayToDayButNotWithinOne()
    {
        var many = Enumerable.Range(0, 30)
            .Select(i => new KostvRewatchCandidate($"m{i}", null, false, null))
            .ToList();
        var monday = KostvFavoritesEngine.Rewatch(many, Now, day: 1, max: 5);
        Assert.Equal(monday, KostvFavoritesEngine.Rewatch(many, Now, day: 1, max: 5));
        Assert.NotEqual(monday, KostvFavoritesEngine.Rewatch(many, Now, day: 2, max: 5));
        Assert.Equal(5, monday.Count);
    }
}
