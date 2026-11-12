using MediaBrowser.Model.Tasks;
using Microsoft.Extensions.Logging;
using Moonfin.Server.Helpers;

namespace Moonfin.Server.Services;

/// <summary>
/// Builds the smart search index: downloads the model on first run, embeds the library, then
/// refreshes the TMDB catalog behind the Seerr row. Only changed entries are embedded again.
/// </summary>
public class SmartSearchIndexTask : IScheduledTask
{
    private readonly SmartSearchService _service;
    private readonly ILogger<SmartSearchIndexTask> _logger;

    public SmartSearchIndexTask(SmartSearchService service, ILogger<SmartSearchIndexTask> logger)
    {
        _service = service;
        _logger = logger;
    }

    public string Name => "kOS TV: índice de la búsqueda inteligente";

    public string Key => "Moonfin.SmartSearch.Index";

    public string Description => "Indexa la biblioteca y los títulos más populares de TMDB para poder buscar con frases.";

    public string Category => "kOS TV";

    public async Task ExecuteAsync(IProgress<double> progress, CancellationToken cancellationToken)
    {
        if (!SmartSearchService.Enabled)
        {
            _logger.LogInformation("Smart search index skipped: disabled in configuration");
            return;
        }

        await _service.RebuildAsync(progress, cancellationToken).ConfigureAwait(false);
    }

    public IEnumerable<TaskTriggerInfo> GetDefaultTriggers()
    {
        yield return TaskTriggers.Startup();
        yield return TaskTriggers.Daily(TimeSpan.FromHours(3));
    }
}
