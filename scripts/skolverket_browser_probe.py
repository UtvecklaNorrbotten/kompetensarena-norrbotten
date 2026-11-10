from pathlib import Path
from urllib.parse import urljoin
from playwright.sync_api import sync_playwright

BASE = "https://www.skolverket.se"
PAGE_URL = BASE + "/statistik-och-utvarderingar/statistik-om-forskola-och-skola/sok-statistik-om-forskola-skola-och-vuxenutbildning"
OUT = Path("artifacts/skolverket_browser_probe")
OUT.mkdir(parents=True, exist_ok=True)

def dump_selects(page, name):
    lines = []
    for sel in page.locator("select").all():
        sid = sel.get_attribute("id") or ""
        sname = sel.get_attribute("name") or ""
        lines.append(f"SELECT\t{sid}\t{sname}")
        for opt in sel.locator("option").all():
            lines.append(f"OPTION\t{sid}\t{opt.get_attribute('value') or ''}\t{(opt.inner_text() or '').strip()}")
    (OUT / f"{name}_selects.tsv").write_text("\n".join(lines), encoding="utf-8")

def collect_download_search(page, name, school_code, area_keywords):
    network = []

    def on_response(resp):
        if "siris.skolverket.se/siris/reports" in resp.url:
            try:
                body = resp.text()
            except Exception:
                body = ""
            network.append((resp.status, resp.url, body))

    page.on("response", on_response)
    page.goto(PAGE_URL, wait_until="networkidle", timeout=120000)
    page.wait_for_timeout(1000)

    cookie_button = page.get_by_role("button", name="Godkänn nödvändiga kakor")
    if cookie_button.count() > 0:
        try:
            cookie_button.click(timeout=5000)
            page.wait_for_timeout(500)
        except Exception:
            pass

    page.locator("#IDSokD").check(force=True)

    # D-läget använder skolformskoder 11=grundskola, 21=gymnasium.
    page.wait_for_selector("#SOK_D_VERKFORM", timeout=15000)
    page.locator("#SOK_D_VERKFORM").select_option(value=school_code)
    page.wait_for_timeout(1500)

    # Level must be chosen before the statistics areas are populated.
    page.locator("#SOK_D_NIVA").select_option(value="S")
    page.wait_for_timeout(2500)
    dump_selects(page, name + "_after_school")

    area = page.locator("#SOK_D_OMRADE")
    area.wait_for(timeout=15000)

    chosen_area = None
    for opt in area.locator("option").all():
        value = opt.get_attribute("value") or ""
        label = (opt.inner_text() or "").strip()
        lo = label.lower()
        if all(k.lower() in lo for k in area_keywords):
            chosen_area = (value, label)
            break

    if chosen_area is None:
        # Spara diagnostik men misslyckas så att vi inte råkar godkänna fel område.
        (OUT / f"{name}_error.txt").write_text(
            "No matching area. Keywords=" + ",".join(area_keywords),
            encoding="utf-8",
        )
        raise RuntimeError(f"Could not find area matching {area_keywords}")

    area.select_option(value=chosen_area[0])
    page.wait_for_timeout(2500)
    dump_selects(page, name + "_after_area")

    export_sel = page.locator("#SOK_D_EXPORT")
    export_options = [(o.get_attribute("value") or "", (o.inner_text() or "").strip()) for o in export_sel.locator("option").all()]
    csv_options = [x for x in export_options if "csv" in x[1].lower()]
    if csv_options:
        export_sel.select_option(value=csv_options[0][0])
    elif any(v for v, _ in export_options):
        export_sel.select_option(value=next(v for v, _ in export_options if v))
    page.wait_for_timeout(500)

    year = page.locator("#SOK_D_AR")
    year.wait_for(timeout=15000)
    options = [(o.get_attribute("value") or "", (o.inner_text() or "").strip()) for o in year.locator("option").all()]

    preferred = [x for x in options if x[1] in ("2025/26", "2025")]
    usable = [x for x in options if x[0] and any(ch.isdigit() for ch in x[1])]
    chosen_year = preferred[0] if preferred else (usable[0] if usable else None)

    if chosen_year is None:
        raise RuntimeError("No year option found")

    year.select_option(value=chosen_year[0])
    page.wait_for_timeout(500)

    page.locator("#statistics-search-submit-button").click()
    page.wait_for_timeout(5000)

    (OUT / f"{name}.html").write_text(page.content(), encoding="utf-8")
    (OUT / f"{name}.txt").write_text(page.locator("body").inner_text(), encoding="utf-8")
    dump_selects(page, name + "_result")

    links = []
    for a in page.locator("a").all():
        href = a.get_attribute("href")
        if not href:
            continue
        label = (a.inner_text() or "").strip().replace("\n", " ")
        full = urljoin(BASE, href)
        if any(k in (label + " " + full).lower() for k in ["xlsx", "xls", "csv", "xml", "ladda", "download"]):
            links.append((label, full))

    (OUT / f"{name}_links.tsv").write_text(
        "label\turl\n" + "\n".join(f"{a}\t{b}" for a, b in dict.fromkeys(links)),
        encoding="utf-8",
    )

    net_lines = ["status\turl\tbody"]
    for status, url, body in network:
        body_clean = body.replace("\t", " ").replace("\r", " ").replace("\n", " ")
        net_lines.append(f"{status}\t{url}\t{body_clean}")
    (OUT / f"{name}_network.tsv").write_text("\n".join(net_lines), encoding="utf-8")

with sync_playwright() as p:
    browser = p.chromium.launch(headless=True)

    page = browser.new_page(viewport={"width": 1600, "height": 1400})
    collect_download_search(page, "gr9", "11", ["betyg", "9"])
    page.close()

    page = browser.new_page(viewport={"width": 1600, "height": 1400})
    collect_download_search(page, "gy", "21", ["betyg", "studie"])
    page.close()

    browser.close()
