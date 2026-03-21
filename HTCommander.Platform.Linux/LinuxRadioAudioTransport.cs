/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;

namespace HTCommander.Platform.Linux
{
    /// <summary>
    /// Linux Bluetooth transport for the radio audio channel using direct RFCOMM sockets.
    /// Uses native read()/write() P/Invoke — NetworkStream doesn't work with RFCOMM fds.
    /// </summary>
    public class LinuxRadioAudioTransport : IRadioAudioTransport
    {
        private int rfcommFd = -1;
        private volatile bool _isConnected = false;
        private volatile bool _disposed = false;

        private const string GENERIC_AUDIO_UUID = "00001203-0000-1000-8000-00805f9b34fb";
        private const int NativeBufferSize = 4096;
        private IntPtr _readPtr = IntPtr.Zero;
        private IntPtr _writePtr = IntPtr.Zero;

        private DataBrokerClient logBroker;

        public bool IsConnected => _isConnected;

        private void Debug(string msg)
        {
            if (logBroker == null) logBroker = new DataBrokerClient();
            logBroker.Dispatch(1, "LogInfo", $"[AudioTransport]: {msg}", store: false);
        }

        public async Task<bool> ConnectAsync(string macAddress, CancellationToken cancellationToken)
        {
            try
            {
                string mac = macAddress.Replace(":", "").Replace("-", "").ToUpper();
                string macColon = string.Join(":", Enumerable.Range(0, 6).Select(i => mac.Substring(i * 2, 2)));
                byte[] bdaddr = ParseMacAddress(mac);

                // Wait for command channel to stabilize
                Debug("Waiting for command channel to stabilize...");
                await Task.Delay(2000, cancellationToken);

                // Step 1: Discover audio channel via SDP
                int[] audioChannels = await DiscoverAudioChannels(macColon);

                if (audioChannels != null && audioChannels.Length > 0)
                {
                    Debug($"SDP found audio channels: {string.Join(", ", audioChannels)}");
                    foreach (int ch in audioChannels)
                    {
                        int fd = CreateRfcommFd(bdaddr, ch);
                        if (fd >= 0)
                        {
                            Debug($"Connected to audio channel {ch}");
                            rfcommFd = fd;
                            break;
                        }
                        else
                        {
                            Debug($"Channel {ch}: connect failed (errno={Marshal.GetLastWin32Error()})");
                        }
                    }
                }

                // Step 2: Probe channels 1-10
                if (rfcommFd < 0)
                {
                    Debug("Probing RFCOMM channels 1-10 for audio...");
                    for (int ch = 1; ch <= 10; ch++)
                    {
                        if (cancellationToken.IsCancellationRequested) return false;
                        int fd = CreateRfcommFd(bdaddr, ch);
                        if (fd >= 0)
                        {
                            Debug($"Channel {ch}: connected");
                            rfcommFd = fd;
                            break;
                        }
                        else
                        {
                            Debug($"Channel {ch}: connect failed (errno={Marshal.GetLastWin32Error()})");
                        }
                    }
                }

                // Step 3: Retry with more delay
                if (rfcommFd < 0)
                {
                    Debug("First attempt failed, retrying after delay...");
                    await Task.Delay(3000, cancellationToken);
                    for (int ch = 1; ch <= 10; ch++)
                    {
                        if (cancellationToken.IsCancellationRequested) return false;
                        int fd = CreateRfcommFd(bdaddr, ch);
                        if (fd >= 0)
                        {
                            Debug($"Retry: Channel {ch}: connected");
                            rfcommFd = fd;
                            break;
                        }
                    }
                }

                if (rfcommFd < 0)
                {
                    Debug("All audio channel connection attempts failed");
                    return false;
                }

                // Set non-blocking mode (same approach as command channel)
                int flags = NativeMethods.fcntl(rfcommFd, 3 /* F_GETFL */, 0);
                if (flags < 0) { Debug("fcntl F_GETFL failed on audio fd"); NativeMethods.close(rfcommFd); rfcommFd = -1; return false; }
                NativeMethods.fcntl(rfcommFd, 4 /* F_SETFL */, flags | 0x800 /* O_NONBLOCK */);

                // Pre-allocate native buffers for read/write to avoid per-call AllocHGlobal
                _readPtr = Marshal.AllocHGlobal(NativeBufferSize);
                _writePtr = Marshal.AllocHGlobal(NativeBufferSize);

                _isConnected = true;
                Debug("Audio transport connected successfully");
                return true;
            }
            catch (Exception ex)
            {
                Debug($"Audio transport connection error: {ex.Message}");
                Disconnect();
                return false;
            }
        }

        public Task<int> ReadAsync(byte[] buffer, int offset, int count, CancellationToken cancellationToken)
        {
            if (rfcommFd < 0 || !_isConnected) return Task.FromResult(0);

            // Non-blocking read with sleep (same pattern as command channel)
            return Task.Run(() =>
            {
                while (!cancellationToken.IsCancellationRequested && _isConnected)
                {
                    int readSize = Math.Min(count, NativeBufferSize);
                    int bytesRead = NativeMethods.read(rfcommFd, _readPtr, readSize);
                    if (bytesRead > 0)
                    {
                        // Clamp to requested count and buffer bounds to prevent overrun
                        if (bytesRead > readSize) bytesRead = readSize;
                        if (offset + bytesRead > buffer.Length) bytesRead = buffer.Length - offset;
                        if (bytesRead <= 0) return 0;
                        Marshal.Copy(_readPtr, buffer, offset, bytesRead);
                        return bytesRead;
                    }
                    else if (bytesRead == 0)
                    {
                        // Connection closed
                        _isConnected = false;
                        return 0;
                    }
                    else
                    {
                        int errno = Marshal.GetLastWin32Error();
                        if (errno == 11 || errno == 35) // EAGAIN / EWOULDBLOCK
                        {
                            Thread.Sleep(10);
                            continue;
                        }
                        // Real error
                        _isConnected = false;
                        return 0;
                    }
                }
                return 0;
            }, cancellationToken);
        }

        public Task WriteAsync(byte[] buffer, int offset, int count, CancellationToken cancellationToken)
        {
            if (rfcommFd < 0 || !_isConnected) return Task.CompletedTask;
            if (buffer == null || offset < 0 || count < 0 || offset + count > buffer.Length) return Task.CompletedTask;

            return Task.Run(() =>
            {
                int totalWritten = 0;
                while (totalWritten < count && !cancellationToken.IsCancellationRequested && _isConnected)
                {
                    int chunkSize = Math.Min(count - totalWritten, NativeBufferSize);
                    Marshal.Copy(buffer, offset + totalWritten, _writePtr, chunkSize);
                    int written = NativeMethods.write(rfcommFd, _writePtr, chunkSize);
                    if (written > 0)
                    {
                        totalWritten += written;
                    }
                    else if (written < 0)
                    {
                        int errno = Marshal.GetLastWin32Error();
                        if (errno == 11 || errno == 35) // EAGAIN
                        {
                            Thread.Sleep(5);
                            continue;
                        }
                        _isConnected = false;
                        break;
                    }
                }
            }, cancellationToken);
        }

        public Task FlushAsync(CancellationToken cancellationToken)
        {
            // Native RFCOMM sockets don't buffer — no flush needed
            return Task.CompletedTask;
        }

        public void Disconnect()
        {
            _isConnected = false;
            if (rfcommFd >= 0)
            {
                try { NativeMethods.close(rfcommFd); } catch (Exception) { }
                rfcommFd = -1;
            }
            if (_readPtr != IntPtr.Zero) { Marshal.FreeHGlobal(_readPtr); _readPtr = IntPtr.Zero; }
            if (_writePtr != IntPtr.Zero) { Marshal.FreeHGlobal(_writePtr); _writePtr = IntPtr.Zero; }
        }

        public void OnPause() { }
        public void OnResume() { }

        private async Task<int[]> DiscoverAudioChannels(string macColon)
        {
            try
            {
                var psi = new ProcessStartInfo("sdptool", $"browse {macColon}")
                {
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    UseShellExecute = false,
                    CreateNoWindow = true
                };
                using var proc = Process.Start(psi);
                if (proc != null)
                {
                    string output = await ReadProcessOutputLimited(proc.StandardOutput, 512 * 1024);
                    proc.WaitForExit(10000);

                    if (proc.ExitCode == 0 && !string.IsNullOrEmpty(output))
                    {
                        var channels = ParseSdptoolOutputForAudio(output);
                        if (channels.Count > 0) return channels.ToArray();
                    }
                }
            }
            catch (Exception ex)
            {
                Debug($"sdptool not available: {ex.Message}");
            }

            return null;
        }

        private static async Task<string> ReadProcessOutputLimited(System.IO.StreamReader reader, int maxBytes)
        {
            var sb = new System.Text.StringBuilder();
            char[] buf = new char[4096];
            int totalRead = 0;
            int read;
            while ((read = await reader.ReadAsync(buf, 0, buf.Length)) > 0)
            {
                totalRead += read;
                if (totalRead > maxBytes) { sb.Append(buf, 0, read - (totalRead - maxBytes)); break; }
                sb.Append(buf, 0, read);
            }
            return sb.ToString();
        }

        private List<int> ParseSdptoolOutputForAudio(string output)
        {
            var audioChannels = new List<int>();
            string[] records = output.Split(new[] { "Service Name:" }, StringSplitOptions.None);

            foreach (string record in records)
            {
                var channelMatch = Regex.Match(record, @"Channel:\s*(\d+)");
                if (!channelMatch.Success) continue;
                if (!int.TryParse(channelMatch.Groups[1].Value, out int channel)) continue;
                if (channel < 1 || channel > 30) continue;

                bool isAudio = record.Contains(GENERIC_AUDIO_UUID) ||
                               record.Contains("BS AOC") ||
                               record.Contains("GenericAudio") ||
                               record.Contains("00001203");

                if (isAudio)
                {
                    audioChannels.Add(channel);
                }
            }

            return audioChannels;
        }

        private static byte[] ParseMacAddress(string mac)
        {
            mac = mac.Replace(":", "").Replace("-", "");
            byte[] bytes = new byte[6];
            for (int i = 0; i < 6; i++)
                bytes[i] = Convert.ToByte(mac.Substring(i * 2, 2), 16);
            return bytes;
        }

        private int CreateRfcommFd(byte[] bdaddr, int channel)
        {
            if (bdaddr == null || bdaddr.Length < 6) return -1;

            int fd = NativeMethods.socket(31, 1, 3); // AF_BLUETOOTH, SOCK_STREAM, BTPROTO_RFCOMM
            if (fd < 0) return -1;

            var addr = new NativeMethods.sockaddr_rc();
            addr.rc_family = 31;
            addr.rc_channel = (byte)channel;
            addr.rc_bdaddr = new byte[6];
            for (int i = 0; i < 6; i++)
                addr.rc_bdaddr[i] = bdaddr[5 - i];

            int size = Marshal.SizeOf(addr);
            IntPtr addrPtr = Marshal.AllocHGlobal(size);
            try
            {
                Marshal.StructureToPtr(addr, addrPtr, false);
                int result = NativeMethods.connect(fd, addrPtr, size);
                if (result < 0)
                {
                    NativeMethods.close(fd);
                    return -1;
                }
            }
            finally
            {
                Marshal.FreeHGlobal(addrPtr);
            }

            return fd;
        }

        public void Dispose()
        {
            if (!_disposed)
            {
                Disconnect();
                logBroker?.Dispose();
                _disposed = true;
            }
        }

        private static class NativeMethods
        {
            [StructLayout(LayoutKind.Sequential)]
            public struct sockaddr_rc
            {
                public ushort rc_family;
                [MarshalAs(UnmanagedType.ByValArray, SizeConst = 6)]
                public byte[] rc_bdaddr;
                public byte rc_channel;
            }

            [DllImport("libc", SetLastError = true)]
            public static extern int socket(int domain, int type, int protocol);

            [DllImport("libc", SetLastError = true)]
            public static extern int connect(int sockfd, IntPtr addr, int addrlen);

            [DllImport("libc", SetLastError = true)]
            public static extern int close(int fd);

            [DllImport("libc", SetLastError = true)]
            public static extern int read(int fd, IntPtr buf, int count);

            [DllImport("libc", SetLastError = true)]
            public static extern int write(int fd, IntPtr buf, int count);

            [DllImport("libc", SetLastError = true)]
            public static extern int fcntl(int fd, int cmd, int arg);
        }
    }
}
