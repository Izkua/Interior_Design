// Small helpers every function uses.

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

export function error(message: string, status: number): Response {
  return json({ error: message }, status);
}

/** Reads a required secret; fails loudly if it was never set. */
export function secret(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing secret ${name}. Set it in the Supabase dashboard.`);
  return value;
}

/**
 * Wraps a request handler so an unexpected failure is logged (see the
 * function's Logs in the Supabase dashboard) and answered with a short,
 * safe message instead of a bare "Internal Server Error".
 */
export function safely(handler: (req: Request) => Promise<Response>) {
  return async (req: Request): Promise<Response> => {
    try {
      return await handler(req);
    } catch (e) {
      // Database errors are plain objects with a "message", not Error.
      const message = e instanceof Error
        ? e.message
        : typeof e === "object" && e !== null && "message" in e
        ? String((e as { message: unknown }).message)
        : String(e);
      console.error("Unhandled error:", message);
      // Only the error's text, never request headers or secrets.
      return error(`Server problem: ${message.slice(0, 200)}`, 500);
    }
  };
}
