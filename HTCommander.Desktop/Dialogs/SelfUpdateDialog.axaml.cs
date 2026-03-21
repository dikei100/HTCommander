using System;
using System.Net.Http;
using System.Reflection;
using System.Text.Json;
using System.Threading.Tasks;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Threading;

namespace HTCommander.Desktop.Dialogs
{
    public partial class SelfUpdateDialog : Window
    {
        private string _releaseUrl;

        public SelfUpdateDialog()
        {
            InitializeComponent();
            Loaded += async (_, _) => await CheckForUpdates();
        }

        private async Task CheckForUpdates()
        {
            try
            {
                var currentVersion = Assembly.GetEntryAssembly()?.GetName().Version;
                if (currentVersion == null)
                {
                    TitleText.Text = "Error";
                    VersionInfo.Text = "Could not determine current version.";
                    return;
                }

                using var client = new HttpClient();
                client.DefaultRequestHeaders.Add("User-Agent", "HTCommander-X");
                client.Timeout = TimeSpan.FromSeconds(15);

                var response = await client.GetStringAsync(
                    "https://api.github.com/repos/dikei100/HTCommander-X/releases/latest");

                using var doc = JsonDocument.Parse(response);
                var root = doc.RootElement;

                var tagName = root.GetProperty("tag_name").GetString();
                _releaseUrl = root.GetProperty("html_url").GetString();

                if (string.IsNullOrEmpty(tagName))
                {
                    TitleText.Text = "Error";
                    VersionInfo.Text = "Could not parse release information.";
                    return;
                }

                // Parse tag like "v0.1.3" into a Version
                var versionStr = tagName.TrimStart('v');
                if (!Version.TryParse(versionStr, out var latestVersion))
                {
                    TitleText.Text = "Error";
                    VersionInfo.Text = $"Could not parse version from tag: {tagName}";
                    return;
                }

                // Compare major.minor.build (ignore revision)
                var current = new Version(currentVersion.Major, currentVersion.Minor, currentVersion.Build);
                var latest = new Version(latestVersion.Major, latestVersion.Minor,
                    latestVersion.Build >= 0 ? latestVersion.Build : 0);

                if (latest > current)
                {
                    TitleText.Text = "Update Available";
                    VersionInfo.Text = $"A new version ({versionStr}) is available. You are running {current}.";
                    ViewReleaseButton.IsVisible = true;
                }
                else
                {
                    TitleText.Text = "Up to Date";
                    VersionInfo.Text = $"You are running the latest version ({current}).";
                }
            }
            catch (TaskCanceledException)
            {
                TitleText.Text = "Error";
                VersionInfo.Text = "Connection timed out. Please check your internet connection.";
            }
            catch (Exception)
            {
                TitleText.Text = "Error";
                VersionInfo.Text = "Could not check for updates. Please check your internet connection and try again.";
            }
        }

        private void ViewReleaseButton_Click(object sender, RoutedEventArgs e)
        {
            if (!string.IsNullOrEmpty(_releaseUrl) &&
                Uri.TryCreate(_releaseUrl, UriKind.Absolute, out Uri releaseUri) &&
                releaseUri.Scheme == "https" &&
                releaseUri.Host == "github.com" &&
                releaseUri.AbsolutePath.StartsWith("/dikei100/HTCommander-X/releases/"))
            {
                Program.PlatformServices?.PlatformUtils?.OpenUrl(_releaseUrl);
            }
        }

        private void CloseButton_Click(object sender, RoutedEventArgs e) => Close();
    }
}
