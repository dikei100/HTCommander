/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;

namespace HTCommander
{
    public class ImapServer
    {
        private DataBrokerClient broker;
        private TcpListener listener;
        private Thread listenerThread;
        private volatile bool running;
        public readonly int Port;
        private const int MaxSessions = 10;
        private List<ImapSession> sessions = new List<ImapSession>();
        private int globalAuthFailures = 0;
        private long lastAuthFailureReset = Environment.TickCount64;
        private readonly object authRateLock = new object();
        private const int MaxGlobalAuthFailuresPerMinute = 20;

        public ImapServer(int port)
        {
            this.Port = port;
            this.broker = new DataBrokerClient();
        }

        public void Start()
        {
            try
            {
                listener = new TcpListener(IPAddress.Loopback, Port);
                listener.Start();
                running = true;
                listenerThread = new Thread(ListenerLoop);
                listenerThread.IsBackground = true;
                listenerThread.Start();
                broker.LogInfo($"IMAP server started on port {Port}");
            }
            catch (Exception)
            {
                // IMAP server failed to start
            }
        }

        public void Stop()
        {
            running = false;
            if (listener != null) listener.Stop();
            lock (sessions)
            {
                ImapSession[] sessionArray = new ImapSession[sessions.Count];
                sessions.CopyTo(sessionArray, 0);
                foreach (var session in sessionArray)
                {
                    session.Close();
                }
                sessions.Clear();
            }
            broker.LogInfo("IMAP server stopped");
        }

        private void ListenerLoop()
        {
            while (running)
            {
                try
                {
                    TcpClient client = listener.AcceptTcpClient();
                    lock (sessions)
                    {
                        if (sessions.Count >= MaxSessions)
                        {
                            client.Close();
                            continue;
                        }
                    }
                    ImapSession session = new ImapSession(this, client, broker);
                    lock (sessions)
                    {
                        sessions.Add(session);
                    }
                    Thread sessionThread = new Thread(session.Run);
                    sessionThread.IsBackground = true;
                    sessionThread.Start();
                }
                catch (Exception)
                {
                    if (running) Thread.Sleep(100);
                }
            }
        }

        public void RemoveSession(ImapSession session)
        {
            lock (sessions)
            {
                sessions.Remove(session);
            }
        }

        internal bool CheckGlobalAuthRateLimit()
        {
            lock (authRateLock)
            {
                long now = Environment.TickCount64;
                if (now - lastAuthFailureReset > 60000)
                {
                    globalAuthFailures = 0;
                    lastAuthFailureReset = now;
                }
                return globalAuthFailures < MaxGlobalAuthFailuresPerMinute;
            }
        }

        internal void RecordAuthFailure()
        {
            lock (authRateLock) { globalAuthFailures++; }
        }
    }

    public class ImapSession
    {
        private ImapServer server;
        private DataBrokerClient broker;
        private TcpClient client;
        private StreamReader reader;
        private StreamWriter writer;
        private const int MaxAuthAttempts = 5;
        private bool authenticated;
        private int authAttempts = 0;
        private int selectedMailbox = -1;
        private Dictionary<int, uint> messageUids = new Dictionary<int, uint>();
        private Dictionary<int, HashSet<string>> messageFlags = new Dictionary<int, HashSet<string>>();
        private uint uidNext = 1;

        // IMAP folder names mapped to mailbox indices
        private readonly Dictionary<string, int> folderToMailbox = new Dictionary<string, int>
        {
            { "INBOX", 0 },
            { "Outbox", 1 },
            { "Drafts", 2 },
            { "Sent", 3 },
            { "Archive", 4 },
            { "Trash", 5 }
        };

        private readonly Dictionary<int, string> mailboxToFolder = new Dictionary<int, string>
        {
            { 0, "INBOX" },
            { 1, "Outbox" },
            { 2, "Drafts" },
            { 3, "Sent" },
            { 4, "Archive" },
            { 5, "Trash" }
        };

        public ImapSession(ImapServer server, TcpClient client, DataBrokerClient broker)
        {
            this.server = server;
            this.client = client;
            this.broker = broker;
            this.reader = new StreamReader(client.GetStream(), Encoding.UTF8);
            this.writer = new StreamWriter(client.GetStream(), Encoding.UTF8) { AutoFlush = true };
        }

        private const int MaxLineLength = 8192; // Max IMAP command line length

        private string ReadLineLimited()
        {
            var sb = new StringBuilder();
            int ch;
            while ((ch = reader.Read()) >= 0)
            {
                if (ch == '\n') return sb.ToString().TrimEnd('\r');
                sb.Append((char)ch);
                if (sb.Length > MaxLineLength) return null; // Line too long
            }
            return sb.Length > 0 ? sb.ToString() : null;
        }

        public void Run()
        {
            try
            {
                // Set read timeout to prevent slowloris-style attacks
                client.GetStream().ReadTimeout = 30000;

                broker.LogInfo("IMAP: Client connected");
                writer.WriteLine("* OK HTCommander IMAP Server Ready");

                string line;
                while ((line = ReadLineLimited()) != null)
                {
                    if (string.IsNullOrWhiteSpace(line)) continue;
                    ProcessCommand(line);
                }
            }
            catch (IOException)
            {
                // Connection closed by client, normal disconnect
            }
            catch (ObjectDisposedException)
            {
                // Stream/socket was disposed, normal during shutdown
            }
            catch (InvalidOperationException)
            {
                // This is expected when LOGOUT is called
            }
            catch (Exception)
            {
                // Session error - connection closed or disposed
            }
            finally
            {
                Close();
            }
        }

        private void ProcessCommand(string line)
        {
            // Parse IMAP command: tag command [args...]
            string[] parts = line.Split(new[] { ' ' }, 3);
            if (parts.Length < 2) return;

            string tag = parts[0];
            string command = parts[1].ToUpper();
            string args = parts.Length > 2 ? parts[2] : "";

            try
            {
                switch (command)
                {
                    case "CAPABILITY":
                        HandleCapability(tag);
                        break;
                    case "AUTHENTICATE":
                        HandleAuthenticate(tag, args);
                        break;
                    case "LOGIN":
                        HandleLogin(tag, args);
                        break;
                    case "LSUB":
                        HandleLsub(tag, args);
                        break;
                    case "LIST":
                        HandleList(tag, args);
                        break;
                    case "SELECT":
                        HandleSelect(tag, args);
                        break;
                    case "EXAMINE":
                        HandleExamine(tag, args);
                        break;
                    case "STATUS":
                        HandleStatus(tag, args);
                        break;
                    case "FETCH":
                        HandleFetch(tag, args);
                        break;
                    case "STORE":
                        HandleStore(tag, args);
                        break;
                    case "COPY":
                        HandleCopy(tag, args);
                        break;
                    case "EXPUNGE":
                        HandleExpunge(tag);
                        break;
                    case "SEARCH":
                        HandleSearch(tag, args);
                        break;
                    case "CLOSE":
                        HandleClose(tag);
                        break;
                    case "LOGOUT":
                        HandleLogout(tag);
                        break;
                    case "NOOP":
                        SendResponse(tag, "OK NOOP completed");
                        break;
                    case "UID":
                        HandleUidCommand(tag, args);
                        break;
                    case "APPEND":
                        HandleAppend(tag, args);
                        break;
                    default:
                        SendResponse(tag, $"BAD Unknown command: {command}");
                        break;
                }
            }
            catch (Exception ex)
            {
                // Don't log or respond if connection is already closed
                if (ex is IOException || ex is InvalidOperationException)
                {
                    return;
                }
                broker.LogInfo($"IMAP command error: {ex.Message}");
                try
                {
                    SendResponse(tag, "BAD Command failed");
                }
                catch
                {
                    // Can't send response, connection is closed
                }
            }
        }

        private void HandleCapability(string tag)
        {
            writer.WriteLine("* CAPABILITY IMAP4rev1 AUTH=PLAIN UIDPLUS");
            SendResponse(tag, "OK CAPABILITY completed");
        }

        private void HandleLogin(string tag, string args)
        {
            if (authAttempts >= MaxAuthAttempts || !server.CheckGlobalAuthRateLimit())
            {
                SendResponse(tag, "NO Too many authentication attempts");
                return;
            }

            string[] parts = ParseImapString(args);
            if (parts.Length < 2)
            {
                SendResponse(tag, "BAD Invalid LOGIN command");
                return;
            }

            string user = parts[0];
            string pass = parts[1];
            string winlinkPassword = DataBroker.GetValue<string>(0, "WinlinkPassword", "");

            // Use constant-time comparison to prevent timing attacks
            bool passMatch = !string.IsNullOrEmpty(winlinkPassword) &&
                pass != null &&
                System.Security.Cryptography.CryptographicOperations.FixedTimeEquals(
                    System.Text.Encoding.UTF8.GetBytes(pass),
                    System.Text.Encoding.UTF8.GetBytes(winlinkPassword));
            if (IsValidUsername(user) && passMatch)
            {
                authenticated = true;
                broker.LogInfo($"IMAP: User {user} authenticated");
                SendResponse(tag, "OK [CAPABILITY IMAP4rev1 AUTH=PLAIN UIDPLUS] LOGIN completed");
            }
            else
            {
                authAttempts++;
                server.RecordAuthFailure();
                broker.LogInfo($"IMAP: Authentication failed (attempt {authAttempts}/{MaxAuthAttempts})");
                SendResponse(tag, "NO LOGIN failed");
            }
        }

        private void HandleAuthenticate(string tag, string args)
        {
            // Thunderbird uses AUTHENTICATE PLAIN
            // For now, just reject it and let it fall back to LOGIN
            SendResponse(tag, "NO AUTHENTICATE not supported, use LOGIN");
        }

        private void HandleLsub(string tag, string args)
        {
            if (!authenticated)
            {
                SendResponse(tag, "NO Not authenticated");
                return;
            }

            // LSUB lists subscribed folders - for simplicity, return all folders
            foreach (var folder in folderToMailbox.Keys)
            {
                writer.WriteLine($"* LSUB () \"/\" \"{folder}\"");
            }

            SendResponse(tag, "OK LSUB completed");
        }

        private void HandleAppend(string tag, string args)
        {
            if (!authenticated)
            {
                SendResponse(tag, "NO Not authenticated");
                return;
            }

            // Parse: APPEND "folder" (\Flags) {size}
            string[] parts = args.Split(new[] { ' ' }, 3);
            if (parts.Length < 3)
            {
                SendResponse(tag, "BAD Invalid APPEND command");
                return;
            }

            string folderName = ParseImapString(parts[0])[0];
            if (!folderToMailbox.TryGetValue(folderName, out int mailboxIndex))
            {
                SendResponse(tag, "NO Folder not found");
                return;
            }

            // Parse flags (optional)
            string flagsStr = parts[1].Trim('(', ')');

            // Parse size {396}
            string sizeStr = parts[2].Trim('{', '}');
            if (!int.TryParse(sizeStr, out int messageSize) || messageSize < 0)
            {
                SendResponse(tag, "BAD Invalid message size");
                return;
            }
            if (messageSize > 10 * 1024 * 1024) // 10MB max
            {
                SendResponse(tag, "NO Message too large");
                return;
            }

            // Tell client we're ready to receive the message
            writer.WriteLine("+ Ready for literal data");

            // Read the message data
            char[] buffer = new char[messageSize];
            int totalRead = 0;
            while (totalRead < messageSize)
            {
                int read = reader.Read(buffer, totalRead, messageSize - totalRead);
                if (read == 0) break;
                totalRead += read;
            }

            string messageData = new string(buffer, 0, totalRead);

            // Read the trailing CRLF
            reader.ReadLine();

            // Parse the RFC822 message
            WinLinkMail mail = ParseRfc822Message(messageData);
            mail.Mailbox = folderName;
            mail.MID = Guid.NewGuid().ToString("N").Substring(0, 12).ToUpper();

            DataBroker.Dispatch(1, "MailReceived", mail, store: false);

            broker.LogInfo($"IMAP: Email appended to {folderName} - Subject: {mail.Subject}");
            SendResponse(tag, "OK APPEND completed");
        }

        private WinLinkMail ParseRfc822Message(string messageData)
        {
            WinLinkMail mail = new WinLinkMail
            {
                DateTime = DateTime.Now,
                From = "",
                To = "",
                Cc = "",
                Subject = "",
                Body = ""
            };

            StringReader sr = new StringReader(messageData);
            string line;
            bool inHeaders = true;
            StringBuilder bodyBuilder = new StringBuilder();

            while ((line = sr.ReadLine()) != null)
            {
                if (inHeaders)
                {
                    if (string.IsNullOrWhiteSpace(line))
                    {
                        inHeaders = false;
                        continue;
                    }

                    if (line.StartsWith("From:", StringComparison.OrdinalIgnoreCase))
                    {
                        mail.From = line.Substring(5).Trim();
                        // Remove angle brackets if present
                        if (mail.From.Contains("<") && mail.From.Contains(">"))
                        {
                            int start = mail.From.IndexOf('<') + 1;
                            int end = mail.From.IndexOf('>');
                            mail.From = mail.From.Substring(start, end - start);
                        }
                    }
                    else if (line.StartsWith("To:", StringComparison.OrdinalIgnoreCase))
                    {
                        mail.To = line.Substring(3).Trim();
                    }
                    else if (line.StartsWith("Cc:", StringComparison.OrdinalIgnoreCase))
                    {
                        mail.Cc = line.Substring(3).Trim();
                    }
                    else if (line.StartsWith("Subject:", StringComparison.OrdinalIgnoreCase))
                    {
                        mail.Subject = line.Substring(8).Trim();
                    }
                    else if (line.StartsWith("Date:", StringComparison.OrdinalIgnoreCase))
                    {
                        string dateStr = line.Substring(5).Trim();
                        DateTime tempDate;
                        if (DateTime.TryParse(dateStr, out tempDate))
                            mail.DateTime = tempDate;
                    }
                }
                else
                {
                    bodyBuilder.AppendLine(line);
                }
            }

            mail.Body = bodyBuilder.ToString().TrimEnd();
            return mail;
        }

        private bool IsValidUsername(string user)
        {
            string callsign = DataBroker.GetValue<string>(0, "CallSign", "");
            int stationId = DataBroker.GetValue<int>(0, "StationId", 0);

            if (string.IsNullOrEmpty(user) || string.IsNullOrEmpty(callsign))
                return false;

            user = user.ToUpper();
            callsign = callsign.ToUpper();
            string callsignWithId = callsign;
            if (stationId > 0)
                callsignWithId += "-" + stationId;

            return user == callsign ||
                   user == callsignWithId ||
                   user == callsign + "@WINLINK.ORG" ||
                   user == callsignWithId + "@WINLINK.ORG";
        }

        private void HandleList(string tag, string args)
        {
            if (!authenticated)
            {
                SendResponse(tag, "NO Not authenticated");
                return;
            }

            // Parse LIST reference pattern
            string[] parts = ParseImapString(args);
            if (parts.Length < 2)
            {
                // If no args provided, list all folders
                foreach (var folder in folderToMailbox.Keys)
                {
                    writer.WriteLine($"* LIST () \"/\" \"{folder}\"");
                }
                SendResponse(tag, "OK LIST completed");
                return;
            }

            string reference = parts[0];
            string pattern = parts[1];

            foreach (var folder in folderToMailbox.Keys)
            {
                writer.WriteLine($"* LIST () \"/\" \"{folder}\"");
            }

            SendResponse(tag, "OK LIST completed");
        }

        private void HandleSelect(string tag, string args)
        {
            if (!authenticated)
            {
                SendResponse(tag, "NO Not authenticated");
                return;
            }

            string folderName = ParseImapString(args)[0];
            if (!folderToMailbox.TryGetValue(folderName, out int mailboxIndex))
            {
                SendResponse(tag, "NO Folder not found");
                return;
            }

            selectedMailbox = mailboxIndex;
            InitializeMailboxState();

            List<WinLinkMail> mails = GetMailsInMailbox(mailboxIndex);

            uint uidValidity = (uint)(mailboxIndex + 1000);

            writer.WriteLine($"* {mails.Count} EXISTS");
            writer.WriteLine($"* {mails.Count} RECENT");
            if (mails.Count > 0)
                writer.WriteLine($"* OK [UNSEEN 1]");
            writer.WriteLine($"* OK [UIDVALIDITY {uidValidity}]");
            writer.WriteLine($"* OK [UIDNEXT {uidNext}]");
            writer.WriteLine("* FLAGS (\\Seen \\Answered \\Flagged \\Deleted \\Draft)");
            writer.WriteLine("* OK [PERMANENTFLAGS (\\Seen \\Answered \\Flagged \\Deleted \\Draft)]");

            SendResponse(tag, $"OK [READ-WRITE] SELECT completed");
        }

        private void HandleExamine(string tag, string args)
        {
            // Same as SELECT but read-only
            HandleSelect(tag, args);
        }

        private void HandleStatus(string tag, string args)
        {
            if (!authenticated)
            {
                SendResponse(tag, "NO Not authenticated");
                return;
            }

            // STATUS "folder" (MESSAGES UNSEEN)
            string[] parts = args.Split(new[] { ' ' }, 2);
            if (parts.Length < 2)
            {
                SendResponse(tag, "BAD Invalid STATUS command");
                return;
            }

            string folderName = ParseImapString(parts[0])[0];
            if (!folderToMailbox.TryGetValue(folderName, out int mailboxIndex))
            {
                SendResponse(tag, "NO Folder not found");
                return;
            }

            List<WinLinkMail> mails = GetMailsInMailbox(mailboxIndex);
            writer.WriteLine($"* STATUS \"{folderName}\" (MESSAGES {mails.Count} UNSEEN 0)");
            SendResponse(tag, "OK STATUS completed");
        }

        private void HandleFetch(string tag, string args)
        {
            if (!authenticated || selectedMailbox < 0)
            {
                SendResponse(tag, "NO No mailbox selected");
                return;
            }

            // Parse: sequence-set items
            string[] parts = args.Split(new[] { ' ' }, 2);
            if (parts.Length < 2)
            {
                SendResponse(tag, "BAD Invalid FETCH command");
                return;
            }

            List<int> sequences = ParseSequenceSet(parts[0]);
            string items = parts[1].Trim('(', ')').ToUpper();

            List<WinLinkMail> mails = GetMailsInMailbox(selectedMailbox);

            foreach (int seq in sequences)
            {
                if (seq < 1 || seq > mails.Count)
                {
                    continue;
                }

                int index = seq - 1;
                WinLinkMail mail = mails[index];
                uint uid = messageUids[index];

                List<string> fetchItems = new List<string>();

                if (items.Contains("UID"))
                    fetchItems.Add($"UID {uid}");

                if (items.Contains("FLAGS"))
                {
                    string flags = GetFlagsString(index);
                    fetchItems.Add($"FLAGS ({flags})");
                }

                bool hasOnlyBasicItems = !items.Contains("BODY") && !items.Contains("RFC822");

                if (hasOnlyBasicItems && fetchItems.Count > 0)
                {
                    string response = $"* {seq} FETCH (" + string.Join(" ", fetchItems) + ")";
                    writer.WriteLine(response);
                    continue;
                }

                if (items.Contains("INTERNALDATE"))
                    fetchItems.Add($"INTERNALDATE \"{mail.DateTime:dd-MMM-yyyy HH:mm:ss +0000}\"");

                if (items.Contains("RFC822.SIZE") || items.Contains("BODYSTRUCTURE"))
                {
                    string fullMessage = BuildRfc822Message(mail);
                    fetchItems.Add($"RFC822.SIZE {Encoding.UTF8.GetByteCount(fullMessage)}");
                }

                if (items.Contains("BODY.PEEK[HEADER]") || items.Contains("BODY[HEADER]"))
                {
                    string header = BuildRfc822Header(mail);
                    fetchItems.Add($"BODY[HEADER] {{{Encoding.UTF8.GetByteCount(header)}}}");
                    writer.WriteLine(string.Join(" ", fetchItems) + ")");
                    writer.WriteLine(header);
                    continue;
                }

                if (!hasOnlyBasicItems && items.Contains("BODY.PEEK[HEADER"))
                {
                    string header = BuildRfc822Header(mail);
                    int headerSize = Encoding.UTF8.GetByteCount(header);

                    if (items.Contains("RFC822.SIZE"))
                    {
                        string fullMessage = BuildRfc822Message(mail);
                        fetchItems.Add($"RFC822.SIZE {Encoding.UTF8.GetByteCount(fullMessage)}");
                    }

                    fetchItems.Add($"BODY[HEADER.FIELDS (FROM TO CC BCC SUBJECT DATE MESSAGE-ID)] {{{headerSize}}}");

                    writer.WriteLine($"* {seq} FETCH (" + string.Join(" ", fetchItems) + ")");
                    writer.Write(header);
                    writer.WriteLine();
                    writer.Flush();
                    continue;
                }

                if (items.Contains("BODY[]") || items.Contains("RFC822"))
                {
                    string fullMessage = BuildRfc822Message(mail);
                    fetchItems.Add($"BODY[] {{{Encoding.UTF8.GetByteCount(fullMessage)}}}");
                    writer.WriteLine(string.Join(" ", fetchItems) + ")");
                    writer.WriteLine(fullMessage);
                    continue;
                }

                writer.WriteLine(string.Join(" ", fetchItems) + ")");
            }

            SendResponse(tag, "OK FETCH completed");
        }

        private void HandleStore(string tag, string args)
        {
            if (!authenticated || selectedMailbox < 0)
            {
                SendResponse(tag, "NO No mailbox selected");
                return;
            }

            // Parse: sequence-set FLAGS (\Seen \Deleted)
            string[] parts = args.Split(new[] { ' ' }, 3);
            if (parts.Length < 3)
            {
                SendResponse(tag, "BAD Invalid STORE command");
                return;
            }

            List<int> sequences = ParseSequenceSet(parts[0]);
            string operation = parts[1].ToUpper();
            string flagsStr = parts[2].Trim('(', ')');

            bool isAdd = operation.Contains("+");
            bool isRemove = operation.Contains("-");

            foreach (int seq in sequences)
            {
                List<WinLinkMail> mails = GetMailsInMailbox(selectedMailbox);
                if (seq < 1 || seq > mails.Count) continue;

                int index = seq - 1;

                if (!messageFlags.ContainsKey(index))
                    messageFlags[index] = new HashSet<string>();

                if (isAdd)
                {
                    foreach (string flag in flagsStr.Split(' '))
                        messageFlags[index].Add(flag.Trim());
                }
                else if (isRemove)
                {
                    foreach (string flag in flagsStr.Split(' '))
                        messageFlags[index].Remove(flag.Trim());
                }
                else
                {
                    messageFlags[index].Clear();
                    foreach (string flag in flagsStr.Split(' '))
                        messageFlags[index].Add(flag.Trim());
                }

                writer.WriteLine($"* {seq} FETCH (FLAGS ({GetFlagsString(index)}))");
            }

            SendResponse(tag, "OK STORE completed");
        }

        private void HandleCopy(string tag, string args)
        {
            if (!authenticated || selectedMailbox < 0)
            {
                SendResponse(tag, "NO No mailbox selected");
                return;
            }

            // Parse: sequence-set destination-folder
            string[] parts = args.Split(new[] { ' ' }, 2);
            if (parts.Length < 2)
            {
                SendResponse(tag, "BAD Invalid COPY command");
                return;
            }

            List<int> sequences = ParseSequenceSet(parts[0]);
            string destFolder = ParseImapString(parts[1])[0];

            if (!folderToMailbox.TryGetValue(destFolder, out int destMailbox))
            {
                SendResponse(tag, "NO Destination folder not found");
                return;
            }

            List<WinLinkMail> mails = GetMailsInMailbox(selectedMailbox);

            foreach (int seq in sequences)
            {
                if (seq < 1 || seq > mails.Count) continue;

                WinLinkMail mail = mails[seq - 1];
                WinLinkMail copy = new WinLinkMail
                {
                    MID = Guid.NewGuid().ToString("N").Substring(0, 12).ToUpper(),
                    From = mail.From,
                    To = mail.To,
                    Cc = mail.Cc,
                    Subject = mail.Subject,
                    Body = mail.Body,
                    DateTime = mail.DateTime,
                    Mailbox = destFolder,
                    Attachments = mail.Attachments
                };

                DataBroker.Dispatch(1, "MailReceived", copy, store: false);
            }

            SendResponse(tag, "OK COPY completed");
        }

        private void HandleExpunge(string tag)
        {
            if (!authenticated || selectedMailbox < 0)
            {
                SendResponse(tag, "NO No mailbox selected");
                return;
            }

            List<WinLinkMail> mails = GetMailsInMailbox(selectedMailbox);
            List<int> toDelete = new List<int>();

            for (int i = 0; i < mails.Count; i++)
            {
                if (messageFlags.ContainsKey(i) && messageFlags[i].Contains("\\Deleted"))
                {
                    toDelete.Add(i);
                }
            }

            // Delete in reverse order to maintain indices
            toDelete.Reverse();
            foreach (int index in toDelete)
            {
                WinLinkMail mail = mails[index];
                mail.Mailbox = "Trash";
                writer.WriteLine($"* {index + 1} EXPUNGE");
            }

            foreach (int index in toDelete)
            {
                WinLinkMail mail = mails[index];
                DataBroker.Dispatch(1, "MailUpdated", mail, store: false);
            }
            InitializeMailboxState();

            SendResponse(tag, "OK EXPUNGE completed");
        }

        private void HandleSearch(string tag, string args)
        {
            if (!authenticated || selectedMailbox < 0)
            {
                SendResponse(tag, "NO No mailbox selected");
                return;
            }

            List<WinLinkMail> mails = GetMailsInMailbox(selectedMailbox);
            List<int> results = new List<int>();

            // Simple search - just return ALL for now
            if (args.ToUpper().Contains("ALL"))
            {
                for (int i = 0; i < mails.Count; i++)
                {
                    results.Add(i + 1);
                }
            }

            writer.Write("* SEARCH");
            foreach (int seq in results)
            {
                writer.Write($" {seq}");
            }
            writer.WriteLine();

            SendResponse(tag, "OK SEARCH completed");
        }

        private void HandleUidCommand(string tag, string args)
        {
            // UID FETCH, UID STORE, UID SEARCH, UID COPY
            string[] parts = args.Split(new[] { ' ' }, 2);
            if (parts.Length < 2)
            {
                SendResponse(tag, "BAD Invalid UID command");
                return;
            }

            string subCommand = parts[0].ToUpper();
            string subArgs = parts[1];

            // Parse the UID set and convert to sequence numbers
            string[] argParts = subArgs.Split(new[] { ' ' }, 2);
            string uidSet = argParts[0];
            string restOfArgs = argParts.Length > 1 ? argParts[1] : "";

            // Convert UID set to sequence set
            List<int> sequences = ParseUidSet(uidSet);
            string sequenceSet = string.Join(",", sequences);

            // For UID FETCH, ensure UID is in the items list
            if (subCommand == "FETCH" && !string.IsNullOrEmpty(restOfArgs))
            {
                string items = restOfArgs.Trim('(', ')').ToUpper();
                if (!items.Contains("UID"))
                {
                    restOfArgs = "(UID " + restOfArgs.TrimStart('(');
                }
            }

            string convertedArgs = sequenceSet + (string.IsNullOrEmpty(restOfArgs) ? "" : " " + restOfArgs);

            switch (subCommand)
            {
                case "FETCH":
                    HandleFetch(tag, convertedArgs);
                    break;
                case "STORE":
                    HandleStore(tag, convertedArgs);
                    break;
                case "SEARCH":
                    HandleSearch(tag, convertedArgs);
                    break;
                case "COPY":
                    HandleCopy(tag, convertedArgs);
                    break;
                default:
                    SendResponse(tag, $"BAD Unknown UID command: {subCommand}");
                    break;
            }
        }

        private const int MaxUidSetResults = 10000;

        private List<int> ParseUidSet(string uidSet)
        {
            List<int> sequences = new List<int>();

            foreach (string part in uidSet.Split(','))
            {
                if (sequences.Count >= MaxUidSetResults) break;

                if (part.Contains(':'))
                {
                    string[] range = part.Split(':');

                    uint startUid;
                    if (!uint.TryParse(range[0], out startUid))
                        continue;

                    uint endUid;
                    if (range[1] == "*") endUid = uint.MaxValue;
                    else if (!uint.TryParse(range[1], out endUid)) continue;

                    for (int i = 0; i < messageUids.Count && sequences.Count < MaxUidSetResults; i++)
                    {
                        uint uid = messageUids[i];
                        if (uid >= startUid && uid <= endUid)
                            sequences.Add(i + 1);
                    }
                }
                else
                {
                    if (part == "*")
                    {
                        if (messageUids.Count > 0)
                            sequences.Add(messageUids.Count);
                    }
                    else
                    {
                        uint uid;
                        if (!uint.TryParse(part, out uid))
                            continue;

                        for (int i = 0; i < messageUids.Count; i++)
                        {
                            if (messageUids[i] == uid)
                            {
                                sequences.Add(i + 1);
                                break;
                            }
                        }
                    }
                }
            }

            return sequences.Distinct().OrderBy(x => x).ToList();
        }

        private void HandleClose(string tag)
        {
            selectedMailbox = -1;
            messageUids.Clear();
            messageFlags.Clear();
            SendResponse(tag, "OK CLOSE completed");
        }

        private void HandleLogout(string tag)
        {
            writer.WriteLine("* BYE HTCommander IMAP Server logging out");
            SendResponse(tag, "OK LOGOUT completed");
            Close();
            throw new InvalidOperationException("Client requested LOGOUT");
        }

        private void InitializeMailboxState()
        {
            messageUids.Clear();
            messageFlags.Clear();

            List<WinLinkMail> mails = GetMailsInMailbox(selectedMailbox);
            for (int i = 0; i < mails.Count; i++)
            {
                int hash = mails[i].MID.GetHashCode();
                uint uid = (hash == int.MinValue) ? (uint)int.MaxValue : (uint)Math.Abs(hash);
                messageUids[i] = uid;
                messageFlags[i] = new HashSet<string>();

                if (uid >= uidNext && uid < uint.MaxValue)
                    uidNext = uid + 1;
            }
        }

        private List<WinLinkMail> GetMailsInMailbox(int mailboxIndex)
        {
            string folderName = mailboxToFolder.ContainsKey(mailboxIndex) ? mailboxToFolder[mailboxIndex] : "";
            return DataBroker.GetValue<List<WinLinkMail>>(1, "Mails", new List<WinLinkMail>()).Where(m => m.Mailbox == folderName).ToList();
        }

        // Sanitize RFC822 header values to prevent IMAP response injection via CRLF
        private static string SanitizeHeaderValue(string value)
        {
            if (string.IsNullOrEmpty(value)) return "";
            return value.Replace("\r", "").Replace("\n", "").Replace("\u2028", "").Replace("\u2029", "");
        }

        private string BuildRfc822Header(WinLinkMail mail)
        {
            StringBuilder sb = new StringBuilder();
            sb.AppendLine($"From: {SanitizeHeaderValue(mail.From)}");
            sb.AppendLine($"To: {SanitizeHeaderValue(mail.To)}");
            if (!string.IsNullOrEmpty(mail.Cc))
                sb.AppendLine($"Cc: {SanitizeHeaderValue(mail.Cc)}");
            sb.AppendLine($"Subject: {SanitizeHeaderValue(mail.Subject)}");
            sb.AppendLine($"Date: {mail.DateTime:R}");
            sb.AppendLine($"Message-ID: <{SanitizeHeaderValue(mail.MID)}@htcommander>");
            sb.AppendLine("MIME-Version: 1.0");
            sb.AppendLine("Content-Type: text/plain; charset=utf-8");
            sb.AppendLine();
            return sb.ToString();
        }

        private string BuildRfc822Message(WinLinkMail mail)
        {
            StringBuilder sb = new StringBuilder();
            sb.Append(BuildRfc822Header(mail));
            sb.AppendLine(mail.Body ?? "");
            return sb.ToString();
        }

        private string GetFlagsString(int index)
        {
            if (!messageFlags.ContainsKey(index) || messageFlags[index].Count == 0)
                return "";
            // Sanitize flags to prevent IMAP response injection via CRLF
            return SanitizeHeaderValue(string.Join(" ", messageFlags[index]));
        }

        private const int MaxSequenceSetResults = 10000;

        private List<int> ParseSequenceSet(string sequenceSet)
        {
            List<int> result = new List<int>();

            if (sequenceSet == "*")
            {
                List<WinLinkMail> mails = GetMailsInMailbox(selectedMailbox);
                for (int i = 1; i <= mails.Count && result.Count < MaxSequenceSetResults; i++)
                    result.Add(i);
                return result;
            }

            foreach (string part in sequenceSet.Split(','))
            {
                if (result.Count >= MaxSequenceSetResults) break;

                if (part.Contains(':'))
                {
                    string[] range = part.Split(':');
                    if (!int.TryParse(range[0], out int start)) continue;
                    int end;
                    if (range[1] == "*") end = GetMailsInMailbox(selectedMailbox).Count;
                    else if (!int.TryParse(range[1], out end)) continue;
                    // Cap range to prevent CPU DoS
                    if (end - start > MaxSequenceSetResults) end = start + MaxSequenceSetResults;
                    for (int i = start; i <= end && result.Count < MaxSequenceSetResults; i++)
                        result.Add(i);
                }
                else
                {
                    if (int.TryParse(part, out int seq))
                        result.Add(seq);
                }
            }

            return result.Distinct().OrderBy(x => x).ToList();
        }

        private string[] ParseImapString(string input)
        {
            List<string> result = new List<string>();
            bool inQuotes = false;
            StringBuilder current = new StringBuilder();

            for (int i = 0; i < input.Length; i++)
            {
                char c = input[i];

                if (c == '"')
                {
                    inQuotes = !inQuotes;
                }
                else if (c == ' ' && !inQuotes)
                {
                    if (current.Length > 0)
                    {
                        result.Add(current.ToString());
                        current.Clear();
                    }
                }
                else
                {
                    current.Append(c);
                }
            }

            if (current.Length > 0)
                result.Add(current.ToString());

            return result.ToArray();
        }

        private void SendResponse(string tag, string response)
        {
            // Sanitize tag and response to prevent IMAP response injection via CRLF and Unicode line separators
            string safeTag = tag.Replace("\r", "").Replace("\n", "").Replace("\u2028", "").Replace("\u2029", "").Replace("\0", "");
            string safeResponse = response.Replace("\r", "").Replace("\n", "").Replace("\u2028", "").Replace("\u2029", "").Replace("\0", "");
            string line = $"{safeTag} {safeResponse}";
            writer.WriteLine(line);
        }

        public void Close()
        {
            try
            {
                client?.Close();
            }
            catch { }
            server.RemoveSession(this);
        }
    }
}
