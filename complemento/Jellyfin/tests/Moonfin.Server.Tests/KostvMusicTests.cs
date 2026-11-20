using System.Text.Json;
using Jellyfin.Data.Entities;
using Jellyfin.Data.Enums;
using Jellyfin.Data.Events.Users;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Entities.Audio;
using MediaBrowser.Controller.Library;
using MediaBrowser.Controller.Session;
using MediaBrowser.Model.Dto;
using MediaBrowser.Model.Entities;
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
        Assert.True(KostvMusicEngine.MomentReady(SlotListens(songs, days: 5, perDay: 5, hourUtc: 14), "tarde", _now, Home));
        Assert.False(KostvMusicEngine.MomentReady(SlotListens(songs, days: 5, perDay: 5, hourUtc: 14), "manana", _now, Home));
        Assert.False(KostvMusicEngine.MomentReady(SlotListens(songs, days: 4, perDay: 7, hourUtc: 14), "tarde", _now, Home));
        Assert.False(KostvMusicEngine.MomentReady(SlotListens(songs, days: 6, perDay: 4, hourUtc: 14), "tarde", _now, Home));
        // Older than 60 days doesn't count.
        Assert.False(KostvMusicEngine.MomentReady(SlotListens(songs, days: 5, perDay: 5, hourUtc: 14, daysBack: 57), "tarde", _now, Home));
        // 18:xx UTC is 19:xx at home, still afternoon; 19:xx UTC is 20:xx, night; 05:xx UTC
        // is 06:xx, morning; 04:xx UTC is 05:xx, still night.
        Assert.True(KostvMusicEngine.MomentReady(SlotListens(songs, days: 5, perDay: 5, hourUtc: 18), "tarde", _now, Home));
        var night = SlotListens(songs, days: 5, perDay: 5, hourUtc: 19);
        Assert.True(KostvMusicEngine.MomentReady(night, "noche", _now, Home));
        Assert.False(KostvMusicEngine.MomentReady(night, "tarde", _now, Home));
        Assert.True(KostvMusicEngine.MomentReady(SlotListens(songs, days: 5, perDay: 5, hourUtc: 5), "manana", _now, Home));
        Assert.True(KostvMusicEngine.MomentReady(SlotListens(songs, days: 5, perDay: 5, hourUtc: 4), "noche", _now, Home));
    }

    [Fact]
    public void AMixOfTheMomentIsPartWhatIsPlayedThenAndTheRestAlike()
    {
        var tracks = Library(genres: 2, artists: 5, played: 6, unplayed: 6);
        var profile = KostvMusicEngine.Profile(tracks, new Dictionary<Guid, KostvTrackListens>(), _now);
        var mornings = tracks.Where(t => t.Genres[0] == "Género 1" && t.PlayCount > 0).Take(20).ToList();
        var events = SlotListens(mornings, days: 6, perDay: 5, hourUtc: 8);
        var user = Guid.NewGuid();

        var items = KostvMusicEngine.Moment(user, "2026-11-20", "manana", events, tracks, profile, _now, Home);
        Assert.Equal(KostvMusicEngine.MomentSize, items.Count);
        Assert.Equal(items.Count, items.Distinct().Count());
        Assert.Equal(16, items.Count(id => mornings.Any(t => t.Id == id)));
        var byId = tracks.ToDictionary(t => t.Id);
        // The rest are like them: their artists, then their genre.
        Assert.All(items, id => Assert.Equal("Género 1", byId[id].Genres[0]));
        Assert.Equal(items, KostvMusicEngine.Moment(user, "2026-11-20", "manana", events, tracks.AsEnumerable().Reverse(), profile, _now, Home));
        Assert.NotEqual(items, KostvMusicEngine.Moment(user, "2026-11-21", "manana", events, tracks, profile, _now, Home));
    }

    // ---------------------------------------------------------------- the server's events, in any order

    private KostvMusicRecorder NewRecorder(KostvMusicStore store, KostvMusicContext? context = null, ILibraryManager? library = null) =>
        new(null!, null!, library!, store, context ?? new KostvMusicContext(), NullLogger<KostvMusicRecorder>.Instance);

    private static Audio Song(int seconds = 200) => new() { Id = Guid.NewGuid(), Name = "Canción", RunTimeTicks = TimeSpan.FromSeconds(seconds).Ticks };

    private static SessionInfo Session(Guid user, BaseItem? playing = null) => new(null!, NullLogger.Instance)
    {
        Id = "sesion-" + Guid.NewGuid().ToString("N"),
        UserId = user,
        Client = "kOS TV para Android TV",
        DeviceName = "Salón",
        NowPlayingItem = playing == null ? null : new BaseItemDto { Id = playing.Id }
    };

    private static long? Ticks(double? seconds) => seconds.HasValue ? TimeSpan.FromSeconds(seconds.Value).Ticks : null;

    private static PlaybackProgressEventArgs Report(SessionInfo session, Audio song, double? at, bool paused = false) =>
        new() { Item = song, Session = session, PlaybackPositionTicks = Ticks(at), IsPaused = paused };

    private static PlaybackStopEventArgs Stop(SessionInfo session, Audio song, double? at, bool toTheEnd = false) =>
        new() { Item = song, Session = session, PlaybackPositionTicks = Ticks(at), PlayedToCompletion = toTheEnd };

    private void Play(KostvMusicRecorder recorder, SessionInfo session, Audio song)
    {
        session.NowPlayingItem = new BaseItemDto { Id = song.Id };
        recorder.OnStart(null, Report(session, song, 0));
    }

    private static List<KostvMusicEvent> ListensOf(KostvMusicStore store, Guid user) => store.Read(user).Where(e => e.IsListen).ToList();

    [Fact]
    public async Task AReportOfProgressAfterTheStopDoesntNoteTheSongTwice()
    {
        var store = NewStore();
        var recorder = NewRecorder(store);
        var user = Guid.NewGuid();
        var song = Song();
        var next = Song();
        var session = Session(user);
        var start = _now;

        Play(recorder, session, song);
        _now = start.AddSeconds(100);
        recorder.OnProgress(null, Report(session, song, 100));
        _now = start.AddSeconds(150);
        recorder.OnStopped(null, Stop(session, song, 150));
        // A report sent before the stop, handled after it (the session still says it plays).
        _now = start.AddSeconds(151);
        recorder.OnProgress(null, Report(session, song, 148));
        _now = start.AddSeconds(152);
        Play(recorder, session, next);
        await recorder.Settled();

        var listen = Assert.Single(ListensOf(store, user));
        Assert.Equal(song.Id.ToString("N"), listen.Item);
        Assert.Equal(150, listen.Played);
        Assert.Equal(KostvListenOutcome.Stopped, listen.Outcome);
    }

    [Fact]
    public async Task AReportOfProgressBeforeTheStartIsTheSameListen()
    {
        var store = NewStore();
        var recorder = NewRecorder(store);
        var user = Guid.NewGuid();
        var song = Song();
        var session = Session(user, song);
        var start = _now;

        // Its start is still on its way when the first report arrives.
        recorder.OnProgress(null, Report(session, song, 1));
        _now = start.AddSeconds(0.5);
        recorder.OnStart(null, Report(session, song, 0));
        _now = start.AddSeconds(100);
        recorder.OnProgress(null, Report(session, song, 100));
        _now = start.AddSeconds(199);
        recorder.OnStopped(null, Stop(session, song, 199));
        await recorder.Settled();

        var listen = Assert.Single(ListensOf(store, user));
        Assert.Equal(KostvListenOutcome.Completed, listen.Outcome);
    }

    [Fact]
    public async Task ASongIsNotTakenUpByAReportWhenTheSessionIsntPlayingIt()
    {
        var store = NewStore();
        var recorder = NewRecorder(store);
        var user = Guid.NewGuid();
        var song = Song();
        var other = Song();
        var session = Session(user, other);

        recorder.OnProgress(null, Report(session, song, 40));
        recorder.OnProgress(null, Report(Session(user, song), song, 40, paused: true));
        Play(recorder, session, other);
        Play(recorder, session, Song());
        await recorder.Settled();

        Assert.DoesNotContain(ListensOf(store, user), e => e.Item == song.Id.ToString("N"));
        Assert.Single(ListensOf(store, user));
    }

    [Fact]
    public async Task WhenTheNextSongStartsBeforeTheLastStopsItIsNotedFromWhereItGot()
    {
        var store = NewStore();
        var recorder = NewRecorder(store);
        var user = Guid.NewGuid();
        var song = Song(60);
        var next = Song();
        var session = Session(user);
        var start = _now;

        Play(recorder, session, song);
        _now = start.AddSeconds(52);
        recorder.OnProgress(null, Report(session, song, 52));
        // The next one's start comes first; the last report was 8 seconds behind.
        _now = start.AddSeconds(60);
        Play(recorder, session, next);
        _now = start.AddSeconds(60.2);
        recorder.OnStopped(null, Stop(session, song, 60));
        recorder.OnProgress(null, Report(session, song, 60));
        await recorder.Settled();

        var listen = Assert.Single(ListensOf(store, user));
        Assert.Equal(60, listen.Played);
        Assert.Equal(KostvListenOutcome.Completed, listen.Outcome);
    }

    [Fact]
    public async Task AStopWithoutPositionIsNotedFromHowLongItPlayed()
    {
        var store = NewStore();
        var recorder = NewRecorder(store);
        var user = Guid.NewGuid();
        var session = Session(user);
        var start = _now;

        // An app that sends no progress and stops without saying where (the server then says
        // it played to the end): about the whole song played.
        var whole = Song(180);
        Play(recorder, session, whole);
        _now = start.AddSeconds(170);
        recorder.OnStopped(null, Stop(session, whole, null, toTheEnd: true));

        // Two minutes of three: stopped, not «skipped, 0 s».
        var part = Song(180);
        Play(recorder, session, part);
        _now = start.AddSeconds(290);
        recorder.OnStopped(null, Stop(session, part, null, toTheEnd: true));

        // Paused at 1:40 and stopped five minutes later: 1:40, not the time it was paused.
        var paused = Song(180);
        Play(recorder, session, paused);
        _now = start.AddSeconds(390);
        recorder.OnProgress(null, Report(session, paused, 100, paused: true));
        _now = start.AddSeconds(690);
        recorder.OnStopped(null, Stop(session, paused, null, toTheEnd: true));
        await recorder.Settled();

        var listens = ListensOf(store, user).ToDictionary(e => e.Item);
        Assert.Equal(KostvListenOutcome.Completed, listens[whole.Id.ToString("N")].Outcome);
        Assert.Equal(120, listens[part.Id.ToString("N")].Played);
        Assert.Equal(KostvListenOutcome.Stopped, listens[part.Id.ToString("N")].Outcome);
        Assert.Equal(100, listens[paused.Id.ToString("N")].Played);
        Assert.Equal(KostvListenOutcome.Stopped, listens[paused.Id.ToString("N")].Outcome);
    }

    [Fact]
    public async Task AListenOnItsWayIsntWrittenAfterTheListensOrTheUserAreDeleted()
    {
        var store = NewStore();
        var recorder = NewRecorder(store);
        var user = Guid.NewGuid();
        var session = Session(user);
        var song = Song();
        var start = _now;

        Play(recorder, session, song);
        _now = start.AddSeconds(50);
        store.DeleteListens(user);
        _now = start.AddSeconds(100);
        recorder.OnStopped(null, Stop(session, song, 100));
        await recorder.Settled();
        Assert.Empty(ListensOf(store, user));

        // One that starts after is kept.
        var after = Song();
        Play(recorder, session, after);
        _now = start.AddSeconds(300);
        recorder.OnStopped(null, Stop(session, after, 199));
        await recorder.Settled();
        Assert.Single(ListensOf(store, user));

        // The user deleted while a song plays: its stop doesn't make their folder again.
        var last = Song();
        Play(recorder, session, last);
        store.DeleteUser(user);
        recorder.OnStopped(null, Stop(session, last, 150));
        await recorder.Settled();
        Assert.False(Directory.Exists(Path.Combine(_root, user.ToString("N"))));
    }

    [Fact]
    public async Task AListenFromADailyMixNotesTheMixGenre()
    {
        var store = NewStore();
        var context = new KostvMusicContext();
        var recorder = NewRecorder(store, context);
        var user = Guid.NewGuid();
        var session = Session(user);
        var song = Song();
        context.Remember(user, "mix:daily-2", [song.Id], _now, "Rock");

        Play(recorder, session, song);
        recorder.OnStopped(null, Stop(session, song, 199));
        await recorder.Settled();

        var listen = Assert.Single(ListensOf(store, user));
        Assert.Equal("mix:daily-2", listen.Source);
        Assert.Equal("Rock", listen.MixGenre);
    }

    // ---------------------------------------------------------------- hearts

    private static UserDataSaveEventArgs Heart(Guid user, Audio song, bool favorite, UserDataSaveReason reason) =>
        new() { UserId = user, Item = song, UserData = new UserItemData { Key = song.Id.ToString("N"), IsFavorite = favorite }, SaveReason = reason };

    [Fact]
    public async Task HeartsAreNotNotedWrongOrTwiceAfterARestart()
    {
        var user = Guid.NewGuid();
        var song = Song();
        var never = Song();
        var store = NewStore();
        var recorder = NewRecorder(store);
        recorder.OnUserDataSaved(null, Heart(user, song, true, UserDataSaveReason.UpdateUserRating));
        await recorder.Settled();

        // Restarted: what was noted is read back from the person's file.
        var again = NewStore();
        var restarted = NewRecorder(again);
        restarted.OnUserDataSaved(null, Heart(user, song, true, UserDataSaveReason.UpdateUserData));
        restarted.OnUserDataSaved(null, Heart(user, song, true, UserDataSaveReason.UpdateUserRating));
        // A rating of a song without a heart, never noted: not a heart taken off.
        restarted.OnUserDataSaved(null, Heart(user, never, false, UserDataSaveReason.UpdateUserRating));
        await restarted.Settled();
        Assert.Single(again.Read(user), e => e.Type == KostvMusicEvent.HeartType);

        restarted.OnUserDataSaved(null, Heart(user, song, false, UserDataSaveReason.UpdateUserRating));
        // Data saved with a heart that was there before anything was noted, then taken off.
        var before = Song();
        restarted.OnUserDataSaved(null, Heart(user, before, true, UserDataSaveReason.UpdateUserData));
        restarted.OnUserDataSaved(null, Heart(user, before, false, UserDataSaveReason.UpdateUserRating));
        await restarted.Settled();
        var hearts = again.Read(user).Where(e => e.Type == KostvMusicEvent.HeartType).ToList();
        // Written as they arrive, which at the same moment may be in any order.
        Assert.Equal(
            new[] { (song.Id, true), (song.Id, false), (before.Id, false) }.OrderBy(h => h.Item1).ThenBy(h => h.Item2),
            hearts.Select(e => (Guid.Parse(e.Item), e.Favorite!.Value)).OrderBy(h => h.Item1).ThenBy(h => h.Item2));
    }

    // ---------------------------------------------------------------- artists, where it came from

    [Fact]
    public void AnArtistNotFoundIsLookedForAgainAfterAnHour()
    {
        var queries = 0;
        var artist = new MusicArtist { Id = Guid.NewGuid(), Name = "Rosalía" };
        var scanned = false;
        var library = RecordingHostProxy.Create<ILibraryManager>((method, _) =>
        {
            queries++;
            return method.Name == "GetItemList" ? (scanned ? new List<BaseItem> { artist } : new List<BaseItem>()) : throw new NotSupportedException(method.Name);
        });
        var recorder = NewRecorder(NewStore(), library: library);

        Assert.Null(recorder.ArtistIdOf("Rosalía"));
        scanned = true;
        Assert.Null(recorder.ArtistIdOf("Rosalía"));
        Assert.Equal(1, queries);
        _now = _now.AddHours(1.1);
        Assert.Equal(artist.Id.ToString("N"), recorder.ArtistIdOf("Rosalía"));
        _now = _now.AddDays(3);
        Assert.Equal(artist.Id.ToString("N"), recorder.ArtistIdOf("Rosalía"));
        Assert.Equal(2, queries);
    }

    [Fact]
    public void WhereSongsCameFromIsKeptUpToALimit()
    {
        var context = new KostvMusicContext();
        var ana = Guid.NewGuid();
        var first = Enumerable.Range(0, 500).Select(_ => Guid.NewGuid()).ToList();
        context.Remember(ana, "album", first, _now);
        for (var i = 1; i <= 4; i++)
        {
            context.Remember(ana, "search", Enumerable.Range(0, 500).Select(_ => Guid.NewGuid()), _now.AddMinutes(i));
        }

        // The oldest said go first.
        Assert.Equal(KostvMusicContext.MaxPerPerson, context.Count(ana));
        Assert.All(first, id => Assert.Null(context.SourceOf(ana, id, _now.AddMinutes(5))));

        for (var person = 0; person < 10; person++)
        {
            var someone = Guid.NewGuid();
            for (var i = 0; i < 4; i++)
            {
                context.Remember(someone, "album", Enumerable.Range(0, 500).Select(_ => Guid.NewGuid()), _now.AddMinutes(10 + person));
            }
        }

        Assert.Equal(KostvMusicContext.MaxTotal, context.Count());
        Assert.Equal(0, context.Count(ana));
    }

    // ---------------------------------------------------------------- users deleted

    [Fact]
    public async Task DeletingAUserForgetsTheirMusic()
    {
        var store = NewStore();
        var service = new KostvMusicService(null!, null!, store, NullLogger<KostvMusicService>.Instance);
        var user = new User("ana", "auth", "reset");
        Assert.True(store.Append(user.Id, Listen(Guid.NewGuid(), _now)));

        await new KostvMusicOnUserDeleted(store, new KostvMusicContext(), service).OnEvent(new UserDeletedEventArgs(user));

        Assert.False(Directory.Exists(Path.Combine(_root, user.Id.ToString("N"))));
        Assert.False(store.Append(user.Id, Listen(Guid.NewGuid(), _now)));
    }

    [Fact]
    public void TheDailyRoundDropsTheFoldersOfUsersNoLongerThere()
    {
        var store = NewStore();
        var ana = Guid.NewGuid();
        var gone = Guid.NewGuid();
        store.Append(ana, Listen(Guid.NewGuid(), _now));
        store.Append(gone, Listen(Guid.NewGuid(), _now));
        Directory.CreateDirectory(Path.Combine(_root, "not-a-user"));

        // Without the server's users, nothing goes.
        Assert.Equal(0, store.RemoveMissingUsers([]));
        Assert.Equal(1, store.RemoveMissingUsers([ana]));
        Assert.True(Directory.Exists(Path.Combine(_root, ana.ToString("N"))));
        Assert.False(Directory.Exists(Path.Combine(_root, gone.ToString("N"))));
        Assert.True(Directory.Exists(Path.Combine(_root, "not-a-user")));
    }

    // ---------------------------------------------------------------- the home's time zone

    [Fact]
    public void TheHomesTimeZoneIsTheSettingAndMadridByDefault()
    {
        Assert.Equal(Home.BaseUtcOffset, KostvMusicTimeZone.Resolve(null).BaseUtcOffset);
        Assert.Equal(Home.BaseUtcOffset, KostvMusicTimeZone.Resolve("Nowhere/Nada").BaseUtcOffset);
        Assert.Null(KostvMusicTimeZone.Find("Nowhere/Nada"));
        Assert.Equal(TimeSpan.Zero, KostvMusicTimeZone.Resolve("Atlantic/Canary").GetUtcOffset(new DateTimeOffset(2026, 11, 20, 12, 0, 0, TimeSpan.Zero)));

        // Madrid's own rules, for a server without the time zone database, give its hours all year.
        for (var at = new DateTimeOffset(2026, 1, 1, 0, 30, 0, TimeSpan.Zero); at.Year == 2026; at = at.AddHours(1))
        {
            Assert.Equal(Home.GetUtcOffset(at), KostvMusicTimeZone.Madrid.GetUtcOffset(at));
        }

        // The store follows the setting as it changes.
        var zone = TimeZoneInfo.Utc;
        _now = new DateTimeOffset(2026, 11, 20, 4, 30, 0, TimeSpan.Zero);
        var service = new KostvMusicService(null!, null!, new KostvMusicStore(_root, () => _now, zoneOf: () => zone), NullLogger<KostvMusicService>.Instance);
        Assert.Equal("2026-11-19", service.Day);
        zone = Home;
        Assert.Equal("2026-11-20", service.Day);
    }

    [Fact]
    public void TheTimeOfDayOfAListenIsWorkedOutFromWhenItWas()
    {
        var songs = Library(genres: 1, artists: 3, played: 10, unplayed: 0).Take(10).ToList();
        // Noted on a server in UTC: 05:xx there, 06:xx at home, the morning.
        var events = SlotListens(songs, days: 5, perDay: 5, hourUtc: 5)
            .Select(e => new KostvMusicEvent { Item = e.Item, Outcome = e.Outcome, Played = e.Played, Duration = e.Duration }.Stamp(e.At, TimeZoneInfo.Utc))
            .ToList();
        Assert.All(events, e => Assert.Equal(5, e.Hour));

        Assert.True(KostvMusicEngine.MomentReady(events, "manana", _now, Home));
        Assert.False(KostvMusicEngine.MomentReady(events, "noche", _now, Home));
    }

    // ---------------------------------------------------------------- enough for the time of day

    [Fact]
    public void SkippedListensDontCountForAMixOfTheMoment()
    {
        var songs = Library(genres: 1, artists: 3, played: 10, unplayed: 0).Take(10).ToList();
        List<KostvMusicEvent> WithSkips(int perDay)
        {
            var events = SlotListens(songs, days: 5, perDay: perDay, hourUtc: 14);
            // One of each day skipped.
            foreach (var day in events.GroupBy(e => e.Day))
            {
                day.First().Outcome = KostvListenOutcome.Skipped;
            }

            return events;
        }

        Assert.False(KostvMusicEngine.MomentReady(WithSkips(5), "tarde", _now, Home));
        Assert.True(KostvMusicEngine.MomentReady(WithSkips(6), "tarde", _now, Home));
    }

    [Fact]
    public void ANightPastMidnightIsOneDay()
    {
        var songs = Library(genres: 1, artists: 3, played: 10, unplayed: 0).Take(10).ToList();
        // 22:00 to 00:15 at home (21:00 to 23:15 UTC in winter), every other night.
        List<KostvMusicEvent> Nights(int nights)
        {
            var events = new List<KostvMusicEvent>();
            for (var n = 0; n < nights; n++)
            {
                var night = new DateTimeOffset(2026, 11, 18 - 2 * n, 21, 0, 0, TimeSpan.Zero);
                for (var i = 0; i < 10; i++)
                {
                    events.Add(Listen(songs[i].Id, night.AddMinutes(i * 15)));
                }
            }

            return events;
        }

        var three = Nights(3);
        Assert.Equal(6, three.Select(e => e.Day).Distinct().Count());
        Assert.False(KostvMusicEngine.MomentReady(three, "noche", _now, Home));
        Assert.True(KostvMusicEngine.MomentReady(Nights(5), "noche", _now, Home));
        Assert.Equal(new DateOnly(2026, 11, 18), KostvMusicEngine.SlotDay(new DateTimeOffset(2026, 11, 18, 23, 30, 0, TimeSpan.Zero), Home));
    }

    // ---------------------------------------------------------------- the day's music, kept

    /// <summary>A made-up music library that answers the queries the music makes.</summary>
    private sealed class MusicLibrary
    {
        public List<BaseItem> Items { get; } = [];

        public Dictionary<Guid, UserItemData> Data { get; } = [];

        public int Queries { get; private set; }

        public Action? OnQuery { get; set; }

        public static MusicLibrary Made(int genres = 5, int artists = 6, int played = 6, int unplayed = 6)
        {
            var library = new MusicLibrary();
            for (var g = 0; g < genres; g++)
            {
                for (var a = 0; a < artists; a++)
                {
                    var artist = $"Artista {g}-{a}";
                    library.Items.Add(new MusicArtist { Id = Guid.NewGuid(), Name = artist });
                    for (var s = 0; s < played + unplayed; s++)
                    {
                        var song = new Audio { Id = Guid.NewGuid(), Name = $"Canción {s}", Artists = [artist], Genres = [$"Género {g}"] };
                        library.Items.Add(song);
                        var plays = s < played ? (genres - g) * 3 : 0;
                        library.Data[song.Id] = new UserItemData
                        {
                            Key = song.Id.ToString("N"),
                            PlayCount = plays,
                            Played = plays > 0,
                            LastPlayedDate = plays > 0 ? new DateTime(2026, 11, 10, 0, 0, 0, DateTimeKind.Utc) : null
                        };
                    }
                }
            }

            return library;
        }

        private UserItemData DataOf(BaseItem item) =>
            Data.TryGetValue(item.Id, out var data) ? data : new UserItemData { Key = item.Id.ToString("N") };

        private List<BaseItem> Run(InternalItemsQuery query)
        {
            Queries++;
            OnQuery?.Invoke();
            if (query.SimilarTo != null)
            {
                return [];
            }

            IEnumerable<BaseItem> found = Items.Where(i => query.IncludeItemTypes.Length == 0 || query.IncludeItemTypes.Contains(i.GetBaseItemKind()));
            if (query.Name != null)
            {
                found = found.Where(i => i.Name == query.Name);
            }

            if (query.ItemIds.Length > 0)
            {
                found = found.Where(i => query.ItemIds.Contains(i.Id));
            }

            if (query.Genres.Count > 0)
            {
                found = found.Where(i => i.Genres.Any(g => query.Genres.Contains(g, StringComparer.OrdinalIgnoreCase)));
            }

            if (query.ArtistIds.Length > 0)
            {
                var names = Items.Where(a => query.ArtistIds.Contains(a.Id)).Select(a => a.Name).ToHashSet();
                found = found.Where(i => i is Audio song && song.Artists.Any(names.Contains));
            }

            if (query.IsPlayed is { } played)
            {
                found = found.Where(i => DataOf(i).Played == played);
            }

            if (query.IsFavorite is { } favorite)
            {
                found = found.Where(i => DataOf(i).IsFavorite == favorite);
            }

            return found.Take(query.Limit ?? int.MaxValue).ToList();
        }

        public ILibraryManager Manager() => RecordingHostProxy.Create<ILibraryManager>((method, args) => method.Name switch
        {
            "GetItemList" => Run((InternalItemsQuery)args![0]!),
            "GetItemIds" => Run((InternalItemsQuery)args![0]!).Select(i => i.Id).ToList(),
            "GetItemById" when args is [Guid id] => Items.FirstOrDefault(i => i.Id == id),
            _ => throw new NotSupportedException(method.Name)
        });

        public IUserDataManager UserData() => RecordingHostProxy.Create<IUserDataManager>((method, args) =>
            method.Name == "GetUserData" && args is [_, BaseItem item] ? DataOf(item) : null);
    }

    private KostvMusicService NewService(MusicLibrary library) =>
        new(library.Manager(), library.UserData(), NewStore(), NullLogger<KostvMusicService>.Instance);

    [Fact]
    public async Task TheDaysMixesStayTheSameAfterARestart()
    {
        var library = MusicLibrary.Made();
        var userId = Guid.NewGuid();
        var user = new User("ana", "auth", "reset");
        var mixes = await NewService(library).MixesAsync(userId, user);
        Assert.Equal(4, mixes.Count);
        Assert.All(mixes, m => Assert.Equal(3, m.ArtistIds!.Count));
        Assert.True(File.Exists(Path.Combine(_root, userId.ToString("N"), "today.json")));

        // Restarted, with more played since: the same mixes, without reading the library.
        foreach (var data in library.Data.Values.Where(d => d.PlayCount == 0).Take(40))
        {
            data.PlayCount = 50;
            data.Played = true;
        }

        var queries = library.Queries;
        var restarted = NewService(library);
        var again = await restarted.MixesAsync(userId, user);
        Assert.Equal(mixes.Select(m => (m.Id, m.Genre)), again.Select(m => (m.Id, m.Genre)));
        Assert.Equal(mixes.Select(m => m.Items), again.Select(m => m.Items));
        Assert.Equal(queries, library.Queries);
        Assert.Equal("Género 1", restarted.MixGenreOf(userId, "daily-2"));

        // The next day, worked out again.
        _now = _now.AddDays(1);
        await restarted.MixesAsync(userId, user);
        Assert.True(library.Queries > queries);
    }

    [Fact]
    public async Task ForgettingAPersonsMusicDropsWhatWasWorkedOut()
    {
        var library = MusicLibrary.Made();
        var userId = Guid.NewGuid();
        var user = new User("ana", "auth", "reset");
        var service = NewService(library);
        await service.MixesAsync(userId, user);
        var file = Path.Combine(_root, userId.ToString("N"), "today.json");
        Assert.True(File.Exists(file));

        // Their listens deleted, or Learn turned off.
        service.Forget(userId);
        Assert.False(File.Exists(file));
        var queries = library.Queries;
        await service.MixesAsync(userId, user);
        Assert.True(library.Queries > queries);

        // Forgotten while being worked out: what comes out isn't kept.
        service.Forget(userId);
        var forgotten = false;
        library.OnQuery = () =>
        {
            if (!forgotten)
            {
                forgotten = true;
                service.Forget(userId);
            }
        };
        await service.MixesAsync(userId, user);
        library.OnQuery = null;
        Assert.False(File.Exists(file));
        queries = library.Queries;
        await service.MixesAsync(userId, user);
        Assert.True(library.Queries > queries);
        Assert.True(File.Exists(file));
    }

    [Fact]
    public async Task TheMixOfTheMomentUsesWhatWasReadForTheMixes()
    {
        var library = MusicLibrary.Made();
        var userId = Guid.NewGuid();
        var user = new User("ana", "auth", "reset");
        var service = NewService(library);
        // Mornings of the genre the person plays most (11:00 at home now is the morning).
        var mornings = library.Items.OfType<Audio>().Where(s => s.Genres[0] == "Género 0" && library.Data[s.Id].Played).Take(20).ToList();
        for (var d = 1; d <= 6; d++)
        {
            for (var i = 0; i < 5; i++)
            {
                var song = mornings[(d * 5 + i) % mornings.Count];
                var listen = Listen(song.Id, new DateTimeOffset(2026, 11, 20 - d, 8, i * 4, 0, TimeSpan.Zero));
                listen.Genres = [.. song.Genres];
                listen.Artists = [.. song.Artists];
                service.Store.Append(userId, listen);
            }
        }

        var before = library.Queries;
        await service.MixesAsync(userId, user);
        var forMixes = library.Queries - before;
        before = library.Queries;
        var moment = await service.MomentAsync(userId, user);
        Assert.True(moment.Ready);
        Assert.Equal(KostvMusicEngine.MomentSize, moment.Items.Count);
        // Its genre and artists were read already for the mixes.
        Assert.True(library.Queries - before < forMixes / 2, $"{library.Queries - before} queries, {forMixes} for the mixes");

        // Kept for the day, also after a restart.
        var restarted = NewService(library);
        before = library.Queries;
        Assert.Equal(moment.Items, (await restarted.MomentAsync(userId, user)).Items);
        Assert.Equal(before, library.Queries);
    }

    [Fact]
    public async Task NewSongsComeFromAllOfAGenreInAnOrderOfTheDay()
    {
        // One genre and six artists with more songs unplayed than are read of them (3000).
        var library = MusicLibrary.Made(genres: 1, artists: 6, played: 6, unplayed: 600);
        var userId = Guid.NewGuid();
        var user = new User("ana", "auth", "reset");
        var service = NewService(library);
        var days = new List<IReadOnlyList<Guid>>();
        for (var d = 0; d < 3; d++)
        {
            days.Add((await service.MixesAsync(userId, user)).Single().Items);
            _now = _now.AddDays(1);
        }

        var unplayed = library.Items.OfType<Audio>().Where(s => !library.Data[s.Id].Played).Select(s => s.Id).ToList();
        Assert.NotEqual(days[0].Where(unplayed.Contains), days[1].Where(unplayed.Contains));
        // Not only the first ones the library gives: also of those past what is read.
        var pastTheFirst = unplayed.Skip(3000).ToHashSet();
        Assert.Contains(days.SelectMany(d => d), pastTheFirst.Contains);
    }
}
