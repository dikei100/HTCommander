/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Linq;
using System.Threading.Tasks;
using NAudio.Wave;
using NAudio.CoreAudioApi;

namespace HTCommander.Platform.Windows
{
    /// <summary>
    /// Windows audio service using NAudio/WASAPI.
    /// </summary>
    public class WinAudioService : IAudioService
    {
        public Task<bool> RequestPermissionsAsync() => Task.FromResult(true);

        public IAudioOutput CreateOutput(int sampleRate, int bitsPerSample, int channels)
        {
            return new WinAudioOutput(sampleRate, bitsPerSample, channels);
        }

        public IAudioInput CreateInput(int sampleRate, int bitsPerSample, int channels)
        {
            return new WinAudioInput(sampleRate, bitsPerSample, channels);
        }

        public string[] GetOutputDevices()
        {
            using var enumerator = new MMDeviceEnumerator();
            return enumerator.EnumerateAudioEndPoints(DataFlow.Render, DeviceState.Active)
                .Select(d => d.FriendlyName)
                .ToArray();
        }

        public string[] GetInputDevices()
        {
            using var enumerator = new MMDeviceEnumerator();
            return enumerator.EnumerateAudioEndPoints(DataFlow.Capture, DeviceState.Active)
                .Select(d => d.FriendlyName)
                .ToArray();
        }

        public void OnPause() { }
        public void OnResume() { }

        public void Dispose() { }
    }

    public class WinAudioOutput : IAudioOutput
    {
        private WasapiOut waveOut;
        private BufferedWaveProvider waveProvider;
        private NAudio.Wave.SampleProviders.VolumeSampleProvider volumeProvider;
        private float _volume = 1.0f;
        private string _deviceId;

        public WinAudioOutput(int sampleRate, int bitsPerSample, int channels)
        {
            Init(sampleRate, bitsPerSample, channels);
        }

        public void Init(int sampleRate, int bitsPerSample, int channels)
        {
            waveProvider = new BufferedWaveProvider(new WaveFormat(sampleRate, bitsPerSample, channels))
            {
                DiscardOnBufferOverflow = true
            };
            volumeProvider = new NAudio.Wave.SampleProviders.VolumeSampleProvider(waveProvider.ToSampleProvider());
            volumeProvider.Volume = _volume;
        }

        public void Play()
        {
            if (waveOut != null) return;
            MMDevice device = null;
            if (!string.IsNullOrEmpty(_deviceId))
            {
                using var enumerator = new MMDeviceEnumerator();
                device = enumerator.EnumerateAudioEndPoints(DataFlow.Render, DeviceState.Active)
                    .FirstOrDefault(d => d.FriendlyName == _deviceId);
            }

            waveOut = device != null ? new WasapiOut(device, AudioClientShareMode.Shared, true, 200) : new WasapiOut(AudioClientShareMode.Shared, true, 200);
            waveOut.Init(volumeProvider);
            waveOut.Play();
        }

        public void Stop()
        {
            waveOut?.Stop();
            waveOut?.Dispose();
            waveOut = null;
        }

        public void AddSamples(byte[] buffer, int offset, int count)
        {
            waveProvider?.AddSamples(buffer, offset, count);
        }

        public float Volume
        {
            get => _volume;
            set
            {
                _volume = value;
                if (volumeProvider != null) volumeProvider.Volume = value;
            }
        }

        public string DeviceId
        {
            get => _deviceId;
            set => _deviceId = value;
        }

        public void Dispose()
        {
            Stop();
        }
    }

    public class WinAudioInput : IAudioInput
    {
        private WasapiCapture capture;
        private int _sampleRate;
        private int _bitsPerSample;
        private int _channels;
        private string _deviceId;

        public event Action<byte[], int> DataAvailable;

        public WinAudioInput(int sampleRate, int bitsPerSample, int channels)
        {
            _sampleRate = sampleRate;
            _bitsPerSample = bitsPerSample;
            _channels = channels;
        }

        public void Start()
        {
            MMDevice device = null;
            if (!string.IsNullOrEmpty(_deviceId))
            {
                using var enumerator = new MMDeviceEnumerator();
                device = enumerator.EnumerateAudioEndPoints(DataFlow.Capture, DeviceState.Active)
                    .FirstOrDefault(d => d.FriendlyName == _deviceId);
            }

            capture = device != null ? new WasapiCapture(device) : new WasapiCapture();
            capture.WaveFormat = new WaveFormat(_sampleRate, _bitsPerSample, _channels);
            capture.DataAvailable += (s, e) =>
            {
                DataAvailable?.Invoke(e.Buffer, e.BytesRecorded);
            };
            capture.StartRecording();
        }

        public void Stop()
        {
            capture?.StopRecording();
            capture?.Dispose();
            capture = null;
        }

        public string DeviceId
        {
            get => _deviceId;
            set => _deviceId = value;
        }

        public void Dispose()
        {
            Stop();
        }
    }
}
