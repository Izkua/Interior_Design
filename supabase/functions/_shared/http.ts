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
