/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Threading;

namespace HTCommander.Platform.Linux
{
    /// <summary>
    /// PulseAudio/PipeWire virtual audio device implementation.
    /// Creates null sinks and virtual sources for bidirectional audio routing.
    /// External software sees "HTCommander Radio Audio" as input and "HTCommander TX" as output.
    /// </summary>
    public class LinuxVirtualAudioProvider : IVirtualAudioProvider
    {
        private int rxSinkModuleId = -1;
        private int txSinkModuleId = -1;
        private int virtualSourceModuleId = -1;
        private Process parecordProcess;
        private Process pacatProcess;
        private Thread txReadThread;
        private volatile bool running = false;
        private int sampleRate;

        public string SinkName => "HTCommander TX";
        public string SourceName => "HTCommander Radio Audio";
        public bool IsRunning => running;
        public event Action<byte[], int> TxDataAvailable;

        public bool Create(int sampleRate)
        {
            this.sampleRate = sampleRate;

            try
            {
                // Clean up any stale modules from previous runs
                CleanupStaleModules();

                // Create RX null sink (radio audio goes here)
                rxSinkModuleId = LoadModule(
                    "module-null-sink",
                    $"sink_name=HTCommander_RX sink_properties=device.description=\"HTCommander\\sRX\"");
                if (rxSinkModuleId < 0) return false;

                // Create TX null sink (external software outputs here)
                txSinkModuleId = LoadModule(
                    "module-null-sink",
                    $"sink_name=HTCommander_TX sink_properties=device.description=\"HTCommander\\sTX\"");
                if (txSinkModuleId < 0) { Destroy(); return false; }

                // Create virtual source from RX sink's monitor
                // This is what external software selects as its input device
                virtualSourceModuleId = LoadModule(
                    "module-virtual-source",
                    $"source_name=HTCommander_RX_Source master=HTCommander_RX.monitor source_properties=device.description=\"HTCommander\\sRadio\\sAudio\"");
                if (virtualSourceModuleId < 0) { Destroy(); return false; }

                // Start pacat for writing RX audio to the RX sink
                pacatProcess = new Process();
                var pacatPsi = new ProcessStartInfo
                {
                    FileName = "pacat",
                    UseShellExecute = false,
                    RedirectStandardInput = true,
                    RedirectStandardOutput = false,
                    RedirectStandardError = false,
                    CreateNoWindow = true
                };
                pacatPsi.ArgumentList.Add("--device=HTCommander_RX");
                pacatPsi.ArgumentList.Add("--format=s16le");
                pacatPsi.ArgumentList.Add($"--rate={sampleRate}");
                pacatPsi.ArgumentList.Add("--channels=1");
                pacatPsi.ArgumentList.Add("--raw");
                pacatPsi.ArgumentList.Add("--latency-msec=20");
                pacatProcess.StartInfo = pacatPsi;
                pacatProcess.Start();

                // Start parecord for reading TX audio from the TX sink's monitor
                parecordProcess = new Process();
                var parecordPsi = new ProcessStartInfo
                {
                    FileName = "parecord",
                    UseShellExecute = false,
                    RedirectStandardInput = false,
                    RedirectStandardOutput = true,
                    RedirectStandardError = false,
                    CreateNoWindow = true
                };
                parecordPsi.ArgumentList.Add("--device=HTCommander_TX.monitor");
                parecordPsi.ArgumentList.Add("--format=s16le");
                parecordPsi.ArgumentList.Add($"--rate={sampleRate}");
                parecordPsi.ArgumentList.Add("--channels=1");
                parecordPsi.ArgumentList.Add("--raw");
                parecordPsi.ArgumentList.Add("--latency-msec=20");
                parecordProcess.StartInfo = parecordPsi;
                try
                {
                    parecordProcess.Start();
                }
                catch
                {
                    // Clean up pacat if parecord fails to start
                    try { pacatProcess.Kill(); } catch { }
                    try { pacatProcess.Dispose(); } catch { }
                    pacatProcess = null;
                    throw;
                }

                // Start TX read thread
                running = true;
                txReadThread = new Thread(TxReadLoop)
                {
                    IsBackground = true,
                    Name = "VirtualAudioTxRead"
                };
                txReadThread.Start();

                return true;
            }
            catch
            {
                Destroy();
                return false;
            }
        }

        public void WriteSamples(byte[] pcm, int offset, int count)
        {
            if (!running || pacatProcess == null || pacatProcess.HasExited) return;

            try
            {
                var stdin = pacatProcess.StandardInput.BaseStream;
                stdin.Write(pcm, offset, count);
                stdin.Flush();
            }
            catch { }
        }

        private void TxReadLoop()
        {
            byte[] buffer = new byte[9600]; // ~100ms at 48kHz mono 16-bit

            try
            {
                var stdout = parecordProcess.StandardOutput.BaseStream;

                while (running && !parecordProcess.HasExited)
                {
                    int bytesRead = stdout.Read(buffer, 0, buffer.Length);
                    if (bytesRead <= 0) break;

                    // Check if the data is silence (all zeros) — skip to avoid unnecessary processing
                    bool isSilence = true;
                    for (int i = 0; i < bytesRead; i += 64)
                    {
                        if (buffer[i] != 0 || (i + 1 < bytesRead && buffer[i + 1] != 0))
                        {
                            isSilence = false;
                            break;
                        }
                    }
                    if (isSilence) continue;

                    byte[] data = new byte[bytesRead];
                    Array.Copy(buffer, data, bytesRead);
                    TxDataAvailable?.Invoke(data, bytesRead);
                }
            }
            catch { }
        }

        public void Destroy()
        {
            running = false;

            // Stop processes
            try { pacatProcess?.StandardInput?.Close(); } catch { }
            try
            {
                if (pacatProcess != null && !pacatProcess.HasExited)
                {
                    pacatProcess.Kill();
                    pacatProcess.WaitForExit(2000);
                }
            }
            catch { }
            pacatProcess?.Dispose();
            pacatProcess = null;

            try
            {
                if (parecordProcess != null && !parecordProcess.HasExited)
                {
                    parecordProcess.Kill();
                    parecordProcess.WaitForExit(2000);
                }
            }
            catch { }
            parecordProcess?.Dispose();
            parecordProcess = null;

            txReadThread?.Join(2000);
            txReadThread = null;

            // Unload PulseAudio modules
            if (virtualSourceModuleId >= 0)
            {
                UnloadModule(virtualSourceModuleId);
                virtualSourceModuleId = -1;
            }
            if (txSinkModuleId >= 0)
            {
                UnloadModule(txSinkModuleId);
                txSinkModuleId = -1;
            }
            if (rxSinkModuleId >= 0)
            {
                UnloadModule(rxSinkModuleId);
                rxSinkModuleId = -1;
            }
        }

        private void CleanupStaleModules()
        {
            // List loaded modules and remove any HTCommander ones from previous runs
            try
            {
                var cleanupPsi = new ProcessStartInfo
                {
                    FileName = "pactl",
                    UseShellExecute = false,
                    RedirectStandardOutput = true,
                    CreateNoWindow = true
                };
                cleanupPsi.ArgumentList.Add("list");
                cleanupPsi.ArgumentList.Add("short");
                cleanupPsi.ArgumentList.Add("modules");
                using var process = Process.Start(cleanupPsi);
                // Read output with size limit to prevent unbounded memory use
                char[] buf = new char[512 * 1024];
                int charsRead = process.StandardOutput.Read(buf, 0, buf.Length);
                string output = new string(buf, 0, charsRead);
                process.WaitForExit(5000);

                foreach (string line in output.Split('\n'))
                {
                    if (line.Contains("HTCommander"))
                    {
                        string[] parts = line.Split('\t', ' ');
                        if (parts.Length > 0 && int.TryParse(parts[0], out int moduleId))
                        {
                            UnloadModule(moduleId);
                        }
                    }
                }
            }
            catch { }
        }

        private static readonly HashSet<string> AllowedModules = new HashSet<string>
        {
            "module-null-sink", "module-virtual-source"
        };

        private int LoadModule(string moduleName, string arguments)
        {
            if (!AllowedModules.Contains(moduleName))
                return -1;

            try
            {
                var psi = new ProcessStartInfo
                {
                    FileName = "pactl",
                    UseShellExecute = false,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    CreateNoWindow = true
                };
                psi.ArgumentList.Add("load-module");
                psi.ArgumentList.Add(moduleName);
                // Split module arguments safely (key=value pairs separated by spaces)
                foreach (string arg in arguments.Split(' ', StringSplitOptions.RemoveEmptyEntries))
                    psi.ArgumentList.Add(arg);
                using var process = Process.Start(psi);
                string output = process.StandardOutput.ReadToEnd().Trim();
                process.WaitForExit(5000);

                if (process.ExitCode == 0 && int.TryParse(output, out int moduleId))
                {
                    return moduleId;
                }
            }
            catch { }
            return -1;
        }

        private void UnloadModule(int moduleId)
        {
            try
            {
                var psi = new ProcessStartInfo
                {
                    FileName = "pactl",
                    UseShellExecute = false,
                    RedirectStandardOutput = false,
                    RedirectStandardError = false,
                    CreateNoWindow = true
                };
                psi.ArgumentList.Add("unload-module");
                psi.ArgumentList.Add(moduleId.ToString());
                using var process = Process.Start(psi);
                process.WaitForExit(3000);
            }
            catch { }
        }

        public void Dispose()
        {
            Destroy();
        }
    }
}
