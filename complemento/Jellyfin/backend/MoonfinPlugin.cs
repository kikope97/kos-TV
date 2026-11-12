using MediaBrowser.Common.Configuration;
using MediaBrowser.Common.Plugins;
using MediaBrowser.Model.Plugins;
using MediaBrowser.Model.Serialization;
using Microsoft.Extensions.DependencyInjection;
using Moonfin.Games;
using Moonfin.Server.Services;

namespace Moonfin.Server;

public class MoonfinPlugin : BasePlugin<PluginConfiguration>, IHasWebPages
{
    public static MoonfinPlugin? Instance { get; private set; }

    private bool _webhookSecretFailed;

    public IServiceProvider? ServiceProvider { get; }

    public MoonfinPlugin(IApplicationPaths applicationPaths, IXmlSerializer xmlSerializer)
        : this(applicationPaths, xmlSerializer, null)
    {
    }

    public MoonfinPlugin(IApplicationPaths applicationPaths, IXmlSerializer xmlSerializer, IServiceProvider? serviceProvider)
        : base(applicationPaths, xmlSerializer)
    {
        Instance = this;
        ServiceProvider = serviceProvider;
        GamesHost.Config = () => Instance?.Configuration;
        GamesHost.DataFolderPath = () => Instance?.DataFolderPath;

        // Nothing here is allowed to throw. Jellyfin reads an exception out of this constructor
        // as the plugin malfunctioning, writes that into meta.json, and deletes the folder on the
        // next startup. Touching Configuration is enough to get there, since Jellyfin answers an
        // unreadable config by writing defaults over it and a failing write escapes.
        TryEnsureWebhookSecret();
    }

    /// <summary>
    /// Swallows any failure, and is safe to call again since it only writes when something changed.
    /// </summary>
    private void TryEnsureWebhookSecret()
    {
        try
        {
            if (Configuration.EnsureWebhookSecret())
            {
                SaveConfiguration();
            }

            _webhookSecretFailed = false;
        }
        catch (Exception)
        {
            _webhookSecretFailed = true;
        }
    }

    /// <inheritdoc />
    public override string Name => "kOS TV";

    /// <inheritdoc />
    public override string Description => "Complemento del servidor de kOS TV, basado en Moonbase (el complemento oficial de Moonfin, GPLv3): sincroniza los ajustes de cada persona entre sus aparatos, con los valores por defecto del administrador; valoraciones (MDBList y TMDB), filas de listas y de temporada, búsqueda inteligente, ver juntos, avisos y PIN de perfiles.";

    /// <inheritdoc />
    public override Guid Id => Guid.Parse("561f86df-fa00-4fca-aa4d-2fed0e332670");

    public new string DataFolderPath => Path.Combine(ApplicationPaths.PluginConfigurationsPath, "Moonfin");

    /// <summary>
    /// Resolves the log folder path for the plugin, falling back to the data folder if the log directory is unavailable.
    /// </summary>
    public static string ResolveLogFolderPath()
    {
        try
        {
            var path = Instance?.ApplicationPaths.LogDirectoryPath;
            if (!string.IsNullOrWhiteSpace(path))
            {
                return path;
            }
        }
        catch
        {
            // A host that wont hand over its log directory just means the log lands in the
            // data folder instead, which is still somewhere the admin can reach.
        }

        return ResolveDataFolderPath();
    }

    public static string ResolveDataFolderPath() =>
        Instance?.DataFolderPath
        ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Jellyfin", "plugins", "Moonfin");

    /// <inheritdoc />
    public override void UpdateConfiguration(BasePluginConfiguration configuration)
    {
        if (_webhookSecretFailed)
        {
            // Startup failed, most likely on transient I/O. A save is a good moment to retry.
            TryEnsureWebhookSecret();
        }

        var previousUrl = Configuration.PublicServerUrl;
        var previousGamesEnabled = Configuration.GamesEnabled;
        var previousGameLibraryIds = Configuration.GameLibraryIds?.ToList() ?? new List<string>();
        var previousRomm = RommSignature(Configuration);
        var previousHideWatched = HideWatchedDefaults(Configuration);
        base.UpdateConfiguration(configuration);

        // Users who inherit a changed Hide Watched default get their HidePlayedInLatest moved to match.
        if (HideWatchedDefaults(Configuration) != previousHideWatched)
        {
            _ = ServiceProvider?.GetService<MoonfinSettingsService>()?.SyncHideWatchedForAffectedUsersAsync(CancellationToken.None);
        }

        // Re-provision the Seerr webhook when the public URL changes, so the new URL is
        // pushed to Seerr without waiting for a restart. The provisioning guardrail only
        // overwrites our own webhook.
        var newUrl = Configuration.PublicServerUrl;
        if (!string.Equals(previousUrl, newUrl, StringComparison.Ordinal))
        {
            var provisioning = ServiceProvider?.GetService<SeerrProvisioningService>();
            if (provisioning != null)
            {
                _ = provisioning.EnsureWebhookAsync(default);
            }
        }

        // Re-watch and re-scan the ROM roots when the selected game libraries change, so a newly
        // picked library's games acquire artwork without waiting for a scheduled scan or a restart.
        // GameArtworkReconciliationService is registered as a concrete singleton and reused as the
        // hosted service (see PluginServiceRegistrator), so this resolves the running instance.
        // Turning retro games on counts too. Reconciliation never reads GamesEnabled, so this
        // is a convenience re-sync rather than something correctness depends on.
        var newGameLibraryIds = Configuration.GameLibraryIds ?? new List<string>();
        if (previousGamesEnabled != Configuration.GamesEnabled ||
            !string.Equals(previousRomm, RommSignature(Configuration), StringComparison.Ordinal) ||
            !previousGameLibraryIds.OrderBy(id => id, StringComparer.OrdinalIgnoreCase)
                .SequenceEqual(newGameLibraryIds.OrderBy(id => id, StringComparer.OrdinalIgnoreCase), StringComparer.OrdinalIgnoreCase))
        {
            try
            {
                ServiceProvider?.GetService<GameArtworkReconciliationService>()?.OnGameLibrariesChanged();
            }
            catch (Exception)
            {
                // Saving the configuration must succeed even if reconciliation cannot be signalled;
                // the next scheduled scan or restart still picks the change up. There is no logger
                // on the plugin instance, and the signal itself only sets a semaphore, so there is
                // nothing here worth taking the config-save request path down for.
            }
        }
    }

    private static (bool?, bool?, bool?, bool?) HideWatchedDefaults(PluginConfiguration config) => (
        config.DefaultUserSettings?.HideWatchedInRecentRows,
        config.GetDefaultsFor("tv")?.HideWatchedInRecentRows,
        config.GetDefaultsFor("desktop")?.HideWatchedInRecentRows,
        config.GetDefaultsFor("mobile")?.HideWatchedInRecentRows);

    private static string RommSignature(PluginConfiguration config) =>
        config.GamesRommUrl + "\n" + config.GamesRommToken + "\n" + config.GamesRommLibraryId;

    /// <inheritdoc />
    public IEnumerable<PluginPageInfo> GetPages()
    {
        return new[]
        {
            new PluginPageInfo
            {
                // kOS TV: the page's own name, without spaces, for its address
                // (configurationpage?name=kOSTV).
                Name = "kOSTV",
                EmbeddedResourcePath = GetType().Namespace + ".Pages.configPage.html",
                EnableInMainMenu = true,
                // kOS TV: a television, from Material Icons (the only thing this slot takes).
                MenuIcon = "live_tv"
            }
        };
    }
}
