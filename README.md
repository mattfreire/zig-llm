<h1 align="center">ZigLLM</h1>
<p align="center">
    <a href="LICENSE"><img src="https://badgen.net/github/license/mattfreire/zig-llm" /></a>
    <a href="https://twitter.com/mattfreire"><img src="https://badgen.net/badge/twitter/@mattfreire/1DA1F2?icon&label" /></a>
</p>

<p align="center">
    ZigLLM is a wrapper around LLM APIs such as OpenAI.
</p>

## Simple and easy to use

ZigLLM aims to provide simple interfaces for common LLM APIs. For example, here's how you can use the OpenAI API:

```zig
const std = @import("std");
const openai = @import("llm/openai.zig");
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

    var llm = try openai.OpenAI.init(alloc, api_key.?, organization_id.?);
    defer llm.deinit();

    const models = try llm.get_models();
    std.debug.print("{}", .{models});

    const completion = try llm.completion("gpt-4", "Write a poem", 30, 1, false);
    for (completion.choices) |choice| {
        std.debug.print("Choice:\n {s}", .{choice.message.content});
    }
}
```

## OpenAI Todos
- Implement more endpoints from the OpenAI API
- Handle streaming responses
- Abstract system messages so they can be passed in
- Write tests