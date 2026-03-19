using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Net.Http;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Media;

namespace HTCommander.Desktop.Dialogs
{
    public class AprsRouteItem
    {
        public string Name { get; set; }
        public string Route { get; set; }
    }

    public partial class SettingsDialog : Window
    {
        private DataBrokerClient broker;
        private ObservableCollection<AprsRouteItem> aprsRoutes = new ObservableCollection<AprsRouteItem>();
        private string _originalGpsPort;
        private int _originalGpsBaud;

        public SettingsDialog()
        {
            InitializeComponent();
            broker = new DataBrokerClient();
            LoadSettings();
        }

        private void LoadSettings()
        {
            // License / General
            CallSignBox.Text = DataBroker.GetValue<string>(0, "CallSign", "");
            for (int i = 0; i <= 15; i++) StationIdCombo.Items.Add(i.ToString());
            int stationId = DataBroker.GetValue<int>(0, "StationId", 0);
            StationIdCombo.SelectedIndex = Math.Min(stationId, 15);
            AllowTransmitCheck.IsChecked = DataBroker.GetValue<int>(0, "AllowTransmit", 0) == 1;
            CheckUpdatesCheck.IsChecked = DataBroker.GetValue<bool>(0, "CheckForUpdates", false);
            UpdateTransmitState();

            // APRS routes
            string routeStr = DataBroker.GetValue<string>(0, "AprsRoutes", "");
            if (string.IsNullOrEmpty(routeStr))
                routeStr = "Standard|APN000,WIDE1-1,WIDE2-2";
            foreach (string entry in routeStr.Split('|'))
            {
                int comma = entry.IndexOf(',');
                if (comma > 0)
                    aprsRoutes.Add(new AprsRouteItem { Name = entry.Substring(0, comma), Route = entry.Substring(comma + 1) });
            }
            AprsRoutesGrid.ItemsSource = aprsRoutes;

            // Voice
            VoiceLanguageCombo.Items.Add("auto");
            VoiceLanguageCombo.SelectedIndex = 0;
            string voiceLang = DataBroker.GetValue<string>(0, "VoiceLanguage", "auto");
            for (int i = 0; i < VoiceLanguageCombo.Items.Count; i++)
            {
                if (VoiceLanguageCombo.Items[i]?.ToString() == voiceLang) { VoiceLanguageCombo.SelectedIndex = i; break; }
            }

            var speech = Program.PlatformServices?.Speech;
            if (speech != null && speech.IsAvailable)
            {
                foreach (var voice in speech.GetVoices()) VoiceCombo.Items.Add(voice);
                string selectedVoice = DataBroker.GetValue<string>(0, "Voice", "");
                for (int i = 0; i < VoiceCombo.Items.Count; i++)
                {
                    if (VoiceCombo.Items[i]?.ToString() == selectedVoice) { VoiceCombo.SelectedIndex = i; break; }
                }
            }
            SpeechToTextCheck.IsChecked = DataBroker.GetValue<bool>(0, "SpeechToText", false);

            // Winlink
            WinlinkPasswordBox.Text = DataBroker.GetValue<string>(0, "WinlinkPassword", "");
            WinlinkUseStationIdCheck.IsChecked = DataBroker.GetValue<int>(0, "WinlinkUseStationId", 0) == 1;

            // Servers
            WebServerCheck.IsChecked = DataBroker.GetValue<int>(0, "WebServerEnabled", 0) == 1;
            WebPortUpDown.Value = DataBroker.GetValue<int>(0, "WebServerPort", 8080);
            AgwpeServerCheck.IsChecked = DataBroker.GetValue<int>(0, "AgwpeServerEnabled", 0) == 1;
            AgwpePortUpDown.Value = DataBroker.GetValue<int>(0, "AgwpeServerPort", 8000);

            // Data Sources
            AirplaneServerBox.Text = DataBroker.GetValue<string>(0, "AirplaneServer", "");

            // GPS
            GpsPortCombo.Items.Add("None");
            try
            {
                foreach (var port in System.IO.Ports.SerialPort.GetPortNames())
                    GpsPortCombo.Items.Add(port);
            }
            catch { }
            _originalGpsPort = DataBroker.GetValue<string>(0, "GpsSerialPort", "None");
            _originalGpsBaud = DataBroker.GetValue<int>(0, "GpsBaudRate", 4800);
            for (int i = 0; i < GpsPortCombo.Items.Count; i++)
            {
                if (GpsPortCombo.Items[i]?.ToString() == _originalGpsPort) { GpsPortCombo.SelectedIndex = i; break; }
            }
            if (GpsPortCombo.SelectedIndex < 0) GpsPortCombo.SelectedIndex = 0;

            // Select matching baud rate
            string baudStr = _originalGpsBaud.ToString();
            for (int i = 0; i < GpsBaudCombo.Items.Count; i++)
            {
                if (GpsBaudCombo.Items[i] is ComboBoxItem item && item.Content?.ToString() == baudStr)
                {
                    GpsBaudCombo.SelectedIndex = i; break;
                }
            }
            if (GpsBaudCombo.SelectedIndex < 0) GpsBaudCombo.SelectedIndex = 0;

            // Audio devices
            var audio = Program.PlatformServices?.Audio;
            if (audio != null)
            {
                foreach (var dev in audio.GetOutputDevices()) OutputDeviceCombo.Items.Add(dev);
                foreach (var dev in audio.GetInputDevices()) InputDeviceCombo.Items.Add(dev);

                string savedOutput = DataBroker.GetValue<string>(0, "AudioOutputDevice", "");
                string savedInput = DataBroker.GetValue<string>(0, "AudioInputDevice", "");
                for (int i = 0; i < OutputDeviceCombo.Items.Count; i++)
                {
                    if (OutputDeviceCombo.Items[i]?.ToString() == savedOutput) { OutputDeviceCombo.SelectedIndex = i; break; }
                }
                for (int i = 0; i < InputDeviceCombo.Items.Count; i++)
                {
                    if (InputDeviceCombo.Items[i]?.ToString() == savedInput) { InputDeviceCombo.SelectedIndex = i; break; }
                }
            }
        }

        private void SaveSettings()
        {
            DataBroker.Dispatch(0, "CallSign", CallSignBox.Text?.ToUpper() ?? "");
            DataBroker.Dispatch(0, "StationId", StationIdCombo.SelectedIndex);
            DataBroker.Dispatch(0, "AllowTransmit", AllowTransmitCheck.IsChecked == true ? 1 : 0);
            DataBroker.Dispatch(0, "CheckForUpdates", CheckUpdatesCheck.IsChecked == true);

            // APRS routes → pipe-delimited string
            var parts = new List<string>();
            foreach (var r in aprsRoutes) parts.Add($"{r.Name},{r.Route}");
            DataBroker.Dispatch(0, "AprsRoutes", string.Join("|", parts));

            // Voice
            DataBroker.Dispatch(0, "VoiceLanguage", VoiceLanguageCombo.SelectedItem?.ToString() ?? "auto");
            DataBroker.Dispatch(0, "Voice", VoiceCombo.SelectedItem?.ToString() ?? "");
            DataBroker.Dispatch(0, "SpeechToText", SpeechToTextCheck.IsChecked == true);

            // Winlink
            DataBroker.Dispatch(0, "WinlinkPassword", WinlinkPasswordBox.Text ?? "");
            DataBroker.Dispatch(0, "WinlinkUseStationId", WinlinkUseStationIdCheck.IsChecked == true ? 1 : 0);

            // Servers
            DataBroker.Dispatch(0, "WebServerEnabled", WebServerCheck.IsChecked == true ? 1 : 0);
            DataBroker.Dispatch(0, "WebServerPort", (int)(WebPortUpDown.Value ?? 8080));
            DataBroker.Dispatch(0, "AgwpeServerEnabled", AgwpeServerCheck.IsChecked == true ? 1 : 0);
            DataBroker.Dispatch(0, "AgwpeServerPort", (int)(AgwpePortUpDown.Value ?? 8000));

            // Data sources
            DataBroker.Dispatch(0, "AirplaneServer", AirplaneServerBox.Text ?? "");
            DataBroker.Dispatch(0, "GpsSerialPort", GpsPortCombo.SelectedItem?.ToString() ?? "None");
            int baud = 4800;
            if (GpsBaudCombo.SelectedItem is ComboBoxItem bi) int.TryParse(bi.Content?.ToString(), out baud);
            DataBroker.Dispatch(0, "GpsBaudRate", baud);

            // Audio
            DataBroker.Dispatch(0, "AudioOutputDevice", OutputDeviceCombo.SelectedItem?.ToString() ?? "");
            DataBroker.Dispatch(0, "AudioInputDevice", InputDeviceCombo.SelectedItem?.ToString() ?? "");
        }

        private void UpdateTransmitState()
        {
            string callSign = CallSignBox.Text?.Trim() ?? "";
            bool valid = callSign.Length >= 3;
            AllowTransmitCheck.IsEnabled = valid;
            TransmitWarning.IsVisible = !valid;
            if (!valid) AllowTransmitCheck.IsChecked = false;
        }

        private void CallSignBox_TextChanged(object sender, TextChangedEventArgs e)
        {
            UpdateTransmitState();
        }

        private void AprsRoutesGrid_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            bool hasSelection = AprsRoutesGrid.SelectedItem != null;
            EditRouteBtn.IsEnabled = hasSelection;
            DeleteRouteBtn.IsEnabled = hasSelection;
        }

        private async void AddRoute_Click(object sender, RoutedEventArgs e)
        {
            var dialog = new AprsRouteDialog();
            await dialog.ShowDialog(this);
            if (dialog.Confirmed)
            {
                aprsRoutes.Add(new AprsRouteItem { Name = dialog.RouteName, Route = dialog.RouteValue });
            }
        }

        private async void EditRoute_Click(object sender, RoutedEventArgs e)
        {
            if (AprsRoutesGrid.SelectedItem is not AprsRouteItem item) return;
            var dialog = new AprsRouteDialog(item.Name, item.Route);
            await dialog.ShowDialog(this);
            if (dialog.Confirmed)
            {
                item.Name = dialog.RouteName;
                item.Route = dialog.RouteValue;
                // Refresh grid
                var items = new ObservableCollection<AprsRouteItem>(aprsRoutes);
                aprsRoutes = items;
                AprsRoutesGrid.ItemsSource = aprsRoutes;
            }
        }

        private void DeleteRoute_Click(object sender, RoutedEventArgs e)
        {
            if (AprsRoutesGrid.SelectedItem is AprsRouteItem item)
                aprsRoutes.Remove(item);
        }

        private async void TestAirplaneServer_Click(object sender, RoutedEventArgs e)
        {
            string url = AirplaneServerBox.Text?.Trim();
            if (string.IsNullOrEmpty(url))
            {
                AirplaneTestResult.Text = "Enter a URL first.";
                AirplaneTestResult.Foreground = new SolidColorBrush(Color.Parse("#F44336"));
                return;
            }

            AirplaneTestResult.Text = "Testing...";
            AirplaneTestResult.Foreground = new SolidColorBrush(Color.Parse("#888"));
            try
            {
                using var client = new HttpClient();
                client.Timeout = TimeSpan.FromSeconds(5);
                var response = await client.GetAsync(url);
                if (response.IsSuccessStatusCode)
                {
                    AirplaneTestResult.Text = "Connection successful!";
                    AirplaneTestResult.Foreground = new SolidColorBrush(Color.Parse("#4CAF50"));
                }
                else
                {
                    AirplaneTestResult.Text = $"HTTP {(int)response.StatusCode}: {response.ReasonPhrase}";
                    AirplaneTestResult.Foreground = new SolidColorBrush(Color.Parse("#F44336"));
                }
            }
            catch (Exception ex)
            {
                AirplaneTestResult.Text = $"Error: {ex.Message}";
                AirplaneTestResult.Foreground = new SolidColorBrush(Color.Parse("#F44336"));
            }
        }

        private bool ValidateSettings()
        {
            // Check port conflict
            if (WebServerCheck.IsChecked == true && AgwpeServerCheck.IsChecked == true &&
                (int)(WebPortUpDown.Value ?? 0) == (int)(AgwpePortUpDown.Value ?? 0))
            {
                PortWarning.Text = "Web Server and AGWPE Server cannot use the same port.";
                return false;
            }
            PortWarning.Text = "";
            return true;
        }

        private void OkButton_Click(object sender, RoutedEventArgs e)
        {
            if (!ValidateSettings()) return;
            SaveSettings();
            Close();
        }

        private void CancelButton_Click(object sender, RoutedEventArgs e)
        {
            // Restore original GPS settings (they may have been applied immediately)
            DataBroker.Dispatch(0, "GpsSerialPort", _originalGpsPort);
            DataBroker.Dispatch(0, "GpsBaudRate", _originalGpsBaud);
            Close();
        }

        protected override void OnClosed(EventArgs e)
        {
            broker?.Dispose();
            base.OnClosed(e);
        }
    }
}
