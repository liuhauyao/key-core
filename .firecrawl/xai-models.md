#### [Key Information](https://docs.x.ai/developers/models\#key-information)

# [Models and Pricing](https://docs.x.ai/developers/models\#models-and-pricing)

Copy for LLM [View as Markdown](https://docs.x.ai/developers/models.md)

An overview of our models' capabilities and their associated pricing.

## Grok 4.20

Grok 4.20 is our newest flagship model with industry-leading speed and agentic tool calling capabilities. It combines the lowest hallucination rate on the market with strict prompt adherance, delivering consistently precise and truthful responses.

Modalities

Context window

2,000,000

Features

Function calling

Structured outputs

Reasoning

Lightning fast

![Grok 4.20](https://docs.x.ai/_next/image?url=https%3A%2F%2Fdata.x.ai%2Fgrok-4.1-alt.webp&w=3840&q=75)

## [Model Pricing](https://docs.x.ai/developers/models\#model-pricing)

[How to increase my rate limits?](https://console.x.ai/team/default/rate-limits)

| Model | Modalities | Capabilities | Context | Rate limits | Pricing |
| --- | --- | --- | --- | --- | --- |
|  |
| Language models |  | Per million tokens |
| [grok-4.20-0309-reasoning](https://docs.x.ai/models/grok-4.20-0309-reasoning?cluster=eu-west-1) |  |  | 2,000,000 | 4Mtpm<br>607rpm | $2.00$6.00 |
| [grok-4.20-0309-non-reasoning](https://docs.x.ai/models/grok-4.20-0309-non-reasoning?cluster=eu-west-1) |  |  | 2,000,000 | 4Mtpm<br>607rpm | $2.00$6.00 |
| [grok-4.20-multi-agent-0309](https://docs.x.ai/models/grok-4.20-multi-agent-0309?cluster=eu-west-1) |  |  | 2,000,000 | 4Mtpm<br>607rpm | $2.00$6.00 |
| [grok-4-1-fast-reasoning](https://docs.x.ai/models/grok-4-1-fast-reasoning?cluster=eu-west-1) |  |  | 2,000,000 | 4Mtpm<br>607rpm | $0.20$0.50 |
| [grok-4-1-fast-non-reasoning](https://docs.x.ai/models/grok-4-1-fast-non-reasoning?cluster=eu-west-1) |  |  | 2,000,000 | 4Mtpm<br>607rpm | $0.20$0.50 |
| Image generation models |  | Per image output |
| [grok-imagine-image-pro](https://docs.x.ai/models/grok-imagine-image-pro?cluster=eu-west-1) |  |  |  | 30rpm<br>1rps | $0.07 |
| [grok-imagine-image](https://docs.x.ai/models/grok-imagine-image?cluster=eu-west-1) |  |  |  | 300rpm<br>5rps | $0.02 |
| Video generation models |  | Per second |
| [grok-imagine-video](https://docs.x.ai/models/grok-imagine-video?cluster=eu-west-1) |  |  |  | 60rpm<br>1rps | $0.05 |
| Voice & Audio |  |  |
| [Voice Agent API](https://docs.x.ai/developers/models/voice-agent-api) |  |  |  | 100cst | $0.05/ min ($3.00 / hr) |
| [Text to Speech](https://docs.x.ai/developers/models/text-to-speech) |  |  |  | 600rpm<br>10rps | $4.20/ 1M characters |

**Grok 4 Information for Grok 3 Users**

When moving from `grok-3`/`grok-3-mini` to `grok-4`, please note the following differences:

- Grok 4 is a reasoning model. There is no non-reasoning mode when using Grok 4.
- `presencePenalty`, `frequencyPenalty` and `stop` parameters are not supported by reasoning models. Adding them in the request would result in an error.
- Grok 4 does not have a `reasoning_effort` parameter. If a `reasoning_effort` is provided, the request will return an error.

**Grok 4.20 Information**

Grok 4.20 models do not support the `logprobs` field. If you specify `logprobs` in your request, it will be ignored.

* * *

## [Tools Pricing](https://docs.x.ai/developers/models\#tools-pricing)

Requests which make use of xAI provided [server-side tools](https://docs.x.ai/developers/tools/overview) are priced based on two components: **token usage** and **server-side tool invocations**. Since the agent autonomously decides how many tools to call, costs scale with query complexity.

### [Token Costs](https://docs.x.ai/developers/models\#token-costs)

All standard token types are billed at the [rate](https://docs.x.ai/developers/models#model-pricing) for the model used in the request:

- **Input tokens**: Your query and conversation history
- **Reasoning tokens**: Agent's internal thinking and planning
- **Completion tokens**: The final response
- **Image tokens**: Visual content analysis (when applicable)
- **Cached prompt tokens**: Prompt tokens that were served from cache rather than recomputed

### [Tool Invocation Costs](https://docs.x.ai/developers/models\#tool-invocation-costs)

| Tool | Description | Cost / 1k Calls | Tool Name |
| --- | --- | --- | --- |
| [Web Search](https://docs.x.ai/developers/tools/web-search) | Search the internet and browse web pages | $5 / 1k calls | `web_search` |
| [X Search](https://docs.x.ai/developers/tools/x-search) | Search X posts, user profiles, and threads | $5 / 1k calls | `x_search` |
| [Code Execution](https://docs.x.ai/developers/tools/code-execution) | Run Python code in a sandboxed environment | $5 / 1k calls | `code_execution``code_interpreter` |
| [File Attachments](https://docs.x.ai/developers/files) | Search through files attached to messages | $10 / 1k calls | `attachment_search` |
| [Collections Search](https://docs.x.ai/developers/tools/collections-search) | Query your uploaded document collections (RAG) | $2.50 / 1k calls | `collections_search``file_search` |
| [Image Understanding](https://docs.x.ai/developers/tools/web-search#enable-image-understanding) | Analyze images found during Web Search and X Search\* | Token-based | `view_image` |
| [X Video Understanding](https://docs.x.ai/developers/tools/x-search#enable-video-understanding) | Analyze videos found during X Search\* | Token-based | `view_x_video` |
| [Remote MCP Tools](https://docs.x.ai/developers/tools/remote-mcp) | Connect and use custom MCP tool servers | Token-based | Tool name is set by each MCP server |

[Web Search](https://docs.x.ai/developers/tools/web-search) $5 / 1k calls

Search the internet and browse web pages

`web_search`

[X Search](https://docs.x.ai/developers/tools/x-search) $5 / 1k calls

Search X posts, user profiles, and threads

`x_search`

[Code Execution](https://docs.x.ai/developers/tools/code-execution) $5 / 1k calls

Run Python code in a sandboxed environment

`code_execution``code_interpreter`

[File Attachments](https://docs.x.ai/developers/files) $10 / 1k calls

Search through files attached to messages

`attachment_search`

[Collections Search](https://docs.x.ai/developers/tools/collections-search) $2.50 / 1k calls

Query your uploaded document collections (RAG)

`collections_search``file_search`

[Image Understanding](https://docs.x.ai/developers/tools/web-search#enable-image-understanding) Token-based

Analyze images found during Web Search and X Search\*

`view_image`

[X Video Understanding](https://docs.x.ai/developers/tools/x-search#enable-video-understanding) Token-based

Analyze videos found during X Search\*

`view_x_video`

[Remote MCP Tools](https://docs.x.ai/developers/tools/remote-mcp) Token-based

Connect and use custom MCP tool servers

Tool name is set by each MCP server

All tool names work in the Responses API. In the gRPC API (Python xAI SDK), `code_interpreter` and `file_search` are not supported.

\\* Only applies to images and videos found by search tools — not to images passed directly in messages.

For the view image and view x video tools, you will not be charged for the tool invocation itself but will be charged for the image tokens used to process the image or video.

For Remote MCP tools, you will not be charged for the tool invocation but will be charged for any tokens used.

For more information on using Tools, please visit [our guide on Tools](https://docs.x.ai/developers/tools/overview).

* * *

## [Batch API Pricing](https://docs.x.ai/developers/models\#batch-api-pricing)

The [Batch API](https://docs.x.ai/developers/advanced-api-usage/batch-api) lets you process large volumes of requests asynchronously at **50% of standard pricing** — effectively cutting your token costs in half. Batch requests are queued and processed in the background, with most completing within 24 hours.

|  | Real-time API | Batch API |
| --- | --- | --- |
| **Token pricing** | Standard rates | **50% off** standard rates |
| **Response time** | Immediate (seconds) | Typically within 24 hours |
| **Rate limits** | Per-minute limits apply | Requests don't count towards rate limits |

The 50% discount applies to all token types — input tokens, output tokens, cached tokens, and reasoning tokens. To see batch pricing for a specific model, visit the model's detail page and toggle **"Show batch API pricing"**.

The 50% batch discount applies to text and language models only. Image and video generation are supported in the Batch API but are billed at standard rates. See [Batch API documentation](https://docs.x.ai/developers/advanced-api-usage/batch-api) for full details.

* * *

## [Voice API Pricing](https://docs.x.ai/developers/models\#voice-api-pricing)

### [Voice Agent API (Realtime)](https://docs.x.ai/developers/models\#voice-agent-api-realtime)

The [Voice Agent API](https://docs.x.ai/developers/model-capabilities/audio/voice-agent) enables real-time voice conversations over WebSocket, billed at a flat rate per minute of connection time.

|  | Details |
| --- | --- |
| **Pricing** | $0.05 / minute ($3.00 / hour) |
| **Concurrent sessions** | 100 per team |
| **Max session duration** | 30 minutes |
| **Capabilities** | Function calling (web search, X search, collections, MCP, custom functions) |

When using the Voice Agent API with tools such as function calling, web search, X search, collections, or MCP, you will be charged for the tool invocations in addition to the per-minute voice session cost. See [Tool Invocation Costs](https://docs.x.ai/developers/models#tool-invocation-costs) above for tool pricing details.

For more details on how to get started, see the [Voice Agent API documentation](https://docs.x.ai/developers/model-capabilities/audio/voice-agent).

### [Text to Speech API](https://docs.x.ai/developers/models\#text-to-speech-api)

The [Text to Speech API](https://docs.x.ai/developers/model-capabilities/audio/text-to-speech) converts text into natural speech, billed per input character.

|  | Details |
| --- | --- |
| **Pricing** | $4.20 / 1M characters |
| **Concurrent requests** | 100 per team |
| **Capabilities** | Multiple voices, streaming and batch output, MP3 / WAV / PCM / μ-law / A-law formats |

* * *

## [Usage Guidelines Violation Fee](https://docs.x.ai/developers/models\#usage-guidelines-violation-fee)

When your request is deemed to be in violation of our usage guideline by our system, we will still charge for the generation of the request.

For violations that are caught before generation in the Responses API, we will charge a $0.05 usage guideline violation fee per request.

* * *

## [Additional Information Regarding Models](https://docs.x.ai/developers/models\#additional-information-regarding-models)

- **No access to realtime events without search tools enabled**
  - Grok has no knowledge of current events or data beyond what was present in its training data.
  - To incorporate realtime data with your request, enable server-side search tools (Web Search / X Search). See [Web Search](https://docs.x.ai/developers/tools/web-search) and [X Search](https://docs.x.ai/developers/tools/x-search).
- **Chat models**
  - No role order limitation: You can mix `system`, `user`, or `assistant` roles in any sequence for your conversation context.
- **Image input models**
  - Maximum image size: `20MiB`
  - Maximum number of images: No limit
  - Supported image file types: `jpg/jpeg` or `png`.
  - Any image/text input order is accepted (e.g. text prompt can precede image prompt)

The knowledge cut-off date of Grok 3 and Grok 4 is November, 2024.

* * *

## [Model Aliases](https://docs.x.ai/developers/models\#model-aliases)

Some models have aliases to help users automatically migrate to the next version of the same model. In general:

- `<modelname>` is aliased to the latest stable version.
- `<modelname>-latest` is aliased to the latest version. This is suitable for users who want to access the latest features.
- `<modelname>-<date>` refers directly to a specific model release. This will not be updated and is for workflows that demand consistency.

For most users, the aliased `<modelname>` or `<modelname>-latest` are recommended, as you would receive the latest features automatically.

* * *

## [Billing and Availability](https://docs.x.ai/developers/models\#billing-and-availability)

Your model access might vary depending on various factors such as geographical location, account limitations, etc.

For how the **bills are charged**, visit [Manage Billing](https://docs.x.ai/console/billing) for more information.

For the most up-to-date information on **your team's model availability**, visit [Models Page](https://console.x.ai/team/default/models) on xAI Console.

* * *

## [Model Input and Output](https://docs.x.ai/developers/models\#model-input-and-output)

Each model can have one or multiple input and output capabilities.
The input capabilities refer to which type(s) of prompt can the model accept in the request message body.
The output capabilities refer to which type(s) of completion will the model generate in the response message body.

This is a prompt example for models with `text` input capability:

JSON

```
[\
  {\
    "role": "system",\
    "content": "You are Grok, a chatbot inspired by the Hitchhiker's Guide to the Galaxy."\
  },\
  {\
    "role": "user",\
    "content": "What is the meaning of life, the universe, and everything?"\
  }\
]
```

This is a prompt example for models with `text` and `image` input capabilities:

JSON

```
[\
  {\
    "role": "user",\
    "content": [\
      {\
        "type": "image_url",\
        "image_url": {\
          "url": "data:image/jpeg;base64,<base64_image_string>",\
          "detail": "high"\
        }\
      },\
      {\
        "type": "text",\
        "text": "Describe what's in this image."\
      }\
    ]\
  }\
]
```

This is a prompt example for models with `text` input and `image` output capabilities:

JSON

```
// The entire request body
{
  "model": "grok-4",
  "prompt": "A cat in a tree",
  "n": 4
}
```

* * *

## [Context Window](https://docs.x.ai/developers/models\#context-window)

The context window determines the maximum amount of tokens accepted by the model in the prompt.

_For more information on how token is counted, visit [Consumption and Rate Limits](https://docs.x.ai/developers/rate-limits)._

If you are sending the entire conversation history in the prompt for use cases like chat assistant, the sum of all the prompts in your conversation history must be no greater than the context window.

* * *

## [Cached prompt tokens](https://docs.x.ai/developers/models\#cached-prompt-tokens)

Trying to run the same prompt multiple times? You can now use cached prompt tokens to incur less cost on repeated prompts. By reusing stored prompt data, you save on processing expenses for identical requests. Enable caching in your settings and start saving today!

The caching is automatically enabled for all requests without user input. You can view the cached prompt token consumption in [the `"usage"` object](https://docs.x.ai/developers/rate-limits#checking-token-consumption).

For details on the pricing, please refer to the pricing table above, or on [xAI Console](https://console.x.ai/).

* * *

Did you find this page helpful?

Yes No

- [Models and Pricing](https://docs.x.ai/developers/models#models-and-pricing)
- [Model Pricing](https://docs.x.ai/developers/models#model-pricing)
- [Tools Pricing](https://docs.x.ai/developers/models#tools-pricing)
- [Token Costs](https://docs.x.ai/developers/models#token-costs)
- [Tool Invocation Costs](https://docs.x.ai/developers/models#tool-invocation-costs)
- [Batch API Pricing](https://docs.x.ai/developers/models#batch-api-pricing)
- [Voice API Pricing](https://docs.x.ai/developers/models#voice-api-pricing)
- [Voice Agent API (Realtime)](https://docs.x.ai/developers/models#voice-agent-api-realtime)
- [Text to Speech API](https://docs.x.ai/developers/models#text-to-speech-api)
- [Usage Guidelines Violation Fee](https://docs.x.ai/developers/models#usage-guidelines-violation-fee)
- [Additional Information Regarding Models](https://docs.x.ai/developers/models#additional-information-regarding-models)
- [Model Aliases](https://docs.x.ai/developers/models#model-aliases)
- [Billing and Availability](https://docs.x.ai/developers/models#billing-and-availability)
- [Model Input and Output](https://docs.x.ai/developers/models#model-input-and-output)
- [Context Window](https://docs.x.ai/developers/models#context-window)
- [Cached prompt tokens](https://docs.x.ai/developers/models#cached-prompt-tokens)

Copy for LLMShare feedback

[Login](https://accounts.x.ai/sign-in?redirect=docs)

API & SDK DocsBuild with Grok APIs and SDKs

Developers

[Welcome](https://docs.x.ai/overview) [Introduction](https://docs.x.ai/developers/introduction) [Getting Started](https://docs.x.ai/developers/quickstart) [Models and Pricing](https://docs.x.ai/developers/models) [Rate Limits](https://docs.x.ai/developers/rate-limits) [Provisioned Throughput\\
\\
new](https://docs.x.ai/developers/provisioned-throughput) [Regional Endpoints](https://docs.x.ai/developers/regions) [Debugging Errors](https://docs.x.ai/developers/debugging) [Docs MCP](https://docs.x.ai/developers/docs-mcp) [Release Notes](https://docs.x.ai/developers/release-notes)

Model Capabilities

Text

[Generate Text](https://docs.x.ai/developers/model-capabilities/text/generate-text) [Reasoning](https://docs.x.ai/developers/model-capabilities/text/reasoning) [Structured Outputs](https://docs.x.ai/developers/model-capabilities/text/structured-outputs) [Streaming](https://docs.x.ai/developers/model-capabilities/text/streaming) [Comparison](https://docs.x.ai/developers/model-capabilities/text/comparison) [Multi Agent\\
\\
beta](https://docs.x.ai/developers/model-capabilities/text/multi-agent)

Images

[Image Understanding](https://docs.x.ai/developers/model-capabilities/images/understanding) [Image Generation\\
\\
new](https://docs.x.ai/developers/model-capabilities/images/generation)

Video

new

[Video Generation\\
\\
new](https://docs.x.ai/developers/model-capabilities/video/generation)

Audio

new

[Voice Overview](https://docs.x.ai/developers/model-capabilities/audio/voice) [Voice Agent API](https://docs.x.ai/developers/model-capabilities/audio/voice-agent) [Text to Speech\\
\\
new](https://docs.x.ai/developers/model-capabilities/audio/text-to-speech)

Files

[Chat with Files](https://docs.x.ai/developers/model-capabilities/files/chat-with-files)

Legacy

[Chat Completions](https://docs.x.ai/developers/model-capabilities/legacy/chat-completions)

Files & Collections

[Files Overview](https://docs.x.ai/developers/files) [Managing Files](https://docs.x.ai/developers/files/managing-files) [Collections](https://docs.x.ai/developers/files/collections) [Collections via API](https://docs.x.ai/developers/files/collections/api) [Collection Metadata](https://docs.x.ai/developers/files/collections/metadata)

Tools

[Overview](https://docs.x.ai/developers/tools/overview) [Function Calling](https://docs.x.ai/developers/tools/function-calling) [Web Search](https://docs.x.ai/developers/tools/web-search) [X Search](https://docs.x.ai/developers/tools/x-search) [Code Execution](https://docs.x.ai/developers/tools/code-execution) [Collections Search (RAG)](https://docs.x.ai/developers/tools/collections-search) [Remote MCP Tools](https://docs.x.ai/developers/tools/remote-mcp) Deep Dive

[Citations](https://docs.x.ai/developers/tools/citations) [Streaming & Sync](https://docs.x.ai/developers/tools/streaming-and-sync) [Tool Usage Details](https://docs.x.ai/developers/tools/tool-usage-details) [Advanced Usage](https://docs.x.ai/developers/tools/advanced-usage)

Advanced API Usage

[Overview](https://docs.x.ai/developers/advanced-api-usage) [Batch API\\
\\
new](https://docs.x.ai/developers/advanced-api-usage/batch-api) [Deferred Completions](https://docs.x.ai/developers/advanced-api-usage/deferred-chat-completions) Prompt Caching

new

[How It Works](https://docs.x.ai/developers/advanced-api-usage/prompt-caching/how-it-works) [Maximizing Cache Hits](https://docs.x.ai/developers/advanced-api-usage/prompt-caching/maximizing-cache-hits) [What Breaks Caching](https://docs.x.ai/developers/advanced-api-usage/prompt-caching/multi-turn) [Usage & Pricing](https://docs.x.ai/developers/advanced-api-usage/prompt-caching/usage-and-pricing) [Best Practices & FAQ](https://docs.x.ai/developers/advanced-api-usage/prompt-caching/best-practices)

[Fingerprint](https://docs.x.ai/developers/advanced-api-usage/fingerprint) [Async Requests](https://docs.x.ai/developers/advanced-api-usage/async) [Use with Code Editors](https://docs.x.ai/developers/advanced-api-usage/use-with-code-editors) [Prompt Engineering for Grok Code](https://docs.x.ai/developers/advanced-api-usage/grok-code-prompt-engineering)

Migration Guides

[Migrating to Responses API](https://docs.x.ai/developers/model-capabilities/text/comparison) [Migrating to New Models](https://docs.x.ai/developers/migration/models)

Community

[Cookbook](https://docs.x.ai/cookbook) [Community Integrations](https://docs.x.ai/developers/community)

FAQ

[Data & Privacy](https://docs.x.ai/developers/faq/security) [General](https://docs.x.ai/developers/faq/general)

[Available](https://status.x.ai/)