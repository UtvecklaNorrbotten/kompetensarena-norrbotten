from pathlib import Path
from urllib.parse import urljoin
from playwright.sync_api import sync_playwright

BASE = "https://www.skolverket.se"
OUT = Path("artifacts/skolverket_browser_probe")
OUT.mkdir(parents=True, exist_ok=True)

URLS = {
    "gr9": BASE + "/statistik-och-utvarderingar/statistik-om-forskola-och-skola/sok-statistik-om-forskola-skola-och-vuxenutbildning?sok=SokC&verkform=Grundskola&omrade=Betyg%20%C3%A5rskurs%209&lasar=2025&run=1",
    "gy": BASE + "/statistik-och-utvarderingar/statistik-om-forskola-skola-och-vuxenutbildning/sok-statistik-om-forskola-skola-och-vuxenutbildning?sok=SokC&verkform=Gymnasieskola&omrade=Betyg%20och%20studieresultat&lasar=2025&run=1",
}

def collect(page, name, url):
    page.goto(url, wait_until="networkidle", timeout=120000)
    page.wait_for_timeout(3000)

    html = page.content()
    text = page.locator("body").inner_text()

    (OUT / f"{name}.html").write_text(html, encoding="utf-8")
    (OUT / f"{name}.txt").write_text(text, encoding="utf-8")

    links = []
    for a in page.locator("a").all():
        try:
            href = a.get_attribute("href")
            label = (a.inner_text() or "").strip().replace("\n", " ")
        except Exception:
            continue
        if not href:
            continue
        full = urljoin(BASE, href)
        if any(k in (label + " " + full).lower() for k in ["xlsx", "xls", "excel", "ladda", "download", "betyg", "studieresultat", "skolenhet"]):
            links.append((label, full))

    rows = ["label\turl"]
    seen = set()
    for label, full in links:
        key = (label, full)
        if key in seen:
            continue
        seen.add(key)
        rows.append(f"{label}\t{full}")
    (OUT / f"{name}_links.tsv").write_text("\n".join(rows), encoding="utf-8")

    # Spara text runt relevanta ord för felsökning.
    relevant = []
    for line in text.splitlines():
        lo = line.lower()
        if any(k in lo for k in ["xlsx", "excel", "ladda ner", "skolenhet", "betyg", "studieresultat", "behör", "genomström"]):
            relevant.append(line)
    (OUT / f"{name}_relevant.txt").write_text("\n".join(relevant), encoding="utf-8")

with sync_playwright() as p:
    browser = p.chromium.launch(headless=True)
    page = browser.new_page(viewport={"width": 1600, "height": 1200})
    for name, url in URLS.items():
        collect(page, name, url)
    browser.close()
