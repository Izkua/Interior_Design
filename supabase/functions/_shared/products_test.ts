// Run with: deno test supabase/functions/_shared/
import { assertEquals } from "jsr:@std/assert@1";
import { channel3Request, colorName, itemType, normalize, sizes, toCm, type C3Product } from "./products.ts";

Deno.test("converts lengths to centimeters", () => {
  assertEquals(toCm({ number: 34, unit: "in" }), 86.4);
  assertEquals(toCm({ number: 2, unit: "m" }), 200);
  assertEquals(toCm({ number: 0, unit: "cm" }), null);
  assertEquals(toCm({ number: 5000, unit: "cm" }), null); // over 10 m: a units mistake
  assertEquals(toCm(null), null);
});

Deno.test("matches item types", () => {
  assertEquals(itemType("Sofas", "Harbor 3-seat"), "sofa");
  assertEquals(itemType(null, "Walnut media console"), "tvStand");
  assertEquals(itemType(null, "Throw pillow"), null);
});

Deno.test("names colors", () => {
  assertEquals(colorName("#f5f3ee"), "White");
  assertEquals(colorName("#3a5a95"), "Blue");
});

const sample: C3Product = {
  id: "abc",
  title: " Oak Coffee Table ",
  brands: [{ id: "b1", name: "Brand" }],
  images: [{ url: "https://img/x.jpg", is_main_image: true }],
  category: { slug: "coffee-tables", title: "Coffee Tables" },
  materials: ["Oak"],
  colors: [{ hex: "#785032", percentage: 0.8 }],
  offers: [
    { url: "https://shop/b", domain: "shop", price: { price: 300, currency: "USD" }, availability: "InStock",
      dimensions: { width: { number: 110, unit: "cm" }, length: { number: 60, unit: "cm" }, height: { number: 42, unit: "cm" } } },
    { url: "https://shop/a", domain: "shop", price: { price: 250, currency: "USD" }, availability: "InStock", dimensions: null },
  ],
  ratings: { value: 4.6, count: 120 },
};

Deno.test("normalizes a product using the cheapest offer", () => {
  const p = normalize(sample)!;
  assertEquals(p.name, "Oak Coffee Table");
  assertEquals(p.price, 250);
  assertEquals(p.url, "https://shop/a");
  // The cheapest offer has no size, so the size comes from another offer.
  assertEquals([p.widthCm, p.depthCm, p.heightCm], [110, 60, 42]);
  assertEquals(p.type, "table");
  assertEquals(p.rating, 4.6);
  assertEquals(p.reviewCount, 120);
  assertEquals(p.colors, ["Brown"]);
});

Deno.test("no offers means no product", () => {
  assertEquals(normalize({ ...sample, offers: [] }), null);
});

Deno.test("one color uses the color filter, several go in the words", () => {
  const one = channel3Request({ type: "sofa", colors: ["Blue"] });
  assertEquals(one.filters, { colors: { palette: [{ hex: "#3c5a96" }] } });
  assertEquals(one.query, "sofa");
  const two = channel3Request({ type: "sofa", colors: ["Blue", "Grey"] });
  assertEquals(two.filters, undefined);
  assertEquals(two.query, "sofa Blue Grey");
});

Deno.test("prefers named colors and adds materials from attributes", () => {
  const p = normalize({ ...sample, structured_attributes: { color: ["Walnut"], material: ["Oak", "Steel"] } })!;
  assertEquals(p.colors, ["Walnut"]);
  assertEquals(p.materials, ["Oak", "Steel"]);
});

Deno.test("builds the Channel3 request", () => {
  const r = channel3Request({ text: "oak", type: "table", maxPrice: 400, limit: 99 });
  assertEquals(r.query, "oak table");
  assertEquals(r.limit, 30);
  assertEquals(r.filters, { price: { max_price: 400 } });
  assertEquals(r.config, { length_unit: "cm" });
});

const inch = (n: number) => ({ number: n, unit: "in" });

Deno.test("a two-number poster is height then width, with no depth", () => {
  // "24 x 36 in": Channel3 files the numbers as length and width.
  assertEquals(sizes({ length: inch(24), width: inch(36) }, "poster"), { widthCm: 91.4, depthCm: null, heightCm: 61 });
  // Width and height missing the other way round still read height first.
  assertEquals(sizes({ length: inch(24), height: inch(36) }, "framedArt"), { widthCm: 91.4, depthCm: null, heightCm: 61 });
});

Deno.test("labelled width and height on wall decor are kept", () => {
  assertEquals(sizes({ width: inch(24), height: inch(36) }, "poster"), { widthCm: 61, depthCm: null, heightCm: 91.4 });
});

Deno.test("three numbers on flat decor: the thin one is depth", () => {
  // "24 x 36 x 1": the 1 is the thickness, not the height.
  assertEquals(sizes({ length: inch(24), width: inch(36), height: inch(1) }, "canvasArt"), { widthCm: 91.4, depthCm: 2.5, heightCm: 61 });
  // Already labelled sensibly: unchanged.
  assertEquals(sizes({ length: inch(1), width: inch(24), height: inch(36) }, "poster"), { widthCm: 61, depthCm: 2.5, heightCm: 91.4 });
});

Deno.test("furniture sizes keep their labels", () => {
  const cm = (n: number) => ({ number: n, unit: "cm" });
  assertEquals(sizes({ length: cm(60), width: cm(110), height: cm(42) }, "table"), { widthCm: 110, depthCm: 60, heightCm: 42 });
  // A two-number rug is not read as height × width.
  assertEquals(sizes({ length: cm(150), width: cm(240) }, "rug"), { widthCm: 240, depthCm: 150, heightCm: null });
  assertEquals(sizes(null, "poster"), { widthCm: null, depthCm: null, heightCm: null });
});

Deno.test("normalize uses the poster reading", () => {
  const poster: C3Product = { ...sample, title: "Botanical Poster", category: null,
    offers: [{ url: "u", domain: "d", price: { price: 20, currency: "USD" }, dimensions: { length: inch(24), width: inch(36) } }] };
  const p = normalize(poster)!;
  assertEquals([p.heightCm, p.widthCm, p.depthCm], [61, 91.4, null]);
});
