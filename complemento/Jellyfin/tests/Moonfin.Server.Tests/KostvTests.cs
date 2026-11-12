using System.Text.Json;
using Moonfin.Server.Api;
using Moonfin.Server.Models;
using Xunit;

namespace Moonfin.Server.Tests;

/// <summary>
/// kOS TV: what the plugin adds for its apps.
/// </summary>
public sealed class KostvTests
{
    [Fact]
    public void TheDiscoverButtonTravelsUnderTheAppsWireName()
    {
        var json = JsonSerializer.Serialize(new MoonfinSettingsProfile { ShowDiscoverButton = false });

        Assert.Contains("\"showDiscoverButton\":false", json);
        Assert.False(JsonSerializer.Deserialize<MoonfinSettingsProfile>(json)!.ShowDiscoverButton);
    }

    [Fact]
    public void PingCarriesTheRequestsServiceUnderTheAppsWireName()
    {
        var json = JsonSerializer.Serialize(new MoonfinPingResponse { KostvRequestsUrl = "https://peticiones.example.com" });

        Assert.Contains("\"kostvRequestsUrl\":\"https://peticiones.example.com\"", json);
    }

    [Theory]
    [InlineData("https://peticiones.example.com", "https://peticiones.example.com")]
    [InlineData("  https://peticiones.example.com/  ", "https://peticiones.example.com")]
    [InlineData("http://peticiones.example.com", "https://peticiones.example.com")]
    [InlineData("peticiones.example.com", "https://peticiones.example.com")]
    [InlineData("https://peticiones.example.com:8443/stremfin/api/v1/", "https://peticiones.example.com:8443/stremfin")]
    [InlineData("https://example.com/stremfin", "https://example.com/stremfin")]
    public void TheRequestsServiceIsAnHttpsBase(string typed, string expected)
    {
        Assert.Equal(expected, KostvRequests.Normalize(typed));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("https://")]
    [InlineData("https://peticiones.example.com/?token=x")]
    [InlineData("https://persona:clave@peticiones.example.com")]
    public void AnythingElseIsNoRequestsService(string? typed)
    {
        Assert.Null(KostvRequests.Normalize(typed));
    }
}
