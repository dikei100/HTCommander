using System;
using System.Collections.Generic;
using System.IO;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Media.Imaging;
using Avalonia.Threading;
using SkiaSharp;

namespace HTCommander.Desktop.Dialogs
{
    public partial class SpectrogramDialog : Window
    {
        private DataBrokerClient broker;
        private DispatcherTimer updateTimer;
        private readonly object audioLock = new object();
        private List<double> audioBuffer = new List<double>();

        // Spectrogram state
        private int sampleRate = 32000;
        private int fftSize = 512;
        private int maxFrequency = 16000;
        private bool roll = false;
        private int spectrogramWidth = 600;
        private int spectrogramHeight = 256;
        private byte[] spectrogramPixels; // BGRA pixel data
        private int columnIndex = 0;
        private int radioDeviceId = -1;
        private bool hasAudioSource = false;

        public SpectrogramDialog()
        {
            InitializeComponent();

            broker = new DataBrokerClient();

            // Load settings
            maxFrequency = broker.GetValue<int>(0, "SpecMaxFrequency", 16000);
            roll = broker.GetValue<int>(0, "SpecRoll", 0) == 1;
            RollCheck.IsChecked = roll;

            switch (maxFrequency)
            {
                case 8000: FreqCombo.SelectedIndex = 1; break;
                case 4000: FreqCombo.SelectedIndex = 2; break;
                default: FreqCombo.SelectedIndex = 0; break;
            }

            // Initialize pixel buffer
            spectrogramPixels = new byte[spectrogramWidth * spectrogramHeight * 4];

            // Subscribe to connected radios to auto-select source
            broker.Subscribe(1, "ConnectedRadios", OnConnectedRadiosChanged);
            CheckInitialRadios();

            // Start update timer
            updateTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(50) };
            updateTimer.Tick += UpdateTimer_Tick;
            updateTimer.Start();

            SourceCombo.SelectedIndex = 0;
        }

        private void CheckInitialRadios()
        {
            var data = broker.GetValue<object>(1, "ConnectedRadios", null);
            if (data is System.Collections.IEnumerable enumerable)
            {
                foreach (var item in enumerable)
                {
                    if (item == null) continue;
                    var did = item.GetType().GetProperty("DeviceId")?.GetValue(item);
                    if (did is int id && id > 0)
                    {
                        SelectRadioSource(id);
                        return;
                    }
                }
            }
        }

        private void OnConnectedRadiosChanged(int deviceId, string name, object data)
        {
            Dispatcher.UIThread.Post(() =>
            {
                if (!hasAudioSource && data is System.Collections.IEnumerable enumerable)
                {
                    foreach (var item in enumerable)
                    {
                        if (item == null) continue;
                        var did = item.GetType().GetProperty("DeviceId")?.GetValue(item);
                        if (did is int id && id > 0)
                        {
                            SelectRadioSource(id);
                            return;
                        }
                    }
                }
            });
        }

        private void SelectRadioSource(int deviceId)
        {
            if (radioDeviceId > 0)
                broker.Unsubscribe(radioDeviceId, "AudioDataAvailable");

            radioDeviceId = deviceId;
            hasAudioSource = true;
            broker.Subscribe(deviceId, "AudioDataAvailable", OnAudioDataAvailable);
            StatusText.Text = $"Radio {deviceId}";
            Title = $"Spectrogram - Radio {deviceId}";
        }

        private void OnAudioDataAvailable(int deviceId, string name, object data)
        {
            if (data == null) return;
            try
            {
                var type = data.GetType();
                var dataProp = type.GetProperty("Data");
                var lenProp = type.GetProperty("Length");
                if (dataProp == null) return;

                byte[] buffer = dataProp.GetValue(data) as byte[];
                int length = 0;
                if (lenProp != null)
                {
                    object lv = lenProp.GetValue(data);
                    if (lv is int li) length = li;
                }
                if (buffer == null) return;
                if (length <= 0) length = buffer.Length;

                // Convert 16-bit PCM to doubles
                int samples = length / 2;
                lock (audioLock)
                {
                    for (int i = 0; i < samples; i++)
                    {
                        int idx = i * 2;
                        if (idx + 1 >= buffer.Length) break;
                        short s = (short)(buffer[idx] | (buffer[idx + 1] << 8));
                        audioBuffer.Add(s / 32768.0);
                    }
                    // Keep buffer manageable
                    if (audioBuffer.Count > sampleRate * 2)
                        audioBuffer.RemoveRange(0, audioBuffer.Count - sampleRate);
                }
            }
            catch (Exception) { }
        }

        private void UpdateTimer_Tick(object sender, EventArgs e)
        {
            double[] newSamples;
            lock (audioLock)
            {
                if (audioBuffer.Count < fftSize) return;
                newSamples = audioBuffer.ToArray();
                audioBuffer.Clear();
            }

            // Process all available FFT windows
            int stepSize = fftSize / 4;
            int offset = 0;
            while (offset + fftSize <= newSamples.Length)
            {
                double[] window = new double[fftSize];
                Array.Copy(newSamples, offset, window, 0, fftSize);

                // Apply Hanning window
                for (int i = 0; i < fftSize; i++)
                    window[i] *= 0.5 * (1 - Math.Cos(2 * Math.PI * i / (fftSize - 1)));

                // Compute FFT magnitude
                double[] magnitudes = ComputeFFTMagnitude(window);

                // Render column
                RenderColumn(magnitudes);
                offset += stepSize;
            }

            // Update display
            RenderBitmap();
        }

        private double[] ComputeFFTMagnitude(double[] input)
        {
            int n = input.Length;
            double[] real = new double[n];
            double[] imag = new double[n];
            Array.Copy(input, real, n);

            // Cooley-Tukey FFT (in-place, radix-2)
            int bits = (int)Math.Log2(n);
            for (int i = 0; i < n; i++)
            {
                int j = ReverseBits(i, bits);
                if (j > i)
                {
                    (real[i], real[j]) = (real[j], real[i]);
                    (imag[i], imag[j]) = (imag[j], imag[i]);
                }
            }

            for (int size = 2; size <= n; size *= 2)
            {
                int halfSize = size / 2;
                double angle = -2.0 * Math.PI / size;
                for (int i = 0; i < n; i += size)
                {
                    for (int j = 0; j < halfSize; j++)
                    {
                        double cos = Math.Cos(angle * j);
                        double sin = Math.Sin(angle * j);
                        int even = i + j;
                        int odd = i + j + halfSize;
                        double tr = real[odd] * cos - imag[odd] * sin;
                        double ti = real[odd] * sin + imag[odd] * cos;
                        real[odd] = real[even] - tr;
                        imag[odd] = imag[even] - ti;
                        real[even] += tr;
                        imag[even] += ti;
                    }
                }
            }

            // Compute magnitudes for the frequency bins up to maxFrequency
            int usableBins = (int)(fftSize * (double)maxFrequency / sampleRate);
            if (usableBins > n / 2) usableBins = n / 2;

            double[] mags = new double[usableBins];
            for (int i = 0; i < usableBins; i++)
                mags[i] = Math.Sqrt(real[i] * real[i] + imag[i] * imag[i]);

            return mags;
        }

        private static int ReverseBits(int value, int bits)
        {
            int result = 0;
            for (int i = 0; i < bits; i++)
            {
                result = (result << 1) | (value & 1);
                value >>= 1;
            }
            return result;
        }

        private void RenderColumn(double[] magnitudes)
        {
            int col = roll ? columnIndex % spectrogramWidth : columnIndex;
            if (col >= spectrogramWidth)
            {
                if (!roll)
                {
                    // Scroll left
                    int rowBytes = spectrogramWidth * 4;
                    for (int y = 0; y < spectrogramHeight; y++)
                    {
                        int rowStart = y * rowBytes;
                        Array.Copy(spectrogramPixels, rowStart + 4, spectrogramPixels, rowStart, rowBytes - 4);
                    }
                    col = spectrogramWidth - 1;
                }
            }

            for (int y = 0; y < spectrogramHeight; y++)
            {
                // Map y to frequency bin (bottom = low freq, top = high freq)
                int binIndex = (int)((spectrogramHeight - 1 - y) * (double)magnitudes.Length / spectrogramHeight);
                if (binIndex >= magnitudes.Length) binIndex = magnitudes.Length - 1;
                if (binIndex < 0) binIndex = 0;

                // Convert magnitude to dB, scale to 0-255
                double mag = magnitudes[binIndex];
                double db = 20 * Math.Log10(Math.Max(mag, 1e-10));
                double normalized = Math.Clamp((db + 60) / 60.0, 0, 1); // -60dB to 0dB range

                // Viridis-inspired colormap
                byte r, g, b;
                GetColor(normalized, out r, out g, out b);

                int pixelIndex = (y * spectrogramWidth + col) * 4;
                spectrogramPixels[pixelIndex + 0] = b; // B
                spectrogramPixels[pixelIndex + 1] = g; // G
                spectrogramPixels[pixelIndex + 2] = r; // R
                spectrogramPixels[pixelIndex + 3] = 255; // A
            }

            columnIndex++;
        }

        private static void GetColor(double value, out byte r, out byte g, out byte b)
        {
            // Simple heat colormap: black -> blue -> cyan -> green -> yellow -> red -> white
            if (value < 0.125)
            {
                double t = value / 0.125;
                r = 0; g = 0; b = (byte)(t * 128);
            }
            else if (value < 0.25)
            {
                double t = (value - 0.125) / 0.125;
                r = 0; g = 0; b = (byte)(128 + t * 127);
            }
            else if (value < 0.375)
            {
                double t = (value - 0.25) / 0.125;
                r = 0; g = (byte)(t * 255); b = 255;
            }
            else if (value < 0.5)
            {
                double t = (value - 0.375) / 0.125;
                r = 0; g = 255; b = (byte)(255 * (1 - t));
            }
            else if (value < 0.625)
            {
                double t = (value - 0.5) / 0.125;
                r = (byte)(t * 255); g = 255; b = 0;
            }
            else if (value < 0.75)
            {
                double t = (value - 0.625) / 0.125;
                r = 255; g = (byte)(255 * (1 - t)); b = 0;
            }
            else if (value < 0.875)
            {
                double t = (value - 0.75) / 0.125;
                r = 255; g = (byte)(t * 128); b = (byte)(t * 128);
            }
            else
            {
                double t = (value - 0.875) / 0.125;
                r = 255; g = (byte)(128 + t * 127); b = (byte)(128 + t * 127);
            }
        }

        private unsafe void RenderBitmap()
        {
            try
            {
                using (var skBitmap = new SKBitmap(spectrogramWidth, spectrogramHeight, SKColorType.Bgra8888, SKAlphaType.Premul))
                {
                    IntPtr ptr = skBitmap.GetPixels();
                    System.Runtime.InteropServices.Marshal.Copy(spectrogramPixels, 0, ptr, spectrogramPixels.Length);

                    using (var encoded = skBitmap.Encode(SKEncodedImageFormat.Png, 80))
                    using (var stream = new MemoryStream(encoded.ToArray()))
                    {
                        SpectrogramImage.Source = new Bitmap(stream);
                    }
                }
            }
            catch (Exception) { }
        }

        #region UI Events

        private void SourceCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            // Radio Audio is the only supported source for now
        }

        private void FreqCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            if (spectrogramPixels == null) return; // Called during InitializeComponent before constructor body
            switch (FreqCombo.SelectedIndex)
            {
                case 0: maxFrequency = 16000; break;
                case 1: maxFrequency = 8000; break;
                case 2: maxFrequency = 4000; break;
            }
            DataBroker.Dispatch(0, "SpecMaxFrequency", maxFrequency);
            ResetSpectrogram();
        }

        private void RollCheck_Click(object sender, RoutedEventArgs e)
        {
            roll = RollCheck.IsChecked == true;
            DataBroker.Dispatch(0, "SpecRoll", roll ? 1 : 0);
        }

        private void CloseButton_Click(object sender, RoutedEventArgs e) => Close();

        #endregion

        private void ResetSpectrogram()
        {
            columnIndex = 0;
            spectrogramPixels = new byte[spectrogramWidth * spectrogramHeight * 4];
        }

        protected override void OnClosed(EventArgs e)
        {
            updateTimer?.Stop();
            if (radioDeviceId > 0)
                broker.Unsubscribe(radioDeviceId, "AudioDataAvailable");
            broker?.Dispose();
            base.OnClosed(e);
        }
    }
}
