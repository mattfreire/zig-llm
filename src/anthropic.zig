const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log;

pub const Usage = struct {
    input_tokens: u64,
    output_tokens: u64,
};

const MessageRole = enum {
    assistant,
    user,
};

pub const Message = struct {
    role: []const u8,
    content: []const u8,
};

pub const Model = struct {
    id: []const u8,
};

pub const Content = struct {
    type: []const u8,
    text: []const u8,
};

pub const CompletionPayload = struct {
    model: []const u8,
    messages: []Message,
    max_tokens: u32,
    // stop_sequences: ?[]const u8,
    // stream: ?bool,
    // system: ?[]const u8 = undefined,
    // temperature: ?u8 = undefined,
};

pub const Completion = struct {
    id: []const u8,
    type: []const u8,
    role: []const u8,
    model: []const u8,
    content: []Content,
    stop_reason: []const u8,
    stop_sequence: ?[]const u8,
    usage: Usage,
};

const APIResponseError = struct {
    type: []const u8, // e.g. invalid_request_error
    message: []const u8,
};

const APIResponse = struct {
    // fields from Completion - FIXME: how to reuse the Completion struct?
    id: ?[]const u8,
    type: ?[]const u8,
    role: ?[]const u8,
    model: ?[]const u8,
    content: ?Content,
    stop_reason: ?[]const u8,
    stop_sequence: ?[]const u8,
    usage: ?Usage,
};

const AnthropicError = error{
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

const ErrorResponse = struct {
    type: AnthropicError,
    message: []const u8,
};

const CompletionError = error{
    NetworkError,
    InvalidRequest,
    OutOfMemory,
};

fn getError(status: std.http.Status) AnthropicError {
    log.debug("status: {}\n", .{status});
    const result = switch (status) {
        .bad_request => AnthropicError.BAD_REQUEST,
        .unauthorized => AnthropicError.UNAUTHORIZED,
        .forbidden => AnthropicError.FORBIDDEN,
        .not_found => AnthropicError.NOT_FOUND,
        .too_many_requests => AnthropicError.TOO_MANY_REQUESTS,
        .internal_server_error => AnthropicError.INTERNAL_SERVER_ERROR,
        .service_unavailable => AnthropicError.SERVICE_UNAVAILABLE,
        .gateway_timeout => AnthropicError.GATEWAY_TIMEOUT,
        else => AnthropicError.UNKNOWN,
    };
    return result;
}

pub const Anthropic = struct {
    base_url: []const u8 = "https://api.anthropic.com/v1/messages",
    api_key: []const u8,
    alloc: Allocator,
    arena: *std.heap.ArenaAllocator,
    headers: std.http.Client.Request.Headers,

    pub fn init(alloc: Allocator, api_key: []const u8) !Anthropic {
        var arena = try alloc.create(std.heap.ArenaAllocator);
        arena.* = std.heap.ArenaAllocator.init(alloc);
        const headers = std.http.Client.Request.Headers{
            .content_type = std.http.Client.Request.Headers.Value{
                .override = "application/json",
            },
        };
        return Anthropic{ .alloc = arena.allocator(), .api_key = api_key, .headers = headers, .arena = arena };
    }

    pub fn deinit(self: *Anthropic) void {
        const alloc = self.arena.child_allocator;
        self.arena.deinit();
        alloc.destroy(self.arena);
    }

    pub fn completion(self: *Anthropic, payload: CompletionPayload, verbose: ?bool) !Completion {
        var client = std.http.Client{
            .allocator = self.alloc,
        };
        defer client.deinit();

        const uri = std.Uri.parse("https://api.anthropic.com/v1/messages") catch unreachable;

        const body = try std.json.stringifyAlloc(self.alloc, payload, .{});
        defer self.alloc.free(body);

        const server_header_buffer: []u8 = try self.alloc.alloc(u8, 8 * 1024 * 4);
        const extra_headers = [2]std.http.Header{
            .{ .name = "x-api-key", .value = self.api_key },
            .{ .name = "anthropic-version", .value = "2023-06-01" },
        };
        var req = try client.open(.POST, uri, std.http.Client.RequestOptions{
            .server_header_buffer = server_header_buffer,
            .headers = self.headers,
            .extra_headers = &extra_headers,
        });
        defer req.deinit();

        req.transfer_encoding = .chunked;

        try req.send();
        try req.writer().writeAll(body);
        try req.finish();
        try req.wait();

        const status = req.response.status;
        std.debug.print("status: {}\n", .{status});

        const response = req.reader().readAllAlloc(self.alloc, 3276800) catch unreachable;
        defer self.alloc.free(response);

        if (verbose.?) {
            log.info("Response: {any}\n", .{response});
        }

        if (status != .ok) {
            // FIXME: handle parsing error response message
            // response: {"type":"error","error":{"type":"invalid_request_error","message":"messages: Unexpected role \"system\". The Messages API accepts a top-level `system` parameter, not \"system\" as an input message role."}}
            const err = getError(status);
            const err_parsed = try std.json.parseFromSlice(APIResponseError, self.alloc, response, .{ .ignore_unknown_fields = true });
            // defer self.alloc.free(err_parsed);
            log.warn("error: {any} and error type: {any}\n", .{ err_parsed, err });
            // const errResponse = ErrorResponse{ .type = err, .message = err_parsed.value.message };
            return CompletionError.InvalidRequest;
        }

        const parsed_completion = try std.json.parseFromSlice(Completion, self.alloc, response, .{ .ignore_unknown_fields = true });
        return parsed_completion.value;
    }
};

test "completion" {
    const alloc = std.testing.allocator;

    var env = try std.process.getEnvMap(alloc);
    defer env.deinit();

    const api_key = env.get("ANTHROPIC_API_KEY");
    try std.testing.expect(api_key != null);

    var anthropic = try Anthropic.init(alloc, api_key.?);
    defer anthropic.deinit();

    var messages = [2]Message{ .{
        .role = "assistant",
        .content = "You are a helpful assistant",
    }, .{
        .role = "user",
        .content = "Write a 1 line haiku",
    } };

    const payload = CompletionPayload{
        .model = "claude-3-5-sonnet-20241022",
        .messages = &messages,
        .max_tokens = 64,
        // .temperature = 0,
    };
    const completion = try anthropic.completion(payload, true);

    try std.testing.expect(completion.content.len > 0);
    try std.testing.expect(completion.usage.input_tokens > 0);
    try std.testing.expect(completion.usage.output_tokens > 0);
}
