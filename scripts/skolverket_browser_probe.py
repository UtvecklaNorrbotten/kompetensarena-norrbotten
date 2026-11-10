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

def collect_download_search(page, name, school_label, area_keywords):
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
    page.wait_for_timeout(1500)

    # Choose search type D: all schools/municipalities/providers.
    page.locator("#IDSokD").check()
    page.wait_for_timeout(2000)
    dump_selects(page, name + "_after_D")

    # The D form uses numeric school-form codes. Select by visible label to avoid hard-coding.
    selects = page.locator("select")
    school_select = None
    for sel in selects.all():
        labels = [(o.inner_text() or "").strip() for o in sel.locator("option").all()]
        if school_label in labels:
            school_select = sel
            break
    if school_select is None:
        raise RuntimeError(f"Could not find school-type select for {school_label}")
    school_select.select_option(label=school_label)
    page.wait_for_timeout(2500)
    dump_selects(page, name + "_after_school")

    # Select the statistics area by matching text.
    area_select = None
    chosen_area = None
    for sel in page.locator("select").all():
        opts = [(o.get_attribute("value") or "", (o.inner_text() or "").strip()) for o in sel.locator("option").all()]
        for value, label in opts:
            lo = label.lower()
            if all(k.lower() in lo for k in area_keywords):
                area_select = sel
                chosen_area = (value, label)
                break
        if area_select is not None:
            break
    if area_select is None:
        raise RuntimeError(f"Could not find area matching {area_keywords}")
    area_select.select_option(value=chosen_area[0])
    page.wait_for_timeout(2500)
    dump_selects(page, name + "_after_area")

    # Choose latest available year/period from a select that looks like years.
    year_select = None
    year_value = None
    for sel in page.locator("select").all():
        opts = [(o.get_attribute("value") or "", (o.inner_text() or "").strip()) for o in sel.locator("option").all()]
        yearish = [(v,l) for v,l in opts if any(ch.isdigit() for ch in l) and len(l) <= 12]
        if yearish:
            # Prefer 2025/26, then 2025, otherwise first populated option.
            preferred = [x for x in yearish if x[1] in ("2025/26", "2025")]
            cand = preferred[0] if preferred else yearish[0]
            year_select = sel
            year_value = cand[0]
            break
    if year_select is not None and year_value:
        year_select.select_option(value=year_value)
        page.wait_for_timeout(1000)

    # Submit the visible D form.
    page.locator("#statistics-search-submit-button").click()
    page.wait_for_timeout(5000)

    (OUT / f"{name}.html").write_text(page.content(), encoding="utf-8")
    (OUT / f"{name}.txt").write_text(page.locator("body").inner_text(), encoding="utf-8")

    links = []
    for a in page.locator("a").all():
        href = a.get_attribute("href")
        if not href:
            continue
        label = (a.inner_text() or "").strip().replace("\n", " ")
        full = urljoin(BASE, href)
        if any(k in (label + " " + full).lower() for k in ["xlsx","xls","csv","xml","ladda","download"]):
            links.append((label, full))
    (OUT / f"{name}_links.tsv").write_text(
        "label\turl\n" + "\n".join(f"{a}\t{b}" for a,b in dict.fromkeys(links)),
        encoding="utf-8"
    )

    net_lines = ["status\turl\tbody"]
    for status, url, body in network:
        body_clean = body.replace("\t"," ").replace("\r"," ").replace("\n"," ")
        net_lines.append(f"{status}\t{url}\t{body_clean}")
    (OUT / f"{name}_network.tsv").write_text("\n".join(net_lines), encoding="utf-8")

with sync_playwright() as p:
    browser = p.chromium.launch(headless=True)
    page = browser.new_page(viewport={"width": 1600, "height": 1400})

    collect_download_search(page, "gr9", "Grundskola och sameskola", ["betyg", "9"])

    # New page avoids event-listener overlap and stale form state.
    page.close()
    page = browser.new_page(viewport={"width": 1600, "height": 1400})
    collect_download_search(page, "gy", "Gymnasieskola", ["betyg", "studie"])

    browser.close()
