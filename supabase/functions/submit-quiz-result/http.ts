export function jsonResponse(
  body: Record<string, unknown>,
  status = 200,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store, max-age=0",
      "x-content-type-options": "nosniff",
    },
  });
}

export function firstClientAddress(rawValue: string | null): string | null {
  if (!rawValue) return null;
  const firstValue = rawValue.split(",")[0]?.trim();
  if (!firstValue || firstValue.length > 128) return null;
  return firstValue;
}
