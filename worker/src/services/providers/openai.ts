import type { CompleteOptions, Completion, Msg, Provider, ToolCall } from "./types";

/**
 * Covers every OpenAI-compatible `/chat/completions` endpoint: OpenRouter,
 * Fireworks, DeepSeek, Groq, Together, and OpenAI itself. Only the base URL
 * differs, so one adapter serves all of them.
 */
export function openAICompatible(
  id: string,
  keyName: string,
  baseURL: string,
  extraHeaders: Record<string, string> = {},
): Provider {
  return {
    id,
    keyName,

    async complete(options: CompleteOptions): Promise<Completion> {
      const deadline = new AbortController();
      const expiry = setTimeout(() => deadline.abort(), options.timeoutMs);

      try {
        const response = await fetch(`${baseURL}/chat/completions`, {
          method: "POST",
          signal: deadline.signal,
          headers: {
            "content-type": "application/json",
            authorization: `Bearer ${options.apiKey}`,
            ...extraHeaders,
          },
          body: JSON.stringify({
            model: options.model,
            max_tokens: options.maxTokens,
            messages: [
              { role: "system", content: options.system },
              ...options.messages.flatMap(toOpenAI),
            ],
            tools: options.tools.map((tool) => ({
              type: "function",
              function: {
                name: tool.name,
                description: tool.description,
                parameters: tool.parameters,
              },
            })),
            tool_choice: "auto",
          }),
        });

        const body = (await response.json()) as {
          choices?: Array<{
            message?: {
              content?: string | null;
              tool_calls?: Array<{
                id?: string;
                function?: { name?: string; arguments?: string };
              }>;
            };
          }>;
          usage?: { prompt_tokens?: number; completion_tokens?: number };
          error?: { message?: string };
        };

        if (!response.ok) {
          return {
            ok: false,
            error: body.error?.message ?? `${id} returned ${response.status}`,
            retryable: response.status === 429 || response.status >= 500,
          };
        }

        const message = body.choices?.[0]?.message;
        const toolCalls: ToolCall[] = [];
        for (const call of message?.tool_calls ?? []) {
          // Arguments arrive as a JSON *string*. Weak models frequently emit
          // malformed JSON here, which is exactly the failure the router needs
          // to see in order to escalate.
          let input: Record<string, unknown>;
          try {
            input = JSON.parse(call.function?.arguments || "{}") as Record<string, unknown>;
          } catch {
            return {
              ok: false,
              error: `${id} emitted unparseable tool arguments`,
              retryable: true,
            };
          }
          toolCalls.push({ id: call.id ?? "", name: call.function?.name ?? "", input });
        }

        return {
          ok: true,
          value: {
            text: (message?.content ?? "").trim(),
            toolCalls,
            inputTokens: body.usage?.prompt_tokens ?? 0,
            outputTokens: body.usage?.completion_tokens ?? 0,
          },
        };
      } catch (cause) {
        // An abort arrives here as a thrown DOMException, not as a response.
        return deadline.signal.aborted
          ? { ok: false, error: `${id} passed its ${options.timeoutMs}ms deadline`, retryable: true }
          : { ok: false, error: `${id} unreachable: ${String(cause)}`, retryable: true };
      } finally {
        clearTimeout(expiry);
      }
    },
  };
}

function toOpenAI(message: Msg): Array<Record<string, unknown>> {
  switch (message.role) {
    case "user":
      return [{ role: "user", content: message.text }];
    case "assistant":
      return [
        {
          role: "assistant",
          content: message.text || null,
          ...(message.toolCalls.length
            ? {
                tool_calls: message.toolCalls.map((call) => ({
                  id: call.id,
                  type: "function",
                  function: { name: call.name, arguments: JSON.stringify(call.input) },
                })),
              }
            : {}),
        },
      ];
    case "toolResults":
      // OpenAI wants one message per result, not one batched message.
      return message.results.map((result) => ({
        role: "tool",
        tool_call_id: result.id,
        content: result.content,
      }));
  }
}
