"""Build the app's sale file from the database export and the parsed PDF.

    python3 build_sale.py kee_nov_2026/ out.json [--pdf parsed.json]

The database export (hips_*.psv, written by export_hips.sql) gives every
hip's catalog facts, agent score and market numbers. The parsed PDF
(parse_catalog.py) adds black type and produce counts read off each page,
and the page each hip is on.
"""

import glob
import json
import os
import re
import sys

COLUMNS = [
    "hip", "book", "session", "name", "sire", "dam", "damsire", "sex", "crop", "foalingDate",
    "consignor", "soldAs", "coveringSire", "bcEligible", "agentScore", "agentTier",
    "femaleLineScore", "sirePctStakesWinners", "sireGradedWinners", "sireFee", "bandQ1",
    "bandMedian", "bandQ3", "bandCount", "bandYear", "coverBandMedian", "coverBandCount",
    "produceSold", "produceMedian",
]
INTS = {"hip", "book", "session", "crop", "sireGradedWinners", "bandCount", "bandYear",
        "coverBandCount", "produceSold"}
FLOATS = {"agentScore", "femaleLineScore", "sirePctStakesWinners", "sireFee", "bandQ1",
          "bandMedian", "bandQ3", "coverBandMedian", "produceMedian"}


def read_export(folder):
    hips = {}
    for path in sorted(glob.glob(os.path.join(folder, "hips_*.psv"))):
        with open(path, encoding="utf-8") as f:
            for line in f.read().split("\n"):
                if not line:
                    continue
                values = line.split("|")
                if len(values) != len(COLUMNS):
                    raise ValueError(f"{path}: expected {len(COLUMNS)} fields, got {len(values)}: {line[:60]}")
                record = {}
                for key, value in zip(COLUMNS, values):
                    if value == "":
                        continue
                    if key in INTS:
                        record[key] = int(float(value))
                    elif key in FLOATS:
                        record[key] = float(value)
                    elif key == "bcEligible":
                        record[key] = value == "1"
                    else:
                        record[key] = value
                hips[record["hip"]] = record
    return hips


def name_key(name):
    """Upper case, letters and digits only, so 'Always At Ease' matches 'ALWAYS AT EASE'."""
    return re.sub(r"[^A-Z0-9]", "", (name or "").upper())


def add_page_numbers(record, page):
    """Copy the parsed page's counts onto the hip record."""
    record["pdfPageIndex"] = page["page_index"]
    sire = page.get("sire", {})
    for src, dst in (("crops", "sireCrops"), ("foals", "sireFoals"), ("starters", "sireStarters"),
                     ("black_type_winners", "sireBlackTypeWinners"), ("winners", "sireWinners")):
        if src in sire:
            record[dst] = sire[src]
    if sire.get("first_crop"):
        record["sireFirstCrop"] = True
    dam1 = page.get("dam1")
    if dam1:
        for src, dst in (("foals", "damFoals"), ("to_race", "damRunners"), ("winners", "damWinners")):
            if src in dam1:
                record[dst] = dam1[src]
        record["damBlackType"] = dam1.get("dam_black_type")
        record["damStakesWinners"] = dam1["produce"]["stakes_winners"]
        record["damStakesPlaced"] = dam1["produce"]["stakes_placed"]
        record["familyStakesWinners"] = dam1["family"]["stakes_winners"]
        record["familyStakesPlaced"] = dam1["family"]["stakes_placed"]
        record["familyGraded"] = dam1["family"]["graded"]
        record["familyG1"] = dam1["family"]["g1"]
    for key, dst in (("dam2", "secondDamStakesWinners"), ("dam3", "thirdDamStakesWinners")):
        if key in page:
            record[dst] = page[key]["family"]["stakes_winners"]
    if "own_produce" in page:
        record["ownProduceStakesWinners"] = page["own_produce"]["stakes_winners"]
        record["ownProduceStakesPlaced"] = page["own_produce"]["stakes_placed"]
    if "race_record" in page and "earned" in page["race_record"]:
        record["earned"] = page["race_record"]["earned"]
    if "mating" in page:
        record["pregnant"] = page["mating"]["pregnant"]


def main():
    folder, out = sys.argv[1], sys.argv[2]
    hips = read_export(folder)
    matched = 0
    if "--pdf" in sys.argv:
        with open(sys.argv[sys.argv.index("--pdf") + 1]) as f:
            pages = {p["hip"]: p for p in json.load(f)["hips"]}
        mismatched = []
        for number, record in hips.items():
            page = pages.get(number)
            if page is None:
                continue
            # Only trust a page whose dam is this hip's dam.
            if name_key(page.get("dam1", {}).get("name")) != name_key(record["dam"]):
                mismatched.append((number, record["dam"], page.get("dam1", {}).get("name")))
                continue
            add_page_numbers(record, page)
            matched += 1
        missing = sorted(set(hips) - set(pages))
        print(f"{len(mismatched)} dam-name mismatches (page data not used): {mismatched[:10]}")
        print(f"{len(missing)} hips with no page: {missing[:20]}")
    sale = {
        "saleId": "KEE_FILE_133",
        "name": "Keeneland November 2026",
        "house": "Keeneland",
        "hips": [hips[k] for k in sorted(hips)],
    }
    with open(out, "w", encoding="utf-8") as f:
        json.dump(sale, f, ensure_ascii=False, separators=(",", ":"))
    print(f"{len(hips)} hips written, {matched} matched to PDF pages")


if __name__ == "__main__":
    main()
