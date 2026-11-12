namespace Moonfin.Server;

/// <summary>
/// kOS TV: the address of the household requests service (Stremfin), as the admin typed it on
/// the settings page, made into what the apps can use.
/// </summary>
public static class KostvRequests
{
    /// <summary>
    /// The address as an https base without a trailing slash or the API path, or null when it is
    /// empty or not a web address. http is taken as https, since the apps only talk https.
    /// </summary>
    public static string? Normalize(string? raw)
    {
        var url = raw?.Trim();
        if (string.IsNullOrEmpty(url))
        {
            return null;
        }

        if (url.StartsWith("http://", StringComparison.OrdinalIgnoreCase))
        {
            url = "https://" + url.Substring(7);
        }
        else if (!url.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
        {
            url = "https://" + url;
        }

        url = url.TrimEnd('/');
        if (url.EndsWith("/api/v1", StringComparison.OrdinalIgnoreCase))
        {
            url = url.Substring(0, url.Length - "/api/v1".Length).TrimEnd('/');
        }

        if (!Uri.TryCreate(url, UriKind.Absolute, out var uri)
            || string.IsNullOrEmpty(uri.Host)
            || !string.IsNullOrEmpty(uri.Query)
            || !string.IsNullOrEmpty(uri.Fragment)
            || !string.IsNullOrEmpty(uri.UserInfo))
        {
            return null;
        }

        return url;
    }
}
