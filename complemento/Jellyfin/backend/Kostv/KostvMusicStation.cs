using System.Collections.Concurrent;
using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using MediaBrowser.Controller.Entities;
using Microsoft.Extensions.Logging;

namespace Moonfin.Server.Kostv;

/// <summary>kOS TV: the seed of a station: a song at home or not at home, by title and artist.</summary>
public sealed record KostvStationSeed(string Title, string Artist, Guid? HomeId = null, string? DeezerId = null, string? Mbid = null);

/// <summary>kOS TV: a song of a person's station: at home (<see cref="Home"/>) or not (<see cref="Away"/>).</summary>
public sealed record KostvStationItem(BaseItem? Home, KostvStationEntry? Away, string Why);

/// <summary>
/// kOS TV: a person's station, as the route gives it. <see cref="Partial"/>: still being worked
/// out (asked again in a while, it comes whole); a station of only Deezer's radio is
/// <c>fallback</c> without being partial.
/// </summary>
public sealed record KostvStationResult(KostvStationSeed Seed, string? SeedMbid, IReadOnlyList<KostvStationItem> Items, string Source, bool Partial = false);

/// <summary>
/// kOS TV: the station of a song (<c>GET /Moonfin/Kostv/Music/Station</c>, see
/// <c>docs/musica-radio.md</c>, «Contrato de la emisora»). Worked out once a day per seed for the
/// whole home from the free outside sources (<see cref="KostvStationWeb"/>, <see cref="KostvStationRecipe"/>),
/// in the background: a request waits for it <see cref="Deadline"/> at most and, past it, gets
/// what there is (<c>Source: "fallback"</c>) while it goes on, so the next one gets it whole.
/// Then, for each person: what is at home that they may see, or else (with <c>away</c>) its
/// Deezer id; without their «no me gusta», nor explicit songs not at home for someone with an
/// age limit; with the variety rules. Nothing of the home's history counts.
/// </summary>
public sealed class KostvMusicStation : IDisposable
{
    /// <summary>The stations worked out are kept this long.</summary>
    public static readonly TimeSpan StationKeep = TimeSpan.FromDays(1);

    /// <summary>The most songs a request may ask for.</summary>
    public const int MaxLimit = 100;

    /// <summary>How many seed recordings of MusicBrainz are asked for songs heard with them.</summary>
    public const int SeedRecordings = 6;

    /// <summary>How many candidates by listening are looked up on MusicBrainz (for ISRC, year and style).</summary>
    public const int CandidatesLookedUp = 100;

    /// <summary>How many related artists' own related are asked, to widen the style filter.</summary>
    public const int RelatedOfRelatedOf = 5;

    // The station is made playable (at home, or with a Deezer id) up to this many songs.
    private const int PlayableTarget = 120;

    // The most stations worked out at once.
    private const int MaxJobs = 8;

    // The most stations kept in memory (being worked out, or that could not be made whole).
    private const int MaxKeptJobs = 200;

    // Matching to Deezer may be cut short by the time limit once this many can sound.
    private const int EnoughPlayable = 60;

    // A station that could not be made whole is kept in memory this long, not on disk.
    private static readonly TimeSpan PartialKeep = TimeSpan.FromMinutes(30);

    private static readonly JsonSerializerOptions Options = new()
    {
        Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping
    };

    private readonly KostvStationWeb _web;
    private readonly IKostvStationLibrary _library;
    private readonly KostvStationDiskCache _cache;
    private readonly ILogger _logger;
    private readonly ConcurrentDictionary<string, Job> _jobs = new(StringComparer.Ordinal);

    // Kos TV: the server stopping cancels what is being worked out (and nothing new starts).
    private readonly CancellationTokenSource _stopping = new();
    private volatile bool _disposed;

    public KostvMusicStation(KostvStationWeb web, IKostvStationLibrary library, KostvStationDiskCache cache, ILogger logger)
    {
        _web = web;
        _library = library;
        _cache = cache;
        _logger = logger;
    }

    /// <summary>The longest a request waits for its station before answering with what there is.</summary>
    public TimeSpan Deadline { get; set; } = TimeSpan.FromSeconds(5);

    /// <summary>The longest a station is worked out in the background.</summary>
    public TimeSpan WorkLimit { get; set; } = TimeSpan.FromSeconds(90);

    /// <summary>The time now, and the home's time zone (the music day, and December).</summary>
    public Func<DateTimeOffset> Now { get; set; } = () => DateTimeOffset.UtcNow;

    public Func<TimeZoneInfo> Zone { get; set; } = () => TimeZoneInfo.Utc;

    /// <summary>What a person doesn't want to hear.</summary>
    public Func<Guid, KostvDislikeSet> DislikesOf { get; set; } = _ => KostvDislikeSet.Empty;

    /// <summary>Whether a person has an age limit (their parental control): nothing explicit from outside.</summary>
    public Func<Guid, bool> AgeLimitedOf { get; set; } = _ => false;

    /// <summary>The server stops: what is being worked out is let go of (not kept half done).</summary>
    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        _stopping.Cancel();
    }

    private sealed class Stored
    {
        public string? Source { get; set; }

        public string? SeedMbid { get; set; }

        public List<KostvStationEntry> Entries { get; set; } = [];
    }

    // ---------------------------------------------------------------- the request

    /// <summary>
    /// The station of <paramref name="seed"/> for <paramref name="userId"/>: up to
    /// <paramref name="limit"/> songs, only those at home without <paramref name="away"/>.
    /// </summary>
    public async Task<KostvStationResult> StationAsync(Guid userId, object user, KostvStationSeed seed, int limit, bool away, CancellationToken cancellationToken)
    {
        limit = Math.Clamp(limit, 1, MaxLimit);
        var key = KeyOf(seed);
        List<KostvStationEntry> entries;
        string source;
        string? seedMbid = seed.Mbid;
        var partial = false;
        if (StoredOf(key) is { } stored)
        {
            entries = stored.Entries;
            source = stored.Source ?? KostvStationSource.Fallback;
            seedMbid ??= stored.SeedMbid;
        }
        else if (JobOf(key, seed) is { } job)
        {
            var wait = Task.Delay(Deadline, cancellationToken);
            await Task.WhenAny(job.Work, wait).ConfigureAwait(false);
            cancellationToken.ThrowIfCancellationRequested();
            (entries, source) = job.Snapshot();
            seedMbid ??= job.SeedMbid;
            partial = !job.Work.IsCompleted;
        }
        else
        {
            entries = [];
            source = KostvStationSource.Fallback;
        }

        var items = ForPerson(userId, user, seed, entries, limit, away);
        return new KostvStationResult(seed, seedMbid, items, source, partial);
    }

    /// <summary>
    /// A seed's key: its title and first artist, compared (the same at home and not), and the kind
    /// of version it is (Kos TV: a live one lets other live ones in; the studio one doesn't).
    /// </summary>
    public static string KeyOf(KostvStationSeed seed)
    {
        var key = KostvStationRecipe.NormTitle(seed.Title) + "|" + KostvStationRecipe.Primary(seed.Artist);
        var versions = KostvStationRecipe.VersionsOf(seed.Title);
        return versions.Count == 0 ? key : key + "|" + string.Join(",", versions.Order(StringComparer.Ordinal));
    }

    private string Day()
    {
        var local = TimeZoneInfo.ConvertTime(Now(), Zone());
        return local.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
    }

    private Stored? StoredOf(string key)
    {
        // The station of the day: one made another day is made again (with another little shuffle).
        if (!_cache.TryGet("emisoras", Day() + "|" + key, StationKeep, out _, out var body) || body is not { } element)
        {
            return null;
        }

        try
        {
            return element.Deserialize<Stored>(Options);
        }
        catch (JsonException)
        {
            return null;
        }
    }

    private Job? JobOf(string key, KostvStationSeed seed)
    {
        var now = Now();
        foreach (var (k, old) in _jobs)
        {
            if (old.Work.IsCompleted && now - old.FinishedAt > PartialKeep)
            {
                _jobs.TryRemove(k, out _);
            }
        }

        if (_jobs.TryGetValue(key, out var job))
        {
            return job;
        }

        if (_disposed || _jobs.Count(j => !j.Value.Work.IsCompleted) >= MaxJobs)
        {
            return null;
        }

        // Kos TV: those that could not be made whole are kept a while, but not without end (a
        // source down for long, many seeds): past the most, the oldest go.
        if (_jobs.Count >= MaxKeptJobs)
        {
            var oldest = _jobs.Where(j => j.Value.Work.IsCompleted).OrderBy(j => j.Value.FinishedAt).Take(_jobs.Count - MaxKeptJobs + 1).Select(j => j.Key).ToList();
            foreach (var k in oldest)
            {
                _jobs.TryRemove(k, out _);
            }
        }

        var fresh = new Job(this, key, seed, Day());
        if (!_jobs.TryAdd(key, fresh))
        {
            return _jobs.GetValueOrDefault(key);
        }

        fresh.Start();
        return fresh;
    }

    // ---------------------------------------------------------------- for each person

    /// <summary>A home song is the entry: its recording, or its title and one of its artists, compared.</summary>
    public static bool IsEntry(KostvStationHomeSong song, KostvStationEntry entry)
    {
        if (entry.Mbid != null && song.Mbid != null && string.Equals(entry.Mbid, song.Mbid, StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        if (KostvStationRecipe.NormTitle(song.Title) != KostvStationRecipe.NormTitle(entry.Title))
        {
            return false;
        }

        var names = KostvStationRecipe.CreditNames(entry.Artist).ToHashSet(StringComparer.Ordinal);
        return song.Artists.Any(a => KostvStationRecipe.CreditNames(a).Any(names.Contains));
    }

    /// <summary>The songs at home an entry is (the plain version first), for everyone.</summary>
    public List<KostvStationHomeSong> HomeOf(KostvStationEntry entry)
    {
        var found = new List<KostvStationHomeSong>();
        foreach (var name in KostvStationRecipe.CreditAsWritten(entry.Artist).Take(2))
        {
            foreach (var song in _library.SongsBy(name))
            {
                if (IsEntry(song, entry) && found.All(f => f.Id != song.Id))
                {
                    found.Add(song);
                }
            }
        }

        return found.OrderBy(s => KostvStationRecipe.VersionsOf(s.Title).Count).ToList();
    }

    private List<KostvStationItem> ForPerson(Guid userId, object user, KostvStationSeed seed, List<KostvStationEntry> entries, int limit, bool away)
    {
        var ageLimited = AgeLimitedOf(userId);
        var dislikes = DislikesOf(userId);
        // For someone with an age limit, only what comes from Deezer (which says what is explicit).
        var candidates = ageLimited
            ? entries.Where(e => e.Why == KostvStationWhy.Deezer).Concat(entries.Where(e => e.Why == KostvStationWhy.Style)).ToList()
            : entries;

        var home = candidates.Select(HomeOf).ToList();
        var visible = _library.Visible(user, home.SelectMany(h => h.Select(s => s.Id)).Distinct().ToList())
            .GroupBy(i => i.Id)
            .ToDictionary(g => g.Key, g => g.First());

        var picked = new List<(KostvStationItem Item, string Artist, string? Album)>();
        var used = new HashSet<Guid>();
        for (var i = 0; i < candidates.Count; i++)
        {
            var entry = candidates[i];
            if (home[i].Count > 0)
            {
                // At home: only if the person may see it (otherwise not from outside either).
                var item = home[i]
                    .Select(s => visible.GetValueOrDefault(s.Id))
                    .FirstOrDefault(it => it != null && it.Id != seed.HomeId && !used.Contains(it.Id) && !KostvMusicService.Blocks(dislikes, it));
                if (item != null)
                {
                    used.Add(item.Id);
                    picked.Add((new KostvStationItem(item, null, entry.Why), KostvStationRecipe.Primary(entry.Artist), (item as MediaBrowser.Controller.Entities.Audio.Audio)?.Album ?? entry.Album));
                }

                continue;
            }

            if (!away || entry.DeezerId == null || entry.DeezerId == seed.DeezerId ||
                dislikes.BlocksStreamed(entry.DeezerId, KostvStationRecipe.CreditAsWritten(entry.Artist)) ||
                (ageLimited && entry.Explicit != false))
            {
                continue;
            }

            picked.Add((new KostvStationItem(null, entry, entry.Why), KostvStationRecipe.Primary(entry.Artist), entry.Album));
        }

        var seedArtist = KostvStationRecipe.CreditNames(seed.Artist).ToHashSet(StringComparer.Ordinal);
        return KostvStationRecipe.Arrange(picked, p => p.Artist, p => p.Album, seedArtist, limit).Select(p => p.Item).ToList();
    }

    // ---------------------------------------------------------------- working it out

    /// <summary>A station being worked out: what has been fetched so far, and the rest coming.</summary>
    private sealed class Job
    {
        private readonly KostvMusicStation _owner;
        private readonly string _key;
        private readonly string _day;
        private readonly KostvStationSeed _seed;
        private readonly object _sync = new();
        private readonly KostvStationInputs _inputs;
        private readonly Dictionary<string, KostvStationTrack> _matched = new(StringComparer.Ordinal);
        private readonly int _jitterSeed;
        // Kos TV: not finished from the moment it is made (another request may find it before it starts).
        private readonly TaskCompletionSource _finished = new(TaskCreationOptions.RunContinuationsAsynchronously);
        private bool _done;
        private bool _failed;

        public Job(KostvMusicStation owner, string key, KostvStationSeed seed, string day)
        {
            _owner = owner;
            _key = key;
            _seed = seed;
            _day = day;
            var month = TimeZoneInfo.ConvertTime(owner.Now(), owner.Zone()).Month;
            _inputs = new KostvStationInputs { SeedTitle = seed.Title, SeedArtist = seed.Artist, Month = month };
            _jitterSeed = BitConverter.ToInt32(SHA256.HashData(Encoding.UTF8.GetBytes(day + "|" + key)), 0);
        }

        public Task Work => _finished.Task;

        public DateTimeOffset FinishedAt { get; private set; } = DateTimeOffset.MaxValue;

        public string? SeedMbid { get; private set; }

        public void Start()
        {
            var stopping = _owner._stopping.Token;
            _ = Task.Run(async () =>
            {
                using var limit = CancellationTokenSource.CreateLinkedTokenSource(stopping);
                limit.CancelAfter(_owner.WorkLimit);
                try
                {
                    await RunAsync(limit.Token, stopping).ConfigureAwait(false);
                }
                catch (OperationCanceledException)
                {
                    lock (_sync)
                    {
                        _failed = true;
                    }
                }
                catch (Exception ex)
                {
                    _owner._logger.LogWarning(ex, "kOS TV station: a station could not be worked out");
                    lock (_sync)
                    {
                        _failed = true;
                    }
                }
                finally
                {
                    try
                    {
                        Finish(stopping.IsCancellationRequested);
                    }
                    catch (Exception ex)
                    {
                        _owner._logger.LogWarning(ex, "kOS TV station: a station could not be kept");
                    }
                    finally
                    {
                        _finished.TrySetResult();
                    }
                }
            });
        }

        private void Set(Action<KostvStationInputs> change)
        {
            lock (_sync)
            {
                change(_inputs);
            }
        }

        private void Failed(bool failed)
        {
            if (failed)
            {
                lock (_sync)
                {
                    _failed = true;
                }
            }
        }

        /// <summary>The station as it stands, and where it came from (<c>fallback</c> until whole).</summary>
        public (List<KostvStationEntry> Entries, string Source) Snapshot()
        {
            lock (_sync)
            {
                var plan = KostvStationRecipe.Plan(_inputs, jitter: 0.05, jitterSeed: _jitterSeed);
                foreach (var entry in plan.Where(e => e.DeezerId == null))
                {
                    if (_matched.TryGetValue(EntryKey(entry), out var track))
                    {
                        entry.DeezerId = track.DeezerId;
                        entry.Explicit = track.Explicit;
                        entry.Album ??= track.Album;
                        entry.Cover = track.Cover;
                        entry.Duration = track.Duration;
                        entry.AlbumDeezerId = track.AlbumDeezerId;
                        entry.ArtistDeezerId = track.ArtistDeezerId;
                    }
                }

                string source;
                if (!_done)
                {
                    source = KostvStationSource.Fallback;
                }
                else if (plan.Any(e => e.Why == KostvStationWhy.ListenBrainz))
                {
                    source = KostvStationSource.ListenBrainz;
                }
                else if (plan.Any(e => e.Why == KostvStationWhy.LastFm))
                {
                    source = KostvStationSource.LastFm;
                }
                else
                {
                    source = KostvStationSource.Fallback;
                }

                return (plan, source);
            }
        }

        private static string EntryKey(KostvStationEntry entry) => KostvStationRecipe.NormTitle(entry.Title) + "|" + KostvStationRecipe.Primary(entry.Artist);

        private void Finish(bool stopping)
        {
            bool whole;
            lock (_sync)
            {
                _done = true;
                whole = !_failed;
            }

            FinishedAt = _owner.Now();
            // Kos TV: the server stopping: nothing half done is kept for the day.
            if (stopping)
            {
                return;
            }

            var (entries, source) = Snapshot();
            if (whole)
            {
                // Whole: kept for the day on disk (and not in memory any more).
                var stored = new Stored { Source = source, SeedMbid = SeedMbid, Entries = entries.Where(e => e.DeezerId != null || _owner.HomeOf(e).Count > 0).ToList() };
                _owner._cache.Put("emisoras", _day + "|" + _key, 200, JsonSerializer.SerializeToElement(stored, Options));
                _owner._jobs.TryRemove(_key, out _);
            }
        }

        private async Task RunAsync(CancellationToken ct, CancellationToken stopping)
        {
            var web = _owner._web;
            var isrc = new TaskCompletionSource<string?>(TaskCreationOptions.RunContinuationsAsynchronously);
            var deezer = DeezerSideAsync(web, isrc, ct);
            var lastFm = LastFmAsync(web, ct);
            var listening = ListeningAsync(web, isrc.Task, ct);
            try
            {
                await Task.WhenAll(deezer, lastFm, listening).ConfigureAwait(false);
            }
            finally
            {
                isrc.TrySetResult(null);
            }

            await FillAsync(web, ct).ConfigureAwait(false);
            await MatchAsync(web, ct, stopping).ConfigureAwait(false);
        }

        private async Task DeezerSideAsync(KostvStationWeb web, TaskCompletionSource<string?> isrc, CancellationToken ct)
        {
            try
            {
                var (track, failed) = _seed.DeezerId != null
                    ? await web.DeezerTrackAsync(_seed.DeezerId, ct).ConfigureAwait(false)
                    : await web.DeezerSeedAsync(_seed.Title, _seed.Artist, ct).ConfigureAwait(false);
                Failed(failed);
                if (track is not { } t || KostvStationWeb.DeezerTrack(t) is not { ArtistDeezerId: { } artistId })
                {
                    return;
                }

                // Kos TV: its ISRC and year only when Deezer's song is the seed: the search gives
                // another song of the artist when Deezer hasn't that one (its radio still is the
                // artist's, but that song's recordings aren't the seed's).
                if (_seed.DeezerId != null || KostvStationWeb.IsTitled(KostvStationWeb.DeezerTrack(t)!, _seed.Title))
                {
                    var (seedIsrc, year) = KostvStationWeb.DeezerTrackExtra(t);
                    isrc.TrySetResult(seedIsrc);
                    Set(i => i.SeedYear ??= year);
                }

                var related = web.DeezerRelatedAsync(artistId, ct);
                var radio = web.DeezerArtistListAsync(artistId, "radio", 50, ct);
                var top = web.DeezerArtistListAsync(artistId, "top", 5, ct);
                var (relatedArtists, f1) = await related.ConfigureAwait(false);
                Set(i => i.Related = relatedArtists.Select(a => a.Name).ToList());
                var (radioTracks, f2) = await radio.ConfigureAwait(false);
                Set(i => i.Radio = radioTracks);
                var (topTracks, f3) = await top.ConfigureAwait(false);
                Set(i => i.SeedArtistTop = topTracks);
                Failed(f1 || f2 || f3);

                _relatedIds = relatedArtists.Select(a => a.Id).ToList();
                var ofRelated = await Task.WhenAll(relatedArtists.Take(RelatedOfRelatedOf).Select(a => web.DeezerRelatedAsync(a.Id, ct))).ConfigureAwait(false);
                Set(i => i.RelatedOfRelated = ofRelated.SelectMany(r => r.Artists.Select(a => a.Name)).Distinct(StringComparer.OrdinalIgnoreCase).ToList());
            }
            finally
            {
                isrc.TrySetResult(null);
            }
        }

        private List<string> _relatedIds = [];

        private async Task LastFmAsync(KostvStationWeb web, CancellationToken ct)
        {
            if (!web.HasLastFm)
            {
                return;
            }

            var (tracks, failed) = await web.LastFmSimilarAsync(_seed.Title, _seed.Artist, ct).ConfigureAwait(false);
            // Last.fm is extra: not answering doesn't make the station partial.
            Set(i => i.LastFm = tracks);
            if (failed)
            {
                _owner._logger.LogDebug("kOS TV station: Last.fm did not answer");
            }
        }

        private async Task ListeningAsync(KostvStationWeb web, Task<string?> seedIsrc, CancellationToken ct)
        {
            var mbids = new List<string>();
            if (_seed.Mbid != null)
            {
                mbids.Add(_seed.Mbid);
            }

            var (found, failed) = await web.RecordingsOfAsync(_seed.Title, _seed.Artist, ct).ConfigureAwait(false);
            Failed(failed);
            mbids.AddRange(found.Where(m => !mbids.Contains(m, StringComparer.OrdinalIgnoreCase)));
            var asked = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var similar = new List<Task>();
            void Ask(IEnumerable<string> some)
            {
                foreach (var mbid in some)
                {
                    if (asked.Count >= SeedRecordings || !asked.Add(mbid))
                    {
                        continue;
                    }

                    similar.Add(SimilarAsync(web, mbid, mlhd: false, ct));
                    similar.Add(SimilarAsync(web, mbid, mlhd: true, ct));
                }
            }

            Ask(mbids);
            SeedMbid = mbids.FirstOrDefault();

            // The seed's artist, its styles and its year, and the artists heard with it.
            var seedInfo = SeedInfoAsync(web, mbids.Take(SeedRecordings).ToList(), ct);

            // One more way to the seed's recordings: its ISRC, on MusicBrainz (optional; often busy).
            if (await seedIsrc.ConfigureAwait(false) is { } isrc && asked.Count < SeedRecordings)
            {
                var (byIsrc, _) = await web.RecordingsOfIsrcAsync(isrc, ct).ConfigureAwait(false);
                SeedMbid ??= byIsrc.FirstOrDefault();
                Ask(byIsrc);
            }

            await Task.WhenAll(similar).ConfigureAwait(false);
            await seedInfo.ConfigureAwait(false);

            // What MusicBrainz knows of the candidates: ISRC (to find them on Deezer), year and style.
            List<string> lookUp;
            lock (_sync)
            {
                lookUp = _inputs.ListenBrainz.Concat(_inputs.LastFm)
                    .OrderByDescending(t => t.Score)
                    .Select(t => t.Mbid)
                    .OfType<string>()
                    .Where(m => !_inputs.Recordings.ContainsKey(m))
                    .Distinct(StringComparer.Ordinal)
                    .Take(CandidatesLookedUp)
                    .ToList();
            }

            var (info, infoFailed) = await web.RecordingInfoAsync(lookUp, ct).ConfigureAwait(false);
            Failed(infoFailed);
            Set(i => i.Recordings = Merged(i.Recordings, info.ToDictionary(p => p.Key, p => p.Value.Info)));
        }

        private static Dictionary<string, KostvStationRecordingInfo> Merged(IReadOnlyDictionary<string, KostvStationRecordingInfo> old, Dictionary<string, KostvStationRecordingInfo> more)
        {
            var merged = new Dictionary<string, KostvStationRecordingInfo>(old, StringComparer.Ordinal);
            foreach (var (k, v) in more)
            {
                merged[k] = v;
            }

            return merged;
        }

        private async Task SeedInfoAsync(KostvStationWeb web, List<string> mbids, CancellationToken ct)
        {
            if (mbids.Count == 0)
            {
                return;
            }

            var (info, failed) = await web.RecordingInfoAsync(mbids, ct).ConfigureAwait(false);
            Failed(failed);
            var artistMbid = mbids.Select(m => info.GetValueOrDefault(m).Info?.ArtistMbids.FirstOrDefault()).FirstOrDefault(a => a != null);
            var tags = mbids.SelectMany(m => info.GetValueOrDefault(m).Info?.ArtistTags ?? (IEnumerable<string>)[]).Distinct(StringComparer.Ordinal).Take(8).ToHashSet(StringComparer.Ordinal);
            var year = mbids.Select(m => info.GetValueOrDefault(m).Info?.Year).Where(y => y != null).DefaultIfEmpty(null).Min();
            Set(i =>
            {
                i.SeedArtistTags = tags;
                // MusicBrainz's year of the song (Deezer's is often a reissue's).
                if (year != null)
                {
                    i.SeedYear = year;
                }

                i.Recordings = Merged(i.Recordings, info.ToDictionary(p => p.Key, p => p.Value.Info));
            });

            if (artistMbid != null)
            {
                var (names, f) = await web.SimilarArtistsAsync(artistMbid, ct).ConfigureAwait(false);
                Failed(f);
                Set(i => i.SimilarArtists = names);
            }
        }

        private async Task SimilarAsync(KostvStationWeb web, string mbid, bool mlhd, CancellationToken ct)
        {
            var (tracks, failed) = await web.SimilarRecordingsAsync(mbid, mlhd, ct).ConfigureAwait(false);
            Failed(failed);
            lock (_sync)
            {
                // Both datasets and every seed recording together, each song by its best score.
                var best = new Dictionary<string, KostvStationTrack>(StringComparer.OrdinalIgnoreCase);
                foreach (var track in _inputs.ListenBrainz.Concat(tracks))
                {
                    if (track.Mbid == null || string.Equals(track.Mbid, _seed.Mbid, StringComparison.OrdinalIgnoreCase))
                    {
                        continue;
                    }

                    if (!best.TryGetValue(track.Mbid, out var old) || track.Score > old.Score)
                    {
                        best[track.Mbid] = track;
                    }
                }

                _inputs.ListenBrainz = best.Values.OrderByDescending(t => t.Score).ToList();
            }
        }

        private async Task FillAsync(KostvStationWeb web, CancellationToken ct)
        {
            // The most heard of the related artists, only when the station is short without them.
            if (Snapshot().Entries.Count >= PlayableTarget || _relatedIds.Count == 0)
            {
                return;
            }

            var tops = await Task.WhenAll(_relatedIds.Take(KostvStationRecipe.RelatedTopArtists)
                .Select(id => web.DeezerArtistListAsync(id, "top", KostvStationRecipe.RelatedTopEach, ct))).ConfigureAwait(false);
            Failed(tops.Any(t => t.Failed));
            Set(i => i.RelatedTop = tops.Select(t => (IReadOnlyList<KostvStationTrack>)t.Tracks).ToList());
        }

        private async Task MatchAsync(KostvStationWeb web, CancellationToken ct, CancellationToken stopping)
        {
            // In the station's order, those by listening not at home, to Deezer, until the first so
            // many of it can sound. Kos TV: counted in order, so the filler after them (which has its
            // Deezer id already) doesn't stand in for the songs heard with the seed.
            var (plan, _) = Snapshot();
            var playable = 0;
            var batch = new List<KostvStationEntry>();

            async Task MatchBatchAsync()
            {
                if (batch.Count == 0)
                {
                    return;
                }

                var found = await Task.WhenAll(batch.Select(e => web.DeezerMatchAsync(e.Title, e.Artist, e.Isrcs, ct))).ConfigureAwait(false);
                Failed(found.Any(f => f.Failed));
                lock (_sync)
                {
                    for (var i = 0; i < batch.Count; i++)
                    {
                        if (found[i].Track is { } track)
                        {
                            _matched[EntryKey(batch[i])] = track;
                            playable++;
                        }
                    }
                }

                batch.Clear();
            }

            try
            {
                foreach (var entry in plan)
                {
                    if (playable + batch.Count >= PlayableTarget)
                    {
                        await MatchBatchAsync().ConfigureAwait(false);
                        if (playable >= PlayableTarget)
                        {
                            break;
                        }
                    }

                    if (entry.DeezerId != null || _owner.HomeOf(entry).Count > 0)
                    {
                        playable++;
                    }
                    else
                    {
                        batch.Add(entry);
                        if (batch.Count == 3)
                        {
                            await MatchBatchAsync().ConfigureAwait(false);
                        }
                    }
                }

                await MatchBatchAsync().ConfigureAwait(false);
            }
            catch (OperationCanceledException) when (!stopping.IsCancellationRequested && playable >= EnoughPlayable)
            {
                // Kos TV: out of time with enough to sound: whole as it is (what wasn't matched
                // stays out), rather than worked out again every half an hour.
            }
        }
    }
}
