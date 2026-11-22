using System.Diagnostics;
using System.Text.Json;
using Jellyfin.Data.Entities;
using Jellyfin.Data.Enums;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Entities.Audio;
using MediaBrowser.Controller.Library;
using MediaBrowser.Model.Querying;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging.Abstractions;
using Moonfin.Server.Kostv;
using Moonfin.Server.Services;
using Xunit;

namespace Moonfin.Server.Tests;

/// <summary>
/// kOS TV: the station of a song (<c>GET /Moonfin/Kostv/Music/Station</c>): the recipe with the
/// free sources and its style filter, the variety rules, matching with home and with Deezer, each
/// person's filters, <c>away=false</c>, the caches, the fallback when the sources are slow or
/// down, the optional keys of the panel and the library across server versions. The outside
/// services answer from recorded answers (<see cref="StationHttp"/>): no network.
/// </summary>
public sealed class KostvStationTests : IDisposable
{
    private readonly string _root = Path.Combine(Path.GetTempPath(), "kostv-station-" + Guid.NewGuid().ToString("N"));
    private DateTimeOffset _now = new(2026, 11, 22, 10, 0, 0, TimeSpan.Zero);
    private readonly User _ana = new("ana", "auth", "reset");
    private readonly User _leo = new("leo", "auth", "reset");

    private static readonly KostvStationSeed Copenhague = new("Copenhague", "Vetusta Morla");
    private static readonly KostvStationSeed Titi = new("Tití Me Preguntó", "Bad Bunny");
    private static readonly KostvStationSeed Taza = new("Soy una taza", "CantaJuego");

    public void Dispose()
    {
        if (Directory.Exists(_root))
        {
            Directory.Delete(_root, recursive: true);
        }
    }

    private sealed class Rig
    {
        public required KostvMusicStation Station { get; init; }

        public required KostvStationWeb Web { get; init; }

        public required StationHttp Http { get; init; }

        public required StationLibrary Library { get; init; }
    }

    private Rig Make(StationHttp? http = null, StationLibrary? library = null, string? lastFm = null, string? token = null)
    {
        http ??= StationHttp.FromPacks("radio0");
        library ??= new StationLibrary();
        var cache = new KostvStationDiskCache(_root, () => _now);
        var web = new KostvStationWeb(new StationHttpFactory(http), cache, NullLogger.Instance)
        {
            LastFmKeyOf = () => lastFm,
            ListenBrainzTokenOf = () => token
        };
        foreach (var host in new[] { KostvStationHosts.Deezer, KostvStationHosts.ListenBrainz, KostvStationHosts.ListenBrainzLabs, KostvStationHosts.MusicBrainz, KostvStationHosts.LastFm })
        {
            web.GateOf(host).Interval = TimeSpan.Zero;
        }

        var station = new KostvMusicStation(web, library, cache, NullLogger.Instance)
        {
            Deadline = TimeSpan.FromSeconds(30),
            Now = () => _now
        };
        return new Rig { Station = station, Web = web, Http = http, Library = library };
    }

    private static Task<KostvStationResult> Ask(Rig rig, User user, KostvStationSeed seed, int limit = 50, bool away = true) =>
        rig.Station.StationAsync(user.Id, user, seed, limit, away, CancellationToken.None);

    private static string ArtistOf(KostvStationItem item) =>
        KostvStationRecipe.Primary(item.Away?.Artist ?? ((Audio)item.Home!).Artists[0]);

    private static void AssertVariety(IReadOnlyList<KostvStationItem> items)
    {
        var artists = items.Select(ArtistOf).ToList();
        for (var i = 1; i < artists.Count; i++)
        {
            Assert.NotEqual(artists[i - 1], artists[i]);
        }

        for (var start = 0; start + KostvStationRecipe.VarietyWindow <= artists.Count; start++)
        {
            Assert.All(artists.Skip(start).Take(KostvStationRecipe.VarietyWindow).GroupBy(a => a), g => Assert.True(g.Count() <= KostvStationRecipe.PerArtistInWindow, g.Key));
        }
    }

    // ---------------------------------------------------------------- the recipe

    private static KostvStationTrack Lb(string title, string artist, double score, string? mbid = null) =>
        new(title, artist, Mbid: mbid ?? Guid.NewGuid().ToString("D"), Score: score);

    private static KostvStationTrack Dz(string title, string artist, string id, bool isExplicit = false) =>
        new(title, artist, DeezerId: id, Explicit: isExplicit);

    [Fact]
    public void TheStyleFilterKeepsTheSeedsArtistAndItsRelatedOnly()
    {
        var plan = KostvStationRecipe.Plan(new KostvStationInputs
        {
            SeedTitle = "Tití Me Preguntó",
            SeedArtist = "Bad Bunny",
            Related = ["ROSALÍA", "Rauw Alejandro"],
            ListenBrainz = [Lb("Anti-Hero", "Taylor Swift", 1), Lb("DESPECHÁ", "Rosalía", 0.9), Lb("Me Porto Bonito", "Bad Bunny & Chencho Corleone", 0.5)]
        });

        Assert.Equal(["DESPECHÁ", "Me Porto Bonito"], plan.Select(e => e.Title));
        Assert.All(plan, e => Assert.Equal(KostvStationWhy.ListenBrainz, e.Why));
    }

    [Fact]
    public void ListenBrainzsLikeArtistsOnlyWidenTheFilterWithAStyleTagOrDeezerAgreeing()
    {
        string drake = Guid.NewGuid().ToString("D"), myke = Guid.NewGuid().ToString("D"), quevedo = Guid.NewGuid().ToString("D");
        var plan = KostvStationRecipe.Plan(new KostvStationInputs
        {
            SeedTitle = "Tití Me Preguntó",
            SeedArtist = "Bad Bunny",
            SeedArtistTags = new HashSet<string> { "reggaeton", "trap latino" },
            SimilarArtists = ["Drake", "Myke Towers", "Quevedo"],
            RelatedOfRelated = ["Quevedo"],
            ListenBrainz = [Lb("Rich Flex", "Drake & 21 Savage", 1, drake), Lb("LALA", "Myke Towers", 0.8, myke), Lb("Columbia", "Quevedo", 0.7, quevedo)],
            Recordings = new Dictionary<string, KostvStationRecordingInfo>
            {
                [drake] = new(2022, [], [], new HashSet<string> { "hip hop", "trap" }),
                [myke] = new(2023, [], [], new HashSet<string> { "reggaeton" }),
                [quevedo] = new(2023, [], [], new HashSet<string>())
            }
        });

        Assert.Equal(["LALA", "Columbia"], plan.Select(e => e.Title));
    }

    [Fact]
    public void AStrongTagIsOneManyTaggedNotALoneOne()
    {
        var tags = KostvStationRecipe.StrongTags(new Dictionary<string, double> { ["reggaeton"] = 7, ["trap latino"] = 5, ["latin trap"] = 3, ["hip hop"] = 1 });
        Assert.Equal(new HashSet<string> { "reggaeton", "trap latino", "latin trap" }, tags);
        Assert.Null(KostvStationRecipe.StyleTag("Pop"));
        Assert.Null(KostvStationRecipe.StyleTag("80s"));
        Assert.Equal("flamenco pop", KostvStationRecipe.StyleTag("Flamenco Pop"));
    }

    [Fact]
    public void DeezersRadioFillsInAfterTheCandidatesOrLeadsWhenFewPass()
    {
        var radio = Enumerable.Range(1, 6).Select(i => Dz("Radio " + i, "Artista " + i, (100 + i).ToString())).ToList();
        KostvStationInputs Inputs(int passing) => new()
        {
            SeedTitle = "Semilla",
            SeedArtist = "Artista",
            Related = Enumerable.Range(1, 20).Select(i => "Parecido " + i).ToList(),
            ListenBrainz = Enumerable.Range(1, passing).Select(i => Lb("Escuchada " + i, "Parecido " + i, 1 - (i / 100.0))).ToList(),
            Radio = radio
        };

        var many = KostvStationRecipe.Plan(Inputs(12));
        Assert.All(many.Take(12), e => Assert.Equal(KostvStationWhy.ListenBrainz, e.Why));
        Assert.All(many.Skip(12), e => Assert.Equal(KostvStationWhy.Deezer, e.Why));

        var few = KostvStationRecipe.Plan(Inputs(3));
        Assert.Equal([KostvStationWhy.Deezer, KostvStationWhy.Deezer, KostvStationWhy.ListenBrainz], few.Take(3).Select(e => e.Why));
        Assert.Equal(9, few.Count);
    }

    [Fact]
    public void VersionsChristmasSongsTheSeedAndRepeatsAreLeftOut()
    {
        KostvStationInputs Inputs(string seedTitle, int month) => new()
        {
            SeedTitle = seedTitle,
            SeedArtist = "Artista",
            Month = month,
            Radio =
            [
                Dz("Canción (En directo)", "Otro", "1"),
                Dz("Una Foto Remix (feat. Emilia)", "Mesita", "2"),
                Dz("Feliz Navidad", "José Feliciano", "3"),
                Dz("Semilla", "Quien la versiona", "4"),
                Dz("Buena", "Otro", "5"),
                Dz("Buena (Remastered 2011)", "Otro", "6"),
                Dz("Otra buena", "Otro más", "5"),
                Dz("Canción - Acoustic", "Otro", "7")
            ]
        };

        Assert.Equal(["Buena"], KostvStationRecipe.Plan(Inputs("Semilla", 11)).Select(e => e.Title));
        Assert.Equal(["Feliz Navidad", "Buena"], KostvStationRecipe.Plan(Inputs("Semilla", 12)).Select(e => e.Title));
        // A live seed lets in the live versions.
        Assert.Contains("Canción (En directo)", KostvStationRecipe.Plan(Inputs("Semilla (En directo)", 11)).Select(e => e.Title));
        Assert.True(KostvStationRecipe.VersionsOf("Te Daré (Remastered)").Count == 0);
        Assert.Contains("karaoke", KostvStationRecipe.VersionsOf("Rosas (Karaoke Version)"));
    }

    [Fact]
    public void FarInTimeWeighsLessWithoutGoingOut()
    {
        string old = Guid.NewGuid().ToString("D"), near = Guid.NewGuid().ToString("D");
        var plan = KostvStationRecipe.Plan(new KostvStationInputs
        {
            SeedTitle = "Copenhague",
            SeedArtist = "Vetusta Morla",
            SeedYear = 2008,
            Related = ["Love of Lesbian", "Los Secretos"],
            ListenBrainz = [Lb("Déjame", "Los Secretos", 1, old), Lb("Club de fans de John Boy", "Love of Lesbian", 0.9, near)],
            Recordings = new Dictionary<string, KostvStationRecordingInfo>
            {
                [old] = new(1975, [], [], new HashSet<string>()),
                [near] = new(2009, [], [], new HashSet<string>())
            }
        });

        Assert.Equal(["Club de fans de John Boy", "Déjame"], plan.Select(e => e.Title));
        Assert.Equal(KostvStationRecipe.FarEraFactor, plan[1].Score, 3);
    }

    [Fact]
    public void VarietyNeverTwoInARowAtMostTwoIn25AndTheSeedsArtistBack()
    {
        var songs = new List<(string Artist, string Title)>();
        for (var i = 0; i < 40; i++)
        {
            songs.Add(("A", "a" + i));
            songs.Add(("B", "b" + i));
            songs.Add(("S", "s" + i));
            songs.Add(("C" + i, "c" + i));
            songs.Add(("D" + i, "d" + i));
        }

        var arranged = KostvStationRecipe.Arrange(songs, s => s.Artist, _ => null, new HashSet<string> { "S" }, 60);
        Assert.Equal(60, arranged.Count);
        for (var i = 1; i < arranged.Count; i++)
        {
            Assert.NotEqual(arranged[i - 1].Artist, arranged[i].Artist);
        }

        for (var start = 0; start + 25 <= arranged.Count; start++)
        {
            Assert.All(arranged.Skip(start).Take(25).GroupBy(s => s.Artist), g => Assert.True(g.Count() <= 2));
        }

        // The seed's artist comes back every 8 (as far as the 2 in 25 let it), though last in the list.
        var others = Enumerable.Range(0, 30).Select(i => ("O" + i, "o" + i)).Concat(Enumerable.Range(0, 10).Select(i => ("S", "s" + i))).ToList();
        var withSeed = KostvStationRecipe.Arrange(others, s => s.Item1, _ => null, new HashSet<string> { "S" }, 40);
        var seedAt = withSeed.Select((s, i) => (s, i)).Where(p => p.s.Item1 == "S").Select(p => p.i).ToList();
        Assert.Equal([7, 15, 32], seedAt);

        // Two of one album never in a row.
        var albums = KostvStationRecipe.Arrange([("X", "Disco"), ("Y", "Disco"), ("Z", "Otro")], s => s.Item1, s => s.Item2, new HashSet<string>(), 3);
        Assert.Equal(["X", "Z", "Y"], albums.Select(a => a.Item1));
    }

    // ---------------------------------------------------------------- the whole station, recorded

    [Fact]
    public async Task ASongWithListenersGetsTheirSongsOfItsStyle()
    {
        var rig = Make();
        var result = await Ask(rig, _ana, Copenhague);

        Assert.Equal(KostvStationSource.ListenBrainz, result.Source);
        Assert.Equal(50, result.Items.Count);
        Assert.All(result.Items, i => Assert.True(i.Away?.DeezerId != null));
        Assert.True(result.Items.Take(15).Count(i => i.Why == KostvStationWhy.ListenBrainz) >= 10);
        Assert.Contains(result.Items, i => i.Away!.Artist == "Love of Lesbian");
        Assert.Contains(result.Items.Take(SeedEveryWithin), i => i.Away!.Artist == "Vetusta Morla");
        Assert.DoesNotContain(result.Items, i => KostvStationRecipe.IsSeedLike(i.Away!.Title, "Copenhague"));
        Assert.NotNull(result.SeedMbid);
        AssertVariety(result.Items);

        // Free and without keys: no Last.fm, no token, a generic User-Agent of the plugin.
        Assert.Equal(0, rig.Http.CountTo(KostvStationHosts.LastFm));
        Assert.All(rig.Http.Requests, r => Assert.False(r.Headers.Contains("Authorization")));
        Assert.All(rig.Http.Requests, r => Assert.StartsWith("kOS-TV-complemento/", r.Headers.UserAgent.ToString(), StringComparison.Ordinal));
        // Both datasets of ListenBrainz Labs.
        Assert.Contains(rig.Http.Requests, r => r.RequestUri!.AbsolutePath == "/mlhd-similar-recordings/json");
        Assert.Contains(rig.Http.Requests, r => r.RequestUri!.AbsolutePath == "/similar-recordings/json");
    }

    private const int SeedEveryWithin = KostvStationRecipe.SeedArtistEvery + 1;

    [Fact]
    public async Task UrbanMusicIsLedByDeezersRadioWithoutTheGlobalHitsOfItsTime()
    {
        var result = await Ask(Make(), _ana, Titi);

        Assert.Equal(KostvStationWhy.Deezer, result.Items[0].Why);
        Assert.Contains(result.Items, i => i.Why == KostvStationWhy.ListenBrainz && i.Away!.Artist.StartsWith("ROSAL", StringComparison.Ordinal));
        foreach (var name in new[] { "Drake", "Lizzo", "Doja Cat", "Post Malone", "Taylor Swift", "Harry Styles" })
        {
            Assert.DoesNotContain(result.Items, i => i.Away!.Artist.Contains(name, StringComparison.Ordinal));
        }

        Assert.DoesNotContain(result.Items, i => KostvStationRecipe.VersionsOf(i.Away!.Title).Count > 0);
        AssertVariety(result.Items);
    }

    [Fact]
    public async Task ASongNobodyListensToOnListenBrainzIsDeezersRadio()
    {
        var result = await Ask(Make(), _ana, Taza);

        Assert.Equal(KostvStationSource.Fallback, result.Source);
        Assert.True(result.Items.Count >= 25);
        Assert.All(result.Items, i => Assert.Contains(i.Why, new[] { KostvStationWhy.Deezer, KostvStationWhy.Style }));
    }

    // ---------------------------------------------------------------- home, Deezer and each person

    [Fact]
    public async Task WhatIsAtHomeComesAsItsCardByRecordingOrByNameAndAwayFalseIsOnlyThat()
    {
        var rig = Make();
        var first = await Ask(rig, _ana, Copenhague);
        var byMbid = first.Items.First(i => i.Away!.Mbid != null && i.Away.Artist == "Love of Lesbian").Away!;
        var atHomeByMbid = rig.Library.Add("Otro nombre en casa", "Love of Lesbian", mbid: byMbid.Mbid);
        var atHomeByName = rig.Library.Add("alta fidelidad", "LORI MEYERS", album: "Cronolánea");

        var second = await Ask(rig, _ana, Copenhague);
        Assert.Contains(second.Items, i => i.Home?.Id == atHomeByMbid.Id && i.Away == null);
        Assert.Contains(second.Items, i => i.Home?.Id == atHomeByName.Id);
        Assert.DoesNotContain(second.Items, i => i.Away?.DeezerId == byMbid.DeezerId);
        Assert.DoesNotContain(second.Items, i => i.Away?.Title == "Alta fidelidad");

        var home = await Ask(rig, _ana, Copenhague, away: false);
        Assert.Equal(2, home.Items.Count);
        Assert.All(home.Items, i => Assert.Null(i.Away));
    }

    [Fact]
    public async Task WhatAPersonMayNotSeeAtHomeDoesntComeFromOutsideEither()
    {
        var rig = Make();
        await Ask(rig, _ana, Copenhague);
        var song = rig.Library.Add("Alta fidelidad", "Lori Meyers");
        rig.Library.Hidden.Add((_leo.Id, song.Id));

        var leo = await Ask(rig, _leo, Copenhague);
        Assert.DoesNotContain(leo.Items, i => i.Home?.Id == song.Id || i.Away?.Title == "Alta fidelidad");
        Assert.Contains((await Ask(rig, _ana, Copenhague)).Items, i => i.Home?.Id == song.Id);
    }

    [Fact]
    public async Task NoMeGustaOfSongsAndArtistsIsLeftOut()
    {
        var rig = Make();
        var before = await Ask(rig, _ana, Copenhague);
        var song = before.Items.First(i => i.Away!.Artist == "Sidonie").Away!;
        var home = rig.Library.Add("Alta fidelidad", "Lori Meyers");
        rig.Station.DislikesOf = id => id == _ana.Id
            ? new KostvDislikeSet([home.Id], ["IZAL"], new Dictionary<string, int>(), streamedSongs: [song.DeezerId!])
            : KostvDislikeSet.Empty;

        var after = await Ask(rig, _ana, Copenhague);
        Assert.DoesNotContain(after.Items, i => i.Away?.Artist == "IZAL");
        Assert.DoesNotContain(after.Items, i => i.Away?.DeezerId == song.DeezerId);
        Assert.DoesNotContain(after.Items, i => i.Home?.Id == home.Id || i.Away?.Title == "Alta fidelidad");
        Assert.Contains((await Ask(rig, _leo, Copenhague)).Items, i => i.Away?.Artist == "IZAL");
    }

    [Fact]
    public async Task SomeoneWithAnAgeLimitGetsDeezersRadioWithoutWhatIsExplicit()
    {
        var rig = Make();
        rig.Station.AgeLimitedOf = id => id == _leo.Id;
        var ana = await Ask(rig, _ana, Titi);
        Assert.Contains(ana.Items, i => i.Away!.Explicit == true);

        var leo = await Ask(rig, _leo, Titi);
        Assert.NotEmpty(leo.Items);
        Assert.All(leo.Items, i => Assert.False(i.Away!.Explicit ?? true));
        Assert.All(leo.Items, i => Assert.Contains(i.Why, new[] { KostvStationWhy.Deezer, KostvStationWhy.Style }));
    }

    [Fact]
    public async Task TheSeedItselfAndLimitAreRespected()
    {
        var rig = Make();
        var seed = rig.Library.Add("Copenhague", "Vetusta Morla");
        var result = await Ask(rig, _ana, new KostvStationSeed("Copenhague", "Vetusta Morla", HomeId: seed.Id), limit: 10);
        Assert.Equal(10, result.Items.Count);
        Assert.DoesNotContain(result.Items, i => i.Home?.Id == seed.Id);
        Assert.Empty(KostvStationRecipe.Plan(new KostvStationInputs { SeedTitle = "x", SeedArtist = "y" }));
    }

    // ---------------------------------------------------------------- caches and fallback

    [Fact]
    public async Task TheStationIsKeptForTheDayAndTheAnswersFor30Days()
    {
        var rig = Make();
        var first = await Ask(rig, _ana, Copenhague);
        Assert.True(rig.Http.Requests.Count > 10);

        // Another server start, nothing answering: the same station, from the disk.
        var offline = new StationHttp();
        offline.Down.UnionWith([KostvStationHosts.Deezer, KostvStationHosts.ListenBrainz, KostvStationHosts.ListenBrainzLabs, KostvStationHosts.MusicBrainz]);
        var again = Make(offline);
        var second = await Ask(again, _ana, Copenhague);
        Assert.Empty(offline.Requests);
        Assert.Equal(first.Items.Select(i => i.Away!.DeezerId), second.Items.Select(i => i.Away!.DeezerId));
        Assert.Equal(KostvStationSource.ListenBrainz, second.Source);

        // The next day it is made again, from the answers kept (30 days): nothing asked of
        // ListenBrainz again (only Deezer, for a song or two the new order reaches first).
        _now = _now.AddDays(1);
        var nextDay = await Ask(Make(offline), _ana, Copenhague);
        Assert.DoesNotContain(offline.Requests, r => r.RequestUri!.Host != KostvStationHosts.Deezer);
        Assert.True(offline.Requests.Count < 20, offline.Requests.Count.ToString());
        Assert.Equal(KostvStationSource.ListenBrainz, nextDay.Source);
        // Much the same songs (with another little shuffle of the order).
        Assert.True(nextDay.Items.Select(i => i.Away!.DeezerId).Intersect(first.Items.Select(i => i.Away!.DeezerId)).Count() >= 30);

        // And after 30 days, asked again.
        _now = _now.AddDays(31);
        await Ask(Make(offline), _ana, Copenhague);
        Assert.NotEmpty(offline.Requests);
    }

    [Fact]
    public void TheDiskKeepsWithinItsSize()
    {
        var cache = new KostvStationDiskCache(_root, () => _now) { MaxBytes = 20_000 };
        var body = JsonSerializer.SerializeToElement(new { data = new string('x', 900) });
        for (var i = 0; i < 100; i++)
        {
            cache.Put("respuestas", "https://api.deezer.com/track/" + i, 200, body);
        }

        var size = new DirectoryInfo(_root).EnumerateFiles("*", SearchOption.AllDirectories).Sum(f => f.Length);
        Assert.True(size <= 20_000, size.ToString());
        Assert.True(cache.TryGet("respuestas", "https://api.deezer.com/track/99", TimeSpan.FromDays(30), out var status, out _));
        Assert.Equal(200, status);
        Assert.False(cache.TryGet("respuestas", "https://api.deezer.com/track/0", TimeSpan.FromDays(30), out _, out _));
    }

    [Fact]
    public async Task SlowSourcesGetWhatThereIsInAFewSecondsAndTheWholeOneNextTime()
    {
        var http = StationHttp.FromPacks("radio0");
        http.Slow[KostvStationHosts.ListenBrainzLabs] = TimeSpan.FromSeconds(1);
        var rig = Make(http);
        rig.Station.Deadline = TimeSpan.FromMilliseconds(300);

        var clock = Stopwatch.StartNew();
        var quick = await Ask(rig, _ana, Copenhague);
        Assert.True(clock.Elapsed < TimeSpan.FromSeconds(3), clock.Elapsed.ToString());
        Assert.Equal(KostvStationSource.Fallback, quick.Source);
        Assert.NotEmpty(quick.Items);
        Assert.All(quick.Items, i => Assert.Contains(i.Why, new[] { KostvStationWhy.Deezer, KostvStationWhy.Style }));

        rig.Station.Deadline = TimeSpan.FromSeconds(60);
        var whole = await Ask(rig, _ana, Copenhague);
        Assert.Equal(KostvStationSource.ListenBrainz, whole.Source);
        Assert.Equal(50, whole.Items.Count);
    }

    [Fact]
    public async Task WithListenBrainzDownTheStationIsDeezersAndNotKept()
    {
        var http = StationHttp.FromPacks("radio0");
        http.Down.UnionWith([KostvStationHosts.ListenBrainz, KostvStationHosts.ListenBrainzLabs]);
        var rig = Make(http);

        var result = await Ask(rig, _ana, Copenhague);
        Assert.Equal(KostvStationSource.Fallback, result.Source);
        Assert.NotEmpty(result.Items);
        Assert.All(result.Items, i => Assert.Contains(i.Why, new[] { KostvStationWhy.Deezer, KostvStationWhy.Style }));
        Assert.False(Directory.Exists(Path.Combine(_root, "emisoras")));

        // Nothing at all answering: an empty fallback, not an error.
        var none = new StationHttp();
        none.Down.UnionWith([KostvStationHosts.Deezer, KostvStationHosts.ListenBrainz, KostvStationHosts.ListenBrainzLabs, KostvStationHosts.MusicBrainz]);
        var empty = await Ask(Make(none), _ana, new KostvStationSeed("Otra", "Nadie"));
        Assert.Equal(KostvStationSource.Fallback, empty.Source);
        Assert.Empty(empty.Items);
    }

    [Fact]
    public async Task TheRateIsKeptToEachService()
    {
        var gate = new KostvRateGate(TimeSpan.FromMilliseconds(100));
        var clock = Stopwatch.StartNew();
        await Task.WhenAll(Enumerable.Range(0, 4).Select(_ => gate.WaitAsync(CancellationToken.None)));
        Assert.True(clock.ElapsedMilliseconds >= 290, clock.ElapsedMilliseconds.ToString());
        Assert.Equal(TimeSpan.FromSeconds(1), KostvStationHosts.IntervalOf(KostvStationHosts.MusicBrainz));
        Assert.Equal(TimeSpan.FromMilliseconds(500), KostvStationHosts.IntervalOf(KostvStationHosts.Deezer));
        Assert.Equal(TimeSpan.FromMilliseconds(500), KostvStationHosts.IntervalOf(KostvStationHosts.ListenBrainzLabs));
    }

    // ---------------------------------------------------------------- the panel's keys

    [Fact]
    public async Task WithLastFmsKeyItIsAskedToAndTheKeyIsNotWrittenDown()
    {
        const string key = "clave-de-prueba-123";
        var http = StationHttp.FromPacks("radio0");
        var query = KostvStationWeb.Query(("method", "track.getsimilar"), ("artist", "Vetusta Morla"), ("track", "Copenhague"), ("autocorrect", "1"), ("limit", "100"), ("format", "json"));
        http.Add(KostvStationWeb.LastFmBase + "?" + query + "&api_key=" + key, 200,
            """{"similartracks":{"track":[{"name":"Maldita dulzura","match":"0.99","artist":{"name":"Vetusta Morla"}}]}}""");
        http.Add(KostvStationWeb.DeezerBase + "/search/track?" + KostvStationWeb.Query(("q", "artist:\"Vetusta Morla\" track:\"Maldita dulzura\""), ("limit", "10")), 200,
            """{"data":[{"id":71000001,"title":"Maldita dulzura","explicit_lyrics":false,"artist":{"id":1,"name":"Vetusta Morla"},"album":{"title":"La Deriva"}}]}""");
        var rig = Make(http, lastFm: key, token: "token-de-prueba");

        var result = await Ask(rig, _ana, Copenhague);
        Assert.Equal(1, http.CountTo(KostvStationHosts.LastFm));
        Assert.Contains(result.Items, i => i.Why == KostvStationWhy.LastFm && i.Away!.DeezerId == "71000001");
        foreach (var file in Directory.EnumerateFiles(_root, "*", SearchOption.AllDirectories))
        {
            var text = File.ReadAllText(file);
            Assert.DoesNotContain(key, text, StringComparison.Ordinal);
            Assert.DoesNotContain("token-de-prueba", text, StringComparison.Ordinal);
        }

        // ListenBrainz's token goes only to its API, as its own header.
        Assert.All(http.Requests.Where(r => r.Headers.Contains("Authorization")), r => Assert.Equal(KostvStationHosts.ListenBrainz, r.RequestUri!.Host));
        Assert.Contains(http.Requests, r => r.Headers.TryGetValues("Authorization", out var v) && v.Single() == "Token token-de-prueba");
    }

    [Fact]
    public async Task WithoutKeysInThePanelNothingIsAskedOfLastFm()
    {
        var web = new KostvStationWeb(new StationHttpFactory(new StationHttp()), new KostvStationDiskCache(_root), NullLogger.Instance)
        {
            LastFmKeyOf = () => "   ",
            ListenBrainzTokenOf = () => null
        };
        Assert.False(web.HasLastFm);
        var (tracks, failed) = await web.LastFmSimilarAsync("Copenhague", "Vetusta Morla", CancellationToken.None);
        Assert.Empty(tracks);
        Assert.False(failed);
        // And the plugin's own settings without them (a server that never had them) are read as empty.
        Assert.Null(new PluginConfiguration().KostvLastFmApiKey);
        Assert.Null(new PluginConfiguration().KostvListenBrainzToken);
    }

    // ---------------------------------------------------------------- the library, on every server version

    [Fact]
    public void TheLibraryFindsAnArtistsSongsAsWrittenOtherwiseAndTheirRecording()
    {
        var artist = new MusicArtist { Id = Guid.NewGuid(), Name = "ROSALÍA" };
        var song = new Audio { Id = Guid.NewGuid(), Name = "DESPECHÁ", Artists = ["ROSALÍA"], ProviderIds = new Dictionary<string, string> { ["MusicBrainzTrack"] = "6B0E5B9E-0000-4000-8000-000000000001" } };
        var other = new Audio { Id = Guid.NewGuid(), Name = "Virtual", Artists = ["ROSALÍA"], IsVirtualItem = true };
        var asked = new List<InternalItemsQuery>();
        var fails = false;
        var library = RecordingHostProxy.Create<ILibraryManager>((method, args) =>
        {
            if (method.Name != "GetItemsResult")
            {
                throw new NotSupportedException(method.Name);
            }

            if (fails)
            {
                throw new MissingMethodException("an older server");
            }

            var query = (InternalItemsQuery)args![0]!;
            asked.Add(query);
            return query.IncludeItemTypes.Contains(BaseItemKind.MusicArtist)
                ? new QueryResult<BaseItem>([artist])
                : new QueryResult<BaseItem>(query.ArtistIds.Contains(artist.Id) ? [song, other] : []);
        });
        var music = new KostvMusicService(library, null!, new KostvMusicStore(_root, () => _now), NullLogger<KostvMusicService>.Instance);
        var station = new KostvStationLibrary(library, music, NullLogger.Instance);

        var songs = station.SongsBy("Rosalia");
        var found = Assert.Single(songs);
        Assert.Equal(song.Id, found.Id);
        Assert.Equal("6b0e5b9e-0000-4000-8000-000000000001", found.Mbid);
        Assert.Contains(asked, q => q.IncludeItemTypes.Contains(BaseItemKind.Audio) && q.IsVirtualItem == false);
        Assert.Equal("6b0e5b9e-0000-4000-8000-000000000001", KostvStationLibrary.MbidOf(new Audio { ProviderIds = new Dictionary<string, string> { ["MusicBrainzRecording"] = "6b0e5b9e-0000-4000-8000-000000000001" } }));
        Assert.Null(KostvStationLibrary.MbidOf(new Audio { ProviderIds = new Dictionary<string, string> { ["MusicBrainzTrack"] = "no" } }));

        // Kept a while; and a server whose library can't be read gives none, not an error.
        var count = asked.Count;
        station.SongsBy("ROSALÍA");
        Assert.Equal(count, asked.Count);
        fails = true;
        Assert.Empty(station.SongsBy("Otra"));
    }

    [Fact]
    public async Task TheRouteSaysWhatIsWrongWithTheSeedAndAnswersAsTheContract()
    {
        var rig = Make();
        var seed = rig.Library.Add("Copenhague", "Vetusta Morla", mbid: "11111111-2222-4333-8444-555555555555");
        var hidden = rig.Library.Add("Escondida", "Vetusta Morla");
        rig.Library.Hidden.Add((_ana.Id, hidden.Id));
        var users = RecordingHostProxy.Create<IUserManager>((method, args) => method.Name == "GetUserById" && args is [Guid id] && id == _ana.Id ? _ana : null);
        var controller = new KostvStationController(rig.Station, rig.Library, rig.Web, new ItemCardDtoMapper(RecordingHostProxy.Create<IUserDataManager>((_, _) => null), NullLogger<ItemCardDtoMapper>.Instance))
        {
            ControllerContext = new ControllerContext
            {
                HttpContext = new Microsoft.AspNetCore.Http.DefaultHttpContext
                {
                    User = new System.Security.Claims.ClaimsPrincipal(new System.Security.Claims.ClaimsIdentity([new System.Security.Claims.Claim("Jellyfin-UserId", _ana.Id.ToString())], "test")),
                    RequestServices = new StationServices(users)
                }
            }
        };

        Assert.IsType<BadRequestObjectResult>(await controller.Station("nada", null, null, null, null));
        // Never a 404 (the app reads it as an older plugin): one it may not see, or unknown, is empty.
        foreach (var unknown in new[] { hidden.Id.ToString(), Guid.NewGuid().ToString() })
        {
            var empty = JsonDocument.Parse(Assert.IsType<ContentResult>(await controller.Station(unknown, null, null, null, null)).Content!).RootElement;
            Assert.Equal("fallback", empty.GetProperty("Source").GetString());
            Assert.Empty(empty.GetProperty("Items").EnumerateArray());
            Assert.Equal(JsonValueKind.Null, empty.GetProperty("Seed").GetProperty("Title").ValueKind);
        }

        // ... and by what the app says of it, a station of its title and artist, without itself.
        var byName = JsonDocument.Parse(Assert.IsType<ContentResult>(await controller.Station(hidden.Id.ToString(), "Copenhague", "Vetusta Morla", 3, true)).Content!).RootElement;
        Assert.Equal(3, byName.GetProperty("Items").GetArrayLength());

        var json = JsonDocument.Parse(Assert.IsType<ContentResult>(await controller.Station(seed.Id.ToString("N"), null, null, 5, true)).Content!).RootElement;
        Assert.Equal("Copenhague", json.GetProperty("Seed").GetProperty("Title").GetString());
        Assert.Equal("Vetusta Morla", json.GetProperty("Seed").GetProperty("Artist").GetString());
        Assert.Equal("11111111-2222-4333-8444-555555555555", json.GetProperty("Seed").GetProperty("Mbid").GetString());
        Assert.Equal(KostvStationSource.ListenBrainz, json.GetProperty("Source").GetString());
        var items = json.GetProperty("Items").EnumerateArray().ToList();
        Assert.Equal(5, items.Count);
        Assert.All(items, i =>
        {
            Assert.Equal(JsonValueKind.Null, i.GetProperty("Card").ValueKind);
            var away = i.GetProperty("Away");
            Assert.False(string.IsNullOrEmpty(away.GetProperty("DeezerId").GetString()));
            Assert.False(string.IsNullOrEmpty(away.GetProperty("Title").GetString()));
            Assert.True(away.TryGetProperty("Explicit", out _));
            Assert.Contains(i.GetProperty("Why").GetString(), new[] { "listenbrainz", "style", "deezer", "lastfm" });
        });

        // A seed not at home, by its Deezer id with its title and artist.
        var away2 = JsonDocument.Parse(Assert.IsType<ContentResult>(await controller.Station("stremfin:3165861441", "Tití Me Preguntó", "Bad Bunny", 3, false)).Content!).RootElement;
        Assert.Equal("Bad Bunny", away2.GetProperty("Seed").GetProperty("Artist").GetString());
        Assert.Empty(away2.GetProperty("Items").EnumerateArray());
    }

    private sealed class StationServices(object users) : IServiceProvider
    {
        public object? GetService(Type serviceType) => serviceType == typeof(IUserManager) ? users : null;
    }
}
