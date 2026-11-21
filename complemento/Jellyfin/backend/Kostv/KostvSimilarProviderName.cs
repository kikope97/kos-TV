using System.Reflection;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Library;
using MediaBrowser.Model.Configuration;
using Microsoft.Extensions.Logging;

namespace Moonfin.Server.Kostv;

/// <summary>
/// kOS TV: the name the similar items provider goes by on Jellyfin 12, where the dashboard lists
/// it under each library's similar items providers. Upstream calls it by its own brand; a library
/// saves its providers (and their order) by name, so the libraries saved under the old name are
/// moved over to the new one, in the same place, when the plugin starts.
/// </summary>
public static class KostvSimilarProviderName
{
    /// <summary>The name the dashboard shows.</summary>
    public const string Current = "kOS TV";

    /// <summary>The name upstream registers it under, which older saved libraries still hold.</summary>
    internal const string Previous = "Moonfin Recommends";

    // TypeOptions only has these from Jellyfin 12 on, and the plugin compiles against 10.10, so
    // they are bound by name.
    private const string ProvidersProperty = "SimilarItemProviders";
    private const string OrderProperty = "SimilarItemProviderOrder";

    /// <summary>
    /// <paramref name="names"/> with the old name swapped for the new one in the same place, or
    /// null when there is nothing to change. If both are there, the old one is just dropped.
    /// </summary>
    public static string[]? Renamed(string[]? names)
    {
        if (names is null || !names.Any(IsPrevious))
        {
            return null;
        }

        var hasCurrent = names.Any(n => string.Equals(n, Current, StringComparison.OrdinalIgnoreCase));
        var result = new List<string>(names.Length);
        foreach (var name in names)
        {
            if (!IsPrevious(name))
            {
                result.Add(name);
            }
            else if (!hasCurrent)
            {
                result.Add(Current);
                hasCurrent = true;
            }
        }

        return result.ToArray();
    }

    /// <summary>
    /// Renames the provider in one item type's options (any object with Jellyfin 12's two string
    /// array properties). False when it had nothing to rename or the properties are not there.
    /// </summary>
    public static bool RenameIn(object? typeOptions)
    {
        if (typeOptions is null)
        {
            return false;
        }

        var changed = false;
        foreach (var propertyName in new[] { ProvidersProperty, OrderProperty })
        {
            var property = typeOptions.GetType().GetProperty(propertyName, BindingFlags.Instance | BindingFlags.Public);
            if (property is null || property.PropertyType != typeof(string[]) || !property.CanRead || !property.CanWrite)
            {
                continue;
            }

            if (Renamed(property.GetValue(typeOptions) as string[]) is { } renamed)
            {
                property.SetValue(typeOptions, renamed);
                changed = true;
            }
        }

        return changed;
    }

    /// <summary>
    /// Moves every library saved under the old name over to the new one and saves it. Does
    /// nothing on servers whose libraries have no similar items providers (before Jellyfin 12),
    /// and nothing once every library is moved, so it is safe on every start. Returns how many
    /// libraries it saved.
    /// </summary>
    public static int RenameInLibraries(ILibraryManager libraryManager, ILogger logger)
    {
        if (typeof(TypeOptions).GetProperty(ProvidersProperty) is null)
        {
            return 0;
        }

        var saved = 0;
        foreach (var folder in libraryManager.GetVirtualFolders(false))
        {
            try
            {
                var options = folder.LibraryOptions;
                if (options?.TypeOptions is not { Length: > 0 } typeOptions)
                {
                    continue;
                }

                var changed = false;
                foreach (var forType in typeOptions)
                {
                    changed |= RenameIn(forType);
                }

                if (!changed)
                {
                    continue;
                }

                // As Jellyfin's own migrations do: the options are saved through the library's
                // collection folder.
                if (!Guid.TryParse(folder.ItemId, out var folderId)
                    || libraryManager.GetItemById(folderId) is not CollectionFolder collectionFolder)
                {
                    logger.LogWarning(
                        "Could not find library '{LibraryName}' to rename its similar items provider to {ProviderName}; it will be tried again on the next start.",
                        folder.Name,
                        Current);
                    continue;
                }

                collectionFolder.UpdateLibraryOptions(options);
                saved++;
                logger.LogInformation(
                    "Similar items provider renamed to {ProviderName} in library '{LibraryName}', in the same place.",
                    Current,
                    folder.Name);
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "Could not rename the similar items provider in library '{LibraryName}'.", folder.Name);
            }
        }

        return saved;
    }

    private static bool IsPrevious(string? name) =>
        string.Equals(name, Previous, StringComparison.OrdinalIgnoreCase);
}
