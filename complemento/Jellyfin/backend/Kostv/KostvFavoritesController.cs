using Jellyfin.Data.Enums;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Moonfin.Server.Api;
using Moonfin.Server.Helpers;
using Moonfin.Server.Services;

namespace Moonfin.Server.Kostv;

/// <summary>
/// kOS TV: each person's favourites the way the app shows them: newest marked first, and what
/// arrived lately of their favourite series.
/// </summary>
[ApiController]
[Route("Moonfin/Kostv/Favorites")]
[Produces("application/json")]
public class KostvFavoritesController : ControllerBase
{
    private readonly KostvHomeService _home;
    private readonly ItemCardDtoMapper _cards;

    public KostvFavoritesController(KostvHomeService home, ItemCardDtoMapper cards)
    {
        _home = home;
        _cards = cards;
    }

    /// <summary>
    /// The caller's favourites of <paramref name="types"/> ("Movie,Series"), newest marked first,
    /// or the other way with <paramref name="ascending"/>: <paramref name="limit"/> from
    /// <paramref name="start"/>, as the server's own item lists.
    /// </summary>
    [HttpGet]
    [Authorize]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public ActionResult Get(
        [FromQuery] string types,
        [FromQuery] int start = 0,
        [FromQuery] int limit = 30,
        [FromQuery] bool ascending = false)
    {
        var userId = this.GetUserIdFromClaims();
        var user = userId.HasValue ? UserReflection.ResolveUser(HttpContext.RequestServices, userId.Value) : null;
        if (userId == null || user == null)
        {
            return Unauthorized(new { Error = "User not authenticated" });
        }

        var kinds = (types ?? string.Empty)
            .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Select(t => Enum.TryParse<BaseItemKind>(t, ignoreCase: true, out var kind) ? kind : (BaseItemKind?)null)
            .OfType<BaseItemKind>()
            .Distinct()
            .ToArray();
        if (kinds.Length == 0)
        {
            return BadRequest(new { Error = "No item types" });
        }

        var (items, total) = _home.FavoritesByAdded(userId.Value, user, kinds, start, limit, ascending);
        return Ok(new
        {
            Items = items.Select(item => _cards.Map(item, user)).ToList(),
            TotalRecordCount = total,
            StartIndex = start
        });
    }

    /// <summary>
    /// What arrived lately of the caller's favourite series, the latest first: the series, its
    /// first new episode, how many, whether a season is new, and whether they have seen it.
    /// </summary>
    [HttpGet("News")]
    [Authorize]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public ActionResult News()
    {
        var userId = this.GetUserIdFromClaims();
        var user = userId.HasValue ? UserReflection.ResolveUser(HttpContext.RequestServices, userId.Value) : null;
        if (userId == null || user == null)
        {
            return Unauthorized(new { Error = "User not authenticated" });
        }

        var news = _home.FavoriteNews(userId.Value, user);
        return Ok(new
        {
            Series = news.Select(n => new
            {
                Series = _cards.Map(n.Series, user),
                Episode = _cards.Map(n.Episode, user),
                n.News.Count,
                n.News.NewSeason,
                n.News.Season,
                Latest = n.News.Latest,
                n.News.Unseen
            }).ToList(),
            Unseen = news.Count(n => n.News.Unseen)
        });
    }

    /// <summary>The caller has seen the news of their favourite series: the alert goes.</summary>
    [HttpPost("News/Seen")]
    [Authorize]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    public async Task<ActionResult> NewsSeen()
    {
        var userId = this.GetUserIdFromClaims();
        if (userId == null)
        {
            return Unauthorized(new { Error = "User not authenticated" });
        }

        await _home.FavoriteNewsSeenAsync(userId.Value).ConfigureAwait(false);
        return NoContent();
    }
}
