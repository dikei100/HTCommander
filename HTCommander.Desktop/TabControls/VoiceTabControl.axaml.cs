/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Media;
using Avalonia.Threading;
using HTCommander.radio;

namespace HTCommander.Desktop.TabControls
{
    public partial class VoiceTabControl : UserControl
    {
        private DataBrokerClient broker;
        private bool hasConnectedRadios = false;
        private bool allowTransmit = false;

        public VoiceTabControl()
        {
            InitializeComponent();
            broker = new DataBrokerClient();

            broker.Subscribe(DataBroker.AllDevices, new[] { "ProcessingVoice", "TextReady", "VoiceTransmitStateChanged" }, OnVoiceEvent);
            broker.Subscribe(DataBroker.AllDevices, "State", OnRadioStateChanged);
            broker.Subscribe(1, "ConnectedRadios", OnConnectedRadiosChanged);
            broker.Subscribe(1, "VoiceHandlerState", OnVoiceHandlerStateChanged);
            broker.Subscribe(0, "AllowTransmit", OnAllowTransmitChanged);

            // Load initial AllowTransmit
            int allow = broker.GetValue<int>(0, "AllowTransmit", 0);
            allowTransmit = allow == 1;
            UpdateTransmitState();

            // Check initial connected radios
            var radios = broker.GetValue<object>(1, "ConnectedRadios", null);
            if (radios != null)
            {
                if (radios is System.Collections.IEnumerable enumerable)
                {
                    foreach (var item in enumerable)
                    {
                        if (item != null) { hasConnectedRadios = true; break; }
                    }
                }
            }
            UpdateTransmitState();
        }

        private void UpdateTransmitState()
        {
            TransmitButton.IsEnabled = allowTransmit && hasConnectedRadios;
        }

        private void OnVoiceEvent(int deviceId, string name, object data)
        {
            Dispatcher.UIThread.Post(() =>
            {
                switch (name)
                {
                    case "TextReady":
                        // TextReady can be a string or an object with properties
                        string text = null;
                        if (data is string s) text = s;
                        else if (data != null)
                        {
                            // Try to get Text property via reflection
                            var textProp = data.GetType().GetProperty("Text");
                            if (textProp != null) text = textProp.GetValue(data) as string;
                            else text = data.ToString();
                        }
                        if (!string.IsNullOrWhiteSpace(text))
                            AddMessage(text, false, DateTime.Now);
                        break;

                    case "VoiceTransmitStateChanged":
                        VoiceStatus.Text = data?.ToString() ?? "Idle";
                        break;

                    case "ProcessingVoice":
                        if (data != null)
                        {
                            var listeningProp = data.GetType().GetProperty("Listening");
                            var processingProp = data.GetType().GetProperty("Processing");
                            bool listening = listeningProp != null && (bool)listeningProp.GetValue(data);
                            bool processing = processingProp != null && (bool)processingProp.GetValue(data);
                            if (processing) VoiceStatus.Text = "Processing...";
                            else if (listening) VoiceStatus.Text = "Listening...";
                            else VoiceStatus.Text = "Idle";
                        }
                        break;
                }
            });
        }

        private void OnConnectedRadiosChanged(int deviceId, string name, object data)
        {
            Dispatcher.UIThread.Post(() =>
            {
                hasConnectedRadios = false;
                if (data is System.Collections.IEnumerable enumerable)
                {
                    foreach (var item in enumerable)
                    {
                        if (item != null) { hasConnectedRadios = true; break; }
                    }
                }
                UpdateTransmitState();

                if (!hasConnectedRadios)
                {
                    broker.Dispatch(1, "VoiceHandlerDisable", null, store: false);
                }
                // VoiceHandler enable happens in OnRadioStateChanged when state becomes "Connected"
            });
        }

        private void OnRadioStateChanged(int deviceId, string name, object data)
        {
            if (deviceId < 100) return; // Only care about radio devices
            Dispatcher.UIThread.Post(() =>
            {
                if (data is string stateStr && stateStr == "Connected")
                {
                    EnableVoiceHandler(deviceId);
                }
            });
        }

        private void EnableVoiceHandler(int deviceId)
        {
            string language = broker.GetValue<string>(0, "VoiceLanguage", "en");
            string model = broker.GetValue<string>(0, "VoiceModel", "");
            broker.Dispatch(1, "VoiceHandlerEnable", new
            {
                DeviceId = deviceId,
                Language = language,
                Model = model
            }, store: false);
        }

        private void OnVoiceHandlerStateChanged(int deviceId, string name, object data)
        {
            Dispatcher.UIThread.Post(() =>
            {
                // Update handler state display
            });
        }

        private void OnAllowTransmitChanged(int deviceId, string name, object data)
        {
            Dispatcher.UIThread.Post(() =>
            {
                if (data is int i) allowTransmit = i == 1;
                else if (data is bool b) allowTransmit = b;
                UpdateTransmitState();
            });
        }

        private void AddMessage(string text, bool outbound, DateTime time)
        {
            var border = new Border
            {
                Background = outbound ?
                    new SolidColorBrush(Color.Parse("#264F78")) :
                    new SolidColorBrush(Color.Parse("#3C3C3C")),
                CornerRadius = new Avalonia.CornerRadius(6),
                Padding = new Avalonia.Thickness(10, 6),
                Margin = new Avalonia.Thickness(outbound ? 60 : 0, 2, outbound ? 0 : 60, 2)
            };

            var stack = new StackPanel();
            stack.Children.Add(new TextBlock
            {
                Text = text,
                TextWrapping = TextWrapping.Wrap,
                Foreground = Brushes.White
            });
            stack.Children.Add(new TextBlock
            {
                Text = time.ToString("HH:mm:ss"),
                FontSize = 10,
                Foreground = new SolidColorBrush(Color.Parse("#888")),
                HorizontalAlignment = Avalonia.Layout.HorizontalAlignment.Right
            });
            border.Child = stack;
            VoiceMessages.Children.Add(border);

            // Auto-scroll to bottom
            MessagesScroller.ScrollToEnd();
        }

        private void TransmitButton_Click(object sender, RoutedEventArgs e)
        {
            SendMessage();
        }

        private void VoiceInput_KeyDown(object sender, KeyEventArgs e)
        {
            if (e.Key == Key.Enter)
            {
                SendMessage();
                e.Handled = true;
            }
        }

        private void SendMessage()
        {
            string text = VoiceInput.Text?.Trim();
            if (string.IsNullOrEmpty(text)) return;

            AddMessage(text, true, DateTime.Now);
            VoiceInput.Text = "";

            // Determine mode from combo
            string mode = "Chat";
            if (ModeCombo.SelectedItem is ComboBoxItem item)
                mode = item.Content?.ToString() ?? "Chat";

            switch (mode)
            {
                case "Chat":
                    broker.Dispatch(1, "Chat", text, store: false);
                    break;
                case "Speak":
                    broker.Dispatch(1, "Speak", text, store: false);
                    break;
                case "Morse":
                    broker.Dispatch(1, "Morse", text, store: false);
                    break;
                case "DTMF":
                    // DTMF generates PCM locally and transmits to radio
                    int targetDeviceId = GetVoiceTargetDeviceId();
                    if (targetDeviceId < 0) break;
                    byte[] pcm8 = DmtfEngine.GenerateDmtfPcm(text);
                    byte[] pcm16 = new byte[pcm8.Length * 2];
                    for (int i = 0; i < pcm8.Length; i++)
                    {
                        short s = (short)((pcm8[i] - 128) << 8);
                        pcm16[i * 2] = (byte)(s & 0xFF);
                        pcm16[i * 2 + 1] = (byte)((s >> 8) & 0xFF);
                    }
                    broker.Dispatch(targetDeviceId, "TransmitVoicePCM", new { Data = pcm16, PlayLocally = true }, store: false);
                    break;
            }
        }

        private int GetVoiceTargetDeviceId()
        {
            // Get the voice handler's target device ID
            var state = DataBroker.GetValue<object>(1, "VoiceHandlerState", null);
            if (state != null)
            {
                var prop = state.GetType().GetProperty("TargetDeviceId");
                if (prop != null)
                {
                    object val = prop.GetValue(state);
                    if (val is int id && id > 0) return id;
                }
            }
            // Fallback: first connected radio
            var radios = DataBroker.GetValue<object>(1, "ConnectedRadios", null);
            if (radios is System.Collections.IEnumerable enumerable)
            {
                foreach (var item in enumerable)
                {
                    if (item == null) continue;
                    var did = item.GetType().GetProperty("DeviceId")?.GetValue(item);
                    if (did is int deviceId && deviceId > 0) return deviceId;
                }
            }
            return -1;
        }

        private bool isRecording = false;

        private void RecordButton_Click(object sender, RoutedEventArgs e)
        {
            isRecording = !isRecording;
            broker.Dispatch(1, isRecording ? "RecordingEnable" : "RecordingDisable", null, store: false);
            RecordButton.Content = isRecording ? "Stop" : "Record";
        }
    }
}
