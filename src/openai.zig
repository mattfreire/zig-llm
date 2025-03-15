const std = @import("std");
const meta = @import("std").meta;
const log = std.log;

const Allocator = std.mem.Allocator;

pub const Usage = struct {
    prompt_tokens: u64,
    completion_tokens: ?u64,
    total_tokens: u64,
};

pub const Choice = struct {
    index: usize,
    finish_reason: ?[]const u8,
    message: struct { role: []const u8, content: []const u8, refusal: ?[]const u8 },
    logprobs: ?[]const u8 = null,
};

pub const Completion = struct {
    id: []const u8,
    object: []const u8,
    created: u64,
    model: []const u8,
    choices: []Choice,
    // Usage is not returned by the Completion endpoint when streamed.
    usage: Usage,
    system_fingerprint: ?[]const u8,
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

pub const CompletionPayload = struct {
    model: []const u8,
    messages: []Message,
    max_tokens: ?u32,
    temperature: ?u8,
};

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

pub const OPENAI_BASE_URL = "https://api.openai.com/v1";
pub const XAI_BASE_URL = "https://api.x.ai/v1";

pub fn OpenAI(base_url: []const u8) type {
    return struct {
        api_key: []const u8,
        alloc: Allocator,
        arena: *std.heap.ArenaAllocator,
        headers: std.http.Client.Request.Headers,
        const Self = @This();

        pub fn init(alloc: Allocator, api_key: []const u8) !Self {
            var arena = try alloc.create(std.heap.ArenaAllocator);
            arena.* = std.heap.ArenaAllocator.init(alloc);
            const headers = try get_headers(arena.allocator(), api_key);
            return Self{
                .alloc = arena.allocator(),
                .api_key = api_key,
                .headers = headers,
                .arena = arena,
            };
        }

        pub fn deinit(self: *Self) void {
            const alloc = self.arena.child_allocator;
            self.arena.deinit();
            alloc.destroy(self.arena);
        }

        fn get_headers(alloc: std.mem.Allocator, api_key: []const u8) !std.http.Client.Request.Headers {
            const auth_header = try std.fmt.allocPrint(alloc, "Bearer {s}", .{api_key});
            //defer alloc.free(auth_header);
            const headers = std.http.Client.Request.Headers{
                .content_type = std.http.Client.Request.Headers.Value{
                    .override = "application/json",
                },
                .authorization = std.http.Client.Request.Headers.Value{
                    .override = auth_header,
                },
            };
            return headers;
        }

        pub fn get_models(self: *Self) anyerror![]Model {
            var client = std.http.Client{
                .allocator = self.alloc,
            };
            defer client.deinit();

            const uri = std.Uri.parse(base_url ++ "/models") catch unreachable;

            const server_header_buffer: []u8 = try self.alloc.alloc(u8, 8 * 1024 * 4);
            defer self.alloc.free(server_header_buffer);
            var req = try client.open(.GET, uri, std.http.Client.RequestOptions{
                .server_header_buffer = server_header_buffer,
                .headers = self.headers,
            });
            defer req.deinit();

            try req.send();
            try req.wait();

            const status = req.response.status;

            if (status != .ok) {
                return getError(status);
            }

            const response = req.reader().readAllAlloc(self.alloc, 3276800) catch unreachable;

            const parsed_models = try std.json.parseFromSlice(ModelResponse, self.alloc, response, .{});

            // TODO return this as a slice
            return parsed_models.value.data;
        }

        pub fn completion(self: *Self, payload: CompletionPayload, verbose: ?bool) !Completion {
            var client = std.http.Client{
                .allocator = self.alloc,
            };
            defer client.deinit();

            const uri = std.Uri.parse(base_url ++ "/chat/completions") catch unreachable;

            const body = try std.json.stringifyAlloc(self.alloc, payload, .{});

            std.debug.print("text: \n{s}\n", .{body});
            defer self.alloc.free(body);

            const server_header_buffer: []u8 = try self.alloc.alloc(u8, 8 * 1024 * 4);
            var req = try client.open(.POST, uri, std.http.Client.RequestOptions{
                .server_header_buffer = server_header_buffer,
                .headers = self.headers,
            });
            defer req.deinit();

            req.transfer_encoding = .chunked;

            try req.send();
            try req.writer().writeAll(body);
            try req.finish();
            try req.wait();

            const status = req.response.status;

            if (status != .ok) {
                return getError(status);
            }

            const response = req.reader().readAllAlloc(self.alloc, 3276800) catch unreachable;

            std.debug.print("text: \n{s}\n", .{response});

            if (verbose.?) {
                log.debug("Response: {s}\n", .{response});
            }
            defer self.alloc.free(response);

            const parsed_completion = try std.json.parseFromSlice(Completion, self.alloc, response, .{ .ignore_unknown_fields = true });

            return parsed_completion.value;
        }
    };
}

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

    var openai = try OpenAI(OPENAI_BASE_URL).init(alloc, api_key.?);
    defer openai.deinit();

    const models = try openai.get_models();

    try std.testing.expect(models.len > 0);
}

test "completion" {
    const alloc = std.testing.allocator;
    var env = try std.process.getEnvMap(alloc);
    defer env.deinit();

    const api_key = env.get("OPENAI_API_KEY");

    var openai = try OpenAI(OPENAI_BASE_URL).init(alloc, api_key.?);
    defer openai.deinit();

    const system_message = .{
        .role = "system",
        .content = "You are a helpful assistant",
    };

    const user_message = .{
        .role = "user",
        .content = "Write a 1 line haiku",
    };

    var messages = [2]Message{ system_message, user_message };

    const payload = CompletionPayload{
        .model = "gpt-3.5-turbo",
        .messages = &messages,
        .max_tokens = 64,
        .temperature = 0,
    };
    const completion = try openai.completion(payload, false);

    try std.testing.expect(completion.choices.len > 0);
}
