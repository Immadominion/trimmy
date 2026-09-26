import { PAGES, PAGE_ORDER } from "@/components/PhoneApp";

/** Review of the phone's app pages, flat and at their own size. Visit /phone-study. */
export default function PhoneStudy() {
  return <main style={{ display: "flex", flexWrap: "wrap", gap: 24, padding: 24, background: "#1c1a22", minHeight: "100vh" }}>
    {PAGE_ORDER.map((name) => {
      const Page = PAGES[name];
      return <figure key={name} style={{ margin: 0 }}>
        <div data-page={name} style={{ position: "relative", width: 390, height: 844, borderRadius: 52.6, overflow: "hidden" }}><Page /></div>
        <figcaption style={{ color: "#fff9", font: "600 13px/2 var(--font-body)" }}>{name}</figcaption>
      </figure>;
    })}
  </main>;
}
