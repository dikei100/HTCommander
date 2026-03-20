/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.IO.Ports;
using System.Threading;

namespace HTCommander.Platform.Windows
{
    /// <summary>
    /// Windows implementation of IVirtualSerialPort using System.IO.Ports.SerialPort.
    /// Opens one end of a com0com virtual COM port pair for CAT control.
    /// The user configures which COM port to use via the CatComPort setting.
    /// </summary>
    public class WinVirtualSerialPort : IVirtualSerialPort
    {
        private SerialPort port;
        private string comPortName;
        private volatile bool running = false;

        public string DevicePath => comPortName;
        public bool IsRunning => running;
        public event Action<byte[], int> DataReceived;

        public WinVirtualSerialPort(string comPort)
        {
            comPortName = comPort;
        }

        public bool Create()
        {
            if (string.IsNullOrEmpty(comPortName)) return false;

            try
            {
                port = new SerialPort(comPortName, 9600, Parity.None, 8, StopBits.One);
                port.ReadTimeout = SerialPort.InfiniteTimeout;
                port.WriteTimeout = 1000;
                port.Open();

                running = true;
                port.DataReceived += OnSerialDataReceived;
                return true;
            }
            catch (Exception)
            {
                port?.Dispose();
                port = null;
                return false;
            }
        }

        private void OnSerialDataReceived(object sender, SerialDataReceivedEventArgs e)
        {
            if (!running || port == null) return;
            try
            {
                int bytesToRead = port.BytesToRead;
                if (bytesToRead <= 0) return;
                byte[] buffer = new byte[bytesToRead];
                int bytesRead = port.Read(buffer, 0, bytesToRead);
                if (bytesRead > 0)
                {
                    DataReceived?.Invoke(buffer, bytesRead);
                }
            }
            catch (Exception) { }
        }

        public void Write(byte[] data, int offset, int count)
        {
            if (!running || port == null) return;
            try
            {
                port.Write(data, offset, count);
            }
            catch (Exception) { }
        }

        public void Dispose()
        {
            running = false;
            if (port != null)
            {
                try { port.DataReceived -= OnSerialDataReceived; } catch { }
                try { port.Close(); } catch { }
                try { port.Dispose(); } catch { }
                port = null;
            }
        }
    }
}
