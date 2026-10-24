// Turning Channel3 products into the app's product shape.
//
// Field names follow Channel3's published OpenAPI spec
// (https://docs.trychannel3.com/openapi/openapi.json, read Oct 2026):
// Product { id, title, brands[], images[], category, materials, colors[],
// offers[], ratings }, ProductOffer { url, domain, price { price, currency },
// availability, dimensions { length, width, height: { number, unit } } }.

/** What the app expects (matches CatalogProduct in the Swift code). */
export interface AppProduct {
  id: string;
  name: string;
  price: number;
  currency: string;
  widthCm: number | null;
  depthCm: number | null;
  heightCm: number | null;
  type: string | null;
  materials: string[];
  styles: string[];
  colors: string[];
  rating: number | null;
  reviewCount: number | null;
  imageURL: string | null;
  retailer: string;
  url: string | null;
  isSample: boolean;
}

/** What the app sends (matches CatalogQuery in the Swift code). */
export interface AppQuery {
  text?: string;
  type?: string | null;
  minPrice?: number | null;
  maxPrice?: number | null;
  minRating?: number;
  materials?: string[];
  styles?: string[];
  colors?: string[];
  limit?: number;
}

interface C3Length { number: number; unit: string }
interface C3Offer {
  url: string;
  domain: string;
  price: { price: number; currency: string };
  availability?: string;
  dimensions?: { length?: C3Length | null; width?: C3Length | null; height?: C3Length | null } | null;
}
export interface C3Product {
  id: string;
  title: string;
  brands?: { id: string; name: string }[];
  images?: { url: string; cleaned_url?: string | null; is_main_image?: boolean }[];
  category?: { slug: string; title: string } | null;
  materials?: string[] | null;
  colors?: { hex: string; percentage?: number }[];
  offers?: C3Offer[];
  ratings?: { value: number; count: number } | null;
}

const CM_PER: Record<string, number> = { mm: 0.1, cm: 1, m: 100, in: 2.54, ft: 30.48 };

/** A length in centimeters, or null if missing or impossible (over 10 m). */
export function toCm(length?: C3Length | null): number | null {
  if (!length || typeof length.number !== "number" || length.number <= 0) return null;
  const factor = CM_PER[length.unit];
  if (!factor) return null;
  const cm = length.number * factor;
  return cm <= 1000 ? Math.round(cm * 10) / 10 : null;
}

/** Our item types, matched from Channel3's category or the product title. */
const TYPE_WORDS: [string, string[]][] = [
  ["tvStand", ["tv stand", "media console", "tv console", "entertainment center"]],
  ["sofa", ["sofa", "couch", "sectional", "loveseat"]],
  ["bed", ["bed frame", "platform bed", "beds", " bed"]],
  ["desk", ["desk"]],
  ["dresser", ["dresser", "chest of drawers"]],
  ["shelf", ["bookcase", "bookshel", "shelf", "shelving"]],
  ["lamp", ["lamp"]],
  ["rug", ["rug"]],
  ["chair", ["armchair", "chair"]],
  ["table", ["coffee table", "dining table", "side table", "table"]],
];

export function itemType(category: string | null | undefined, title: string): string | null {
  const text = ` ${category ?? ""} ${title} `.toLowerCase();
  for (const [type, words] of TYPE_WORDS) {
    if (words.some((w) => text.includes(w))) return type;
  }
  return null;
}

/** A plain color name for a hex color, close enough for filtering. */
export function colorName(hex: string): string | null {
  const m = /^#?([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i.exec(hex);
  if (!m) return null;
  const [r, g, b] = [m[1], m[2], m[3]].map((h) => parseInt(h, 16));
  const named: [string, number[]][] = [
    ["White", [240, 240, 235]], ["Black", [25, 25, 25]], ["Grey", [128, 128, 128]],
    ["Beige", [215, 195, 165]], ["Brown", [120, 80, 50]], ["Green", [70, 120, 80]], ["Blue", [60, 90, 150]],
  ];
  let best = named[0][0];
  let bestDistance = Infinity;
  for (const [name, [nr, ng, nb]] of named) {
    const d = (r - nr) ** 2 + (g - ng) ** 2 + (b - nb) ** 2;
    if (d < bestDistance) [best, bestDistance] = [name, d];
  }
  return best;
}

/** One Channel3 product in the app's shape, using its cheapest in-stock offer. */
export function normalize(p: C3Product): AppProduct | null {
  const offers = (p.offers ?? []).filter((o) => o.availability !== "OutOfStock");
  const offer = offers.sort((a, b) => a.price.price - b.price.price)[0] ?? p.offers?.[0];
  if (!offer) return null;

  // Furniture: width is side to side, depth is Channel3's "length".
  const d = offer.dimensions ?? p.offers?.find((o) => o.dimensions)?.dimensions ?? null;
  const image = p.images?.find((i) => i.is_main_image) ?? p.images?.[0];

  return {
    id: p.id,
    name: p.title.trim(),
    price: offer.price.price,
    currency: offer.price.currency ?? "USD",
    widthCm: toCm(d?.width),
    depthCm: toCm(d?.length),
    heightCm: toCm(d?.height),
    type: itemType(p.category?.title ?? p.category?.slug, p.title),
    materials: p.materials ?? [],
    styles: [],
    colors: [...new Set((p.colors ?? []).slice(0, 2).map((c) => colorName(c.hex)).filter((c): c is string => !!c))],
    rating: p.ratings ? Math.min(Math.max(p.ratings.value, 0), 5) : null,
    reviewCount: p.ratings?.count ?? null,
    imageURL: image?.cleaned_url ?? image?.url ?? null,
    retailer: p.brands?.[0]?.name ?? offer.domain,
    url: offer.url,
    isSample: false,
  };
}

/** Friendly words for each item type, to help the search text. */
const TYPE_SEARCH: Record<string, string> = {
  sofa: "sofa", bed: "bed frame", desk: "desk", table: "table", chair: "accent chair",
  dresser: "dresser", shelf: "bookshelf", tvStand: "tv stand", lamp: "floor lamp", rug: "area rug",
};

/** The Channel3 search request for an app query. */
export function channel3Request(q: AppQuery) {
  const words = [q.text?.trim(), q.type ? TYPE_SEARCH[q.type] : null, ...(q.materials ?? []), ...(q.styles ?? [])]
    .filter((w): w is string => !!w && w.length > 0);
  const query = words.length > 0 ? words.join(" ") : "furniture";
  const price: Record<string, number> = {};
  if (q.minPrice) price.min_price = q.minPrice;
  if (q.maxPrice) price.max_price = q.maxPrice;
  return {
    query,
    limit: Math.min(Math.max(q.limit ?? 20, 1), 30),
    filters: Object.keys(price).length > 0 ? { price } : undefined,
    config: { length_unit: "cm" },
  };
}

/** The same query always gives the same cache key. */
export async function cacheKey(q: AppQuery): Promise<string> {
  const request = channel3Request(q);
  const text = JSON.stringify(request);
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
