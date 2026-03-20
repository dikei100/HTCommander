/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;

namespace HTCommander.Platform.Windows
{
    /// <summary>
    /// Windows platform service provider. Creates Windows-specific implementations
    /// of all platform abstractions.
    /// </summary>
    public class WinPlatformServices : IPlatformServices
    {
        public ISettingsStore Settings { get; }
        public IAudioService Audio { get; }
        public ISpeechService Speech { get; }
        public IFilePickerService FilePicker { get; }
        public IPlatformUtils PlatformUtils { get; }

        public WinPlatformServices(string appName)
        {
            Settings = new RegistrySettingsStore(appName);
            Audio = new WinAudioService();
            Speech = new WinSpeechService();
            FilePicker = new WinFilePickerService();
            PlatformUtils = new WinPlatformUtils();
        }

        public IRadioBluetooth CreateRadioBluetooth(IRadioHost radioHost)
        {
            return new RadioBluetoothWin(radioHost);
        }

        public IRadioAudioTransport CreateRadioAudioTransport()
        {
            return new WinRadioAudioTransport();
        }

        public IVirtualSerialPort CreateVirtualSerialPort()
        {
            // Read the user-configured COM port (one end of a com0com pair)
            string comPort = DataBroker.GetValue<string>(0, "CatComPort", "");
            if (string.IsNullOrEmpty(comPort) || comPort == "None")
                return null;
            return new WinVirtualSerialPort(comPort);
        }

        public IVirtualAudioProvider CreateVirtualAudioProvider()
        {
            return null; // Windows: use VB-CABLE for virtual audio
        }
    }
}
