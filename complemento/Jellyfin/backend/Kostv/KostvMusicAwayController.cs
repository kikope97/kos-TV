using System.Text.Json;
using MediaBrowser.Controller.Entities.Audio;
using MediaBrowser.Controller.Playlists;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Moonfin.Server.Api;
using Moonfin.Server.Helpers;

namespace Moonfin.Server.Kostv;

/// <summary>
/// kOS TV: songs not at home («Toda la música») in the server's playlists and with a heart: kept
/// by the plugin (see <see cref="KostvAwayStore"/>), as the server keeps only its own, and moved
/// to the server's own when they come home (see <see cref="KostvMusicAway"/>).
/// </summary>
[ApiController]
[Route("Moonfin/Kostv/Music/Away")]
[Produces("application/json")]
public class KostvMusicAwayController : ControllerBase
{
    /// <summary>The longest title, artist or album kept: a longer one is cut.</summary>
    public const int MaxTextLength = 200;

    /// <summary>The longest address of a cover kept.</summary>
    public const int MaxCoverLength = 1000;

    /// <summary>The most elements the whole order of a playlist may name.</summary>
    public const int MaxOrderIds = 20000;

    /// <summary>kOS TV: the most playlists asked about at once (which may be changed).</summary>
    public const int MaxEditableIds = 1000;

    private static readonly JsonSerializerOptions OutputOptions = new()
    {
        // As declared (PascalCase, as the server's own), and nulls written: "After": null.
        PropertyNamingPolicy = null,
        Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping
    };

    private readonly KostvMusicAway _away;

    public KostvMusicAwayController(KostvMusicAway away)
    {
        _away = away;
    }

    private KostvAwayStore Store => _away.Store;

    private (Guid Id, object User)? Caller()
    {
        var userId = this.GetUserIdFromClaims();
        var user = userId.HasValue ? UserReflection.ResolveUser(HttpContext.RequestServices, userId.Value) : null;
        return userId.HasValue && user != null ? (userId.Value, user) : null;
    }

    private ActionResult NotSignedIn() => Unauthorized(new { Error = "User not authenticated" });

    private ContentResult Json(object value) => Content(JsonSerializer.Serialize(value, OutputOptions), "application/json");

    private static object Song(KostvAwaySong s) => new
    {
        s.DeezerId,
        s.Title,
        s.Artist,
        s.Album,
        s.AlbumDeezerId,
        s.ArtistDeezerId,
        s.Cover,
        s.Duration,
        s.Explicit,
        Added = s.Added.UtcDateTime
    };

    private static object Entry(KostvAwaySong s) => new
    {
        s.DeezerId,
        s.Title,
        s.Artist,
        s.Album,
        s.AlbumDeezerId,
        s.ArtistDeezerId,
        s.Cover,
        s.Duration,
        s.Explicit,
        s.After,
        Added = s.Added.UtcDateTime
    };

    /// <summary>The songs not at home of a playlist, in the order of the whole list.</summary>
    private static object EntriesOf(IReadOnlyList<string> jellyfin, List<KostvAwaySong> entries)
    {
        var at = KostvAwayOrder.Merged(jellyfin, entries).Select((key, i) => (key, i)).GroupBy(x => x.key).ToDictionary(g => g.Key, g => g.First().i, StringComparer.Ordinal);
        return new { Entries = entries.OrderBy(e => at.GetValueOrDefault(e.Key, int.MaxValue)).Select(Entry).ToList() };
    }

    // ---------------------------------------------------------------- playlists

    /// <summary>
    /// The songs not at home of the server's playlist <paramref name="playlistId"/>, each with the
    /// element before it in the whole list (<c>After</c>: an id of the server, or
    /// <c>stremfin:&lt;DeezerId&gt;</c>; null, the first). For whoever may see the playlist; for
    /// anyone else, as for one that isn't there, a <c>404</c>.
    /// </summary>
    [HttpGet("Playlist/{playlistId}")]
    [Authorize]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    [ProducesResponseType(StatusCodes.Status503ServiceUnavailable)]
    public async Task<ActionResult> GetPlaylist([FromRoute] string playlistId)
    {
        if (Caller() is not { } caller)
        {
            return NotSignedIn();
        }

        if (!Guid.TryParse(playlistId, out var id))
        {
            return NotFound(new { Error = "Playlist not found." });
        }

        // kOS TV: the server couldn't say (busy): not «not there», so the app says it failed.
        if (!_away.TryPlaylistOf(id, out var playlist))
        {
            return Unavailable();
        }

        if (playlist == null || KostvMusicAway.AccessOf(playlist, caller.Id) == KostvPlaylistAccess.None)
        {
            return NotFound(new { Error = "Playlist not found." });
        }

        // kOS TV: those after an element taken out (also in another app) in their place again.
        var entries = await _away.EntriesOfAsync(playlist, HttpContext.RequestAborted).ConfigureAwait(false);
        return Json(EntriesOf(KostvMusicAway.JellyfinIdsOf(playlist), entries));
    }

    private ObjectResult Unavailable() => StatusCode(StatusCodes.Status503ServiceUnavailable, new { Error = "The playlist could not be read now." });

    /// <summary>
    /// kOS TV: which of the server's playlists <c>{ "Ids": [...] }</c> the caller may change (theirs,
    /// or shared with them to edit), as <c>{ "Ids": [...] }</c> (without dashes), so the app offers
    /// to add, take out and move only in those. Up to <see cref="MaxEditableIds"/>.
    /// </summary>
    [HttpPost("Playlists/Editable")]
    [Authorize]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    public ActionResult EditablePlaylists([FromBody] JsonElement body)
    {
        if (Caller() is not { } caller)
        {
            return NotSignedIn();
        }

        if (Property(body, "Ids") is not { ValueKind: JsonValueKind.Array } list || list.GetArrayLength() > MaxEditableIds)
        {
            return BadRequest(new { Error = $"Ids is a list of up to {MaxEditableIds} ids." });
        }

        var editable = new List<string>();
        foreach (var element in list.EnumerateArray())
        {
            if (element.ValueKind != JsonValueKind.String || !Guid.TryParse(element.GetString(), out var id) || id == Guid.Empty)
            {
                return BadRequest(new { Error = "Each of Ids is an id." });
            }

            var key = id.ToString("N");
            if (!editable.Contains(key) && KostvMusicAway.AccessOf(_away.PlaylistOf(id), caller.Id) == KostvPlaylistAccess.Edit)
            {
                editable.Add(key);
            }
        }

        return Json(new { Ids = editable });
    }

    /// <summary>
    /// Adds songs not at home to the server's playlist <paramref name="playlistId"/>
    /// (<c>{ "Songs": [...], "After": "&lt;id&gt;" | null }</c>; without After, at the end), one
    /// after the other; one already in it isn't added again. Only for whoever may change the
    /// playlist (<c>403</c>). The list as <see cref="GetPlaylist"/> gives it.
    /// </summary>
    [HttpPost("Playlist/{playlistId}")]
    [Authorize]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    [ProducesResponseType(StatusCodes.Status500InternalServerError)]
    public async Task<ActionResult> AddToPlaylist([FromRoute] string playlistId, [FromBody] JsonElement body)
    {
        if (Caller() is not { } caller)
        {
            return NotSignedIn();
        }

        if (Editable(playlistId, caller.Id, out var id) is { } refused)
        {
            return refused;
        }

        if (Property(body, "Songs") is not { ValueKind: JsonValueKind.Array } list || list.GetArrayLength() is 0 or > KostvAwayStore.MaxPerPlaylist)
        {
            return BadRequest(new { Error = $"Songs is a list of 1 to {KostvAwayStore.MaxPerPlaylist} songs." });
        }

        var songs = new List<KostvAwaySong>();
        foreach (var element in list.EnumerateArray())
        {
            if (SongOf(element, out var error) is not { } song)
            {
                return BadRequest(new { Error = error });
            }

            songs.Add(song);
        }

        // Without After, at the end; After null, the first.
        var afterSaid = false;
        string? after = null;
        if (Property(body, "After") is { } said)
        {
            afterSaid = true;
            if (said.ValueKind != JsonValueKind.Null)
            {
                after = said.ValueKind == JsonValueKind.String ? KostvAwayOrder.NormalizeId(said.GetString()) : null;
                if (after == null)
                {
                    return BadRequest(new { Error = "After is an id, stremfin:<DeezerId> or null." });
                }
            }
        }

        var gate = Store.PlaylistLock(id);
        await gate.WaitAsync(HttpContext.RequestAborted).ConfigureAwait(false);
        try
        {
            // Read again under the lock: what is in it now.
            if (_away.PlaylistOf(id) is not { } playlist)
            {
                return NotFound(new { Error = "Playlist not found." });
            }

            // kOS TV: songs only in a playlist of music: one of videos wouldn't show them.
            if (!KostvMusicAway.IsForMusic(playlist))
            {
                return BadRequest(new { Error = "Songs not at home go only in a playlist of music." });
            }

            var jellyfin = KostvMusicAway.JellyfinIdsOf(playlist);
            var (entries, lastOrder) = Store.Read(id);
            KostvAwayOrder.Reanchor(entries, jellyfin, lastOrder);
            switch (KostvAwayOrder.Insert(entries, jellyfin, songs, afterSaid, after, Store.Now))
            {
                case KostvAwayOrder.InsertRefusal.TooMany:
                    return BadRequest(new { Error = $"A playlist keeps up to {KostvAwayStore.MaxPerPlaylist} songs not at home." });
                case KostvAwayOrder.InsertRefusal.AfterItself:
                    return BadRequest(new { Error = "After can't be one of the songs added." });
            }

            if (!Store.SaveEntries(id, entries, KostvAwayOrder.Merged(jellyfin, entries)))
            {
                return StatusCode(StatusCodes.Status500InternalServerError, new { Error = "The songs could not be stored." });
            }

            return Json(EntriesOf(jellyfin, entries));
        }
        finally
        {
            gate.Release();
        }
    }

    /// <summary>Takes the song not at home <paramref name="deezerId"/> out of the playlist; <c>204</c> also when it wasn't in it.</summary>
    [HttpDelete("Playlist/{playlistId}/{deezerId}")]
    [Authorize]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    [ProducesResponseType(StatusCodes.Status500InternalServerError)]
    public async Task<ActionResult> RemoveFromPlaylist([FromRoute] string playlistId, [FromRoute] string deezerId)
    {
        if (Caller() is not { } caller)
        {
            return NotSignedIn();
        }

        if (Editable(playlistId, caller.Id, out var id, out var playlist) is { } refused)
        {
            return refused;
        }

        if (DeezerIdOf(deezerId) is not { } song)
        {
            return BadRequest(new { Error = "deezerId is a Deezer id, or stremfin:<DeezerId>." });
        }

        var gate = Store.PlaylistLock(id);
        await gate.WaitAsync(HttpContext.RequestAborted).ConfigureAwait(false);
        try
        {
            var (entries, lastOrder) = Store.Read(id);
            var jellyfin = KostvMusicAway.JellyfinIdsOf(playlist!);
            KostvAwayOrder.Reanchor(entries, jellyfin, lastOrder);
            if (KostvAwayOrder.Remove(entries, song) && !Store.SaveEntries(id, entries, KostvAwayOrder.Merged(jellyfin, entries)))
            {
                return StatusCode(StatusCodes.Status500InternalServerError, new { Error = "The song could not be taken out." });
            }

            return NoContent();
        }
        finally
        {
            gate.Release();
        }
    }

    /// <summary>
    /// The playlist's whole order as it is now (<c>{ "Ids": [...] }</c>, ids of the server and
    /// <c>stremfin:&lt;DeezerId&gt;</c>): each song not at home after the element before it there.
    /// The server's elements are moved by the app with the server's own routes.
    /// </summary>
    [HttpPost("Playlist/{playlistId}/Order")]
    [Authorize]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    [ProducesResponseType(StatusCodes.Status500InternalServerError)]
    public async Task<ActionResult> OrderPlaylist([FromRoute] string playlistId, [FromBody] JsonElement body)
    {
        if (Caller() is not { } caller)
        {
            return NotSignedIn();
        }

        if (Editable(playlistId, caller.Id, out var id, out var playlist) is { } refused)
        {
            return refused;
        }

        if (Property(body, "Ids") is not { ValueKind: JsonValueKind.Array } list || list.GetArrayLength() > MaxOrderIds)
        {
            return BadRequest(new { Error = $"Ids is a list of up to {MaxOrderIds} ids." });
        }

        var ids = new List<string>();
        foreach (var element in list.EnumerateArray())
        {
            if ((element.ValueKind == JsonValueKind.String ? KostvAwayOrder.NormalizeId(element.GetString()) : null) is not { } key)
            {
                return BadRequest(new { Error = "Each of Ids is an id or stremfin:<DeezerId>." });
            }

            ids.Add(key);
        }

        var gate = Store.PlaylistLock(id);
        await gate.WaitAsync(HttpContext.RequestAborted).ConfigureAwait(false);
        try
        {
            var entries = Store.Entries(id);
            if (entries.Count == 0)
            {
                return NoContent();
            }

            KostvAwayOrder.Reorder(entries, ids);
            // kOS TV: the whole list as it is now, for what follows an element taken out later.
            var now = _away.PlaylistOf(id) ?? playlist!;
            return Store.SaveEntries(id, entries, KostvAwayOrder.Merged(KostvMusicAway.JellyfinIdsOf(now), entries))
                ? NoContent()
                : StatusCode(StatusCodes.Status500InternalServerError, new { Error = "The order could not be stored." });
        }
        finally
        {
            gate.Release();
        }
    }

    /// <summary>Null when <paramref name="userId"/> may change the playlist; otherwise why not (<c>404</c> or <c>403</c>).</summary>
    private ActionResult? Editable(string playlistId, Guid userId, out Guid id) => Editable(playlistId, userId, out id, out _);

    private ActionResult? Editable(string playlistId, Guid userId, out Guid id, out Playlist? playlist)
    {
        playlist = null;
        if (!Guid.TryParse(playlistId, out id) || id == Guid.Empty)
        {
            return NotFound(new { Error = "Playlist not found." });
        }

        // kOS TV: the server couldn't say (busy): not «not there».
        if (!_away.TryPlaylistOf(id, out playlist))
        {
            return Unavailable();
        }

        return KostvMusicAway.AccessOf(playlist, userId) switch
        {
            KostvPlaylistAccess.Edit => null,
            KostvPlaylistAccess.Read => StatusCode(StatusCodes.Status403Forbidden, new { Error = "Only who may change the playlist." }),
            _ => NotFound(new { Error = "Playlist not found." })
        };
    }

    // ---------------------------------------------------------------- hearts

    /// <summary>The caller's hearts on songs not at home, the latest first.</summary>
    [HttpGet("Favorites")]
    [Authorize]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public ActionResult GetFavorites()
    {
        return Caller() is { } caller
            ? Json(new { Songs = Store.Favorites(caller.Id).Select(Song).ToList() })
            : NotSignedIn();
    }

    /// <summary>
    /// A heart of the caller on a song not at home (the song, as in a playlist): it counts for
    /// their taste as a heart, from the next music day. Up to 2000 (past them, a <c>400</c>).
    /// </summary>
    [HttpPost("Favorites")]
    [Authorize]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status500InternalServerError)]
    public ActionResult AddFavorite([FromBody] JsonElement body)
    {
        if (Caller() is not { } caller)
        {
            return NotSignedIn();
        }

        if (SongOf(body, out var error) is not { } song)
        {
            return BadRequest(new { Error = error });
        }

        // Kos TV: as a heart on a song at home, it doesn't make the day's music again.
        return Store.AddFavorite(caller.Id, song) switch
        {
            KostvAwayStore.FavoriteResult.Stored => NoContent(),
            KostvAwayStore.FavoriteResult.TooMany => BadRequest(new { Error = $"Up to {KostvAwayStore.MaxFavorites} hearts on songs not at home." }),
            _ => StatusCode(StatusCodes.Status500InternalServerError, new { Error = "The heart could not be stored." })
        };
    }

    /// <summary>Takes the caller's heart off a song not at home; <c>204</c> also when it had none.</summary>
    [HttpDelete("Favorites/{deezerId}")]
    [Authorize]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status500InternalServerError)]
    public ActionResult RemoveFavorite([FromRoute] string deezerId)
    {
        if (Caller() is not { } caller)
        {
            return NotSignedIn();
        }

        if (DeezerIdOf(deezerId) is not { } song)
        {
            return BadRequest(new { Error = "deezerId is a Deezer id, or stremfin:<DeezerId>." });
        }

        return Store.RemoveFavorite(caller.Id, song)
            ? NoContent()
            : StatusCode(StatusCodes.Status500InternalServerError, new { Error = "The heart could not be taken off." });
    }

    // ---------------------------------------------------------------- come home

    /// <summary>
    /// The app tells a song not at home is at home now (<c>{ "DeezerId": "…", "JellyfinId": "…" }</c>,
    /// as Stremfin said): in every playlist and heart where it was, it is made the server's (see
    /// <see cref="KostvMusicAway.ArriveAsync"/>). A <c>404</c> when the song isn't a song of the
    /// library the caller may see.
    /// </summary>
    [HttpPost("Arrived")]
    [Authorize]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<ActionResult> Arrived([FromBody] JsonElement body)
    {
        if (Caller() is not { } caller)
        {
            return NotSignedIn();
        }

        var deezerId = DeezerIdOf(Property(body, "DeezerId") is { } d ? TextOrNumber(d) : null);
        var jellyfinSaid = Property(body, "JellyfinId") is { ValueKind: JsonValueKind.String } j ? j.GetString() : null;
        if (deezerId == null || !Guid.TryParse(jellyfinSaid, out var jellyfinId) || jellyfinId == Guid.Empty)
        {
            return BadRequest(new { Error = "DeezerId (digits) and JellyfinId (an id) are needed." });
        }

        // Kos TV: only a song of the library the caller may see, so no one can put in the others'
        // playlists what they don't know is there.
        if (_away.ItemOf(jellyfinId) is not Audio item || !_away.Sees(item, caller.User))
        {
            return NotFound(new { Error = "Song not found." });
        }

        await _away.ArriveOnceAsync(deezerId, item).ConfigureAwait(false);
        return NoContent();
    }

    // ---------------------------------------------------------------- reading what the app says

    /// <summary>A Deezer id, alone or as <c>stremfin:&lt;DeezerId&gt;</c>; null when it isn't one.</summary>
    private static string? DeezerIdOf(string? said)
    {
        said = said?.Trim();
        return KostvMusicEvent.IsDeezerId(said) ? said : KostvMusicEvent.DeezerIdOf(said);
    }

    /// <summary>A text, or a whole number as its digits (a Deezer id may come as either).</summary>
    private static string? TextOrNumber(JsonElement value) => value.ValueKind switch
    {
        JsonValueKind.String => value.GetString()?.Trim(),
        JsonValueKind.Number when value.TryGetDecimal(out var number) && number >= 0 && number == decimal.Truncate(number) => value.GetRawText(),
        _ => null
    };

    /// <summary>
    /// A song not at home as the app gives it: its <c>DeezerId</c> (digits, up to 32) and
    /// <c>Title</c>; and, optional, its <c>Artist</c> and <c>Album</c> (each of these cut to
    /// <see cref="MaxTextLength"/>), <c>AlbumDeezerId</c> and <c>ArtistDeezerId</c> (digits),
    /// <c>Cover</c> (an http or https address of up to <see cref="MaxCoverLength"/>),
    /// <c>Duration</c> (seconds, up to six hours) and <c>Explicit</c>. Null, and why, when not so.
    /// </summary>
    internal static KostvAwaySong? SongOf(JsonElement body, out string error)
    {
        error = $"A song has its DeezerId (digits, up to {KostvMusicEvent.MaxDeezerIdLength}) and its Title, and may have an Artist and an Album (text; longer than {MaxTextLength}, cut), an AlbumDeezerId and an ArtistDeezerId (digits), a Cover (an http or https address of up to {MaxCoverLength}), a Duration (seconds, 0 to {KostvMusicController.MaxStreamSeconds}) and Explicit (true or false).";
        if (body.ValueKind != JsonValueKind.Object)
        {
            return null;
        }

        var deezerId = Property(body, "DeezerId") is { } d ? TextOrNumber(d) : null;
        if (!KostvMusicEvent.IsDeezerId(deezerId) ||
            !Text(body, "Title", out var title) || title == null ||
            !Text(body, "Artist", out var artist) ||
            !Text(body, "Album", out var album) ||
            !OptionalDeezerId(body, "AlbumDeezerId", out var albumId) ||
            !OptionalDeezerId(body, "ArtistDeezerId", out var artistId) ||
            !Cover(body, out var cover))
        {
            return null;
        }

        int? duration = null;
        if (Property(body, "Duration") is { ValueKind: not JsonValueKind.Null } said)
        {
            if (said.ValueKind != JsonValueKind.Number || !said.TryGetDouble(out var seconds) || !double.IsFinite(seconds) || seconds < 0 || seconds > KostvMusicController.MaxStreamSeconds)
            {
                return null;
            }

            duration = seconds > 0 ? (int)Math.Round(seconds) : null;
        }

        var isExplicit = false;
        if (Property(body, "Explicit") is { ValueKind: not JsonValueKind.Null } e)
        {
            if (e.ValueKind is not (JsonValueKind.True or JsonValueKind.False))
            {
                return null;
            }

            isExplicit = e.GetBoolean();
        }

        return new KostvAwaySong
        {
            DeezerId = deezerId!,
            Title = title,
            Artist = artist,
            Album = album,
            AlbumDeezerId = albumId,
            ArtistDeezerId = artistId,
            Cover = cover,
            Duration = duration,
            Explicit = isExplicit
        };
    }

    /// <summary>An optional text: absent or null is null; a longer one, cut to <see cref="MaxTextLength"/>.</summary>
    private static bool Text(JsonElement body, string name, out string? value)
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
        if (text?.Length > MaxTextLength)
        {
            // Not halfway through a character outside the basic plane.
            text = text[..(char.IsHighSurrogate(text[MaxTextLength - 1]) ? MaxTextLength - 1 : MaxTextLength)].TrimEnd();
        }

        value = string.IsNullOrEmpty(text) ? null : text;
        return true;
    }

    private static bool OptionalDeezerId(JsonElement body, string name, out string? value)
    {
        value = null;
        if (Property(body, name) is not { } said || said.ValueKind == JsonValueKind.Null)
        {
            return true;
        }

        value = TextOrNumber(said);
        if (string.IsNullOrEmpty(value))
        {
            value = null;
            return said.ValueKind == JsonValueKind.String;
        }

        return KostvMusicEvent.IsDeezerId(value);
    }

    private static bool Cover(JsonElement body, out string? value)
    {
        value = null;
        if (Property(body, "Cover") is not { } said || said.ValueKind == JsonValueKind.Null)
        {
            return true;
        }

        if (said.ValueKind != JsonValueKind.String)
        {
            return false;
        }

        var text = said.GetString()?.Trim();
        if (string.IsNullOrEmpty(text))
        {
            return true;
        }

        if (text.Length > MaxCoverLength || !Uri.TryCreate(text, UriKind.Absolute, out var uri) || (uri.Scheme != Uri.UriSchemeHttps && uri.Scheme != Uri.UriSchemeHttp))
        {
            return false;
        }

        value = text;
        return true;
    }

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
