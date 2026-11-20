using System.Text.Json;
using MediaBrowser.Controller.Entities.Audio;
using Microsoft.Extensions.Logging.Abstractions;
using Moonfin.Server.Kostv;
using Xunit;

namespace Moonfin.Server.Tests;

/// <summary>
/// kOS TV: what the server keeps of what each person listens to, and the music worked out from
/// it: daily mixes, the artists for «Descubrimiento semanal» and the mix for the time of day.
/// </summary>
public sealed class KostvMusicTests : IDisposable
{
    private readonly string _root = Path.Combine(Path.GetTempPath(), "kostv-music-" + Guid.NewGuid().ToString("N"));

    // Madrid, the home's time zone in these tests (whatever the machine's).
    private static readonly TimeZoneInfo Home = TimeZoneInfo.FindSystemTimeZoneById("Europe/Madrid");

    private DateTimeOffset _now = new(2026, 11, 20, 10, 0, 0, TimeSpan.Zero);

    public void Dispose()
    {
        if (Directory.Exists(_root))
        {
            Directory.Delete(_root, recursive: true);
        }
    }

    private KostvMusicStore NewStore() => new(_root, () => _now, Home);

    private static KostvMusicEvent Listen(Guid item, DateTimeOffset at, string outcome = KostvListenOutcome.Completed) =>
        new KostvMusicEvent { Item = item.ToString("N"), Outcome = outcome, Played = 200, Duration = 200 }.Stamp(at, Home);

    // ---------------------------------------------------------------- how a listen ended

    [Theory]
    [InlineData(200, 200, false, KostvListenOutcome.Completed)]
    [InlineData(180, 200, false, KostvListenOutcome.Completed)]
    [InlineData(179, 200, false, KostvListenOutcome.Stopped)]
    [InlineData(100, 200, false, KostvListenOutcome.Stopped)]
    [InlineData(99, 200, false, KostvListenOutcome.Skipped)]
    [InlineData(29, 40, false, KostvListenOutcome.Skipped)]
    [InlineData(10, 200, false, KostvListenOutcome.Skipped)]
    [InlineData(20, 20, false, KostvListenOutcome.Completed)]
    [InlineData(5, 200, true, KostvListenOutcome.Completed)]
    [InlineData(29, null, false, KostvListenOutcome.Skipped)]
    [InlineData(31, null, false, KostvListenOutcome.Stopped)]
    public void AListenIsCompletedSkippedOrStopped(int played, int? duration, bool reachedEnd, string outcome)
    {
        Assert.Equal(outcome, KostvListenOutcome.Classify(played, duration, reachedEnd));
    }

    [Fact]
    public void AListenIsNotedFromWhereTheSongStopped()
    {
        var store = NewStore();
        var recorder = new KostvMusicRecorder(null!, null!, null!, store, new KostvMusicContext(), NullLogger<KostvMusicRecorder>.Instance);
        var song = new Audio { Id = Guid.NewGuid(), RunTimeTicks = TimeSpan.FromSeconds(200).Ticks };
        var open = new KostvMusicRecorder.Open { UserId = Guid.NewGuid(), Item = song, StartedAt = _now, Device = KostvDeviceKind.Tv, SeenAt = _now };

        // Stopped a moment before its end: played to the end.
        var whole = recorder.ListenOf(open, 198.5, _now.AddSeconds(198), "mix:daily-1");
        Assert.Equal(KostvListenOutcome.Completed, whole.Outcome);
        Assert.Equal(200, whole.Duration);
        Assert.Equal("mix:daily-1", whole.Source);
        Assert.Equal("tv", whole.Device);
        // 10:00 UTC is 11:00 in Madrid, on a Friday.
        Assert.Equal(11, whole.Hour);
        Assert.Equal(5, whole.Weekday);
        Assert.Equal("2026-11-20", whole.Day);

        // Without a position, as long as it has been playing.
        var unsaid = recorder.ListenOf(open, null, _now.AddSeconds(12), null);
        Assert.Equal(12, unsaid.Played);
        Assert.Equal(KostvListenOutcome.Skipped, unsaid.Outcome);
        Assert.Null(unsaid.Source);
    }

    // ---------------------------------------------------------------- what kind of device

    [Theory]
    [InlineData("kOS TV para Android TV", "SHIELD Android TV", "tv")]
    [InlineData("kOS TV para Apple TV", "Apple TV", "tv")]
    [InlineData("kOS TV para la web", "kOS TV para la web", "web")]
    [InlineData("kOS TV para Android", "Pixel 9 Pro", "mobile")]
    [InlineData("kOS TV para iOS", "iPhone de Ana", "mobile")]
    [InlineData("kOS TV", "Salón TV", "tv")]
    [InlineData("kOS TV", "Escritorio", "other")]
    [InlineData("Jellyfin Web", "Chrome", "web")]
    [InlineData("Jellyfin Android", "Galaxy S7 edge", "mobile")]
    [InlineData("Android TV", "BRAVIA 4K", "tv")]
    [InlineData("Jellyfin iOS", "iPad", "mobile")]
    [InlineData("Swiftfin tvOS", "Apple TV", "tv")]
    [InlineData("Finamp", "Phone", "mobile")]
    [InlineData("Kodi", "LibreELEC", "tv")]
    [InlineData("Jellyfin Media Player", "Ordenador", "other")]
    [InlineData(null, null, "other")]
    public void TheDeviceKindComesFromTheClientAndDeviceNames(string? client, string? device, string kind)
    {
        Assert.Equal(kind, KostvDeviceKind.Of(client, device));
    }

    // ---------------------------------------------------------------- the store

    [Fact]
    public void ListensAreAppendedByMonthAndCounted()
    {
        var store = NewStore();
        var user = Guid.NewGuid();
        var song = Guid.NewGuid();
        Assert.Equal(new KostvMusicSummary(0, null), store.Summary(user));

        Assert.True(store.Append(user, Listen(song, _now.AddDays(-25))));
        Assert.True(store.Append(user, Listen(song, _now)));
        Assert.True(store.Append(user, new KostvMusicEvent { Type = KostvMusicEvent.HeartType, Item = song.ToString("N"), Favorite = true }.Stamp(_now, Home)));

        var folder = Path.Combine(_root, user.ToString("N"));
        Assert.True(File.Exists(Path.Combine(folder, "2026-10.jsonl")));
        Assert.Equal(2, File.ReadAllLines(Path.Combine(folder, "2026-11.jsonl")).Length);
        Assert.Equal(new KostvMusicSummary(2, _now.AddDays(-25)), store.Summary(user));

        // A line cut short by a crash is skipped; the rest still reads, from a new start too.
        File.AppendAllText(Path.Combine(folder, "2026-11.jsonl"), "{\"type\":\"listen\",\"it");
        var again = NewStore();
        Assert.Equal(3, again.Read(user).Count);
        Assert.Equal(2, again.Summary(user).Listens);
        Assert.Single(again.Read(user, _now.AddDays(-1)), e => e.IsListen);
    }

    [Fact]
    public void WithLearnOffNothingIsNotedAndTheChoiceStays()
    {
        var store = NewStore();
        var user = Guid.NewGuid();
        Assert.True(store.Learns(user));

        store.SetLearn(user, false);
        Assert.False(store.Append(user, Listen(Guid.NewGuid(), _now)));
        Assert.Empty(store.Read(user));
        Assert.False(NewStore().Learns(user));

        store.SetLearn(user, true);
        Assert.True(store.Append(user, Listen(Guid.NewGuid(), _now)));
        Assert.Single(store.Read(user));
    }

    [Fact]
    public void DeletingListensKeepsLearnAndDeletingTheUserKeepsNothing()
    {
        var store = NewStore();
        var user = Guid.NewGuid();
        store.SetLearn(user, false);
        store.SetLearn(user, true);
        store.Append(user, Listen(Guid.NewGuid(), _now));
        store.SetLearn(user, false);

        store.DeleteListens(user);
        Assert.Empty(store.Read(user));
        Assert.Equal(0, store.Summary(user).Listens);
        Assert.False(NewStore().Learns(user));

        store.DeleteUser(user);
        Assert.False(Directory.Exists(Path.Combine(_root, user.ToString("N"))));
        Assert.True(store.Learns(user));
    }

    [Fact]
    public void MonthsPastAYearAreDropped()
    {
        var user = Guid.NewGuid();
        var folder = Path.Combine(_root, user.ToString("N"));
        Directory.CreateDirectory(folder);
        foreach (var month in new[] { "2025-09", "2025-10", "2025-11", "2025-12", "2026-11" })
        {
            File.WriteAllText(Path.Combine(folder, month + ".jsonl"), string.Empty);
        }

        File.WriteAllText(Path.Combine(folder, "notes.txt"), string.Empty);

        // November 2026: twelve months back is November 2025, which stays.
        Assert.Equal(2, NewStore().TrimAll());
        Assert.Equal(
            ["2025-11.jsonl", "2025-12.jsonl", "2026-11.jsonl", "notes.txt"],
            Directory.GetFiles(folder).Select(p => Path.GetFileName(p)!).Order(StringComparer.Ordinal).ToArray());

        // Writing trims too, once a day.
        _now = new DateTimeOffset(2026, 12, 2, 10, 0, 0, TimeSpan.Zero);
        NewStore().Append(user, Listen(Guid.NewGuid(), _now));
        Assert.False(File.Exists(Path.Combine(folder, "2025-11.jsonl")));
        Assert.True(File.Exists(Path.Combine(folder, "2025-12.jsonl")));
    }

    // ---------------------------------------------------------------- where it came from

    [Theory]
    [InlineData("mix:daily-2", "mix:daily-2")]
    [InlineData("MIX:Daily-2", "mix:daily-2")]
    [InlineData("discovery", "discovery")]
    [InlineData("moment:tarde", "moment:tarde")]
    [InlineData("moment:siesta", "other")]
    [InlineData("search", "search")]
    [InlineData("whatever", "other")]
    [InlineData("mix:", "other")]
    [InlineData("  ", null)]
    [InlineData(null, null)]
    public void SourcesAreTheKnownOnes(string? source, string? noted)
    {
        Assert.Equal(noted, KostvMusicContext.Normalize(source));
    }

    [Fact]
    public void WhereASongCameFromIsKeptSixHoursPerPerson()
    {
        var context = new KostvMusicContext();
        var ana = Guid.NewGuid();
        var luis = Guid.NewGuid();
        var song = Guid.NewGuid();
        context.Remember(ana, "mix:daily-1", [song], _now);

        Assert.Equal("mix:daily-1", context.SourceOf(ana, song, _now.AddHours(5.9)));
        Assert.Null(context.SourceOf(luis, song, _now));
        Assert.Null(context.SourceOf(ana, song, _now.AddHours(6.1)));

        // Said again: from then.
        context.Remember(ana, "album", [song], _now.AddHours(5));
        Assert.Equal("album", context.SourceOf(ana, song, _now.AddHours(10)));

        context.Forget(ana);
        Assert.Null(context.SourceOf(ana, song, _now.AddHours(5)));
    }

    // ---------------------------------------------------------------- daily mixes

    /// <summary>A made-up library: per genre, artists with songs played and unplayed.</summary>
    private static List<KostvMusicTrack> Library(int genres = 5, int artists = 6, int played = 6, int unplayed = 6, DateTime? lastPlayed = null)
    {
        var tracks = new List<KostvMusicTrack>();
        for (var g = 0; g < genres; g++)
        {
            for (var a = 0; a < artists; a++)
            {
                var artist = $"Artista {g}-{a}";
                for (var s = 0; s < played + unplayed; s++)
                {
                    var plays = s < played ? (genres - g) * 3 : 0;
                    tracks.Add(new KostvMusicTrack(Guid.NewGuid(), [artist], [$"Género {g}"], plays, plays > 0 ? lastPlayed ?? new DateTime(2026, 11, 10, 0, 0, 0, DateTimeKind.Utc) : null));
                }
            }
        }

        return tracks;
    }

    [Fact]
    public void MixesAreOneGenreEachWithoutRepeatsAndHalfNew()
    {
        var user = Guid.NewGuid();
        var tracks = Library();
        var profile = KostvMusicEngine.Profile(tracks, new Dictionary<Guid, KostvTrackListens>(), _now);
        var mixes = KostvMusicEngine.Mixes(user, "2026-11-20", tracks, profile);

        Assert.Equal(4, mixes.Count);
        Assert.Equal(["daily-1", "daily-2", "daily-3", "daily-4"], mixes.Select(m => m.Id));
        // The genres played most first.
        Assert.Equal(["Género 0", "Género 1", "Género 2", "Género 3"], mixes.Select(m => m.Genre));
        var byId = tracks.ToDictionary(t => t.Id);
        foreach (var mix in mixes)
        {
            Assert.Equal(KostvMusicEngine.MixSize, mix.Items.Count);
            Assert.All(mix.Items, id => Assert.Equal(mix.Genre, byId[id].Genres[0]));
            Assert.Equal(25, mix.Items.Count(id => byId[id].PlayCount > 0));
            Assert.Equal(3, mix.Artists.Count);
            // Never the same artist twice in a row.
            Assert.All(mix.Items.Zip(mix.Items.Skip(1)), pair => Assert.NotEqual(byId[pair.First].PrimaryArtist, byId[pair.Second].PrimaryArtist));
        }

        var all = mixes.SelectMany(m => m.Items).ToList();
        Assert.Equal(all.Count, all.Distinct().Count());
    }

    [Fact]
    public void MixesAreTheSameAllDayAndChangeTheNext()
    {
        var user = Guid.NewGuid();
        var tracks = Library();
        var profile = KostvMusicEngine.Profile(tracks, new Dictionary<Guid, KostvTrackListens>(), _now);
        var first = KostvMusicEngine.Mixes(user, "2026-11-20", tracks, profile);

        // The library read in another order makes the same.
        var shuffled = tracks.OrderBy(t => t.Id.ToString("N")[5]).Reverse().ToList();
        var again = KostvMusicEngine.Mixes(user, "2026-11-20", shuffled, KostvMusicEngine.Profile(shuffled, new Dictionary<Guid, KostvTrackListens>(), _now));
        Assert.Equal(first.Select(m => m.Items), again.Select(m => m.Items));

        var tomorrow = KostvMusicEngine.Mixes(user, "2026-11-21", tracks, profile);
        Assert.NotEqual(first[0].Items, tomorrow[0].Items);
        var someoneElse = KostvMusicEngine.Mixes(Guid.NewGuid(), "2026-11-20", tracks, profile);
        Assert.NotEqual(first[0].Items, someoneElse[0].Items);
    }

    [Fact]
    public void SongsMostlySkippedAreLeftOutButOneSkipIsNot()
    {
        var tracks = Library(genres: 1, artists: 4, played: 4, unplayed: 4);
        var skipped = tracks.First(t => t.PlayCount > 0);
        var once = tracks.Where(t => t.PlayCount > 0).Skip(1).First();
        var events = new List<KostvMusicEvent>
        {
            Listen(skipped.Id, _now.AddDays(-2), KostvListenOutcome.Skipped),
            Listen(skipped.Id, _now.AddDays(-1), KostvListenOutcome.Skipped),
            Listen(skipped.Id, _now.AddDays(-3)),
            Listen(once.Id, _now.AddDays(-1), KostvListenOutcome.Skipped),
            Listen(once.Id, _now.AddDays(-4))
        };
        var profile = KostvMusicEngine.Profile(tracks, KostvMusicEngine.Listens(events, _now), _now);

        Assert.Contains(skipped.Id, profile.Dropped);
        Assert.DoesNotContain(once.Id, profile.Dropped);
        var mix = Assert.Single(KostvMusicEngine.Mixes(Guid.NewGuid(), "2026-11-20", tracks, profile));
        Assert.DoesNotContain(skipped.Id, mix.Items);
        Assert.Contains(once.Id, mix.Items);
    }

    [Fact]
    public void WithLittleMusicThereAreFewerMixesOrNone()
    {
        var none = KostvMusicEngine.Mixes(Guid.NewGuid(), "2026-11-20", [], KostvMusicEngine.Profile([], new Dictionary<Guid, KostvTrackListens>(), _now));
        Assert.Empty(none);

        // Two genres with enough, one with too few songs liked.
        var tracks = Library(genres: 2, artists: 4, played: 4, unplayed: 2);
        tracks.AddRange(Enumerable.Range(0, 3).Select(_ => new KostvMusicTrack(Guid.NewGuid(), ["Solista"], ["Jazz"], 50, new DateTime(2026, 11, 19, 0, 0, 0, DateTimeKind.Utc))));
        var profile = KostvMusicEngine.Profile(tracks, new Dictionary<Guid, KostvTrackListens>(), _now);
        Assert.Contains(profile.Genres, g => g.Name == "Jazz");
        var mixes = KostvMusicEngine.Mixes(Guid.NewGuid(), "2026-11-20", tracks, profile);
        Assert.Equal(["Género 0", "Género 1"], mixes.Select(m => m.Genre));
        Assert.All(mixes, m => Assert.Equal(24, m.Items.Count));
    }

    [Fact]
    public void NewSongsComeFromSimilarArtistsWhenTheirOwnRunOut()
    {
        var mine = Enumerable.Range(0, 25).Select(i => new KostvMusicTrack(Guid.NewGuid(), [i % 2 == 0 ? "Bad Bunny" : "Karol G"], ["Reguetón"], 5, new DateTime(2026, 11, 19, 0, 0, 0, DateTimeKind.Utc))).ToList();
        var alike = Enumerable.Range(0, 10).Select(_ => new KostvMusicTrack(Guid.NewGuid(), ["Feid"], ["Reguetón"])).ToList();
        var others = Enumerable.Range(0, 10).Select(_ => new KostvMusicTrack(Guid.NewGuid(), ["Otro"], ["reguetón"])).ToList();
        var outside = Enumerable.Range(0, 10).Select(_ => new KostvMusicTrack(Guid.NewGuid(), ["Feid"], ["Pop"])).ToList();
        var tracks = mine.Concat(alike).Concat(others).Concat(outside).ToList();
        var profile = KostvMusicEngine.Profile(tracks, new Dictionary<Guid, KostvTrackListens>(), _now);
        var similar = new Dictionary<string, IReadOnlyList<string>> { ["bad bunny"] = ["Feid"] };

        var mix = Assert.Single(KostvMusicEngine.Mixes(Guid.NewGuid(), "2026-11-20", tracks, profile, similar));
        // 25 of theirs and the 20 new ones there are of the genre.
        Assert.Equal(45, mix.Items.Count);
        Assert.All(alike, t => Assert.Contains(t.Id, mix.Items));
        // Genres match without minding case; songs of other genres stay out.
        Assert.All(others, t => Assert.Contains(t.Id, mix.Items));
        Assert.All(outside, t => Assert.DoesNotContain(t.Id, mix.Items));
    }

    // ---------------------------------------------------------------- seeds

    [Fact]
    public void SeedsAreTheArtistsLikedMostAndListensCount()
    {
        var day = new DateTime(2026, 11, 19, 0, 0, 0, DateTimeKind.Utc);
        var tracks = Enumerable.Range(0, 12)
            .Select(i => new KostvMusicTrack(Guid.NewGuid(), [$"Artista {i:00}", "Invitado"], ["Pop"], 12 - i, day))
            .ToList();
        var profile = KostvMusicEngine.Profile(tracks, new Dictionary<Guid, KostvTrackListens>(), _now);
        var seeds = KostvMusicEngine.Seeds(profile);
        Assert.Equal(KostvMusicEngine.MaxSeeds, seeds.Count);
        // The guest on every song adds up past all of them.
        Assert.Equal("Invitado", seeds[0]);
        Assert.Equal("Artista 00", seeds[1]);

        // Listened to lately, whole: up it goes; skipped often: out.
        var events = Enumerable.Range(0, 6).Select(i => Listen(tracks[11].Id, _now.AddDays(-i))).ToList();
        events.AddRange(Enumerable.Range(0, 3).Select(i => Listen(tracks[0].Id, _now.AddDays(-i), KostvListenOutcome.Skipped)));
        seeds = KostvMusicEngine.Seeds(KostvMusicEngine.Profile(tracks, KostvMusicEngine.Listens(events, _now), _now));
        Assert.Equal("Artista 11", seeds[1]);
        Assert.DoesNotContain("Artista 00", seeds);
    }

    // ---------------------------------------------------------------- the week's list

    [Fact]
    public void TheWeeksListIsOnlyForThisWeekAndWithinItsLimits()
    {
        var store = NewStore();
        var user = Guid.NewGuid();
        var week = KostvMusicEngine.WeekOf(_now, Home);
        Assert.Equal("2026-W47", week);
        Assert.Null(store.DiscoveryOf(user, week));

        JsonElement Songs(int count, int size = 10) => JsonSerializer.SerializeToElement(
            Enumerable.Range(0, count).Select(i => new { title = $"Canción {i}", artist = new string('a', size) }).ToList());

        Assert.Equal(KostvMusicStore.DiscoveryRefusal.NotThisWeek, store.SetDiscovery(user, "2026-W46", Songs(20), week));
        Assert.Equal(KostvMusicStore.DiscoveryRefusal.TooMany, store.SetDiscovery(user, week, Songs(31), week));
        Assert.Equal(KostvMusicStore.DiscoveryRefusal.TooLarge, store.SetDiscovery(user, week, Songs(30, 2500), week));
        Assert.Equal(KostvMusicStore.DiscoveryRefusal.NotAList, store.SetDiscovery(user, week, JsonSerializer.SerializeToElement(new { a = 1 }), week));
        Assert.Null(store.DiscoveryOf(user, week));

        Assert.Equal(KostvMusicStore.DiscoveryRefusal.None, store.SetDiscovery(user, week, Songs(30), week));
        var stored = store.DiscoveryOf(user, week);
        Assert.NotNull(stored);
        Assert.Equal(30, stored.Value.GetArrayLength());
        Assert.Equal("Canción 0", stored.Value[0].GetProperty("title").GetString());

        // Next week: the old list is gone.
        Assert.Null(store.DiscoveryOf(user, "2026-W48"));
        Assert.Null(store.DiscoveryOf(user, week));
    }

    // ---------------------------------------------------------------- time

    [Theory]
    [InlineData(5, "noche")]
    [InlineData(6, "manana")]
    [InlineData(11, "manana")]
    [InlineData(12, "tarde")]
    [InlineData(19, "tarde")]
    [InlineData(20, "noche")]
    [InlineData(23, "noche")]
    [InlineData(0, "noche")]
    public void TheTimesOfDayAreMorningAfternoonAndNight(int hour, string slot)
    {
        Assert.Equal(slot, KostvMusicEngine.SlotOf(hour));
    }

    [Fact]
    public void TheMusicDayStartsAtFiveAtHome()
    {
        // 03:59 UTC is 04:59 in Madrid: still the day before.
        Assert.Equal("2026-11-19", KostvMusicEngine.DayKey(KostvMusicEngine.MusicDay(new DateTimeOffset(2026, 11, 20, 3, 59, 0, TimeSpan.Zero), Home)));
        Assert.Equal("2026-11-20", KostvMusicEngine.DayKey(KostvMusicEngine.MusicDay(new DateTimeOffset(2026, 11, 20, 4, 0, 0, TimeSpan.Zero), Home)));
        // The week by the home's clock: Sunday 23:30 UTC is already Monday in Madrid.
        Assert.Equal("2026-W47", KostvMusicEngine.WeekOf(new DateTimeOffset(2026, 11, 22, 22, 59, 0, TimeSpan.Zero), Home));
        Assert.Equal("2026-W48", KostvMusicEngine.WeekOf(new DateTimeOffset(2026, 11, 22, 23, 30, 0, TimeSpan.Zero), Home));
        Assert.Equal("2026-W53", KostvMusicEngine.WeekOf(new DateTimeOffset(2026, 12, 31, 12, 0, 0, TimeSpan.Zero), Home));
        Assert.Equal("2027-W01", KostvMusicEngine.WeekOf(new DateTimeOffset(2027, 1, 4, 12, 0, 0, TimeSpan.Zero), Home));
    }

    // ---------------------------------------------------------------- the time of day

    /// <summary>Listens at <paramref name="hourUtc"/> (an hour less than at home in winter), <paramref name="perDay"/> a day.</summary>
    private List<KostvMusicEvent> SlotListens(IReadOnlyList<KostvMusicTrack> songs, int days, int perDay, int hourUtc, int daysBack = 1)
    {
        var events = new List<KostvMusicEvent>();
        for (var d = 0; d < days; d++)
        {
            var day = new DateTimeOffset(_now.Year, _now.Month, _now.Day, hourUtc, 0, 0, TimeSpan.Zero).AddDays(-(d + daysBack));
            for (var i = 0; i < perDay; i++)
            {
                events.Add(Listen(songs[(d * perDay + i) % songs.Count].Id, day.AddMinutes(i * 4)));
            }
        }

        return events;
    }

    [Fact]
    public void AMixOfTheMomentNeedsTwentyFiveListensOnFiveDays()
    {
        var songs = Library(genres: 1, artists: 3, played: 10, unplayed: 0).Take(10).ToList();
        // 15:00 at home: afternoon.
        Assert.True(KostvMusicEngine.MomentReady(SlotListens(songs, days: 5, perDay: 5, hourUtc: 14), "tarde", _now));
        Assert.False(KostvMusicEngine.MomentReady(SlotListens(songs, days: 5, perDay: 5, hourUtc: 14), "manana", _now));
        Assert.False(KostvMusicEngine.MomentReady(SlotListens(songs, days: 4, perDay: 7, hourUtc: 14), "tarde", _now));
        Assert.False(KostvMusicEngine.MomentReady(SlotListens(songs, days: 6, perDay: 4, hourUtc: 14), "tarde", _now));
        // Older than 60 days doesn't count.
        Assert.False(KostvMusicEngine.MomentReady(SlotListens(songs, days: 5, perDay: 5, hourUtc: 14, daysBack: 57), "tarde", _now));
        // 18:xx UTC is 19:xx at home, still afternoon; 19:xx UTC is 20:xx, night; 05:xx UTC
        // is 06:xx, morning; 04:xx UTC is 05:xx, still night.
        Assert.True(KostvMusicEngine.MomentReady(SlotListens(songs, days: 5, perDay: 5, hourUtc: 18), "tarde", _now));
        var night = SlotListens(songs, days: 5, perDay: 5, hourUtc: 19);
        Assert.True(KostvMusicEngine.MomentReady(night, "noche", _now));
        Assert.False(KostvMusicEngine.MomentReady(night, "tarde", _now));
        Assert.True(KostvMusicEngine.MomentReady(SlotListens(songs, days: 5, perDay: 5, hourUtc: 5), "manana", _now));
        Assert.True(KostvMusicEngine.MomentReady(SlotListens(songs, days: 5, perDay: 5, hourUtc: 4), "noche", _now));
    }

    [Fact]
    public void AMixOfTheMomentIsPartWhatIsPlayedThenAndTheRestAlike()
    {
        var tracks = Library(genres: 2, artists: 5, played: 6, unplayed: 6);
        var profile = KostvMusicEngine.Profile(tracks, new Dictionary<Guid, KostvTrackListens>(), _now);
        var mornings = tracks.Where(t => t.Genres[0] == "Género 1" && t.PlayCount > 0).Take(20).ToList();
        var events = SlotListens(mornings, days: 6, perDay: 5, hourUtc: 8);
        var user = Guid.NewGuid();

        var items = KostvMusicEngine.Moment(user, "2026-11-20", "manana", events, tracks, profile, _now);
        Assert.Equal(KostvMusicEngine.MomentSize, items.Count);
        Assert.Equal(items.Count, items.Distinct().Count());
        Assert.Equal(16, items.Count(id => mornings.Any(t => t.Id == id)));
        var byId = tracks.ToDictionary(t => t.Id);
        // The rest are like them: their artists, then their genre.
        Assert.All(items, id => Assert.Equal("Género 1", byId[id].Genres[0]));
        Assert.Equal(items, KostvMusicEngine.Moment(user, "2026-11-20", "manana", events, tracks.AsEnumerable().Reverse(), profile, _now));
        Assert.NotEqual(items, KostvMusicEngine.Moment(user, "2026-11-21", "manana", events, tracks, profile, _now));
    }
}
