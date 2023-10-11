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

pub const OpenAI = struct {
    base_url: []const u8 = "https://api.openai.com/v1",
    api_key: []const u8,
    organization_id: []const u8,
    alloc: Allocator,
    headers: std.http.Headers,

    pub fn init(alloc: Allocator, api_key: []const u8, organization_id: []const u8) !OpenAI {
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

    pub fn get_models(self: *OpenAI) !void {
        var client = std.http.Client{
            .allocator = self.alloc,
        };
        defer client.deinit();

        const uri = std.Uri.parse("https://api.openai.com/v1/models") catch unreachable;

        var req = try client.request(.GET, uri, self.headers, .{});
        defer req.deinit();

        try req.start();
        try req.wait();

        const body = req.reader().readAllAlloc(self.alloc, 3276800) catch unreachable;
        defer self.alloc.free(body);
    }

    pub fn completion(self: *OpenAI, model: []const u8, prompt: []const u8, max_tokens: u32, temperature: u8, verbose: bool) !Completion {
        var client = std.http.Client{
            .allocator = self.alloc,
        };
        defer client.deinit();

        const uri = std.Uri.parse("https://api.openai.com/v1/chat/completions") catch unreachable;

        var system_message = .{
            .role = "system",
            .content = "You are a helpful assistant",
        };

        var user_message = .{
            .role = "user",
            .content = prompt,
        };

        const messages = [2]Message{ system_message, user_message };

        var body_raw = .{ .max_tokens = max_tokens, .temperature = temperature, .model = model, .messages = messages };

        const body = try std.json.stringifyAlloc(self.alloc, body_raw, .{});
        defer self.alloc.free(body);

        var req = try client.request(.POST, uri, self.headers, .{});
        defer req.deinit();

        req.transfer_encoding = .chunked;

        try req.start();
        try req.writer().writeAll(body);
        try req.finish();
        try req.wait();

        const response = req.reader().readAllAlloc(self.alloc, 3276800) catch unreachable;
        if (verbose) {
            log.debug("Response: {s}\n", .{response});
        }
        // defer self.alloc.free(response);
        const parsed_completion = try std.json.parseFromSlice(Completion, self.alloc, response, .{});
        // defer config.deinit();
        return parsed_completion.value;
    }
};
