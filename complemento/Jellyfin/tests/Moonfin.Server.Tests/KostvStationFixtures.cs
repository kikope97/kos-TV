using System.Collections.Concurrent;
using System.Net;
using System.Runtime.CompilerServices;
using System.Text;
using System.Text.Json;
using Jellyfin.Data.Entities;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Entities.Audio;
using Moonfin.Server.Kostv;

namespace Moonfin.Server.Tests;

/// <summary>
/// kOS TV: the outside services of the stations, answered from recorded answers (no network in
/// the tests). The recordings in <c>Fixtures/Station</c> are real answers of the public APIs
/// (Deezer, ListenBrainz, MusicBrainz) for a few seeds of the cold test of phase 0, trimmed to
/// what the plugin reads. ListenBrainz's metadata of several recordings at once is put together
/// from the recordings of each. What isn't recorded answers 404.
/// </summary>
internal sealed class StationHttp : HttpMessageHandler
{
    private readonly Dictionary<string, (int Status, string? Body)> _records = new(StringComparer.Ordinal);

    public ConcurrentQueue<HttpRequestMessage> Requests { get; } = new();

    public ConcurrentQueue<string> Missing { get; } = new();

    /// <summary>Hosts that don't answer (a 503).</summary>
    public HashSet<string> Down { get; } = new(StringComparer.Ordinal);

    /// <summary>Hosts that take this long to answer.</summary>
    public Dictionary<string, TimeSpan> Slow { get; } = new(StringComparer.Ordinal);

    public static string FixturesDir([CallerFilePath] string here = "") => Path.Combine(Path.GetDirectoryName(here)!, "Fixtures", "Station");

    public static StationHttp FromPacks(params string[] packs)
    {
        var http = new StationHttp();
        foreach (var pack in packs)
        {
            http.Load(Path.Combine(FixturesDir(), pack + ".json"));
        }

        return http;
    }

    public void Load(string path)
    {
        using var document = JsonDocument.Parse(File.ReadAllText(path));
        foreach (var record in document.RootElement.EnumerateObject())
        {
            var status = record.Value.GetProperty("status").GetInt32();
            var body = record.Value.TryGetProperty("body", out var b) && b.ValueKind != JsonValueKind.Null ? b.GetRawText() : null;
            _records[record.Name] = (status, body);
        }
    }

    public void Add(string url, int status, string? body) => _records[url] = (status, body);

    public int CountTo(string host) => Requests.Count(r => r.RequestUri!.Host == host);

    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        Requests.Enqueue(request);
        var url = request.RequestUri!.OriginalString;
        var host = request.RequestUri.Host;
        if (Slow.TryGetValue(host, out var delay))
        {
            await Task.Delay(delay, cancellationToken).ConfigureAwait(false);
        }

        if (Down.Contains(host))
        {
            return new HttpResponseMessage(HttpStatusCode.ServiceUnavailable);
        }

        if (!_records.TryGetValue(url, out var record) && Compose(url) is { } composed)
        {
            record = (200, composed);
        }
        else if (!_records.ContainsKey(url))
        {
            Missing.Enqueue(url);
            return new HttpResponseMessage(HttpStatusCode.NotFound);
        }

        return new HttpResponseMessage((HttpStatusCode)record.Status)
        {
            Content = new StringContent(record.Body ?? string.Empty, Encoding.UTF8, "application/json")
        };
    }

    // ListenBrainz's metadata of several recordings: from the recordings of each.
    private string? Compose(string url)
    {
        const string start = KostvStationWeb.ListenBrainzBase + "/metadata/recording/?recording_mbids=";
        if (!url.StartsWith(start, StringComparison.Ordinal))
        {
            return null;
        }

        var rest = url[start.Length..];
        var ids = Uri.UnescapeDataString(rest[..rest.IndexOf('&', StringComparison.Ordinal)]).Split(',');
        var parts = new List<string>();
        foreach (var id in ids)
        {
            var single = start + id + "&inc=artist+tag";
            if (_records.TryGetValue(single, out var one) && one.Body != null)
            {
                using var document = JsonDocument.Parse(one.Body);
                parts.AddRange(document.RootElement.EnumerateObject().Select(p => JsonSerializer.Serialize(p.Name) + ":" + p.Value.GetRawText()));
            }
        }

        return "{" + string.Join(",", parts) + "}";
    }
}

internal sealed class StationHttpFactory(HttpMessageHandler handler) : IHttpClientFactory
{
    public HttpClient CreateClient(string name) => new(handler, disposeHandler: false);
}

/// <summary>A library for the stations: its songs, and who may see which.</summary>
internal sealed class StationLibrary : IKostvStationLibrary
{
    public List<Audio> Songs { get; } = [];

    public HashSet<(Guid User, Guid Item)> Hidden { get; } = [];

    public int Reads { get; private set; }

    public Audio Add(string title, string artist, string? mbid = null, string? album = null)
    {
        var song = new Audio { Id = Guid.NewGuid(), Name = title, Artists = [artist], Album = album };
        if (mbid != null)
        {
            song.ProviderIds = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase) { ["MusicBrainzTrack"] = mbid };
        }

        Songs.Add(song);
        return song;
    }

    public KostvStationHomeSong? Seed(object user, Guid id) =>
        Visible(user, [id]).Select(KostvStationLibrary.SongOf).FirstOrDefault(s => s != null);

    public IReadOnlyList<KostvStationHomeSong> SongsBy(string artist)
    {
        Reads++;
        var key = KostvStationRecipe.Norm(artist);
        return Songs.Where(s => s.Artists.Any(a => KostvStationRecipe.Norm(a) == key)).Select(KostvStationLibrary.SongOf).OfType<KostvStationHomeSong>().ToList();
    }

    public IReadOnlyList<BaseItem> Visible(object user, IReadOnlyList<Guid> ids)
    {
        var userId = ((User)user).Id;
        return ids.Select(id => Songs.FirstOrDefault(s => s.Id == id)).OfType<Audio>().Where(s => !Hidden.Contains((userId, s.Id))).ToList<BaseItem>();
    }
}
