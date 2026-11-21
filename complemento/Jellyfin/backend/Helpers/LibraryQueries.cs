using System.Reflection;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Library;

namespace Moonfin.Server.Helpers;

/// <summary>
/// Kos TV: library reads whose compiled form only binds on the server version it was built
/// against. Jellyfin 10.11 turned ILibraryManager.GetItemList and GetItemIds from List into
/// IReadOnlyList and dropped InternalItemsQuery.SimilarTo, so a call compiled against 10.10
/// fails with MissingMethodException on 10.11 and 12 (and fails the whole calling method, before
/// any try in it runs). These bind by name and work on 10.10 to 12.
/// </summary>
internal static class LibraryQueries
{
    // Matched on the return type being a list of items/ids, whichever list it is.
    private static readonly MethodInfo? GetItemListMethod = Find("GetItemList", typeof(IEnumerable<BaseItem>));
    private static readonly MethodInfo? GetItemIdsMethod = Find("GetItemIds", typeof(IEnumerable<Guid>));

    /// <summary>InternalItemsQuery.SimilarTo, which only 10.10 has.</summary>
    internal static readonly PropertyInfo? SimilarToProperty =
        typeof(InternalItemsQuery).GetProperty("SimilarTo", BindingFlags.Public | BindingFlags.Instance);

    /// <summary>
    /// ILibraryManager.GetItemList, as the server has it. Only when it has none, GetItemsResult,
    /// which has the same signature everywhere (on 10.10 it doesn't drop what the query's user may
    /// not see one by one as GetItemList does, so it is only the fallback for queries with a user).
    /// </summary>
    public static IReadOnlyList<BaseItem> ItemList(ILibraryManager library, InternalItemsQuery query)
    {
        if (GetItemListMethod == null)
        {
            return library.GetItemsResult(query).Items;
        }

        var items = Invoke(GetItemListMethod, library, query);
        return items as IReadOnlyList<BaseItem> ?? ((IEnumerable<BaseItem>?)items ?? []).ToList();
    }

    /// <summary>ILibraryManager.GetItemIds, as the server has it; null when it has none.</summary>
    public static List<Guid>? ItemIds(ILibraryManager library, InternalItemsQuery query) =>
        GetItemIdsMethod == null ? null : ((IEnumerable<Guid>?)Invoke(GetItemIdsMethod, library, query) ?? []).ToList();

    private static MethodInfo? Find(string name, Type returns) => typeof(ILibraryManager)
        .GetMethods()
        .FirstOrDefault(m =>
            m.Name == name &&
            m.GetParameters() is [{ ParameterType: var type }] &&
            type == typeof(InternalItemsQuery) &&
            returns.IsAssignableFrom(m.ReturnType));

    // The server's own exception, not the reflection wrapper, so callers log what went wrong.
    private static object? Invoke(MethodInfo method, ILibraryManager library, InternalItemsQuery query)
    {
        try
        {
            return method.Invoke(library, [query]);
        }
        catch (TargetInvocationException ex) when (ex.InnerException != null)
        {
            System.Runtime.ExceptionServices.ExceptionDispatchInfo.Capture(ex.InnerException).Throw();
            throw;
        }
    }
}
