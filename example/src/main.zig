const std = @import("std");
const llm = @import("zig-llm");
const exit = std.process.exit;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();
    var env = try std.process.getEnvMap(alloc);
    defer env.deinit();

    const api_key = env.get("OPENAI_API_KEY");

    if (api_key == null) {
        std.log.info("Please set your API key and Organization ID \n", .{});
        exit(2);
    }

    var openai = try llm.OpenAI(llm.OPENAI_BASE_URL).init(alloc, api_key);
    defer openai.deinit();

    const models = try openai.get_models();
    std.debug.print("Models: ", .{});
    for (models) |m| {
        std.debug.print("{s} ", .{m.id});
    }
    std.debug.print("\n", .{});

    const system_message = .{
        .role = "system",
        .content = "You are a helpful assistant",
    };

    const user_message = .{
        .role = "user",
        .content = "what is 2 + 2",
    };

    var messages = [2]llm.Message{ system_message, user_message };

    const payload = llm.CompletionPayload{
        .model = "grok-2-latest",
        .messages = &messages,
        .max_tokens = 64,
        .temperature = 0,
    };
    const completion = try openai.completion(payload, false);
    for (completion.choices) |choice| {
        std.debug.print("Choice:\n {s}", .{choice.message.content});
    }
    std.debug.print("\n", .{});
}
