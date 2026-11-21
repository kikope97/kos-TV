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
/// from, what they do that the server doesn't see, what they don't want to hear («no me gusta»),
/// their taste, their daily mixes, «Descubrimiento semanal» and the mix for the time of day (each
/// noted as shown the first time in its day or week).
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
    private readonly ItemCardDtoMapper _cards;

    public KostvMusicController(KostvMusicService music, KostvMusicContext context, ItemCardDtoMapper cards)
    {
        _music = music;
        _context = context;
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
            Catalog = Store.Catalog(userId),
            summary.Listens,
            Since = summary.Since is { } since ? DateTime.SpecifyKind(since.UtcDateTime.AddTicks(-(since.UtcDateTime.Ticks % TimeSpan.TicksPerSecond)), DateTimeKind.Utc) : (DateTime?)null
        };
    }

    /// <summary>
    /// Whether what the caller listens to is kept, what music the app offers them
    /// (<c>Catalog</c>: <c>all</c>, by default, or <c>home</c>), how many listens there are and
    /// since when.
    /// </summary>
    [HttpGet("Settings")]
    [Authorize]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public ActionResult GetSettings()
    {
        return Caller() is { } caller ? Ok(SettingsOf(caller.Id)) : NotSignedIn();
    }

    /// <summary>
    /// Turns keeping what the caller listens to on or off (<c>{ "Learn": false }</c>), or chooses
    /// what music the app offers them (<c>{ "Catalog": "home" }</c>), or both; what isn't said
    /// stays as it was.
    /// </summary>
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

        var learnSaid = Property(body, "Learn");
        var catalogSaid = Property(body, "Catalog");
        if (learnSaid == null && catalogSaid == null)
        {
            return BadRequest(new { Error = "Learn (true or false) or Catalog (all or home) is needed." });
        }

        bool? learn = null;
        if (learnSaid is { } l)
        {
            if (l.ValueKind is not (JsonValueKind.True or JsonValueKind.False))
            {
                return BadRequest(new { Error = "Learn must be true or false." });
            }

            learn = l.GetBoolean();
        }

        string? catalog = null;
        if (catalogSaid is { } c)
        {
            catalog = c.ValueKind == JsonValueKind.String ? KostvMusicCatalog.Normalize(c.GetString()) : null;
            if (catalog == null)
            {
                return BadRequest(new { Error = "Catalog must be all or home." });
            }
        }

        Store.SetSettings(caller.Id, learn, catalog);
        if (learn.HasValue)
        {
            _music.Forget(caller.Id);
        }

        return Ok(SettingsOf(caller.Id));
    }

    /// <summary>Forgets everything the caller listened to, and their taste worked out of it; «no me gusta» and the settings stay.</summary>
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
        // A daily mix's id is its place that day: its genre is noted too, to tell the mixes apart later.
        var mixGenre = source.StartsWith("mix:", StringComparison.Ordinal) ? _music.MixGenreOf(caller.Id, source["mix:".Length..]) : null;
        _context.Remember(caller.Id, source, ids, Store.Now, mixGenre);
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
        // «No me gusta» goes out as it is served, without waiting for the mixes to be made again.
        var dislikes = _music.DislikeSetOf(caller.Id);
        var result = new List<object>();
        var shown = new List<KostvShownMix>();
        foreach (var mix in mixes)
        {
            var songs = Visible(mix.Items, caller.User, dislikes);
            if (songs.Count == 0)
            {
                continue;
            }

            result.Add(new
            {
                mix.Id,
                mix.Genre,
                Artists = _music.CoverArtists(mix)
                    .Where(a => UserReflection.IsVisibleStandaloneTo(a, caller.User) && !dislikes.BlocksArtist(a.Id, a.Name))
                    .Select(a => _cards.Map(a, caller.User))
                    .ToList(),
                Items = songs.Select(item => _cards.Map(item, caller.User)).ToList(),
                Because = BecauseOf(mix.Because ?? mix.Artists, dislikes)
            });
            shown.Add(new KostvShownMix { Id = mix.Id, Genre = mix.Genre, Items = songs.Select(s => s.Id.ToString("N")).ToList() });
        }

        // The first time today: what the person was shown, to measure later how much of it is heard.
        _music.NoteShownMixes(caller.Id, shown);
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
        // The first time this week, the stored list as shown.
        _music.NoteShownDiscovery(caller.Id, week, songs);
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
        var refusal = Store.SetDiscovery(caller.Id, week, songs, _music.Week);
        if (refusal == KostvMusicStore.DiscoveryRefusal.None)
        {
            // The app shows the list it stores: noted as shown, once this week.
            _music.NoteShownDiscovery(caller.Id, _music.Week, songs);
        }

        return refusal switch
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
        var dislikes = _music.DislikeSetOf(caller.Id);
        var songs = moment.Ready ? Visible(moment.Items, caller.User, dislikes) : [];
        if (songs.Count == 0)
        {
            return Ok(new { moment.Slot, Ready = false });
        }

        // The first time today at this time of day: what the person was shown.
        _music.NoteShownMoment(caller.Id, moment.Slot, songs.Select(s => s.Id).ToList());
        var because = moment.Because ?? songs.Select(s => KostvMusicService.TrackOf(s, null).PrimaryArtist).OfType<string>().Distinct(StringComparer.OrdinalIgnoreCase).ToList();
        return Ok(new { moment.Slot, Ready = true, Items = songs.Select(item => _cards.Map(item, caller.User)).ToList(), Because = BecauseOf(because, dislikes) });
    }

    /// <summary>The three artists to say a mix is made of, none with «no me gusta».</summary>
    private static List<string> BecauseOf(IEnumerable<string> names, KostvDislikeSet dislikes) =>
        names.Where(n => !string.IsNullOrWhiteSpace(n) && !dislikes.BlocksArtist(n)).Take(3).ToList();

    /// <summary>
    /// The caller's taste, the one their music is made of: <c>Learned</c> (0, all the server's
    /// plays, to 1, 300 listens at home or more), up to 20 <c>Artists</c> at home by their
    /// background taste, 20 <c>Recent</c> by their taste of now (each followed by up to 20 not at
    /// home, with <c>Id</c> null) and 10 <c>Genres</c>; no artist with «no me gusta».
    /// </summary>
    [HttpGet("Taste")]
    [Authorize]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public async Task<ActionResult> GetTaste()
    {
        if (Caller() is not { } caller)
        {
            return NotSignedIn();
        }

        var taste = await _music.TasteAsync(caller.Id, caller.User).ConfigureAwait(false);
        return Ok(new
        {
            taste.Learned,
            Artists = taste.Artists.Select(a => new { a.Id, a.Name, a.Score }).ToList(),
            Recent = taste.Recent.Select(a => new { a.Id, a.Name, a.Score }).ToList(),
            Genres = taste.Genres.Select(g => new { g.Name, g.Score }).ToList()
        });
    }

    /// <summary>
    /// What the caller doesn't want to hear, the latest first: <c>Songs</c> (with their artist and
    /// album; one not at home with its <c>DeezerId</c> and <c>Id</c> null) and <c>Artists</c>;
    /// what is no longer in the library, with the name kept.
    /// </summary>
    [HttpGet("Dislikes")]
    [Authorize]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public ActionResult GetDislikes()
    {
        if (Caller() is not { } caller)
        {
            return NotSignedIn();
        }

        var dislikes = _music.DislikesView(caller.Id, caller.User);
        static Guid? IdOf(string? id) => Guid.TryParse(id, out var guid) ? guid : null;
        return Ok(new
        {
            Songs = dislikes.Songs.Select(s => new { Id = IdOf(s.Id), DeezerId = string.IsNullOrEmpty(s.Id) ? s.DeezerId : null, s.Name, s.Artist, ArtistId = IdOf(s.ArtistId), AlbumId = IdOf(s.AlbumId), At = s.At.UtcDateTime }).ToList(),
            Artists = dislikes.Artists.Select(a => new { Id = IdOf(a.Id), a.Name, At = a.At.UtcDateTime }).ToList()
        });
    }

    /// <summary>
    /// Takes a song or an artist off what the caller doesn't want to hear (to undo it, or from the
    /// list): its id, or <c>stremfin:&lt;DeezerId&gt;</c> for a song not at home. <c>204</c> also
    /// when it wasn't there.
    /// </summary>
    [HttpDelete("Dislikes/{itemId}")]
    [Authorize]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status500InternalServerError)]
    public ActionResult RemoveDislike([FromRoute] string itemId)
    {
        if (Caller() is not { } caller)
        {
            return NotSignedIn();
        }

        bool stored;
        if (KostvMusicEvent.DeezerIdOf(itemId?.Trim()) is { } deezerId)
        {
            stored = _music.Undislike(caller.Id, KostvMusicEvent.StreamedItem(deezerId));
        }
        else if (Guid.TryParse(itemId, out var id) && id != Guid.Empty)
        {
            stored = _music.Undislike(caller.Id, id);
        }
        else
        {
            return BadRequest(new { Error = "itemId is an id, or stremfin:<DeezerId>." });
        }

        // Kos TV: not stored, it stays on the list (here and after a restart): a 500, as for adding one.
        return stored ? NoContent() : StatusCode(StatusCodes.Status500InternalServerError, new { Error = "The dislike could not be taken off." });
    }

    /// <summary>Empties what the caller doesn't want to hear.</summary>
    [HttpDelete("Dislikes")]
    [Authorize]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    public ActionResult ClearDislikes()
    {
        if (Caller() is not { } caller)
        {
            return NotSignedIn();
        }

        _music.ClearDislikes(caller.Id);
        return NoContent();
    }

    /// <summary>The most songs (or artists) one event may name.</summary>
    public const int MaxEventItems = 500;

    /// <summary>The longest album or artist name a request event may carry.</summary>
    public const int MaxEventNameLength = 200;

    /// <summary>The longest Deezer id a request event may carry.</summary>
    public const int MaxDeezerIdLength = KostvMusicEvent.MaxDeezerIdLength;

    /// <summary>The most seconds a listen of a song not at home may say it played, or last: six hours.</summary>
    public const double MaxStreamSeconds = 6 * 60 * 60;

    private static readonly HashSet<string> EndedByValues = new(StringComparer.Ordinal)
    {
        KostvListenEnd.Natural, KostvListenEnd.Next, KostvListenEnd.Stop, KostvListenEnd.Closed, KostvListenEnd.Error
    };

    /// <summary>
    /// What the caller did that the server doesn't see, noted with the time in their music:
    /// <c>{ "Type": "playlist_add", "ItemIds": [...] }</c> (songs added to a playlist, up to 500),
    /// <c>{ "Type": "request", "Album": "…", "Artist": "…", "DeezerAlbumId": "…" }</c> (an album
    /// asked for in Stremfin, each optional), <c>{ "Type": "stream_listen", "DeezerId": "…",
    /// "Title": "…", "Artist": "…", "Album": "…", "Genre": "…", "Played": 123.4, "Duration": 224,
    /// "EndedBy": "natural", "Source": "…", "Shuffle": false }</c> (a song not at home heard
    /// through Stremfin, noted as a listen of <c>stremfin:&lt;DeezerId&gt;</c>; Album, Genre,
    /// Duration, Source and Shuffle optional) or <c>{ "Type": "dislike", "ItemIds": [...],
    /// "Songs": [ { "DeezerId", "Name", "Artist" } ], "Kind": "song" | "artist" }</c> («no me
    /// gusta» of songs, by default, or artists; <c>Songs</c>, of songs not at home, either or both).
    /// The first three are noted in the caller's music, and not while Learn is off; «no me gusta»
    /// is kept apart, also with Learn off (see <see cref="KostvMusicStore.AddDislikes"/>). An
    /// unknown type, or one not as said, is a <c>400</c>.
    /// </summary>
    [HttpPost("Event")]
    [Authorize]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status500InternalServerError)]
    public ActionResult AddEvent([FromBody] JsonElement body)
    {
        if (Caller() is not { } caller)
        {
            return NotSignedIn();
        }

        var type = Property(body, "Type") is { ValueKind: JsonValueKind.String } t ? t.GetString()?.Trim().ToLowerInvariant() : null;
        KostvMusicEvent entry;
        switch (type)
        {
            case KostvMusicEvent.PlaylistAddType:
            {
                if (EventItems(body, out var error) is not { } items)
                {
                    return BadRequest(new { Error = error });
                }

                entry = new KostvMusicEvent { Type = type, Items = items };
                break;
            }

            case KostvMusicEvent.RequestType:
            {
                if (!EventText(body, "Album", MaxEventNameLength, out var album) ||
                    !EventText(body, "Artist", MaxEventNameLength, out var artist) ||
                    !EventText(body, "DeezerAlbumId", MaxDeezerIdLength, out var deezer))
                {
                    return BadRequest(new { Error = $"Album and Artist are text of up to {MaxEventNameLength} characters, and DeezerAlbumId of up to {MaxDeezerIdLength}." });
                }

                entry = new KostvMusicEvent { Type = type, AlbumName = album, ArtistName = artist, DeezerAlbumId = deezer };
                break;
            }

            case KostvMusicEvent.StreamListenType:
                return StreamListen(caller.Id, body);

            case KostvMusicEvent.DislikeType:
            {
                // Songs at home (ItemIds), songs not at home (Songs), or both: at least one.
                var songsSaid = Property(body, "Songs") is { ValueKind: not JsonValueKind.Null };
                List<string>? items = null;
                if (Property(body, "ItemIds") is { ValueKind: not JsonValueKind.Null } || !songsSaid)
                {
                    items = EventItems(body, out var error);
                    if (items == null)
                    {
                        return BadRequest(new { Error = error });
                    }
                }

                List<KostvMusicService.KostvStreamedDislike>? streamed = null;
                if (songsSaid)
                {
                    streamed = StreamedDislikes(body);
                    if (streamed == null)
                    {
                        return BadRequest(new { Error = $"Songs is a list of 1 to {MaxEventItems} songs, each with its DeezerId (digits, up to {MaxDeezerIdLength}) and its Name and Artist (text of up to {MaxEventNameLength} characters)." });
                    }
                }

                var kind = KostvMusicEvent.SongKind;
                if (Property(body, "Kind") is { ValueKind: not JsonValueKind.Null } said)
                {
                    kind = said.ValueKind == JsonValueKind.String ? said.GetString()?.Trim().ToLowerInvariant() ?? string.Empty : string.Empty;
                    if (kind is not (KostvMusicEvent.ArtistKind or KostvMusicEvent.SongKind))
                    {
                        return BadRequest(new { Error = "Kind is artist or song." });
                    }
                }

                if (streamed != null && kind == KostvMusicEvent.ArtistKind)
                {
                    return BadRequest(new { Error = "Songs are only of Kind song." });
                }

                // Kept apart from the listens (not in their history), also with Learn off. What
                // isn't at home, or of its kind, is let go of (still a 204); not stored, a 500.
                var stored = items == null || _music.Dislike(caller.Id, caller.User, kind == KostvMusicEvent.ArtistKind, items.Select(Guid.Parse).ToList());
                stored &= streamed == null || _music.DislikeStreamed(caller.Id, streamed);
                if (!stored)
                {
                    return StatusCode(StatusCodes.Status500InternalServerError, new { Error = "The dislike could not be stored." });
                }

                return NoContent();
            }

            default:
                return BadRequest(new { Error = "Type is playlist_add, request, stream_listen or dislike." });
        }

        // With Learn off, nothing is noted (the store won't write it).
        Store.Append(caller.Id, entry.Stamp(Store.Now, Store.Zone));
        return NoContent();
    }

    /// <summary>
    /// Kos TV: a song not at home heard through Stremfin, noted as a listen of
    /// <c>stremfin:&lt;DeezerId&gt;</c> with its artist, genre and album by name, how it ended by the
    /// same rule as those at home, and linked to the listen before; only with Learn on. Not as said,
    /// a <c>400</c>.
    /// </summary>
    private ActionResult StreamListen(Guid userId, JsonElement body)
    {
        var deezerId = Property(body, "DeezerId") is { ValueKind: JsonValueKind.String } d ? d.GetString()?.Trim() : null;
        var endedBy = Property(body, "EndedBy") is { ValueKind: JsonValueKind.String } e ? e.GetString()?.Trim().ToLowerInvariant() : null;
        var shuffleSaid = Property(body, "Shuffle");
        if (!KostvMusicEvent.IsDeezerId(deezerId) ||
            !EventText(body, "Title", MaxEventNameLength, out var title, cut: true) || title == null ||
            !EventText(body, "Artist", MaxEventNameLength, out var artist, cut: true) || artist == null ||
            !EventText(body, "Album", MaxEventNameLength, out var album, cut: true) ||
            !EventText(body, "Genre", MaxEventNameLength, out var genre) ||
            !EventText(body, "Source", MaxEventNameLength, out var source) ||
            !EventSeconds(body, "Played", required: true, out var played) ||
            !EventSeconds(body, "Duration", required: false, out var duration) ||
            endedBy == null || !EndedByValues.Contains(endedBy) ||
            shuffleSaid is { ValueKind: not (JsonValueKind.True or JsonValueKind.False or JsonValueKind.Null) })
        {
            return BadRequest(new { Error = $"A stream_listen has a DeezerId (digits, up to {MaxDeezerIdLength}), a Title and an Artist (and may have an Album, a Genre and a Source), text (a Genre and a Source of up to {MaxEventNameLength} characters; a longer Title, Artist or Album is cut to {MaxEventNameLength}); Played (and Duration) in seconds, 0 to {MaxStreamSeconds}; EndedBy natural, next, stop, closed or error; and Shuffle true or false." });
        }

        // With Learn off, nothing is noted, nor linked to what comes after.
        if (!Store.Learns(userId))
        {
            return NoContent();
        }

        // Kos TV: no more than a person's listening could send (see TakeStreamListen); past it,
        // let go of, as with Learn off, so an app that went wrong doesn't keep at it.
        if (!Store.TakeStreamListen(userId))
        {
            return NoContent();
        }

        var now = Store.Now;
        double? length = duration is > 0 ? duration : null;
        var heard = Math.Min(played!.Value, length ?? double.MaxValue);
        var client = User.FindFirst("Jellyfin-Client")?.Value;
        var device = User.FindFirst("Jellyfin-Device")?.Value;
        var entry = new KostvMusicEvent
        {
            Type = KostvMusicEvent.ListenType,
            Item = KostvMusicEvent.StreamedItem(deezerId!),
            Title = title,
            Artists = [artist],
            Genres = genre != null ? [genre] : null,
            AlbumName = album,
            Played = (int)Math.Round(heard),
            Duration = length.HasValue ? (int)Math.Round(length.Value) : null,
            Outcome = KostvListenOutcome.Classify(heard, length, endedBy == KostvListenEnd.Natural),
            Device = client != null || device != null ? KostvDeviceKind.Of(client, device) : null,
            Source = KostvMusicContext.Normalize(source),
            EndedBy = endedBy,
            Shuffle = shuffleSaid is { ValueKind: JsonValueKind.True or JsonValueKind.False } shuffle ? shuffle.GetBoolean() : null
        }.Stamp(now.AddSeconds(-heard), Store.Zone);
        // It started about what was heard of it ago, and ends now. Linked to the one before only
        // once written (Learn turned off, or the listens deleted, meanwhile: not written).
        Store.LinkAndAppend(userId, entry, now);
        return NoContent();
    }

    /// <summary>
    /// Seconds of an event: a number from 0 to <see cref="MaxStreamSeconds"/>; absent or null is
    /// null, and only fine when not <paramref name="required"/>.
    /// </summary>
    private static bool EventSeconds(JsonElement body, string name, bool required, out double? value)
    {
        value = null;
        if (Property(body, name) is not { } said || said.ValueKind == JsonValueKind.Null)
        {
            return !required;
        }

        if (said.ValueKind != JsonValueKind.Number || !said.TryGetDouble(out var seconds) || !double.IsFinite(seconds) || seconds < 0 || seconds > MaxStreamSeconds)
        {
            return false;
        }

        value = seconds;
        return true;
    }

    /// <summary>
    /// The Songs of a «no me gusta» of songs not at home: 1 to <see cref="MaxEventItems"/>, each
    /// with its DeezerId and, optional, its Name and Artist; null when not so.
    /// </summary>
    private static List<KostvMusicService.KostvStreamedDislike>? StreamedDislikes(JsonElement body)
    {
        if (Property(body, "Songs") is not { ValueKind: JsonValueKind.Array } list || list.GetArrayLength() is 0 or > MaxEventItems)
        {
            return null;
        }

        var songs = new List<KostvMusicService.KostvStreamedDislike>();
        foreach (var song in list.EnumerateArray())
        {
            var deezerId = Property(song, "DeezerId") is { ValueKind: JsonValueKind.String } d ? d.GetString()?.Trim() : null;
            if (song.ValueKind != JsonValueKind.Object ||
                !KostvMusicEvent.IsDeezerId(deezerId) ||
                !EventText(song, "Name", MaxEventNameLength, out var name) ||
                !EventText(song, "Artist", MaxEventNameLength, out var artist))
            {
                return null;
            }

            songs.Add(new KostvMusicService.KostvStreamedDislike(deezerId!, name, artist));
        }

        return songs;
    }

    /// <summary>The ItemIds of an event, without dashes: at least one and at most <see cref="MaxEventItems"/>, each an id.</summary>
    private static List<string>? EventItems(JsonElement body, out string error)
    {
        error = $"ItemIds is a list of 1 to {MaxEventItems} ids.";
        if (Property(body, "ItemIds") is not { ValueKind: JsonValueKind.Array } list || list.GetArrayLength() is 0 or > MaxEventItems)
        {
            return null;
        }

        var ids = new List<string>();
        foreach (var element in list.EnumerateArray())
        {
            if (element.ValueKind != JsonValueKind.String || !Guid.TryParse(element.GetString(), out var id) || id == Guid.Empty)
            {
                return null;
            }

            ids.Add(id.ToString("N"));
        }

        return ids.Distinct(StringComparer.Ordinal).ToList();
    }

    /// <summary>
    /// An optional text of an event: absent or null is null; otherwise text of up to
    /// <paramref name="max"/> characters (a longer one, with <paramref name="cut"/>, cut to it).
    /// </summary>
    private static bool EventText(JsonElement body, string name, int max, out string? value, bool cut = false)
    {
        value = null;
        if (Property(body, name) is not { } said || said.ValueKind == JsonValueKind.Null)
        {
            return true;
        }

        if (said.ValueKind != JsonValueKind.String)
        {
            return false;
        }

        var text = said.GetString()?.Trim();
        if (text?.Length > max)
        {
            if (!cut)
            {
                return false;
            }

            // Kos TV: not halfway through a character outside the basic plane.
            text = text[..(char.IsHighSurrogate(text[max - 1]) ? max - 1 : max)].TrimEnd();
        }

        value = string.IsNullOrEmpty(text) ? null : text;
        return true;
    }

    // Read at once within the person's limits, and each checked again as the card goes out;
    // none with «no me gusta».
    private List<BaseItem> Visible(IReadOnlyList<Guid> ids, object user, KostvDislikeSet dislikes) =>
        _music.Songs(user, ids)
            .Where(item => UserReflection.IsVisibleStandaloneTo(item, user) && !KostvMusicService.Blocks(dislikes, item))
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
