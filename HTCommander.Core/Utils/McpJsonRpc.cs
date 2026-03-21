/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

// MCP (Model Context Protocol) JSON-RPC 2.0 implementation
// Spec: https://spec.modelcontextprotocol.io/

using System;
using System.Collections.Generic;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace HTCommander
{
    /// <summary>
    /// JSON-RPC 2.0 request message.
    /// </summary>
    public class JsonRpcRequest
    {
        [JsonPropertyName("jsonrpc")]
        public string JsonRpc { get; set; }

        [JsonPropertyName("id")]
        public JsonElement? Id { get; set; }

        [JsonPropertyName("method")]
        public string Method { get; set; }

        [JsonPropertyName("params")]
        public JsonElement? Params { get; set; }
    }

    /// <summary>
    /// JSON-RPC 2.0 response message.
    /// </summary>
    public class JsonRpcResponse
    {
        [JsonPropertyName("jsonrpc")]
        public string JsonRpc { get; set; } = "2.0";

        [JsonPropertyName("id")]
        public JsonElement? Id { get; set; }

        [JsonPropertyName("result")]
        [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
        public object Result { get; set; }

        [JsonPropertyName("error")]
        [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
        public JsonRpcError Error { get; set; }
    }

    /// <summary>
    /// JSON-RPC 2.0 error object.
    /// </summary>
    public class JsonRpcError
    {
        [JsonPropertyName("code")]
        public int Code { get; set; }

        [JsonPropertyName("message")]
        public string Message { get; set; }

        [JsonPropertyName("data")]
        [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
        public object Data { get; set; }
    }

    /// <summary>
    /// MCP tool definition for tools/list response.
    /// </summary>
    public class McpToolDefinition
    {
        [JsonPropertyName("name")]
        public string Name { get; set; }

        [JsonPropertyName("description")]
        public string Description { get; set; }

        [JsonPropertyName("inputSchema")]
        public McpToolInputSchema InputSchema { get; set; }
    }

    /// <summary>
    /// JSON Schema for MCP tool input parameters.
    /// </summary>
    public class McpToolInputSchema
    {
        [JsonPropertyName("type")]
        public string Type { get; set; } = "object";

        [JsonPropertyName("properties")]
        [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
        public Dictionary<string, McpToolProperty> Properties { get; set; }

        [JsonPropertyName("required")]
        [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
        public List<string> Required { get; set; }
    }

    /// <summary>
    /// JSON Schema property definition for MCP tool parameters.
    /// </summary>
    public class McpToolProperty
    {
        [JsonPropertyName("type")]
        public string Type { get; set; }

        [JsonPropertyName("description")]
        [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
        public string Description { get; set; }

        [JsonPropertyName("enum")]
        [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
        public List<string> Enum { get; set; }

        [JsonPropertyName("minimum")]
        [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
        public int? Minimum { get; set; }

        [JsonPropertyName("maximum")]
        [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
        public int? Maximum { get; set; }

        [JsonPropertyName("default")]
        [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
        public object Default { get; set; }
    }

    /// <summary>
    /// MCP resource definition for resources/list response.
    /// </summary>
    public class McpResourceDefinition
    {
        [JsonPropertyName("uri")]
        public string Uri { get; set; }

        [JsonPropertyName("name")]
        public string Name { get; set; }

        [JsonPropertyName("description")]
        [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
        public string Description { get; set; }

        [JsonPropertyName("mimeType")]
        [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
        public string MimeType { get; set; }
    }

    /// <summary>
    /// MCP resource content returned by resources/read.
    /// </summary>
    public class McpResourceContent
    {
        [JsonPropertyName("uri")]
        public string Uri { get; set; }

        [JsonPropertyName("mimeType")]
        [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
        public string MimeType { get; set; }

        [JsonPropertyName("text")]
        [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
        public string Text { get; set; }
    }

    /// <summary>
    /// MCP content block returned by tools/call.
    /// </summary>
    public class McpToolContent
    {
        [JsonPropertyName("type")]
        public string Type { get; set; } = "text";

        [JsonPropertyName("text")]
        [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
        public string Text { get; set; }
    }

    /// <summary>
    /// MCP protocol dispatcher. Routes JSON-RPC requests to the appropriate handler.
    /// </summary>
    public class McpProtocolHandler
    {
        private readonly McpTools tools;
        private readonly McpResources resources;

        private static readonly JsonSerializerOptions jsonOptions = new JsonSerializerOptions
        {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
            DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
            WriteIndented = false
        };

        public McpProtocolHandler(McpTools tools, McpResources resources)
        {
            this.tools = tools;
            this.resources = resources;
        }

        /// <summary>
        /// Processes a JSON-RPC request string and returns a JSON-RPC response string.
        /// </summary>
        public string ProcessRequest(string requestJson)
        {
            JsonRpcRequest request;
            try
            {
                request = JsonSerializer.Deserialize<JsonRpcRequest>(requestJson);
                if (request == null || request.Method == null)
                {
                    return SerializeResponse(MakeError(null, -32600, "Invalid request"));
                }
            }
            catch (JsonException)
            {
                return SerializeResponse(MakeError(null, -32700, "Parse error"));
            }

            JsonRpcResponse response;
            try
            {
                response = HandleMethod(request);
            }
            catch (Exception)
            {
                response = MakeError(request.Id, -32603, "Internal error");
            }

            return SerializeResponse(response);
        }

        private JsonRpcResponse HandleMethod(JsonRpcRequest request)
        {
            switch (request.Method)
            {
                case "initialize":
                    return HandleInitialize(request);
                case "notifications/initialized":
                    return null; // Notification, no response needed
                case "ping":
                    return MakeResult(request.Id, new { });
                case "tools/list":
                    return HandleToolsList(request);
                case "tools/call":
                    return HandleToolsCall(request);
                case "resources/list":
                    return HandleResourcesList(request);
                case "resources/read":
                    return HandleResourcesRead(request);
                default:
                    return MakeError(request.Id, -32601, "Method not found: " + request.Method);
            }
        }

        private JsonRpcResponse HandleInitialize(JsonRpcRequest request)
        {
            var result = new
            {
                protocolVersion = "2024-11-05",
                capabilities = new
                {
                    tools = new { },
                    resources = new { }
                },
                serverInfo = new
                {
                    name = "htcommander",
                    version = "1.0.0"
                }
            };
            return MakeResult(request.Id, result);
        }

        private JsonRpcResponse HandleToolsList(JsonRpcRequest request)
        {
            var toolDefs = tools.GetToolDefinitions();
            return MakeResult(request.Id, new { tools = toolDefs });
        }

        private JsonRpcResponse HandleToolsCall(JsonRpcRequest request)
        {
            if (!request.Params.HasValue)
            {
                return MakeError(request.Id, -32602, "Missing params");
            }

            string toolName = null;
            JsonElement arguments = default;

            var paramsElem = request.Params.Value;
            if (paramsElem.TryGetProperty("name", out JsonElement nameElem))
            {
                toolName = nameElem.GetString();
            }
            if (paramsElem.TryGetProperty("arguments", out JsonElement argsElem))
            {
                arguments = argsElem;
            }

            if (string.IsNullOrEmpty(toolName))
            {
                return MakeError(request.Id, -32602, "Missing tool name");
            }

            var callResult = tools.CallTool(toolName, arguments);
            return MakeResult(request.Id, callResult);
        }

        private JsonRpcResponse HandleResourcesList(JsonRpcRequest request)
        {
            var resourceDefs = resources.GetResourceDefinitions();
            return MakeResult(request.Id, new { resources = resourceDefs });
        }

        private JsonRpcResponse HandleResourcesRead(JsonRpcRequest request)
        {
            if (!request.Params.HasValue)
            {
                return MakeError(request.Id, -32602, "Missing params");
            }

            string uri = null;
            var paramsElem = request.Params.Value;
            if (paramsElem.TryGetProperty("uri", out JsonElement uriElem))
            {
                uri = uriElem.GetString();
            }

            if (string.IsNullOrEmpty(uri))
            {
                return MakeError(request.Id, -32602, "Missing resource URI");
            }

            var readResult = resources.ReadResource(uri);
            return MakeResult(request.Id, readResult);
        }

        private JsonRpcResponse MakeResult(JsonElement? id, object result)
        {
            return new JsonRpcResponse { Id = id, Result = result };
        }

        private JsonRpcResponse MakeError(JsonElement? id, int code, string message)
        {
            return new JsonRpcResponse
            {
                Id = id,
                Error = new JsonRpcError { Code = code, Message = message }
            };
        }

        private string SerializeResponse(JsonRpcResponse response)
        {
            if (response == null) return null;
            return JsonSerializer.Serialize(response, jsonOptions);
        }
    }
}
