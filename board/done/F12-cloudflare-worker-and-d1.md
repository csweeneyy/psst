# F12 - Cloudflare Worker and D1

**Why**
Holds the API key, the conversation history, and eventually the push scheduler.

**Acceptance**
- Worker deploys via wrangler
- D1 schema for habits, occurrences, messages
- `POST /chat` accepts a message plus habit snapshot and returns a reply plus mutations
