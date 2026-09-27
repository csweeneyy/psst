/** Normalized shapes every provider adapter maps to and from. */

export interface ToolSpec {
  name: string;
  description: string;
  parameters: Record<string, unknown>;
}

export interface ToolCall {
  id: string;
  name: string;
  input: Record<string, unknown>;
}

export interface ToolResult {
  id: string;
  content: string;
  isError?: boolean;
}

export type Msg =
  | { role: "user"; text: string }
  | { role: "assistant"; text: string; toolCalls: ToolCall[] }
  | { role: "toolResults"; results: ToolResult[] };

export interface ModelReply {
  text: string;
  toolCalls: ToolCall[];
  inputTokens: number;
  outputTokens: number;
}

export interface CompleteOptions {
  apiKey: string;
  model: string;
  system: string;
  messages: Msg[];
  tools: ToolSpec[];
  maxTokens: number;
  /**
   * Hard deadline for this one call. A model that has not answered by then is
   * aborted and reported as a retryable failure, because a hung upstream is
   * indistinguishable from a dead one and the caller is waiting either way.
   */
  timeoutMs: number;
}

export type Completion =
  | { ok: true; value: ModelReply }
  | { ok: false; error: string; retryable: boolean };

export interface Provider {
  id: string;
  /** Which env var holds this provider's credential. */
  keyName: string;
  complete(options: CompleteOptions): Promise<Completion>;
}
