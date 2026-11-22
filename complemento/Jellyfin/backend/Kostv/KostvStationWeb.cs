using System.Collections.Concurrent;
using System.Diagnostics;
using System.Globalization;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Logging;
using Moonfin.Server.Helpers;

namespace Moonfin.Server.Kostv;

/// <summary>kOS TV: the outside services a station is asked of, each with its own pace.</summary>
public static class KostvStationHosts
{
    public const string Deezer = "api.deezer.com";
    public const string ListenBrainzLabs = "labs.api.listenbrainz.org";
    public const string ListenBrainz = "api.listenbrainz.org";
    public const string MusicBrainz = "musicbrainz.org";
    public const string LastFm = "ws.audioscrobbler.com";

    /// <summary>The time between two requests to a service: 2 a second, MusicBrainz 1.</summary>
    public static TimeSpan IntervalOf(string service) =>
        service == MusicBrainz ? TimeSpan.FromSeconds(1) : TimeSpan.FromMilliseconds(500);
}

/// <summary>
/// kOS TV: one request every <see cref="Interval"/> at most, in the order asked (the pace the
/// plugin keeps to each outside service, whatever the stations being worked out).
/// </summary>
public sealed class KostvRateGate
{
    private readonly SemaphoreSlim _turn = new(1, 1);
    private readonly Stopwatch _clock = Stopwatch.StartNew();
    private TimeSpan _next = TimeSpan.Zero;

    public KostvRateGate(TimeSpan interval)
    {
        Interval = interval;
    }

    public TimeSpan Interval { get; set; }

    public async Task WaitAsync(CancellationToken cancellationToken)
    {
        await _turn.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            var wait = _next - _clock.Elapsed;
            if (wait > TimeSpan.Zero)
            {
                await Task.Delay(wait, cancellationToken).ConfigureAwait(false);
            }

            _next = _clock.Elapsed + Interval;
        }
        finally
        {
            _turn.Release();
        }
    }
}

/// <summary>
/// kOS TV: the answers of the outside services kept on disk (30 days), and the stations worked
/// out (1 day), in the plugin's data folder, within <see cref="MaxBytes"/>: past it, the oldest go.
/// </summary>
public sealed class KostvStationDiskCache
{
    /// <summary>The folder in the plugin's data folder.</summary>
    public const string FolderName = "kostv-emisoras";

    private static readonly JsonSerializerOptions Options = new()
    {
        Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping
    };

    private readonly string _root;
    private readonly Func<DateTimeOffset> _now;
    private readonly ILogger? _logger;
    private readonly object _sync = new();
    private long? _bytes;

    public KostvStationDiskCache(string root, Func<DateTimeOffset>? now = null, ILogger? logger = null)
    {
        _root = root;
        _now = now ?? (() => DateTimeOffset.UtcNow);
        _logger = logger;
    }

    /// <summary>The most the folder may take: 64 MB.</summary>
    public long MaxBytes { get; set; } = 64L * 1024 * 1024;

    public string Root => _root;

    private sealed class Record
    {
        public DateTimeOffset At { get; set; }

        public int Status { get; set; }

        public JsonElement? Body { get; set; }
    }

    private string PathOf(string kind, string key)
    {
        var hash = Convert.ToHexString(SHA1.HashData(Encoding.UTF8.GetBytes(key))).ToLowerInvariant();
        return Path.Combine(_root, kind, hash[..2], hash + ".json");
    }

    /// <summary>What was kept for <paramref name="key"/>, if newer than <paramref name="keep"/>.</summary>
    public bool TryGet(string kind, string key, TimeSpan keep, out int status, out JsonElement? body)
    {
        status = 0;
        body = null;
        var path = PathOf(kind, key);
        try
        {
            if (!File.Exists(path))
            {
                return false;
            }

            var record = JsonSerializer.Deserialize<Record>(File.ReadAllText(path), Options);
            if (record == null || _now() - record.At > keep || record.At > _now() + TimeSpan.FromDays(1))
            {
                return false;
            }

            status = record.Status;
            body = record.Body;
            return true;
        }
        catch (Exception ex)
        {
            _logger?.LogDebug(ex, "kOS TV station: a kept answer could not be read");
            return false;
        }
    }

    public void Put(string kind, string key, int status, JsonElement? body)
    {
        var path = PathOf(kind, key);
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            var text = JsonSerializer.Serialize(new Record { At = _now(), Status = status, Body = body }, Options);
            var old = File.Exists(path) ? new FileInfo(path).Length : 0;
            var temp = path + ".tmp";
            File.WriteAllText(temp, text);
            File.Move(temp, path, overwrite: true);
            lock (_sync)
            {
                _bytes = (_bytes ?? Measure()) + Encoding.UTF8.GetByteCount(text) - old;
                if (_bytes > MaxBytes)
                {
                    Prune();
                }
            }
        }
        catch (Exception ex)
        {
            _logger?.LogDebug(ex, "kOS TV station: an answer could not be kept");
        }
    }

    private long Measure() =>
        Directory.Exists(_root)
            ? new DirectoryInfo(_root).EnumerateFiles("*.json", SearchOption.AllDirectories).Sum(f => f.Length)
            : 0;

    // The oldest go until it takes three quarters of the most.
    private void Prune()
    {
        var files = new DirectoryInfo(_root).EnumerateFiles("*.json", SearchOption.AllDirectories)
            .OrderBy(f => f.LastWriteTimeUtc)
            .ToList();
        var total = files.Sum(f => f.Length);
        foreach (var file in files)
        {
            if (total <= MaxBytes * 3 / 4)
            {
                break;
            }

            try
            {
                total -= file.Length;
                file.Delete();
            }
            catch (IOException)
            {
            }
        }

        _bytes = total;
    }
}

/// <summary>
/// kOS TV: the outside services a station is made of, all free: ListenBrainz (and its Labs),
/// MusicBrainz, Deezer's public API and, only with a key in the panel, Last.fm. Each at its pace
/// (<see cref="KostvStationHosts.IntervalOf"/>), with a generic User-Agent of the plugin, and
/// each answer kept 30 days on disk. Only titles and artists go out: nothing of the person.
/// </summary>
public sealed class KostvStationWeb
{
    public const string LabsBase = "https://labs.api.listenbrainz.org";
    public const string ListenBrainzBase = "https://api.listenbrainz.org/1";
    public const string MusicBrainzBase = "https://musicbrainz.org/ws/2";
    public const string DeezerBase = "https://api.deezer.com";
    public const string LastFmBase = "https://ws.audioscrobbler.com/2.0/";

    // ListenBrainz Labs' datasets: its own listens of late, and MLHD (2005–2013), which knows
    // far more of the music in Spanish (the cold test of phase 0).
    public const string RecentAlgorithm = "session_based_days_9000_session_300_contribution_5_threshold_15_limit_50_skip_30";
    public const string MlhdAlgorithm = "session_based_mlhd_session_300_contribution_5_threshold_15_limit_50_skip_30";
    public const string ArtistsAlgorithm = "session_based_days_7500_session_300_contribution_5_threshold_10_limit_100_filter_True_skip_30";

    /// <summary>The answers of the outside services are kept this long.</summary>
    public static readonly TimeSpan Keep = TimeSpan.FromDays(30);

    private static readonly string UserAgent = "kOS-TV-complemento/" +
        (typeof(KostvStationWeb).Assembly.GetName().Version?.ToString(3) ?? "0");

    private readonly IHttpClientFactory _http;
    private readonly KostvStationDiskCache _cache;
    private readonly ILogger _logger;
    private readonly ConcurrentDictionary<string, KostvRateGate> _gates = new(StringComparer.Ordinal);

    public KostvStationWeb(IHttpClientFactory http, KostvStationDiskCache cache, ILogger logger)
    {
        _http = http;
        _cache = cache;
        _logger = logger;
    }

    /// <summary>The household's ListenBrainz token (the panel's, optional), read each time.</summary>
    public Func<string?> ListenBrainzTokenOf { get; set; } = () => MoonfinPlugin.Instance?.Configuration?.KostvListenBrainzToken;

    /// <summary>The household's Last.fm key (the panel's, optional), read each time.</summary>
    public Func<string?> LastFmKeyOf { get; set; } = () => MoonfinPlugin.Instance?.Configuration?.KostvLastFmApiKey;

    /// <summary>The longest one request may take (MusicBrainz, which often doesn't answer, less).</summary>
    public TimeSpan RequestTimeout { get; set; } = TimeSpan.FromSeconds(8);

    /// <summary>The pace kept to <paramref name="service"/> (for tests, to change).</summary>
    public KostvRateGate GateOf(string service) => _gates.GetOrAdd(service, s => new KostvRateGate(KostvStationHosts.IntervalOf(s)));

    /// <summary>Whether a Last.fm key is in the panel.</summary>
    public bool HasLastFm => !string.IsNullOrWhiteSpace(LastFmKeyOf());

    /// <summary>A query string as Python's urlencode writes it (spaces as <c>+</c>).</summary>
    public static string Query(params (string Name, string Value)[] parameters) =>
        string.Join("&", parameters.Select(p => p.Name + "=" + Uri.EscapeDataString(p.Value).Replace("%20", "+", StringComparison.Ordinal)));

    /// <summary>
    /// The answer of <paramref name="url"/>: from the disk when kept, else asked at the service's
    /// pace and kept (also a 404 or an empty answer). Null, and not kept, when it didn't answer
    /// or said to wait (so it is asked again next time); <c>Failed</c> says so.
    /// </summary>
    public async Task<(JsonElement? Body, bool Failed)> GetAsync(
        string service,
        string url,
        CancellationToken cancellationToken,
        string? keyUrl = null,
        string? token = null)
    {
        var key = keyUrl ?? url;
        if (_cache.TryGet("respuestas", key, Keep, out var keptStatus, out var kept))
        {
            return (keptStatus == 200 ? kept : null, false);
        }

        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(service == KostvStationHosts.MusicBrainz ? TimeSpan.FromSeconds(Math.Min(4, RequestTimeout.TotalSeconds)) : RequestTimeout);
        try
        {
            await GateOf(service).WaitAsync(timeout.Token).ConfigureAwait(false);
            using var request = new HttpRequestMessage(HttpMethod.Get, url);
            request.Headers.TryAddWithoutValidation("User-Agent", UserAgent);
            request.Headers.TryAddWithoutValidation("Accept", "application/json");
            if (!string.IsNullOrWhiteSpace(token))
            {
                request.Headers.TryAddWithoutValidation("Authorization", "Token " + token.Trim());
            }

            using var client = _http.CreateClient();
            using var response = await client.SendAsync(request, timeout.Token).ConfigureAwait(false);
            var status = (int)response.StatusCode;
            if (response.StatusCode is HttpStatusCode.TooManyRequests or HttpStatusCode.ServiceUnavailable || status >= 500)
            {
                return (null, true);
            }

            var text = await response.Content.ReadAsStringAsync(timeout.Token).ConfigureAwait(false);
            JsonElement? body = null;
            if (status == 200 && !string.IsNullOrWhiteSpace(text))
            {
                using var document = JsonDocument.Parse(text);
                body = document.RootElement.Clone();
                // Deezer's «too many requests» comes as a 200 with its error code 4.
                if (service == KostvStationHosts.Deezer && ErrorCode(body.Value) is 4 or 700)
                {
                    return (null, true);
                }

                // Last.fm's: 11 (offline), 16 (temporary) and 29 (rate); a key not valid (10, 26) isn't kept either.
                if (service == KostvStationHosts.LastFm && ErrorCode(body.Value) is { } lastFmError && lastFmError is 10 or 11 or 16 or 26 or 29)
                {
                    _logger.LogInformation("kOS TV station: Last.fm said error {Code}", lastFmError);
                    return (null, true);
                }
            }

            if (status is 401 or 403)
            {
                return (null, true);
            }

            _cache.Put("respuestas", key, status, body);
            return (status == 200 ? body : null, false);
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            return (null, true);
        }
        catch (Exception ex) when (ex is HttpRequestException or JsonException or IOException)
        {
            _logger.LogDebug(ex, "kOS TV station: {Service} did not answer", service);
            return (null, true);
        }
    }

    private static int? ErrorCode(JsonElement body)
    {
        if (body.ValueKind != JsonValueKind.Object || !body.TryGetProperty("error", out var error))
        {
            return null;
        }

        if (error.ValueKind == JsonValueKind.Number && error.TryGetInt32(out var plain))
        {
            return plain;
        }

        return error.ValueKind == JsonValueKind.Object && error.TryGetProperty("code", out var code) && code.TryGetInt32(out var value) ? value : -1;
    }

    // ---------------------------------------------------------------- Deezer

    /// <summary>A song of Deezer's answer.</summary>
    public static KostvStationTrack? DeezerTrack(JsonElement track)
    {
        if (track.ValueKind != JsonValueKind.Object || ErrorCode(track) != null ||
            Number(track, "id") is not { } id || Text(track, "title") is not { } title ||
            !track.TryGetProperty("artist", out var artist) || Text(artist, "name") is not { } artistName)
        {
            return null;
        }

        var album = track.TryGetProperty("album", out var a) ? Text(a, "title") : null;
        bool? isExplicit = track.TryGetProperty("explicit_lyrics", out var e) && e.ValueKind is JsonValueKind.True or JsonValueKind.False ? e.GetBoolean() : null;
        return new KostvStationTrack(title, artistName, album, DeezerId: id, Explicit: isExplicit, ArtistDeezerId: Number(artist, "id"));
    }

    private static List<KostvStationTrack> DeezerTracks(JsonElement? body) =>
        body is { ValueKind: JsonValueKind.Object } b && b.TryGetProperty("data", out var data) && data.ValueKind == JsonValueKind.Array
            ? data.EnumerateArray().Select(DeezerTrack).OfType<KostvStationTrack>().ToList()
            : [];

    /// <summary>The ISRC and the year of a song of Deezer's answer.</summary>
    public static (string? Isrc, int? Year) DeezerTrackExtra(JsonElement? track) =>
        track is { ValueKind: JsonValueKind.Object } t ? (Text(t, "isrc"), KostvStationRecipe.YearOf(Text(t, "release_date"))) : (null, null);

    public async Task<(JsonElement? Track, bool Failed)> DeezerTrackAsync(string id, CancellationToken ct)
    {
        var (body, failed) = await GetAsync(KostvStationHosts.Deezer, $"{DeezerBase}/track/{Uri.EscapeDataString(id)}", ct).ConfigureAwait(false);
        return (body is { } b && DeezerTrack(b) != null ? b : null, failed);
    }

    /// <summary>The song of Deezer that a title and an artist are, as the seed: the same artist, its title begun alike.</summary>
    public async Task<(JsonElement? Track, bool Failed)> DeezerSeedAsync(string title, string artist, CancellationToken ct)
    {
        var failed = false;
        var wantArtist = KostvStationRecipe.Norm(artist);
        var wantTitle = KostvStationRecipe.NormTitle(title);
        var start = wantTitle[..Math.Min(12, wantTitle.Length)];
        foreach (var q in new[] { $"artist:\"{artist}\" track:\"{title}\"", $"{artist} {title}" })
        {
            var (body, f) = await GetAsync(KostvStationHosts.Deezer, $"{DeezerBase}/search/track?" + Query(("q", q), ("limit", "10")), ct).ConfigureAwait(false);
            failed |= f;
            var found = body is { ValueKind: JsonValueKind.Object } b && b.TryGetProperty("data", out var data) && data.ValueKind == JsonValueKind.Array
                ? data.EnumerateArray().Where(t => DeezerTrack(t) != null).ToList()
                : [];
            foreach (var t in found)
            {
                var track = DeezerTrack(t)!;
                if (KostvStationRecipe.Norm(track.Artist) == wantArtist && KostvStationRecipe.NormTitle(track.Title).StartsWith(start, StringComparison.Ordinal))
                {
                    return (t, failed);
                }
            }

            foreach (var t in found)
            {
                if (KostvStationRecipe.Norm(DeezerTrack(t)!.Artist).Contains(wantArtist, StringComparison.Ordinal))
                {
                    return (t, failed);
                }
            }
        }

        return (null, failed);
    }

    public async Task<(List<KostvStationTrack> Tracks, bool Failed)> DeezerArtistListAsync(string artistId, string list, int limit, CancellationToken ct)
    {
        var (body, failed) = await GetAsync(KostvStationHosts.Deezer, $"{DeezerBase}/artist/{Uri.EscapeDataString(artistId)}/{list}?limit={limit}", ct).ConfigureAwait(false);
        return (DeezerTracks(body), failed);
    }

    public async Task<(List<(string Id, string Name)> Artists, bool Failed)> DeezerRelatedAsync(string artistId, CancellationToken ct)
    {
        var (body, failed) = await GetAsync(KostvStationHosts.Deezer, $"{DeezerBase}/artist/{Uri.EscapeDataString(artistId)}/related?limit=50", ct).ConfigureAwait(false);
        var artists = body is { ValueKind: JsonValueKind.Object } b && b.TryGetProperty("data", out var data) && data.ValueKind == JsonValueKind.Array
            ? data.EnumerateArray()
                .Select(a => (Id: Number(a, "id"), Name: Text(a, "name")))
                .Where(a => a.Id != null && a.Name != null)
                .Select(a => (a.Id!, a.Name!))
                .ToList()
            : [];
        return (artists, failed);
    }

    /// <summary>
    /// The song of Deezer a candidate by listening is: by its ISRCs first (the first three), then
    /// by searching its title and first artist; it must have its title and one of its artists.
    /// </summary>
    public async Task<(KostvStationTrack? Track, bool Failed)> DeezerMatchAsync(string title, string artist, IReadOnlyList<string> isrcs, CancellationToken ct)
    {
        var failed = false;
        var names = KostvStationRecipe.CreditNames(artist).ToHashSet(StringComparer.Ordinal);
        var wantTitle = KostvStationRecipe.NormTitle(title);
        bool Same(KostvStationTrack t, bool byIsrc) =>
            KostvStationRecipe.CreditNames(t.Artist).Any(names.Contains) &&
            (byIsrc || KostvStationRecipe.NormTitle(t.Title) == wantTitle);

        foreach (var isrc in isrcs.Where(i => !string.IsNullOrWhiteSpace(i)).Take(3))
        {
            var (body, f) = await GetAsync(KostvStationHosts.Deezer, $"{DeezerBase}/track/isrc:{Uri.EscapeDataString(isrc)}", ct).ConfigureAwait(false);
            failed |= f;
            if (body is { } b && DeezerTrack(b) is { } track && (Same(track, byIsrc: true) || KostvStationRecipe.NormTitle(track.Title) == wantTitle))
            {
                return (track, failed);
            }
        }

        // Deezer's search finds nothing without the accents: as written, without what goes in brackets.
        var main = KostvStationRecipe.PrimaryAsWritten(artist);
        var clean = KostvStationRecipe.TitleAsWritten(title);
        foreach (var q in new[] { $"artist:\"{main}\" track:\"{clean}\"", $"{main} {clean}" })
        {
            var (body, f) = await GetAsync(KostvStationHosts.Deezer, $"{DeezerBase}/search/track?" + Query(("q", q), ("limit", "10")), ct).ConfigureAwait(false);
            failed |= f;
            if (DeezerTracks(body).FirstOrDefault(t => Same(t, byIsrc: false)) is { } track)
            {
                return (track, failed);
            }
        }

        return (null, failed);
    }

    // ---------------------------------------------------------------- ListenBrainz and MusicBrainz

    /// <summary>
    /// The recordings of MusicBrainz a song may be, as ListenBrainz matches its listens: by the
    /// name of its artist and its title, and by searching them.
    /// </summary>
    public async Task<(List<string> Mbids, bool Failed)> RecordingsOfAsync(string title, string artist, CancellationToken ct)
    {
        var lookup = GetAsync(KostvStationHosts.ListenBrainzLabs, $"{LabsBase}/acr-lookup/json?" + Query(("artist_credit_name", artist), ("recording_name", title)), ct);
        var search = GetAsync(KostvStationHosts.ListenBrainzLabs, $"{LabsBase}/recording-search/json?" + Query(("query", $"{title} {artist}")), ct);
        var (byName, f1) = await lookup.ConfigureAwait(false);
        var (found, f2) = await search.ConfigureAwait(false);
        var mbids = new List<string>();
        foreach (var r in Array(byName))
        {
            if (Text(r, "recording_mbid") is { } mbid && !mbids.Contains(mbid))
            {
                mbids.Add(mbid);
            }
        }

        var wantArtist = KostvStationRecipe.Norm(artist);
        var wantTitle = KostvStationRecipe.NormTitle(title);
        foreach (var r in Array(found))
        {
            if (Text(r, "recording_mbid") is { } mbid && !mbids.Contains(mbid) &&
                KostvStationRecipe.Norm(Text(r, "artist_credit_name")).Contains(wantArtist, StringComparison.Ordinal) &&
                KostvStationRecipe.NormTitle(Text(r, "recording_name")) == wantTitle)
            {
                mbids.Add(mbid);
            }
        }

        return (mbids, f1 || f2);
    }

    /// <summary>The recordings of MusicBrainz with an ISRC (MusicBrainz, at 1 a second, often busy).</summary>
    public async Task<(List<string> Mbids, bool Failed)> RecordingsOfIsrcAsync(string isrc, CancellationToken ct)
    {
        var (body, failed) = await GetAsync(KostvStationHosts.MusicBrainz, $"{MusicBrainzBase}/isrc/{Uri.EscapeDataString(isrc)}?fmt=json", ct).ConfigureAwait(false);
        var mbids = body is { ValueKind: JsonValueKind.Object } b && b.TryGetProperty("recordings", out var list)
            ? Array(list).Select(r => Text(r, "id")).OfType<string>().ToList()
            : [];
        return (mbids, failed);
    }

    /// <summary>
    /// The recordings heard in the same sessions as <paramref name="mbid"/>, in one of ListenBrainz
    /// Labs' datasets; their score made 1 for the most like, so both datasets can be put together.
    /// </summary>
    public async Task<(List<KostvStationTrack> Tracks, bool Failed)> SimilarRecordingsAsync(string mbid, bool mlhd, CancellationToken ct)
    {
        var path = mlhd ? "/mlhd-similar-recordings/json" : "/similar-recordings/json";
        var (body, failed) = await GetAsync(
            KostvStationHosts.ListenBrainzLabs,
            $"{LabsBase}{path}?" + Query(("recording_mbids", mbid), ("algorithm", mlhd ? MlhdAlgorithm : RecentAlgorithm)),
            ct).ConfigureAwait(false);
        var rows = Array(body).ToList();
        var top = rows.Select(r => Double(r, "score") ?? 0).DefaultIfEmpty(0).Max();
        if (top <= 0)
        {
            top = 1;
        }

        var tracks = rows
            .Select(r => (Mbid: Text(r, "recording_mbid"), Title: Text(r, "recording_name"), Artist: Text(r, "artist_credit_name"), Album: Text(r, "release_name"), Score: Double(r, "score") ?? 0))
            .Where(r => r.Mbid != null && r.Title != null && r.Artist != null)
            .Select(r => new KostvStationTrack(r.Title!, r.Artist!, r.Album, r.Mbid, Score: Math.Round(r.Score / top, 4)))
            .ToList();
        return (tracks, failed);
    }

    /// <summary>The artists heard in the same sessions as <paramref name="artistMbid"/>, by name.</summary>
    public async Task<(List<string> Names, bool Failed)> SimilarArtistsAsync(string artistMbid, CancellationToken ct)
    {
        var (body, failed) = await GetAsync(
            KostvStationHosts.ListenBrainzLabs,
            $"{LabsBase}/similar-artists/json?" + Query(("artist_mbids", artistMbid), ("algorithm", ArtistsAlgorithm)),
            ct).ConfigureAwait(false);
        return (Array(body).Select(r => Text(r, "name")).OfType<string>().Take(50).ToList(), failed);
    }

    /// <summary>What MusicBrainz knows of some recordings (ListenBrainz's metadata, up to 25 at once).</summary>
    public async Task<(Dictionary<string, (KostvStationRecordingInfo Info, string? ArtistName)> Recordings, bool Failed)> RecordingInfoAsync(IReadOnlyList<string> mbids, CancellationToken ct)
    {
        var result = new Dictionary<string, (KostvStationRecordingInfo, string?)>(StringComparer.Ordinal);
        var failed = false;
        var token = ListenBrainzTokenOf();
        foreach (var chunk in mbids.Distinct(StringComparer.Ordinal).Chunk(25))
        {
            var url = $"{ListenBrainzBase}/metadata/recording/?" + Query(("recording_mbids", string.Join(",", chunk)), ("inc", "artist tag"));
            var (body, f) = await GetAsync(KostvStationHosts.ListenBrainz, url, ct, token: token).ConfigureAwait(false);
            failed |= f;
            if (body is not { ValueKind: JsonValueKind.Object } b)
            {
                continue;
            }

            foreach (var entry in b.EnumerateObject())
            {
                result[entry.Name] = RecordingInfo(entry.Value);
            }
        }

        return (result, failed);
    }

    private static (KostvStationRecordingInfo Info, string? ArtistName) RecordingInfo(JsonElement value)
    {
        var recording = value.TryGetProperty("recording", out var r) ? r : default;
        var year = recording.ValueKind == JsonValueKind.Object ? KostvStationRecipe.YearOf(Text(recording, "first_release_date")) : null;
        var isrcs = recording.ValueKind == JsonValueKind.Object && recording.TryGetProperty("isrcs", out var i)
            ? Array(i).Where(x => x.ValueKind == JsonValueKind.String).Select(x => x.GetString()!).ToList()
            : [];
        var artist = value.TryGetProperty("artist", out var a) ? a : default;
        var artistMbids = artist.ValueKind == JsonValueKind.Object && artist.TryGetProperty("artists", out var list)
            ? Array(list).Select(x => Text(x, "artist_mbid")).OfType<string>().ToList()
            : [];
        var counts = new Dictionary<string, double>(StringComparer.Ordinal);
        if (value.TryGetProperty("tag", out var tag) && tag.ValueKind == JsonValueKind.Object && tag.TryGetProperty("artist", out var artistTags))
        {
            foreach (var t in Array(artistTags))
            {
                if (KostvStationRecipe.StyleTag(Text(t, "tag")) is { } style)
                {
                    counts[style] = counts.GetValueOrDefault(style) + Math.Max(1, Double(t, "count") ?? 1);
                }
            }
        }

        return (new KostvStationRecordingInfo(year, isrcs, artistMbids, KostvStationRecipe.StrongTags(counts)), artist.ValueKind == JsonValueKind.Object ? Text(artist, "name") : null);
    }

    // ---------------------------------------------------------------- Last.fm (only with a key)

    /// <summary>Last.fm's songs like a song (<c>track.getSimilar</c>); nothing without a key in the panel.</summary>
    public async Task<(List<KostvStationTrack> Tracks, bool Failed)> LastFmSimilarAsync(string title, string artist, CancellationToken ct)
    {
        var key = LastFmKeyOf()?.Trim();
        if (string.IsNullOrEmpty(key))
        {
            return ([], false);
        }

        var query = Query(("method", "track.getsimilar"), ("artist", artist), ("track", title), ("autocorrect", "1"), ("limit", "100"), ("format", "json"));
        // Kept by the song, not by the key (so the key isn't written on the disk).
        var (body, failed) = await GetAsync(KostvStationHosts.LastFm, LastFmBase + "?" + query + "&" + Query(("api_key", key)), ct, keyUrl: LastFmBase + "?" + query).ConfigureAwait(false);
        var tracks = new List<KostvStationTrack>();
        if (body is { ValueKind: JsonValueKind.Object } b && b.TryGetProperty("similartracks", out var similar) && similar.ValueKind == JsonValueKind.Object &&
            similar.TryGetProperty("track", out var list))
        {
            foreach (var t in Array(list))
            {
                var name = Text(t, "name");
                var by = t.TryGetProperty("artist", out var a) ? Text(a, "name") : null;
                var match = Double(t, "match") ?? 0;
                if (name != null && by != null)
                {
                    var mbid = Text(t, "mbid");
                    tracks.Add(new KostvStationTrack(name, by, Mbid: string.IsNullOrWhiteSpace(mbid) ? null : mbid, Score: Math.Round(match, 4)));
                }
            }
        }

        return (tracks, failed);
    }

    // ---------------------------------------------------------------- reading JSON

    private static IEnumerable<JsonElement> Array(JsonElement? value) =>
        value is { ValueKind: JsonValueKind.Array } list ? list.EnumerateArray() : [];

    private static string? Text(JsonElement value, string name) =>
        value.ValueKind == JsonValueKind.Object && value.TryGetProperty(name, out var p) && p.ValueKind == JsonValueKind.String && !string.IsNullOrWhiteSpace(p.GetString())
            ? p.GetString()!.Trim()
            : null;

    private static string? Number(JsonElement value, string name)
    {
        if (value.ValueKind != JsonValueKind.Object || !value.TryGetProperty(name, out var p))
        {
            return null;
        }

        return p.ValueKind switch
        {
            JsonValueKind.Number when p.TryGetInt64(out var n) && n > 0 => n.ToString(CultureInfo.InvariantCulture),
            JsonValueKind.String when KostvMusicEvent.IsDeezerId(p.GetString()) => p.GetString(),
            _ => null
        };
    }

    private static double? Double(JsonElement value, string name)
    {
        if (value.ValueKind != JsonValueKind.Object || !value.TryGetProperty(name, out var p))
        {
            return null;
        }

        return p.ValueKind switch
        {
            JsonValueKind.Number => p.GetDouble(),
            JsonValueKind.String when double.TryParse(p.GetString(), NumberStyles.Float, CultureInfo.InvariantCulture, out var d) => d,
            _ => null
        };
    }
}
