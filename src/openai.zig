const std = @import("std");
const meta = @import("std").meta;
const log = std.log;

const Allocator = std.mem.Allocator;

pub const Usage = struct {
    prompt_tokens: u64,
    completion_tokens: ?u64,
    total_tokens: u64,
};

pub const Choice = struct { index: usize, finish_reason: ?[]const u8, message: struct { role: []const u8, content: []const u8 } };

pub const Completion = struct {
    id: []const u8,
    object: []const u8,
    created: u64,
    model: []const u8,
    choices: []Choice,
    // Usage is not returned by the Completion endpoint when streamed.
    usage: Usage,
};

pub const Message = struct {
    role: []const u8,
    content: []const u8,
};

pub const Model = struct {
    id: []const u8,
    object: []const u8,
    created: u64,
    owned_by: []const u8,
};

pub const ModelResponse = struct {
    object: []const u8,
    data: []Model,
};

pub const CompletionPayload = struct { model: []const u8, messages: []Message, max_tokens: ?u32, temperature: ?u8 };

const OpenAIError = error{
    BAD_REQUEST,
    UNAUTHORIZED,
    FORBIDDEN,
    NOT_FOUND,
    TOO_MANY_REQUESTS,
    INTERNAL_SERVER_ERROR,
    SERVICE_UNAVAILABLE,
    GATEWAY_TIMEOUT,
    UNKNOWN,
};

fn getError(status: std.http.Status) OpenAIError {
    const result = switch (status) {
        .bad_request => OpenAIError.BAD_REQUEST,
        .unauthorized => OpenAIError.UNAUTHORIZED,
        .forbidden => OpenAIError.FORBIDDEN,
        .not_found => OpenAIError.NOT_FOUND,
        .too_many_requests => OpenAIError.TOO_MANY_REQUESTS,
        .internal_server_error => OpenAIError.INTERNAL_SERVER_ERROR,
        .service_unavailable => OpenAIError.SERVICE_UNAVAILABLE,
        .gateway_timeout => OpenAIError.GATEWAY_TIMEOUT,
        else => OpenAIError.UNKNOWN,
    };
    return result;
}

pub const OpenAI = struct {
    base_url: []const u8 = "https://api.openai.com/v1",
    api_key: []const u8,
    organization_id: ?[]const u8,
    alloc: Allocator,
    headers: std.http.Headers,

    pub fn init(alloc: Allocator, api_key: []const u8, organization_id: ?[]const u8) !OpenAI {
        const headers = try get_headers(alloc, api_key);
        return OpenAI{ .alloc = alloc, .api_key = api_key, .organization_id = organization_id, .headers = headers };
    }

    pub fn deinit(self: *OpenAI) void {
        self.headers.deinit();
    }

    fn get_headers(alloc: std.mem.Allocator, api_key: []const u8) !std.http.Headers {
        var headers = std.http.Headers.init(alloc);
        try headers.append("Content-Type", "application/json");
        var auth_header = try std.fmt.allocPrint(alloc, "Bearer {s}", .{api_key});
        defer alloc.free(auth_header);
        try headers.append("Authorization", auth_header);
        return headers;
    }

    pub fn get_models(self: *OpenAI) anyerror![]Model {
        var client = std.http.Client{
            .allocator = self.alloc,
        };
        defer client.deinit();

        const uri = std.Uri.parse("https://api.openai.com/v1/models") catch unreachable;

        var req = try client.request(.GET, uri, self.headers, .{});
        defer req.deinit();

        try req.start();
        try req.wait();

        const status = req.response.status;

        if (status != .ok) {
            return getError(status);
        }

        const response = req.reader().readAllAlloc(self.alloc, 3276800) catch unreachable;
        defer self.alloc.free(response);

        const parsed_models = try std.json.parseFromSlice(ModelResponse, self.alloc, response, .{});
        defer parsed_models.deinit();

        // TODO return this as a slice
        return parsed_models.value.data;
    }

    pub fn completion(self: *OpenAI, payload: CompletionPayload, verbose: ?bool) !Completion {
        var client = std.http.Client{
            .allocator = self.alloc,
        };
        defer client.deinit();

        const uri = std.Uri.parse("https://api.openai.com/v1/chat/completions") catch unreachable;

        const body = try std.json.stringifyAlloc(self.alloc, payload, .{});
        defer self.alloc.free(body);

        var req = try client.request(.POST, uri, self.headers, .{});
        defer req.deinit();

        req.transfer_encoding = .chunked;

        try req.start();
        try req.writer().writeAll(body);
        try req.finish();
        try req.wait();

        const status = req.response.status;

        if (status != .ok) {
            return getError(status);
        }

        const response = req.reader().readAllAlloc(self.alloc, 3276800) catch unreachable;
        if (verbose.?) {
            log.debug("Response: {s}\n", .{response});
        }
        defer self.alloc.free(response);

        const parsed_completion = try std.json.parseFromSlice(Completion, self.alloc, response, .{});
        defer parsed_completion.deinit();

        return parsed_completion.value;
    }
};

test "unauthorized api key" {
    const alloc = std.testing.allocator;

    const api_key = "sk-1234567890";

    var openai = try OpenAI.init(alloc, api_key, null);
    defer openai.deinit();

    const models = openai.get_models();

    try std.testing.expectEqual(models, OpenAIError.UNAUTHORIZED);
}

test "get models" {
    const alloc = std.testing.allocator;
    var env = try std.process.getEnvMap(alloc);
    defer env.deinit();

    const api_key = env.get("OPENAI_API_KEY");

    var openai = try OpenAI.init(alloc, api_key.?, null);
    defer openai.deinit();

    const models = try openai.get_models();

    try std.testing.expect(models.len > 0);
}

test "completion" {
    const alloc = std.testing.allocator;
    var env = try std.process.getEnvMap(alloc);
    defer env.deinit();

    const api_key = env.get("OPENAI_API_KEY");

    var openai = try OpenAI.init(alloc, api_key.?, null);
    defer openai.deinit();

    var system_message = .{
        .role = "system",
        .content = "You are a helpful assistant",
    };

    var user_message = .{
        .role = "user",
        .content = "Write a 1 line haiku",
    };

    var messages = [2]Message{ system_message, user_message };

    var payload = CompletionPayload{
        .model = "gpt-3.5-turbo",
        .messages = &messages,
        .max_tokens = 64,
        .temperature = 0,
    };
    const completion = try openai.completion(payload, false);

    try std.testing.expect(completion.choices.len > 0);
}
