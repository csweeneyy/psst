import type { CompleteOptions, Completion, Msg, Provider, ToolCall } from "./types";

interface Block {
  type: string;
  text?: string;
  id?: string;
  name?: string;
  input?: Record<string, unknown>;
  tool_use_id?: string;
  content?: string;
  is_error?: boolean;
}

export const anthropic: Provider = {
  id: "anthropic",
  keyName: "ANTHROPIC_API_KEY",

  async complete(options: CompleteOptions): Promise<Completion> {
    const deadline = new AbortController();
    const expiry = setTimeout(() => deadline.abort(), options.timeoutMs);

    try {
      const response = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        signal: deadline.signal,
        headers: {
          "content-type": "application/json",
          "x-api-key": options.apiKey,
          "anthropic-version": "2023-06-01",
        },
        body: JSON.stringify({
          model: options.model,
          max_tokens: options.maxTokens,
          system: options.system,
          tools: options.tools.map((tool) => ({
            name: tool.name,
            description: tool.description,
            input_schema: tool.parameters,
          })),
          messages: options.messages.map(toAnthropic),
        }),
      });

      const body = (await response.json()) as {
        content?: Block[];
        usage?: { input_tokens?: number; output_tokens?: number };
        error?: { message?: string };
      };

      if (!response.ok) {
        return {
          ok: false,
          error: body.error?.message ?? `anthropic returned ${response.status}`,
          // 4xx other than rate limiting is our bug, not a reason to try a
          // different model with the same malformed request.
          retryable: response.status === 429 || response.status >= 500,
        };
      }

      const blocks = body.content ?? [];
      return {
        ok: true,
        value: {
          text: blocks.filter((b) => b.type === "text").map((b) => b.text ?? "").join("\n").trim(),
          toolCalls: blocks
            .filter((b) => b.type === "tool_use")
            .map<ToolCall>((b) => ({ id: b.id ?? "", name: b.name ?? "", input: b.input ?? {} })),
          inputTokens: body.usage?.input_tokens ?? 0,
          outputTokens: body.usage?.output_tokens ?? 0,
        },
      };
    } catch (cause) {
      // An abort arrives here as a thrown DOMException, not as a response.
      return deadline.signal.aborted
        ? { ok: false, error: `anthropic passed its ${options.timeoutMs}ms deadline`, retryable: true }
        : { ok: false, error: `anthropic unreachable: ${String(cause)}`, retryable: true };
    } finally {
      clearTimeout(expiry);
    }
  },
};

function toAnthropic(message: Msg): { role: string; content: unknown } {
  switch (message.role) {
    case "user":
      return { role: "user", content: message.text };
    case "assistant": {
      const blocks: Block[] = [];
      if (message.text) blocks.push({ type: "text", text: message.text });
      for (const call of message.toolCalls) {
        blocks.push({ type: "tool_use", id: call.id, name: call.name, input: call.input });
      }
      return { role: "assistant", content: blocks };
    }
    case "toolResults":
      return {
        role: "user",
        content: message.results.map((result) => ({
          type: "tool_result",
          tool_use_id: result.id,
          content: result.content,
          ...(result.isError ? { is_error: true } : {}),
        })),
      };
  }
}
