// Turning Channel3 products into the app's product shape.
//
// Field names follow Channel3's published OpenAPI spec
// (https://docs.trychannel3.com/openapi/openapi.json) and their official
// channel3-api skill (both read Oct 2026):
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
  /** "furniture", "wallDecor", or "smallDecor". */
  category?: string | null;
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
  /** shot_type: "hero", "angle_view", "lifestyle", "detail", "size_chart", ... */
  images?: { url: string; cleaned_url?: string | null; is_main_image?: boolean; shot_type?: string | null }[];
  category?: { slug: string; title: string } | null;
  materials?: string[] | null;
  colors?: { hex: string; percentage?: number }[];
  offers?: C3Offer[];
  ratings?: { value: number; count: number } | null;
  /** e.g. { color: ["Navy"], material: ["Leather"] } */
  structured_attributes?: Record<string, string[]>;
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

/**
 * Wall decor that hangs flat, where a two-number size means height × width
 * and a listing's thin side is its depth. (Not wall shelves: "24 x 6 in" on
 * a shelf is width × depth.)
 */
const FLAT_WALL_DECOR = new Set(["poster", "framedArt", "canvasArt", "mirror", "wallClock"]);

type Sizes = { widthCm: number | null; depthCm: number | null; heightCm: number | null };

/**
 * A product's width, depth, and height from Channel3's labelled sizes.
 *
 * Furniture: width is side to side, depth is Channel3's "length", height is
 * height, as labelled.
 *
 * Flat wall decor is usually listed with just two numbers ("24 x 36 in", height
 * then width) and Channel3 files them in its first two slots, length and
 * width. Read that way, a poster came out 36 wide, 24 deep, and with no
 * height (or a tiny one), so it was drawn as a sliver. For flat wall decor:
 * - two numbers: the first listed (length, else width) is height, the
 *   other is width, and depth stays missing (never filled with 1).
 *   If the two are already labelled width and height, those labels win.
 * - three numbers on flat decor: the thinnest is the depth (frame or canvas
 *   thickness); of the other two, a labelled height stays the height,
 *   otherwise the first listed is the height.
 */
export function sizes(d: Partial<Record<"length" | "width" | "height", C3Length | null>> | null, type: string | null): Sizes {
  const length = toCm(d?.length);
  const width = toCm(d?.width);
  const height = toCm(d?.height);
  const asLabelled = { widthCm: width, depthCm: length, heightCm: height };
  if (!type || !FLAT_WALL_DECOR.has(type)) return asLabelled;

  const present = [length, width, height].filter((v): v is number => v !== null);
  if (present.length === 2) {
    if (length === null) return { widthCm: width, depthCm: null, heightCm: height };
    // Length is the first number listed, so it is the height.
    return { widthCm: width ?? height, depthCm: null, heightCm: length };
  }
  if (present.length === 3) {
    const slots: ["length" | "width" | "height", number][] = [["length", length!], ["width", width!], ["height", height!]];
    const thin = slots.reduce((a, b) => (b[1] < a[1] ? b : a));
    const rest = slots.filter((s) => s !== thin);
    // Already sensible (height and width are the big two): keep the labels.
    if (thin[0] === "length") return asLabelled;
    const tall = rest.find((s) => s[0] === "height") ?? rest[0];
    const wide = rest.find((s) => s !== tall)!;
    return { widthCm: wide[1], depthCm: thin[1], heightCm: tall[1] };
  }
  return asLabelled;
}

/** Our item types, matched from Channel3's category or the product title. */
const TYPE_WORDS: [string, string[]][] = [
  // Decor first, so "table lamp" isn't read as a table.
  ["tableLamp", ["table lamp", "desk lamp", "bedside lamp"]],
  ["wallClock", ["wall clock"]],
  ["tableClock", ["desk clock", "alarm clock", "table clock", "mantel clock"]],
  ["wallShelf", ["floating shelf", "wall shelf", "wall-mounted shelf"]],
  ["mirror", ["mirror"]],
  ["poster", ["poster"]],
  ["canvasArt", ["canvas"]],
  ["framedArt", ["framed print", "framed art", "wall art", "art print", "picture frame"]],
  ["monitor", ["monitor"]],
  ["plant", ["plant", "planter", "flower pot", "plant pot"]],
  ["vase", ["vase"]],
  ["candle", ["candle"]],
  ["deskStorage", ["desk organizer", "pen holder", "desktop organizer", "storage box", "desk tray"]],
  ["books", ["book set", "decorative books", "coffee table book"]],
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

  const d = offer.dimensions ?? p.offers?.find((o) => o.dimensions)?.dimensions ?? null;
  const image = p.images?.find((i) => i.is_main_image) ?? p.images?.[0];
  const type = itemType(p.category?.title ?? p.category?.slug, p.title);

  return {
    id: p.id,
    name: p.title.trim(),
    price: offer.price.price,
    currency: offer.price.currency ?? "USD",
    ...sizes(d, type),
    type,
    materials: [...new Set([...(p.materials ?? []), ...(p.structured_attributes?.material ?? [])])],
    styles: [],
    // Named colors if Channel3 gives them; otherwise the closest name to
    // the main colors in the product photo.
    colors: p.structured_attributes?.color?.length
      ? p.structured_attributes.color.slice(0, 3)
      : [...new Set((p.colors ?? []).slice(0, 2).map((c) => colorName(c.hex)).filter((c): c is string => !!c))],
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
  poster: "poster print", framedArt: "framed wall art", canvasArt: "canvas wall art", mirror: "wall mirror",
  wallShelf: "floating wall shelf", wallClock: "wall clock", plant: "artificial plant in pot", vase: "decorative vase",
  books: "decorative books", tableLamp: "table lamp", monitor: "computer monitor", deskStorage: "desk organizer",
  tableClock: "desk clock", candle: "candle holder",
};

/** Search words for a kind of item, when no type is picked. */
const CATEGORY_SEARCH: Record<string, string> = {
  furniture: "furniture", wallDecor: "wall decor", smallDecor: "home decor accents",
};

/** sRGB hex for each color the app offers, for Channel3's color filter. */
export const COLOR_HEX: Record<string, string> = {
  White: "#f5f5f2", Black: "#1a1a1a", Grey: "#808080", Beige: "#d8c3a5",
  Brown: "#7b5235", Green: "#4a7a55", Blue: "#3c5a96",
};

/** The Channel3 search request for an app query. */
export function channel3Request(q: AppQuery) {
  // Materials and styles have no reliable filter without knowing the
  // category's attribute names, so they go in the search words (Channel3
  // recommends this over dropping them).
  const kind = q.type ? TYPE_SEARCH[q.type] : q.category ? CATEGORY_SEARCH[q.category] : null;
  const words = [q.text?.trim(), kind, ...(q.materials ?? []), ...(q.styles ?? [])]
    .filter((w): w is string => !!w && w.length > 0);
  const filters: Record<string, unknown> = {};
  const price: Record<string, number> = {};
  if (q.minPrice) price.min_price = q.minPrice;
  if (q.maxPrice) price.max_price = q.maxPrice;
  if (Object.keys(price).length > 0) filters.price = price;
  // Colors use Channel3's color filter, not the search words. Their palette
  // means "has all of these", so it's only used for a single color; with
  // several (meaning "any of these") the names go in the search words.
  const colors = (q.colors ?? []).filter((c) => COLOR_HEX[c]);
  if (colors.length === 1) {
    filters.colors = { palette: [{ hex: COLOR_HEX[colors[0]] }] };
  } else {
    words.push(...colors);
  }
  return {
    query: words.length > 0 ? words.join(" ") : "furniture",
    limit: Math.min(Math.max(q.limit ?? 20, 1), 30),
    filters: Object.keys(filters).length > 0 ? filters : undefined,
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
