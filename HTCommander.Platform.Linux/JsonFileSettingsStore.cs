/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.IO;
using System.Text.Json;
using System.Collections.Generic;

namespace HTCommander.Platform.Linux
{
    /// <summary>
    /// JSON file-backed settings store for Linux (and Android with different base path).
    /// Stores settings at ~/.config/HTCommander/settings.json
    /// </summary>
    public class JsonFileSettingsStore : ISettingsStore
    {
        private readonly string _filePath;
        private readonly object _lock = new object();
        private Dictionary<string, JsonElement> _settings;

        public JsonFileSettingsStore(string filePath = null)
        {
            if (filePath == null)
            {
                string configDir = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                    "HTCommander");
                Directory.CreateDirectory(configDir);
                _filePath = Path.Combine(configDir, "settings.json");
            }
            else
            {
                _filePath = filePath;
                Directory.CreateDirectory(Path.GetDirectoryName(filePath));
            }

            Load();
        }

        private void Load()
        {
            lock (_lock)
            {
                try
                {
                    if (File.Exists(_filePath))
                    {
                        string json = File.ReadAllText(_filePath);
                        _settings = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(json)
                            ?? new Dictionary<string, JsonElement>();
                    }
                    else
                    {
                        _settings = new Dictionary<string, JsonElement>();
                    }
                }
                catch (Exception)
                {
                    _settings = new Dictionary<string, JsonElement>();
                }
            }
        }

        private void Save()
        {
            try
            {
                var options = new JsonSerializerOptions { WriteIndented = true };
                string json = JsonSerializer.Serialize(_settings, options);
                File.WriteAllText(_filePath, json);
                // Set restrictive file permissions (owner-only read/write) for settings containing credentials
                try { File.SetUnixFileMode(_filePath, UnixFileMode.UserRead | UnixFileMode.UserWrite); } catch { }
            }
            catch (Exception)
            {
                // Silently fail on write errors
            }
        }

        public void WriteString(string key, string value)
        {
            lock (_lock)
            {
                _settings[key] = JsonSerializer.SerializeToElement(value);
                Save();
            }
        }

        public string ReadString(string key, string defaultValue)
        {
            lock (_lock)
            {
                if (_settings.TryGetValue(key, out JsonElement element))
                {
                    if (element.ValueKind == JsonValueKind.String)
                        return element.GetString();
                }
                return defaultValue;
            }
        }

        public void WriteInt(string key, int value)
        {
            lock (_lock)
            {
                _settings[key] = JsonSerializer.SerializeToElement(value);
                Save();
            }
        }

        public int? ReadInt(string key, int? defaultValue)
        {
            lock (_lock)
            {
                if (_settings.TryGetValue(key, out JsonElement element))
                {
                    if (element.ValueKind == JsonValueKind.Number && element.TryGetInt32(out int intValue))
                        return intValue;
                }
                return defaultValue;
            }
        }

        public void WriteBool(string key, bool value)
        {
            lock (_lock)
            {
                _settings[key] = JsonSerializer.SerializeToElement(value);
                Save();
            }
        }

        public bool ReadBool(string key, bool defaultValue)
        {
            lock (_lock)
            {
                if (_settings.TryGetValue(key, out JsonElement element))
                {
                    if (element.ValueKind == JsonValueKind.True) return true;
                    if (element.ValueKind == JsonValueKind.False) return false;
                }
                return defaultValue;
            }
        }

        public void DeleteValue(string key)
        {
            lock (_lock)
            {
                if (_settings.Remove(key))
                {
                    Save();
                }
            }
        }
    }
}
