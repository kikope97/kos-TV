using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Moonfin.Server.Api;
using Moonfin.Server.Helpers;
using Moonfin.Server.Services;

namespace Moonfin.Server.Kostv;

/// <summary>
/// kOS TV: the station of a song, for «Crear emisora» and ∞ (see <see cref="KostvMusicStation"/>
/// and <c>docs/musica-radio.md</c>, «Contrato de la emisora»).
/// </summary>
[ApiController]
[Route("Moonfin/Kostv/Music")]
[Produces("application/json")]
public class KostvStationController : ControllerBase
{
    /// <summary>How many songs a station has when the app doesn't say.</summary>
    public const int DefaultLimit = 50;

    private const int MaxTextLength = 200;

    private static readonly JsonSerializerOptions OutputOptions = new()
    {
        // As declared (PascalCase, as the server's own), and nulls written: "Card": null.
        PropertyNamingPolicy = null,
        Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping
    };

    private readonly KostvMusicStation _station;
    private readonly IKostvStationLibrary _library;
    private readonly KostvStationWeb _web;
    private readonly ItemCardDtoMapper _cards;

    public KostvStationController(KostvMusicStation station, IKostvStationLibrary library, KostvStationWeb web, ItemCardDtoMapper cards)
    {
        _station = station;
        _library = library;
        _web = web;
        _cards = cards;
    }

    /// <summary>
    /// The station of <c>seed</c> (a song's id at home, or <c>stremfin:&lt;DeezerId&gt;</c> with its
    /// <c>title</c> and <c>artist</c>, which help): <c>{ "Seed": { "Title", "Artist", "Mbid" },
    /// "Items": [ { "Card", "Away": { "Title", "Artist", "Album", "DeezerId", "Explicit" }, "Why" } ],
    /// "Source" }</c>, up to <c>limit</c> songs (50; 1 to 100), only those at home with
    /// <c>away=false</c>. A seed at home the caller may not see counts by its <c>title</c> and
    /// <c>artist</c>; without them, as one that can't be told, an empty station (<c>fallback</c>),
    /// never a <c>404</c> (what an older plugin answers). A seed not so is a <c>400</c>.
    /// </summary>
    [HttpGet("Station")]
    [Authorize]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    public async Task<ActionResult> Station(
        [FromQuery] string? seed,
        [FromQuery] string? title,
        [FromQuery] string? artist,
        [FromQuery] int? limit,
        [FromQuery] bool? away)
    {
        var userId = this.GetUserIdFromClaims();
        var user = userId.HasValue ? UserReflection.ResolveUser(HttpContext.RequestServices, userId.Value) : null;
        if (!userId.HasValue || user == null)
        {
            return Unauthorized(new { Error = "User not authenticated" });
        }

        title = Clean(title);
        artist = Clean(artist);
        KostvStationSeed? from;
        var said = seed?.Trim();
        if (KostvMusicEvent.DeezerIdOf(said) is { } deezerId)
        {
            from = title != null && artist != null
                ? new KostvStationSeed(title, artist, DeezerId: deezerId)
                : await FromDeezerAsync(deezerId, title, artist).ConfigureAwait(false);
        }
        else if (Guid.TryParse(said, out var id) && id != Guid.Empty)
        {
            // One the caller may not see (or gone) counts as not at home, by what the app said of it.
            from = _library.Seed(user, id) is { } song
                ? new KostvStationSeed(song.Title, song.Artists[0], HomeId: song.Id, Mbid: song.Mbid)
                : title != null && artist != null ? new KostvStationSeed(title, artist) : null;
        }
        else
        {
            return BadRequest(new { Error = "seed is a song's id, or stremfin:<DeezerId>." });
        }

        // Kos TV: a song that can't be told is an empty station, not a 404 (which says the plugin is old).
        if (from == null)
        {
            return Content(
                JsonSerializer.Serialize(new { Seed = new { Title = title, Artist = artist, Mbid = (string?)null }, Items = Array.Empty<object>(), Source = KostvStationSource.Fallback }, OutputOptions),
                "application/json");
        }

        var result = await _station.StationAsync(userId.Value, user, from, limit ?? DefaultLimit, away ?? true, HttpContext.RequestAborted).ConfigureAwait(false);
        var json = JsonSerializer.Serialize(
            new
            {
                Seed = new { result.Seed.Title, result.Seed.Artist, Mbid = result.SeedMbid },
                Items = result.Items.Select(i => new
                {
                    Card = i.Home != null ? _cards.Map(i.Home, user) : null,
                    Away = i.Away != null ? new { i.Away.Title, i.Away.Artist, i.Away.Album, i.Away.DeezerId, i.Away.Explicit } : null,
                    i.Why
                }).ToList(),
                result.Source
            },
            OutputOptions);
        return Content(json, "application/json");
    }

    private async Task<KostvStationSeed?> FromDeezerAsync(string deezerId, string? title, string? artist)
    {
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(HttpContext.RequestAborted);
        timeout.CancelAfter(_station.Deadline);
        try
        {
            var (track, _) = await _web.DeezerTrackAsync(deezerId, timeout.Token).ConfigureAwait(false);
            return track is { } t && KostvStationWeb.DeezerTrack(t) is { } found
                ? new KostvStationSeed(title ?? found.Title, artist ?? found.Artist, DeezerId: deezerId)
                : null;
        }
        catch (OperationCanceledException)
        {
            return null;
        }
    }

    private static string? Clean(string? text)
    {
        text = text?.Trim();
        if (string.IsNullOrEmpty(text))
        {
            return null;
        }

        // Not halfway through a character outside the basic plane.
        return text.Length > MaxTextLength ? text[..(char.IsHighSurrogate(text[MaxTextLength - 1]) ? MaxTextLength - 1 : MaxTextLength)].TrimEnd() : text;
    }
}
