/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Diagnostics;
using System.Threading.Tasks;

namespace HTCommander.Platform.Linux
{
    /// <summary>
    /// Linux file picker using zenity or kdialog.
    /// When used with Avalonia, the Avalonia file picker will be preferred.
    /// This serves as a fallback.
    /// </summary>
    public class LinuxFilePickerService : IFilePickerService
    {
        public Task<string> PickFileAsync(string title, string[] filters)
        {
            return RunZenity(title, null, false, false);
        }

        public Task<string> SaveFileAsync(string title, string defaultName, string[] filters)
        {
            return RunZenity(title, defaultName, true, false);
        }

        public Task<string> PickFolderAsync(string title)
        {
            return RunZenity(title, null, false, true);
        }

        private static async Task<string> RunZenity(string title, string defaultName, bool save, bool directory)
        {
            try
            {
                var psi = new ProcessStartInfo("zenity")
                {
                    RedirectStandardOutput = true,
                    UseShellExecute = false,
                    CreateNoWindow = true
                };
                psi.ArgumentList.Add("--file-selection");
                if (!string.IsNullOrEmpty(title))
                {
                    psi.ArgumentList.Add("--title=" + title);
                }
                if (save) psi.ArgumentList.Add("--save");
                if (directory) psi.ArgumentList.Add("--directory");
                if (!string.IsNullOrEmpty(defaultName))
                {
                    psi.ArgumentList.Add("--filename=" + defaultName);
                }

                using var process = Process.Start(psi);
                string result = await process.StandardOutput.ReadToEndAsync();
                await process.WaitForExitAsync();

                if (process.ExitCode == 0)
                    return result?.Trim();
            }
            catch (Exception)
            {
                // zenity not available, try kdialog
                try
                {
                    var psi = new ProcessStartInfo("kdialog")
                    {
                        RedirectStandardOutput = true,
                        UseShellExecute = false,
                        CreateNoWindow = true
                    };

                    if (directory)
                        psi.ArgumentList.Add("--getexistingdirectory");
                    else if (save)
                        psi.ArgumentList.Add("--getsavefilename");
                    else
                        psi.ArgumentList.Add("--getopenfilename");

                    psi.ArgumentList.Add(".");

                    if (!string.IsNullOrEmpty(title))
                    {
                        psi.ArgumentList.Add("--title");
                        psi.ArgumentList.Add(title);
                    }

                    using var process = Process.Start(psi);
                    string result = await process.StandardOutput.ReadToEndAsync();
                    await process.WaitForExitAsync();

                    if (process.ExitCode == 0)
                        return result?.Trim();
                }
                catch (Exception) { }
            }

            return null;
        }
    }
}
