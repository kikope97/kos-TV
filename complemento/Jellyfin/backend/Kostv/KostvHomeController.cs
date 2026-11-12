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
/// kOS TV: the rows of each person's home page, worked out from what they watched.
/// </summary>
[ApiController]
[Route("Moonfin/Kostv/Home")]
[Produces("application/json")]
public class KostvHomeController : ControllerBase
{
    private readonly KostvHomeService _home;
    private readonly ILibraryManager _libraryManager;
    private readonly ItemCardDtoMapper _cards;

    public KostvHomeController(KostvHomeService home, ILibraryManager libraryManager, ItemCardDtoMapper cards)
    {
        _home = home;
        _libraryManager = libraryManager;
        _cards = cards;
    }

    /// <summary>
    /// The caller's rows, <paramref name="limit"/> of them from <paramref name="start"/>, so the
    /// app fetches more as the person scrolls down. <paramref name="refresh"/> works them out
    /// again, for when they have just finished something.
    /// </summary>
    [HttpGet]
    [Authorize]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public async Task<ActionResult> Get([FromQuery] int start = 0, [FromQuery] int limit = 6, [FromQuery] bool refresh = false)
    {
        var userId = this.GetUserIdFromClaims();
        var user = userId.HasValue ? UserReflection.ResolveUser(HttpContext.RequestServices, userId.Value) : null;
        if (userId == null || user == null)
        {
            return Unauthorized(new { Error = "User not authenticated" });
        }

        var page = await _home.GetAsync(userId.Value, user, refresh).ConfigureAwait(false);
        start = Math.Max(0, start);
        limit = Math.Clamp(limit, 1, 20);
        var rows = page.Rows.Skip(start).Take(limit).Select(row => new
        {
            row.Kind,
            row.Label,
            SeedId = row.SeedItemId,
            Items = row.ItemIds
                .Select(id => Guid.TryParse(id, out var guid) ? _libraryManager.GetItemById(guid) : null)
                .Where(item => item != null && UserReflection.IsVisibleTo(item, user))
                .Select(item => _cards.Map(item!, user))
                .ToList()
        }).ToList();

        // With the first rows: the new episodes of what they follow, read now so one shows as it
        // lands, and what they turned down, for the rows the app makes itself.
        var first = start == 0;
        return Ok(new
        {
            Rows = rows,
            Start = start,
            Total = page.Rows.Count,
            page.Tmdb,
            NewEpisodes = first
                ? _home.NewEpisodes(user, page).Where(item => UserReflection.IsVisibleTo(item, user)).Select(item => _cards.Map(item, user)).ToList()
                : null,
            Hidden = first ? _home.Hidden(userId.Value, page).Select(id => id.ToString("N")).ToList() : null,
            // Their list: what they haven't started, for its row, and every id, for the buttons.
            MyList = first ? Cards(_home.MyList(userId.Value, user).ToStart.Take(20), user) : null,
            MyListIds = first ? _home.MyListIds(userId.Value) : null
        });
    }

    private List<object> Cards(IEnumerable<BaseItem> items, object user) =>
        items.Select(item => (object)_cards.Map(item, user)).ToList();

    /// <summary>
    /// The caller's list in its three parts: what they are part way through, what they haven't
    /// started and what they have watched, and the ids of all of it.
    /// </summary>
    [HttpGet("/Moonfin/Kostv/MyList")]
    [Authorize]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public ActionResult MyList()
    {
        var userId = this.GetUserIdFromClaims();
        var user = userId.HasValue ? UserReflection.ResolveUser(HttpContext.RequestServices, userId.Value) : null;
        if (userId == null || user == null)
        {
            return Unauthorized(new { Error = "User not authenticated" });
        }

        var list = _home.MyList(userId.Value, user);
        return Ok(new
        {
            Watching = Cards(list.Watching, user),
            ToStart = Cards(list.ToStart, user),
            Watched = Cards(list.Watched, user),
            Ids = _home.MyListIds(userId.Value)
        });
    }

    /// <summary>
    /// Puts <paramref name="itemId"/> (a film or series, or the series of an episode) on the
    /// caller's list, or with <paramref name="remove"/> takes it off. <paramref name="arrived"/>:
    /// the app putting on something the person asked for that has just arrived, only the first
    /// time, so taking it off sticks.
    /// </summary>
    [HttpPost("/Moonfin/Kostv/MyList")]
    [Authorize]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<ActionResult> SetOnList([FromQuery] Guid itemId, [FromQuery] bool remove = false, [FromQuery] bool arrived = false)
    {
        var userId = this.GetUserIdFromClaims();
        var user = userId.HasValue ? UserReflection.ResolveUser(HttpContext.RequestServices, userId.Value) : null;
        if (userId == null || user == null)
        {
            return Unauthorized(new { Error = "User not authenticated" });
        }

        if (_home.ListItemFor(itemId, user) is not { } item)
        {
            return NotFound();
        }

        var onList = await _home.SetOnListAsync(userId.Value, item, remove, arrived).ConfigureAwait(false);
        return Ok(new { ItemId = item.Id.ToString("N"), OnList = onList });
    }

    /// <summary>Takes off the caller's list everything they have watched.</summary>
    [HttpPost("/Moonfin/Kostv/MyList/ClearWatched")]
    [Authorize]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public async Task<ActionResult> ClearWatched()
    {
        var userId = this.GetUserIdFromClaims();
        var user = userId.HasValue ? UserReflection.ResolveUser(HttpContext.RequestServices, userId.Value) : null;
        if (userId == null || user == null)
        {
            return Unauthorized(new { Error = "User not authenticated" });
        }

        return Ok(new { Removed = await _home.ClearWatchedAsync(userId.Value, user).ConfigureAwait(false) });
    }

    /// <summary>
    /// The caller isn't interested in <paramref name="itemId"/> (a film or series): it leaves their
    /// home page, and what is like it ranks lower. <paramref name="undo"/> takes that back.
    /// </summary>
    [HttpPost("NotInterested")]
    [Authorize]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<ActionResult> NotInterested([FromQuery] Guid itemId, [FromQuery] bool undo = false)
    {
        var userId = this.GetUserIdFromClaims();
        var user = userId.HasValue ? UserReflection.ResolveUser(HttpContext.RequestServices, userId.Value) : null;
        if (userId == null || user == null)
        {
            return Unauthorized(new { Error = "User not authenticated" });
        }

        if (_libraryManager.GetItemById(itemId) is not { } item || !UserReflection.IsVisibleTo(item, user))
        {
            return NotFound();
        }

        var key = await _home.DismissAsync(userId.Value, itemId, undo).ConfigureAwait(false);
        return key == null ? NotFound() : NoContent();
    }

    /// <summary>
    /// Which of these TMDB titles ("movie:123,tv:45") are on the home server for the caller, as
    /// cards with their played state. For the rows the app builds from outside lists: what the
    /// person asked for and has arrived, and what is most watched now.
    /// </summary>
    [HttpGet("Lookup")]
    [Authorize]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public async Task<ActionResult> Lookup([FromQuery] string keys)
    {
        var userId = this.GetUserIdFromClaims();
        var user = userId.HasValue ? UserReflection.ResolveUser(HttpContext.RequestServices, userId.Value) : null;
        if (userId == null || user == null)
        {
            return Unauthorized(new { Error = "User not authenticated" });
        }

        var wanted = (keys ?? string.Empty)
            .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Take(200)
            .ToList();
        var items = (await _home.FindAsync(userId.Value, user, wanted).ConfigureAwait(false)).Select(found => new { found.Key, Item = _cards.Map(found.Item, user) }).ToList();
        return Ok(new { Items = items });
    }

    /// <summary>
    /// For the settings page: how full each person's page comes out, to tell whether the library
    /// and the TMDB key give enough to go on.
    /// </summary>
    [HttpGet("Diagnostics")]
    [Authorize(Policy = "RequiresElevation")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public async Task<ActionResult> Diagnostics()
    {
        var people = new List<object>();
        foreach (var user in UserReflection.AllUsers(HttpContext.RequestServices) ?? Array.Empty<object>())
        {
            var type = user.GetType();
            if (type.GetProperty("Id")?.GetValue(user) is not Guid id)
            {
                continue;
            }

            var page = await _home.GetAsync(id, user, refresh: false).ConfigureAwait(false);
            people.Add(new
            {
                Name = type.GetProperty("Username")?.GetValue(user) as string ?? id.ToString("N"),
                page.Seeds,
                page.Library,
                page.Tmdb,
                Rows = page.Rows.Select(r => new { r.Kind, r.Label, Count = r.ItemIds.Count }).ToList()
            });
        }

        return Ok(new { People = people });
    }
}
