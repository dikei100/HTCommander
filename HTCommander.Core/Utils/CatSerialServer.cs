/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

// Protocol: Kenwood TS-2000 CAT (Computer Aided Transceiver)
// Commands are ASCII, semicolon-terminated, 9600 8N1

using System;
using System.Text;
using System.Threading;

namespace HTCommander
{
    /// <summary>
    /// Virtual COM port emulating a Kenwood TS-2000 for CAT control.
    /// Primary path for VaraFM PTT. Uses IVirtualSerialPort for platform PTY/COM.
    /// </summary>
    public class CatSerialServer : IDisposable
    {
        private DataBrokerClient broker;
        private IVirtualSerialPort serialPort;
        private IPlatformServices platformServices;
        private bool running = false;
        private bool pttActive = false;
        private Timer pttSilenceTimer;
        private long cachedFrequencyA = 145500000;
        private long cachedFrequencyB = 145500000;
        private int activeRadioId = -1;
        private StringBuilder commandBuffer = new StringBuilder();
        private bool autoInfo = false;

        public CatSerialServer(IPlatformServices platform)
        {
            platformServices = platform;
            broker = new DataBrokerClient();
            broker.Subscribe(0, "CatServerEnabled", OnSettingChanged);
            broker.Subscribe(1, "ConnectedRadios", OnConnectedRadiosChanged);
            broker.Subscribe(DataBroker.AllDevices, "Settings", OnSettingsChanged);

            int enabled = broker.GetValue<int>(0, "CatServerEnabled", 0);
            if (enabled == 1)
            {
                Start();
            }
        }

        private void OnSettingChanged(int deviceId, string name, object data)
        {
            int enabled = broker.GetValue<int>(0, "CatServerEnabled", 0);
            if (enabled == 1 && !running)
            {
                Start();
            }
            else if (enabled != 1 && running)
            {
                Stop();
            }
        }

        private void OnConnectedRadiosChanged(int deviceId, string name, object data)
        {
            activeRadioId = GetFirstConnectedRadioId();
        }

        private void OnSettingsChanged(int deviceId, string name, object data)
        {
            if (deviceId < 100) return;
            try
            {
                if (data is RadioSettings settings)
                {
                    if (settings.vfo1_mod_freq_x > 0) cachedFrequencyA = settings.vfo1_mod_freq_x;
                    if (settings.vfo2_mod_freq_x > 0) cachedFrequencyB = settings.vfo2_mod_freq_x;
                }
            }
            catch { }
        }

        private void Start()
        {
            if (running) return;
            if (platformServices == null) return;

            serialPort = platformServices.CreateVirtualSerialPort();
            if (serialPort == null)
            {
                Log("CAT server: platform does not support virtual serial ports");
                return;
            }

            if (!serialPort.Create())
            {
                Log("CAT server: failed to create virtual serial port");
                serialPort.Dispose();
                serialPort = null;
                return;
            }

            serialPort.DataReceived += OnDataReceived;
            running = true;
            Log($"CAT server started on {serialPort.DevicePath}");
            broker.Dispatch(1, "CatPortPath", serialPort.DevicePath, store: false);
        }

        private void Stop()
        {
            if (!running) return;
            Log("CAT server stopping...");
            running = false;
            SetPtt(false);

            if (serialPort != null)
            {
                serialPort.DataReceived -= OnDataReceived;
                serialPort.Dispose();
                serialPort = null;
            }

            broker.Dispatch(1, "CatPortPath", "", store: false);
            Log("CAT server stopped");
        }

        private void OnDataReceived(byte[] data, int length)
        {
            if (!running) return;

            string text = Encoding.ASCII.GetString(data, 0, length);
            commandBuffer.Append(text);

            // Process complete commands (semicolon-terminated)
            string buffer = commandBuffer.ToString();
            int semicolon;
            while ((semicolon = buffer.IndexOf(';')) >= 0)
            {
                string cmd = buffer.Substring(0, semicolon + 1);
                buffer = buffer.Substring(semicolon + 1);
                ProcessCommand(cmd.TrimEnd(';'));
            }
            commandBuffer.Clear();
            commandBuffer.Append(buffer);
        }

        private void ProcessCommand(string cmd)
        {
            if (string.IsNullOrEmpty(cmd)) return;

            string response = null;

            // TX command (PTT ON)
            if (cmd == "TX" || cmd == "TX0" || cmd == "TX1" || cmd == "TX2")
            {
                SetPtt(true);
                response = cmd + ";";
            }
            // RX command (PTT OFF)
            else if (cmd == "RX")
            {
                SetPtt(false);
                response = "RX;";
            }
            // Get/Set VFO A frequency
            else if (cmd == "FA")
            {
                response = $"FA{cachedFrequencyA.ToString("D11")};";
            }
            else if (cmd.StartsWith("FA") && cmd.Length > 2)
            {
                long freq;
                if (long.TryParse(cmd.Substring(2), out freq) && freq > 0)
                {
                    cachedFrequencyA = freq;
                    SetRadioFrequency(freq, "A");
                }
                response = $"FA{cachedFrequencyA.ToString("D11")};";
            }
            // Get/Set VFO B frequency
            else if (cmd == "FB")
            {
                response = $"FB{cachedFrequencyB.ToString("D11")};";
            }
            else if (cmd.StartsWith("FB") && cmd.Length > 2)
            {
                long freq;
                if (long.TryParse(cmd.Substring(2), out freq) && freq > 0)
                {
                    cachedFrequencyB = freq;
                    SetRadioFrequency(freq, "B");
                }
                response = $"FB{cachedFrequencyB.ToString("D11")};";
            }
            // Get mode (always FM = 4)
            else if (cmd == "MD")
            {
                response = "MD4;";
            }
            else if (cmd.StartsWith("MD") && cmd.Length > 2)
            {
                response = "MD4;"; // Always FM
            }
            // IF — transceiver info (38 chars)
            else if (cmd == "IF")
            {
                response = BuildIfResponse();
            }
            // ID — radio identification (TS-2000 = 019)
            else if (cmd == "ID")
            {
                response = "ID019;";
            }
            // Auto-info
            else if (cmd == "AI0")
            {
                autoInfo = false;
                response = "AI0;";
            }
            else if (cmd == "AI1")
            {
                autoInfo = true;
                response = "AI1;";
            }
            else if (cmd == "AI")
            {
                response = autoInfo ? "AI1;" : "AI0;";
            }
            // Power status
            else if (cmd == "PS")
            {
                response = "PS1;";
            }
            else if (cmd == "PS1")
            {
                response = "PS1;";
            }
            // Read meter
            else if (cmd.StartsWith("RM"))
            {
                response = "RM00000;";
            }
            // Antenna selector
            else if (cmd.StartsWith("AN"))
            {
                response = "AN0;";
            }
            // Function key
            else if (cmd.StartsWith("FN"))
            {
                response = "FN0;";
            }
            // VFO select
            else if (cmd.StartsWith("FR") || cmd.StartsWith("FT"))
            {
                response = cmd.Substring(0, 2) + "0;";
            }
            else
            {
                // Unknown command — respond with ? for error
                Log($"CAT unknown command: {cmd}");
                response = "?;";
            }

            if (response != null)
            {
                SendResponse(response);
            }
        }

        private string BuildIfResponse()
        {
            // TS-2000 IF response format (38 chars before semicolon):
            // IF[freq 11d][step 4d][rit/xit 6d][rit 1d][xit 1d][bank 1d][ch 2d]
            //   [ctcss 1d][tone 2d][shift 1d][mode 1d][fn 1d][scan 1d][split 1d]
            //   [tone2 1d][dtmf 1d][00]
            var sb = new StringBuilder("IF");
            sb.Append(cachedFrequencyA.ToString("D11"));  // P1: frequency
            sb.Append("0000");                             // P2: step
            sb.Append("+00000");                           // P3: RIT/XIT offset
            sb.Append("0");                                // P4: RIT on/off
            sb.Append("0");                                // P5: XIT on/off
            sb.Append("0");                                // P6: memory bank
            sb.Append("00");                               // P7: memory channel
            sb.Append(pttActive ? "1" : "0");              // P8: TX status
            sb.Append("4");                                // P9: operating mode (4=FM)
            sb.Append("0");                                // P10: function key
            sb.Append("0");                                // P11: scan
            sb.Append("0");                                // P12: split
            sb.Append("0");                                // P13: CTCSS tone
            sb.Append("00");                               // P14: tone number
            sb.Append("0");                                // P15: shift
            sb.Append(";");
            return sb.ToString();
        }

        private void SendResponse(string response)
        {
            if (serialPort == null || !running) return;
            byte[] data = Encoding.ASCII.GetBytes(response);
            try
            {
                serialPort.Write(data, 0, data.Length);
            }
            catch (Exception ex)
            {
                Log($"CAT write error: {ex.Message}");
            }
        }

        private void SetRadioFrequency(long freqHz, string vfo)
        {
            int radioId = activeRadioId;
            if (radioId < 0) radioId = GetFirstConnectedRadioId();
            if (radioId < 0) return;

            var info = broker.GetValue<RadioDevInfo>(radioId, "Info", null);
            if (info == null) return;

            int scratchIndex = info.channel_count - 1;
            var scratch = new RadioChannelInfo();
            scratch.channel_id = scratchIndex;
            scratch.rx_freq = (int)freqHz;
            scratch.tx_freq = (int)freqHz;
            scratch.rx_mod = Radio.RadioModulationType.FM;
            scratch.tx_mod = Radio.RadioModulationType.FM;
            scratch.bandwidth = Radio.RadioBandwidthType.WIDE;
            scratch.name_str = "QF";

            broker.Dispatch(radioId, "WriteChannel", scratch, store: false);
            string eventName = (vfo == "B") ? "ChannelChangeVfoB" : "ChannelChangeVfoA";
            broker.Dispatch(radioId, eventName, scratchIndex, store: false);
            Log($"CAT set VFO {vfo} freq: {freqHz} Hz → scratch channel {scratchIndex}");
        }

        private void SetPtt(bool on)
        {
            bool wasActive = pttActive;
            pttActive = on;

            if (on && !wasActive)
            {
                pttSilenceTimer = new Timer(DispatchSilence, null, 0, 80);
                Log("CAT PTT ON");
                broker?.Dispatch(1, "ExternalPttState", true, store: false);
            }
            else if (!on && wasActive)
            {
                pttSilenceTimer?.Dispose();
                pttSilenceTimer = null;
                Log("CAT PTT OFF");
                broker?.Dispatch(1, "ExternalPttState", false, store: false);
            }
        }

        private void DispatchSilence(object state)
        {
            if (!pttActive) return;
            int radioId = activeRadioId;
            if (radioId < 0) radioId = GetFirstConnectedRadioId();
            if (radioId < 0) return;

            byte[] silence = new byte[6400];
            broker?.Dispatch(radioId, "TransmitVoicePCM", silence, store: false);
        }

        private int GetFirstConnectedRadioId()
        {
            var radios = broker.GetValue<object>(1, "ConnectedRadios", null);
            if (radios is System.Collections.IEnumerable enumerable)
            {
                foreach (var item in enumerable)
                {
                    if (item == null) continue;
                    var prop = item.GetType().GetProperty("DeviceId");
                    if (prop != null)
                    {
                        object val = prop.GetValue(item);
                        if (val is int id && id > 0) return id;
                    }
                }
            }
            return -1;
        }

        private void Log(string message)
        {
            broker?.LogInfo(message);
        }

        public void Dispose()
        {
            Stop();
            broker?.Dispose();
        }
    }
}
