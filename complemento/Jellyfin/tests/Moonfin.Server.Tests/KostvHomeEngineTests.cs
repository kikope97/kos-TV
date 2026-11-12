using System.Text.Json;
using Moonfin.Server.Api;
using Moonfin.Server.Kostv;
using Xunit;

namespace Moonfin.Server.Tests;

/// <summary>
/// kOS TV: the rows of the home page, worked out from what a person watched.
/// </summary>
public sealed class KostvHomeEngineTests
{
    private static KostvCandidate Film(int n, bool seen = false, double rating = 6, params string[] genres) =>
        new($"item{n}", $"movie:{n}", false, seen, rating, genres);

    private static KostvSeed Seed(int n, double weight, KostvSeedKind kind = KostvSeedKind.Finished, bool series = false) =>
        new($"{(series ? "tv" : "movie")}:{n}", $"item{n}", $"Title {n}", series, kind, weight);

    private static KostvSeedFacts Recs(params int[] ids) =>
        new(ids.Select(i => $"movie:{i}").ToList(), Array.Empty<KostvPerson>());

    private static readonly IReadOnlyDictionary<string, IReadOnlyList<string>> NoCredits =
        new Dictionary<string, IReadOnlyList<string>>();

    [Fact]
    public void ARowOnlyOffersWhatIsAtHomeAndNotSeen()
    {
        var library = Enumerable.Range(1, 8).Select(n => Film(n)).Append(Film(9, seen: true)).Append(Film(100, seen: true)).ToList();
        var facts = new Dictionary<string, KostvSeedFacts>
        {
            // 9 is seen, 50 and 51 aren't on the home server.
            ["movie:100"] = Recs(50, 1, 9, 2, 51, 3, 4, 5, 6),
        };

        var rows = KostvHomeEngine.Build([Seed(100, 1)], facts, NoCredits, library, day: 1);

        var first = rows[0];
        Assert.Equal(KostvHomeEngine.BecauseWatched, first.Kind);
        Assert.Equal("Title 100", first.Label);
        Assert.Equal("item100", first.SeedItemId);
        Assert.Equal(["item1", "item2", "item3", "item4", "item5", "item6"], first.ItemIds);
    }

    [Fact]
    public void ASeedWithTooFewAtHomeGetsNoRowOfItsOwnButStillCountsForTheMix()
    {
        var library = Enumerable.Range(1, 12).Select(n => Film(n)).ToList();
        var facts = new Dictionary<string, KostvSeedFacts>
        {
            ["movie:100"] = Recs(1, 2, 3),
            ["movie:101"] = Recs(3, 4, 5),
            ["movie:102"] = Recs(3, 6, 7, 8),
        };

        var rows = KostvHomeEngine.Build(
            [Seed(100, 1), Seed(101, 0.8), Seed(102, 0.5)],
            facts,
            NoCredits,
            library,
            day: 1);

        Assert.DoesNotContain(rows, r => r.Kind == KostvHomeEngine.BecauseWatched);
        var forYou = Assert.Single(rows, r => r.Kind == KostvHomeEngine.ForYou);
        // 3 is recommended by all three, so it leads.
        Assert.Equal("item3", forYou.ItemIds[0]);
        Assert.Equal(8, forYou.ItemIds.Count);
    }

    [Fact]
    public void ATitleShowsInOneRowOnly()
    {
        var library = Enumerable.Range(1, 30).Select(n => Film(n, rating: 8, genres: "Drama")).ToList();
        var facts = new Dictionary<string, KostvSeedFacts>
        {
            ["movie:100"] = Recs(Enumerable.Range(1, 12).ToArray()),
            ["movie:101"] = Recs(Enumerable.Range(6, 14).ToArray()),
        };

        var rows = KostvHomeEngine.Build([Seed(100, 1), Seed(101, 0.9)], facts, NoCredits, library, day: 3);

        var all = rows.SelectMany(r => r.ItemIds).ToList();
        Assert.Equal(all.Count, all.Distinct().Count());
        Assert.All(rows, r => Assert.InRange(r.ItemIds.Count, KostvHomeEngine.MinRow, KostvHomeEngine.MaxRow));
    }

    [Fact]
    public void TheSeriesTheyAreOnGetsItsOwnKindOfRow()
    {
        var library = Enumerable.Range(1, 20).Select(n => new KostvCandidate($"s{n}", $"tv:{n}", true, false, 7, [])).ToList();
        var facts = new Dictionary<string, KostvSeedFacts>
        {
            ["tv:200"] = new(Enumerable.Range(1, 8).Select(i => $"tv:{i}").ToList(), []),
        };

        var rows = KostvHomeEngine.Build(
            [Seed(200, 1, KostvSeedKind.Watching, series: true)],
            facts,
            NoCredits,
            library,
            day: 1);

        Assert.Equal(KostvHomeEngine.BecauseWatching, rows[0].Kind);
    }

    [Fact]
    public void SomeoneFromWhatTheyWatchedGetsARowOfTheirOtherWork()
    {
        var library = Enumerable.Range(1, 10).Select(n => Film(n)).ToList();
        var director = new KostvPerson("p1", "Ana Directora", true);
        var facts = new Dictionary<string, KostvSeedFacts>
        {
            ["movie:100"] = new([], [director]),
        };
        var credits = new Dictionary<string, IReadOnlyList<string>>
        {
            ["p1"] = Enumerable.Range(1, 7).Select(i => $"movie:{i}").ToList(),
        };

        var rows = KostvHomeEngine.Build([Seed(100, 1)], facts, credits, library, day: 1);

        var row = Assert.Single(rows, r => r.Kind == KostvHomeEngine.WithPerson);
        Assert.Equal("Ana Directora", row.Label);
        Assert.Equal(7, row.ItemIds.Count);
    }

    [Fact]
    public void WithNothingWatchedThereAreStillTheGems()
    {
        var library = Enumerable.Range(1, 10).Select(n => Film(n, rating: 8.2)).ToList();

        var rows = KostvHomeEngine.Build([], new Dictionary<string, KostvSeedFacts>(), NoCredits, library, day: 1);

        Assert.Equal(KostvHomeEngine.HiddenGems, Assert.Single(rows).Kind);
    }

    [Fact]
    public void TheSameDayGivesTheSamePageAndAnotherDayMayNot()
    {
        var library = Enumerable.Range(1, 80).Select(n => Film(n, rating: 5 + (n % 5), genres: n % 2 == 0 ? "Drama" : "Comedia")).ToList();
        var seeds = Enumerable.Range(100, 6).Select(n => Seed(n, 1.0 - ((n - 100) * 0.1))).ToList();
        var facts = seeds.ToDictionary(
            s => s.Key,
            s => Recs(Enumerable.Range(1 + ((int.Parse(s.Key[6..]) - 100) * 9), 12).ToArray()));

        string Page(int day) => string.Join("|", KostvHomeEngine.Build(seeds, facts, NoCredits, library, day).Select(r => $"{r.Kind}:{r.Label}"));

        Assert.Equal(Page(7), Page(7));
        Assert.Contains(Enumerable.Range(8, 6), d => Page(d) != Page(7));
    }

    [Fact]
    public void AWatchCountsLessTheLongerAgoItWas()
    {
        Assert.Equal(1, KostvHomeEngine.Recency(0), 3);
        Assert.Equal(0.5, KostvHomeEngine.Recency(21), 3);
        Assert.Equal(0.05, KostvHomeEngine.Recency(400), 3);
    }

    [Fact]
    public void ATitleFromTmdbGivesItsRecommendationsAndWhoMadeIt()
    {
        using var doc = JsonDocument.Parse("""
            {"id": 5,
             "recommendations": {"results": [{"id": 7, "media_type": "movie"}, {"id": 9}, {"id": 7}]},
             "credits": {"cast": [{"id": 1, "name": "Uno"}, {"id": 2, "name": "Dos"}, {"id": 3, "name": "Tres"}],
                         "crew": [{"id": 8, "name": "Montadora", "job": "Editor"}, {"id": 4, "name": "Directora", "job": "Director"}]}}
            """);

        var entry = KostvHomeService.ParseSeed(doc.RootElement, "movie");

        Assert.Equal(["movie:7", "movie:9"], entry.Recs);
        Assert.Equal(["Directora", "Uno", "Dos"], entry.People.Select(p => p.Name));
        Assert.True(entry.People[0].Director);
    }

    [Fact]
    public void APersonsWorkIsTheirFilmsAndSeriesBestKnownFirst()
    {
        using var doc = JsonDocument.Parse("""
            {"cast": [{"id": 1, "media_type": "movie", "popularity": 3}, {"id": 2, "media_type": "tv", "popularity": 9}],
             "crew": [{"id": 3, "media_type": "movie", "job": "Director", "popularity": 5},
                      {"id": 4, "media_type": "movie", "job": "Producer", "popularity": 50}]}
            """);

        Assert.Equal(["tv:2", "movie:3", "movie:1"], KostvHomeService.ParseCredits(doc.RootElement));
    }

    [Fact]
    public void PingTellsTheAppsThisPluginWorksOutTheHomePage()
    {
        Assert.Contains("\"kostvHome\":true", JsonSerializer.Serialize(new MoonfinPingResponse { KostvHome = true }));
    }
}
