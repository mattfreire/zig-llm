const std = @import("std");
const llm = @import("src/main.zig");
const exit = std.os.exit;

pub fn main() !void {
    const alloc = std.heap.page_allocator;
    const env = try std.process.getEnvMap(alloc);

    const api_key = env.get("OPENAI_API_KEY");
    const organization_id = env.get("OPENAI_ORGANIZATION_ID");

    if (api_key == null or organization_id == null) {
        std.log.info("Please set your API key and Organization ID\n", .{});
        exit(1);
    }

    var openai = try llm.OpenAI.init(alloc, api_key.?, organization_id.?);
    defer openai.deinit();

    const models = try openai.get_models();
    std.debug.print("{}", .{models});

    const completion = try openai.completion("gpt-4", "Write a poem", 30, 1, false);
    for (completion.choices) |choice| {
        std.debug.print("Choice:\n {s}", .{choice.message.content});
    }
}
