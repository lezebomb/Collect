const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return Response.json(body, { status, headers: cors });
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const authorization = request.headers.get("Authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) return json({ error: "Sign in required" }, 401);
  try {
    // Validate the user's access token with Supabase Auth.
    // A publishable key alone never grants access to the paid search API.
    const auth = await fetch(`${Deno.env.get("SUPABASE_URL")}/auth/v1/user`, {
      headers: {
        Authorization: authorization,
        apikey: Deno.env.get("SUPABASE_ANON_KEY") ?? "",
      },
      signal: AbortSignal.timeout(3000),
    });
    if (!auth.ok) return json({ error: "Sign in required" }, 401);
    const user = await auth.json();
    if (!user.id || user.is_anonymous === true) return json({ error: "Sign in required" }, 401);

    const reader = request.body?.getReader();
    if (!reader) return json({ error: "Invalid JSON" }, 400);
    const decoder = new TextDecoder();
    let raw = "";
    let bytes = 0;
    while (true) {
      const chunk = await reader.read();
      if (chunk.done) break;
      bytes += chunk.value.byteLength;
      if (bytes > 4096) {
        await reader.cancel();
        return json({ error: "Request too large" }, 413);
      }
      raw += decoder.decode(chunk.value, { stream: true });
    }
    raw += decoder.decode();
    let body;
    try { body = JSON.parse(raw); } catch (_) { return json({ error: "Invalid JSON" }, 400); }
    if (!body || typeof body !== "object") return json({ error: "Invalid JSON" }, 400);
    const query = typeof body.query === "string" ? body.query.trim() : "";
    if (query.length < 2 || query.length > 160) return json({ error: "Invalid query" }, 400);
    // Enforce the exact-email allowlist and persistent quotas in Postgres.
    // The caller's JWT is used; this endpoint never needs a service-role key.
    const permission = await fetch(`${Deno.env.get("SUPABASE_URL")}/rest/v1/rpc/take_email_collection_search_slot`, {
      method: "POST",
      headers: { Authorization: authorization, apikey: Deno.env.get("SUPABASE_ANON_KEY") ?? "",
        "Content-Type": "application/json" },
      body: "{}",
      signal: AbortSignal.timeout(3000),
    });
    if (!permission.ok) return json({ error: "Access denied" }, 403);
    if (await permission.json() !== true) return json({ error: "Search limit reached" }, 429);

    const key = Deno.env.get("TAVILY_API_KEY");
    if (!key) return json({ candidates: [], configured: false });

    const response = await fetch("https://api.tavily.com/search", {
      method: "POST",
      headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        query: `${query} product cover image`,
        topic: "general",
        search_depth: "fast",
        max_results: 5,
        include_images: true,
        include_image_descriptions: false,
        include_answer: false,
        include_raw_content: false,
        auto_parameters: false,
      }),
      signal: AbortSignal.timeout(6500),
    });
    if (!response.ok) {
      console.error(`Tavily search returned HTTP ${response.status}`);
      return json({ error: "Search source unavailable" }, 502);
    }
    const data = await response.json();
    const images = Array.isArray(data.images) ? data.images : [];
    const candidates = images.flatMap((image: unknown) => {
      const record: Record<string, unknown> = typeof image === "string"
        ? { url: image }
        : image as Record<string, unknown>;
      if (!record || typeof record.url !== "string") return [];
      try {
        const url = new URL(record.url);
        if (url.protocol !== "https:") return [];
        return [{
          title: query,
          source: `Tavily · ${url.hostname}`,
          image_url: url.toString(),
          // An image caption is shown as a candidate description; it is not
          // treated as an official product name or filled without user choice.
          description: typeof record.description === "string" ? record.description.slice(0, 3000) : "",
        }];
      } catch (_) {
        return [];
      }
    }).slice(0, 24);
    return json({ candidates, configured: true });
  } catch (error) {
    console.error(`Catalog search failed: ${error instanceof Error ? error.name : "Unknown error"}`);
    return json({ error: "Search temporarily unavailable" }, 503);
  }
});
