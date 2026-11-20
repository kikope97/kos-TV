using System.Text.Json;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Library;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Moonfin.Server.Api;
using Moonfin.Server.Helpers;
using Moonfin.Server.Services;

namespace Moonfin.Server.Kostv;

/// <summary>
/// kOS TV: each person's music: whether what they listen to is kept, where what they play comes
/// from, their daily mixes, «Descubrimiento semanal» and the mix for the time of day.
/// </summary>
[ApiController]
[Route("Moonfin/Kostv/Music")]
[Produces("application/json")]
public class KostvMusicController : ControllerBase
{
    private static readonly JsonSerializerOptions OutputOptions = new()
    {
        // As declared (PascalCase, as the server's own), and nulls written: "Songs": null.
        PropertyNamingPolicy = null,
        Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping
    };

    private readonly KostvMusicService _music;
    private readonly KostvMusicContext _context;
    private readonly ILibraryManager _library;
    private readonly ItemCardDtoMapper _cards;

    public KostvMusicController(KostvMusicService music, KostvMusicContext context, ILibraryManager library, ItemCardDtoMapper cards)
    {
        _music = music;
        _context = context;
        _library = library;
        _cards = cards;
    }

    private KostvMusicStore Store => _music.Store;

    private (Guid Id, object User)? Caller()
    {
        var userId = this.GetUserIdFromClaims();
        var user = userId.HasValue ? UserReflection.ResolveUser(HttpContext.RequestServices, userId.Value) : null;
        return userId.HasValue && user != null ? (userId.Value, user) : null;
    }

    private ActionResult NotSignedIn() => Unauthorized(new { Error = "User not authenticated" });

    private object SettingsOf(Guid userId)
    {
        var summary = Store.Summary(userId);
        return new
        {
            Learn = Store.Learns(userId),
            summary.Listens,
            Since = summary.Since is { } since ? DateTime.SpecifyKind(since.UtcDateTime.AddTicks(-(since.UtcDateTime.Ticks % TimeSpan.TicksPerSecond)), DateTimeKind.Utc) : (DateTime?)null
        };
    }

    /// <summary>Whether what the caller listens to is kept, how many listens there are and since when.</summary>
    [HttpGet("Settings")]
    [Authorize]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public ActionResult GetSettings()
    {
        return Caller() is { } caller ? Ok(SettingsOf(caller.Id)) : NotSignedIn();
    }

    /// <summary>Turns keeping what the caller listens to on or off (<c>{ "Learn": false }</c>).</summary>
    [HttpPost("Settings")]
    [Authorize]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    public ActionResult SetSettings([FromBody] JsonElement body)
    {
        if (Caller() is not { } caller)
        {
            return NotSignedIn();
        }

        if (Property(body, "Learn") is not { ValueKind: JsonValueKind.True or JsonValueKind.False } learn)
        {
            return BadRequest(new { Error = "Learn must be true or false." });
        }

        Store.SetLearn(caller.Id, learn.GetBoolean());
        _music.Forget(caller.Id);
        return Ok(SettingsOf(caller.Id));
    }

    /// <summary>Forgets everything the caller listened to.</summary>
    [HttpDelete("Listens")]
    [Authorize]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    public ActionResult DeleteListens()
    {
        if (Caller() is not { } caller)
        {
            return NotSignedIn();
        }

        Store.DeleteListens(caller.Id);
        _context.Forget(caller.Id);
        _music.Forget(caller.Id);
        return NoContent();
    }

    /// <summary>
    /// Where the songs the caller is about to play come from
    /// (<c>{ "Source": "mix:daily-2", "ItemIds": [...] }</c>), noted with their listens for 6 hours.
    /// </summary>
    [HttpPost("Context")]
    [Authorize]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    public ActionResult SetContext([FromBody] JsonElement body)
    {
        if (Caller() is not { } caller)
        {
            return NotSignedIn();
        }

        var source = KostvMusicContext.Normalize(Property(body, "Source") is { ValueKind: JsonValueKind.String } s ? s.GetString() : null);
        if (source == null || Property(body, "ItemIds") is not { ValueKind: JsonValueKind.Array } list)
        {
            return BadRequest(new { Error = "Source and ItemIds are needed." });
        }

        var ids = list.EnumerateArray()
            .Take(KostvMusicContext.MaxItems)
            .Select(e => e.ValueKind == JsonValueKind.String && Guid.TryParse(e.GetString(), out var id) ? id : Guid.Empty)
            .Where(id => id != Guid.Empty)
            .ToList();
        _context.Remember(caller.Id, source, ids, Store.Now);
        return NoContent();
    }

    /// <summary>The caller's daily mixes: up to four of about 50 songs, the same all day.</summary>
    [HttpGet("Mixes")]
    [Authorize]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public async Task<ActionResult> Mixes()
    {
        if (Caller() is not { } caller)
        {
            return NotSignedIn();
        }

        var day = _music.Day;
        var mixes = await _music.MixesAsync(caller.Id, caller.User).ConfigureAwait(false);
        var result = new List<object>();
        foreach (var mix in mixes)
        {
            var items = Cards(mix.Items, caller.User);
            if (items.Count == 0)
            {
                continue;
            }

            var artists = _music.ArtistsByName(mix.Artists);
            result.Add(new
            {
                mix.Id,
                mix.Genre,
                Artists = mix.Artists
                    .Select(name => artists.GetValueOrDefault(name))
                    .Where(a => a != null && UserReflection.IsVisibleStandaloneTo(a, caller.User))
                    .Select(a => _cards.Map(a!, caller.User))
                    .ToList(),
                Items = items
            });
        }

        return Ok(new { Day = day, Mixes = result });
    }

    /// <summary>
    /// For «Descubrimiento semanal»: the week, the artists to ask for songs like theirs, and the
    /// week's list once the app stored it (<c>Songs</c>, null until then).
    /// </summary>
    [HttpGet("Discovery")]
    [Authorize]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public async Task<ActionResult> GetDiscovery()
    {
        if (Caller() is not { } caller)
        {
            return NotSignedIn();
        }

        var week = _music.Week;
        var seeds = await _music.SeedsAsync(caller.Id, caller.User).ConfigureAwait(false);
        var songs = _music.DiscoverySongs(caller.Id);
        var json = JsonSerializer.Serialize(new { Week = week, Seeds = seeds, Songs = songs }, OutputOptions);
        return Content(json, "application/json");
    }

    /// <summary>
    /// Stores the app's list for this week (<c>{ "Week": "2026-W47", "Songs": [...] }</c>, up to 30
    /// songs and 64 KB, as Stremfin gives them), so every device shows the same.
    /// </summary>
    [HttpPut("Discovery")]
    [Authorize]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status409Conflict)]
    [ProducesResponseType(StatusCodes.Status413PayloadTooLarge)]
    public async Task<ActionResult> SetDiscovery()
    {
        if (Caller() is not { } caller)
        {
            return NotSignedIn();
        }

        // Read here rather than bound, so a body past the limit is turned away unread.
        var buffer = new MemoryStream();
        var chunk = new byte[8192];
        int read;
        while ((read = await Request.Body.ReadAsync(chunk, HttpContext.RequestAborted).ConfigureAwait(false)) > 0)
        {
            buffer.Write(chunk, 0, read);
            if (buffer.Length > KostvMusicStore.MaxDiscoveryBytes)
            {
                return StatusCode(StatusCodes.Status413PayloadTooLarge, new { Error = "The list is over 64 KB." });
            }
        }

        JsonElement body;
        try
        {
            using var document = JsonDocument.Parse(buffer.ToArray());
            body = document.RootElement.Clone();
        }
        catch (JsonException)
        {
            return BadRequest(new { Error = "The body is not JSON." });
        }

        var week = Property(body, "Week") is { ValueKind: JsonValueKind.String } w ? w.GetString() : null;
        var songs = Property(body, "Songs") ?? default;
        return Store.SetDiscovery(caller.Id, week, songs, _music.Week) switch
        {
            KostvMusicStore.DiscoveryRefusal.None => NoContent(),
            KostvMusicStore.DiscoveryRefusal.NotThisWeek => Conflict(new { Error = "Only this week's list can be stored.", Week = _music.Week }),
            KostvMusicStore.DiscoveryRefusal.TooMany => BadRequest(new { Error = "Up to 30 songs." }),
            KostvMusicStore.DiscoveryRefusal.TooLarge => StatusCode(StatusCodes.Status413PayloadTooLarge, new { Error = "The list is over 64 KB." }),
            _ => BadRequest(new { Error = "Songs must be a list." })
        };
    }

    /// <summary>
    /// The mix for the time of day it is at home (<c>manana</c>, <c>tarde</c> or <c>noche</c>):
    /// <c>Ready</c> false, without <c>Items</c>, until the caller has listened enough at this time.
    /// </summary>
    [HttpGet("Moment")]
    [Authorize]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public async Task<ActionResult> Moment()
    {
        if (Caller() is not { } caller)
        {
            return NotSignedIn();
        }

        var moment = await _music.MomentAsync(caller.Id, caller.User).ConfigureAwait(false);
        var items = moment.Ready ? Cards(moment.Items, caller.User) : [];
        if (items.Count == 0)
        {
            return Ok(new { moment.Slot, Ready = false });
        }

        return Ok(new { moment.Slot, Ready = true, Items = items });
    }

    private List<object> Cards(IEnumerable<Guid> ids, object user) =>
        ids.Select(id => _library.GetItemById(id))
            .Where(item => item != null && UserReflection.IsVisibleStandaloneTo(item, user))
            .Select(item => _cards.Map(item!, user))
            .ToList();

    /// <summary>A property of <paramref name="body"/>, its name in any case.</summary>
    private static JsonElement? Property(JsonElement body, string name)
    {
        if (body.ValueKind != JsonValueKind.Object)
        {
            return null;
        }

        foreach (var property in body.EnumerateObject())
        {
            if (string.Equals(property.Name, name, StringComparison.OrdinalIgnoreCase))
            {
                return property.Value;
            }
        }

        return null;
    }
}
