using System;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Media;
using Avalonia.Threading;

namespace HTCommander.Desktop.Dialogs
{
    public partial class RadioAudioDialog : Window
    {
        private DataBrokerClient broker;
        private int deviceId;
        private bool isLoading = true;

        // Microphone capture
        private IAudioInput micInput;
        private bool isTransmitting = false;
        private int captureSampleRate;
        private int captureChannels;

        public RadioAudioDialog()
        {
            InitializeComponent();
        }

        public RadioAudioDialog(int deviceId)
        {
            InitializeComponent();
            this.deviceId = deviceId;

            broker = new DataBrokerClient();
            broker.Subscribe(deviceId, "Volume", OnVolumeLevelChanged);
            broker.Subscribe(deviceId, "Settings", OnSettingsChanged);
            broker.Subscribe(deviceId, "AudioState", OnAudioStateChanged);
            broker.Subscribe(deviceId, "HtStatus", OnHtStatusChanged);

            LoadInitialValues();
            isLoading = false;

            // Request current volume from radio
            DataBroker.Dispatch(deviceId, "GetVolume", null, store: false);

            // Start microphone capture
            InitMicrophone();
        }

        private void Log(string msg)
        {
            DataBroker.Dispatch(1, "LogInfo", $"[AudioDialog]: {msg}", store: false);
        }

        private void InitMicrophone()
        {
            try
            {
                var audio = Program.PlatformServices?.Audio;
                if (audio == null) { Log("Audio service is null"); return; }

                // Capture at 48kHz mono 16-bit (universally supported), resample to 32kHz for radio
                captureSampleRate = 48000;
                captureChannels = 1;
                micInput = audio.CreateInput(captureSampleRate, 16, captureChannels);
                if (micInput != null)
                {
                    micInput.DataAvailable += OnMicDataAvailable;
                    micInput.Start();
                    Log("Microphone capture started (48kHz, 16-bit, mono)");
                    MicStatusText.Text = "Hold button or Space to transmit";
                }
                else
                {
                    Log("CreateInput returned null");
                    MicStatusText.Text = "Microphone not available";
                }
            }
            catch (Exception ex)
            {
                Log($"Mic init error: {ex.Message}");
                MicStatusText.Text = $"Mic error: {ex.Message}";
            }
        }

        private int micDataCount = 0;
        private void OnMicDataAvailable(byte[] data, int bytesRecorded)
        {
            if (micDataCount == 0) Log($"First mic data received: {bytesRecorded} bytes");
            micDataCount++;

            if (!isTransmitting || bytesRecorded == 0) return;

            // Resample from 48kHz to 32kHz (radio format)
            byte[] pcm = ResampleTo32kHz(data, bytesRecorded, captureSampleRate);
            if (pcm != null && pcm.Length > 0)
            {
                if (micDataCount % 50 == 1) Log($"Transmitting mic PCM: {pcm.Length} bytes");
                broker.Dispatch(deviceId, "TransmitVoicePCM", pcm, store: false);
            }
        }

        private static byte[] ResampleTo32kHz(byte[] input, int bytesRecorded, int srcRate)
        {
            if (srcRate == 32000)
            {
                byte[] copy = new byte[bytesRecorded];
                Array.Copy(input, 0, copy, 0, bytesRecorded);
                return copy;
            }

            int srcSamples = bytesRecorded / 2; // 16-bit
            int dstSamples = (int)((long)srcSamples * 32000 / srcRate);
            if (dstSamples <= 0) return null;

            byte[] output = new byte[dstSamples * 2];
            double ratio = (double)srcRate / 32000;

            for (int i = 0; i < dstSamples; i++)
            {
                double srcPos = i * ratio;
                int idx = (int)srcPos;
                double frac = srcPos - idx;

                short s0 = GetSample16(input, idx, srcSamples);
                short s1 = GetSample16(input, idx + 1, srcSamples);
                short interpolated = (short)(s0 + (s1 - s0) * frac);

                output[i * 2] = (byte)(interpolated & 0xFF);
                output[i * 2 + 1] = (byte)((interpolated >> 8) & 0xFF);
            }
            return output;
        }

        private static short GetSample16(byte[] data, int index, int totalSamples)
        {
            if (index < 0) index = 0;
            if (index >= totalSamples) index = totalSamples - 1;
            int offset = index * 2;
            if (offset + 1 >= data.Length) return 0;
            return (short)(data[offset] | (data[offset + 1] << 8));
        }

        private void StartTransmit()
        {
            if (isTransmitting) return;
            isTransmitting = true;
            Log($"PTT pressed (micInput={micInput != null})");
            TransmitButton.Background = new SolidColorBrush(Color.Parse("#C62828"));
            MicStatusText.Text = "TRANSMITTING...";
        }

        private void StopTransmit()
        {
            if (!isTransmitting) return;
            isTransmitting = false;
            Log("PTT released");
            TransmitButton.Background = new SolidColorBrush(Color.Parse("#444"));
            MicStatusText.Text = "Hold button or Space to transmit";
            // Don't cancel — let buffered audio finish transmitting naturally
        }

        private void TransmitButton_PointerPressed(object sender, PointerPressedEventArgs e)
        {
            StartTransmit();
        }

        private void TransmitButton_PointerReleased(object sender, PointerReleasedEventArgs e)
        {
            StopTransmit();
        }

        private System.Timers.Timer pttReleaseTimer;

        private void Window_KeyDown(object sender, KeyEventArgs e)
        {
            if (e.Key == Key.Space)
            {
                // Cancel any pending release (Wayland key repeat sends KeyUp+KeyDown pairs)
                pttReleaseTimer?.Stop();
                if (!isTransmitting) StartTransmit();
                e.Handled = true;
            }
        }

        private void Window_KeyUp(object sender, KeyEventArgs e)
        {
            if (e.Key == Key.Space)
            {
                // Debounce: delay release to absorb Wayland key repeat KeyUp/KeyDown pairs
                if (pttReleaseTimer == null)
                {
                    pttReleaseTimer = new System.Timers.Timer(150);
                    pttReleaseTimer.AutoReset = false;
                    pttReleaseTimer.Elapsed += (s, args) =>
                    {
                        Dispatcher.UIThread.Post(() => StopTransmit());
                    };
                }
                pttReleaseTimer.Stop();
                pttReleaseTimer.Start();
                e.Handled = true;
            }
        }

        private void LoadInitialValues()
        {
            // Audio state
            bool audioEnabled = DataBroker.GetValue<bool>(deviceId, "AudioState", false);
            AudioEnabledCheck.IsChecked = audioEnabled;
            AudioStatusText.Text = audioEnabled ? "Audio streaming is active" : "Audio streaming is off";

            // Squelch from settings
            var settings = DataBroker.GetValue<RadioSettings>(deviceId, "Settings", null);
            if (settings != null)
            {
                SquelchSlider.Value = settings.squelch_level;
                SquelchValueText.Text = settings.squelch_level.ToString();
            }

            // Volume from radio (may arrive later via event)
            int volume = DataBroker.GetValue<int>(deviceId, "Volume", 0);
            VolumeSlider.Value = volume;
            VolumeValueText.Text = volume.ToString();

            // Software output volume
            int outputVol = broker.GetValue<int>(deviceId, "OutputAudioVolume", 100);
            OutputVolumeSlider.Value = outputVol;
            OutputVolumeText.Text = $"{outputVol}%";
        }

        #region DataBroker Event Handlers

        private void OnVolumeLevelChanged(int devId, string name, object data)
        {
            int volume = 0;
            if (data is int i) volume = i;
            else if (data is byte b) volume = b;
            else return;

            Dispatcher.UIThread.Post(() =>
            {
                isLoading = true;
                VolumeSlider.Value = Math.Clamp(volume, 0, 15);
                VolumeValueText.Text = volume.ToString();
                isLoading = false;
            });
        }

        private void OnSettingsChanged(int devId, string name, object data)
        {
            if (data is RadioSettings settings)
            {
                Dispatcher.UIThread.Post(() =>
                {
                    isLoading = true;
                    SquelchSlider.Value = settings.squelch_level;
                    SquelchValueText.Text = settings.squelch_level.ToString();
                    isLoading = false;
                });
            }
        }

        private void OnAudioStateChanged(int devId, string name, object data)
        {
            if (data is bool enabled)
            {
                Dispatcher.UIThread.Post(() =>
                {
                    AudioEnabledCheck.IsChecked = enabled;
                    AudioStatusText.Text = enabled ? "Audio streaming is active" : "Audio streaming is off";
                });
            }
        }

        private void OnHtStatusChanged(int devId, string name, object data)
        {
        }

        #endregion

        #region UI Event Handlers

        private void AudioEnabled_Click(object sender, RoutedEventArgs e)
        {
            bool enable = AudioEnabledCheck.IsChecked == true;
            DataBroker.Dispatch(deviceId, "SetAudio", enable, store: false);
            DataBroker.Dispatch(deviceId, "AudioState", enable, store: true);
            AudioStatusText.Text = enable ? "Audio streaming is active" : "Audio streaming is off";
        }

        private void VolumeSlider_Changed(object sender, Avalonia.Controls.Primitives.RangeBaseValueChangedEventArgs e)
        {
            if (isLoading) return;
            int level = (int)VolumeSlider.Value;
            VolumeValueText.Text = level.ToString();
            DataBroker.Dispatch(deviceId, "SetVolumeLevel", level, store: false);
        }

        private void SquelchSlider_Changed(object sender, Avalonia.Controls.Primitives.RangeBaseValueChangedEventArgs e)
        {
            if (isLoading) return;
            int level = (int)SquelchSlider.Value;
            SquelchValueText.Text = level.ToString();
            DataBroker.Dispatch(deviceId, "SetSquelchLevel", level, store: false);
        }

        private void OutputVolumeSlider_Changed(object sender, Avalonia.Controls.Primitives.RangeBaseValueChangedEventArgs e)
        {
            if (isLoading) return;
            int vol = (int)OutputVolumeSlider.Value;
            OutputVolumeText.Text = $"{vol}%";
            DataBroker.Dispatch(deviceId, "SetOutputVolume", vol, store: false);
            broker.Dispatch(deviceId, "OutputAudioVolume", vol);
        }

        private void Mute_Click(object sender, RoutedEventArgs e)
        {
            DataBroker.Dispatch(deviceId, "SetMute", MuteCheck.IsChecked == true, store: false);
        }

        private void CloseButton_Click(object sender, RoutedEventArgs e) => Close();

        #endregion

        protected override void OnClosed(EventArgs e)
        {
            StopTransmit();
            if (micInput != null)
            {
                micInput.DataAvailable -= OnMicDataAvailable;
                micInput.Stop();
                micInput.Dispose();
                micInput = null;
            }
            broker?.Dispose();
            base.OnClosed(e);
        }
    }
}
