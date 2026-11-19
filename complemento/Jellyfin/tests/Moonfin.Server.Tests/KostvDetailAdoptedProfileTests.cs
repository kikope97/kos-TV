using System.Text.Json;
using Moonfin.Server.Models;
using Moonfin.Server.Services;
using Xunit;

namespace Moonfin.Server.Tests;

/// <summary>
/// Kos TV: the app's "already moved to the kOS TV page" mark travels with the detail style, so
/// a style picked by hand on one device isn't moved again by the next one to read it.
/// </summary>
public sealed class KostvDetailAdoptedProfileTests : IDisposable
{
    private readonly string _dataPath;
    private readonly MoonfinSettingsService _service;

    public KostvDetailAdoptedProfileTests()
    {
        _dataPath = Path.Combine(Path.GetTempPath(), "kostv-detail-adopted-tests-" + Guid.NewGuid().ToString("N"));
        _service = new MoonfinSettingsService(new NoOpLogger<MoonfinSettingsService>(), _dataPath);
    }

    public void Dispose()
    {
        if (Directory.Exists(_dataPath))
        {
            Directory.Delete(_dataPath, recursive: true);
        }
    }

    [Fact]
    public void TheFieldUsesTheClientsWireName()
    {
        var json = JsonSerializer.Serialize(new MoonfinSettingsProfile { KostvDetailAdopted = true });

        Assert.Contains("\"kostvDetailAdopted\":true", json);
        Assert.True(JsonSerializer.Deserialize<MoonfinSettingsProfile>(json)!.KostvDetailAdopted);
    }

    [Fact]
    public async Task TheMarkComesBackWithTheStyle()
    {
        var userId = Guid.NewGuid();
        await _service.SaveProfileAsync(
            userId,
            "global",
            new MoonfinSettingsProfile { DetailScreenStyle = "frost", KostvDetailAdopted = true },
            "client",
            notifySettingsChanged: false);

        var resolved = await _service.GetResolvedProfileAsync(userId, "mobile");
        Assert.Equal("frost", resolved!.DetailScreenStyle);
        Assert.True(resolved.KostvDetailAdopted);
    }
}
