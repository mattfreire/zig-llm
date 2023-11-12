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

## Installation

Add it to your `build.zig.zon` file:

```
.{
    .name = "zig-example-use",
    .version = "0.0.1",
    .dependencies = .{
        .zig_llm = .{
            .url = "https://github.com/mattfreire/zig-llm/archive/refs/tags/v0.0.3.tar.gz",
            .hash = "1220145cd26ccbbf94dd8c23c4d66acc4fbf56cec2c876592000732ce6b7481278b9",
        },
    },
    .paths = .{""},
}
```

### Example Usage

Check the example folder for how to use ZigLLM.

## Todos
- Implement more endpoints from the OpenAI API
- Handle streaming responses
- Add support for other llms