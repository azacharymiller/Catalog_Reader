"""Turn a US sale catalog PDF (one hip per page) into numbers.

Reads the fonts as well as the words. US catalogs print stakes winners in
BOLD CAPITALS and stakes-placed horses in Bold Upper And Lower Case, so
black type is counted from the type itself, not guessed from the text.

    python3 parse_catalog.py catalog.pdf out.json [--pages 1-50]

Output: one record per page with the hip number and the counts below.
Tested against the Keeneland November catalog layout.
"""

import json
import re
import sys

import pdfplumber

GRADE = re.compile(r"\[G([123])\]")
DAM_OF = re.compile(
    r"Dam of (?:(\d+) (?:other )?registered foals?|(\d+) (?:other )?foals?)"
    r"(?:, (\d+) of racing age)?(?:, (\d+) to race)?(?:, (\d+) winners?)?"
)
SIRE_STATS = {
    "crops": re.compile(r"sire of (\d+) crops?", re.IGNORECASE),
    "foals": re.compile(r"(\d+) foals"),
    "starters": re.compile(r"(\d+) starters"),
    "black_type_winners": re.compile(r"(\d+) black-?\s?type winners"),
    "champions": re.compile(r"(\d+) champions?"),
    "winners": re.compile(r"(\d+) winners of"),
}
SECTION_HEADS = ("1st dam", "2nd dam", "3rd dam", "4th dam")
NOT_A_HORSE = {"PREGNANT", "BARREN", "SLIPPED", "NOT", "MATED", "By"}


def is_bold(word):
    return "Bold" in word["fontname"]


def page_lines(words):
    """Words grouped into reading lines. Bold words sit ~2pt off the
    plain text's baseline, so lines merge within a 4pt tolerance."""
    words = sorted(words, key=lambda w: w["top"])
    lines, current, top = [], [], None
    for w in words:
        if top is not None and w["top"] - top > 4:
            lines.append(sorted(current, key=lambda x: x["x0"]))
            current = []
        if not current:
            top = w["top"]
        current.append(w)
    if current:
        lines.append(sorted(current, key=lambda x: x["x0"]))
    return lines


def number_under(words, label):
    """The bold number printed directly below a header label ("Hip" or "Barn").
    The labels swap sides on facing pages, so match by position."""
    for w in words:
        if w["text"] == label and "Arial" in w["fontname"] and w["top"] < 80:
            nums = [x for x in words
                    if re.fullmatch(r"\d+[A-Z]?", x["text"]) and "Arial" in x["fontname"]
                    and 0 < x["top"] - w["top"] < 25 and abs(x["x0"] - w["x0"]) < 45]
            if nums:
                return min(nums, key=lambda x: abs(x["x0"] - w["x0"]))["text"]
    return None


def split_sections(lines):
    """Map section name → list of lines. Sections: header, sire, 1st..4th dam,
    race record, produce record, mating."""
    sections = {"header": []}
    name = "header"
    for line in lines:
        first = line[0]
        text = " ".join(w["text"] for w in line)
        head = next((h for h in SECTION_HEADS if text.startswith(h) and is_bold(first)), None)
        if head:
            name = head
        elif is_bold(first) and first["text"] == "By":
            name = "sire"
        elif text.startswith("RACE RECORD"):
            name = "race record"
        elif text.startswith("PRODUCE RECORD"):
            name = "produce record"
        elif text.startswith("Mated to") or text.startswith("Last mated"):
            name = "mating"
        sections.setdefault(name, []).append(line)
    return sections


def text_of(lines):
    text = " ".join(" ".join(w["text"] for w in line) for line in lines)
    return re.sub(r"(\w)- (\w)", r"\1\2", text)  # rejoin hyphenated line breaks


def black_type(lines):
    """Bold runs in reading order → horses. Each horse: name, stakes winner
    (all capitals) or placed, grades from the bold grade tags after it, and
    whether it opens its line (and at what indent) so a dam's own produce
    can be told from grand-produce. A name that wraps onto the next line
    stays one name."""
    horses, run, run_opens_line = [], [], False

    def flush():
        nonlocal run
        if not run:
            return
        name = " ".join(x["text"] for x in run)
        grades = [int(g) for g in GRADE.findall(name)]
        name = GRADE.sub("", name).strip(" ,.")
        letters = [c for c in name if c.isalpha()]
        if letters and name not in NOT_A_HORSE and not any(name.startswith(h) for h in SECTION_HEADS):
            horses.append({
                "name": name,
                "winner": all(c.isupper() for c in letters),
                "grades": grades,
                "starts_line": run_opens_line,
                "x": run[0]["x0"],
            })
        run = []

    for line in lines:
        # A run that reached the end of the previous line continues only if
        # this line opens in bold.
        if run and not is_bold(line[0]):
            flush()
        for i, w in enumerate(line):
            grade = GRADE.fullmatch(w["text"])
            if is_bold(w) and not grade:
                if not run:
                    run_opens_line = i == 0
                run.append(w)
                continue
            flush()
            if is_bold(w) and grade and horses:
                horses[-1]["grades"].append(int(grade.group(1)))
        if run and run[-1] is not line[-1]:
            flush()
    flush()
    return horses


def summarize(horses):
    winners = [h for h in horses if h["winner"]]
    return {
        "stakes_winners": len(winners),
        "stakes_placed": len(horses) - len(winners),
        # Stakes winners whose entry names a graded race. The race may be a
        # placing rather than the win, so read this as "graded-level".
        "graded": sum(1 for h in winners if h["grades"]),
        "g1": sum(1 for h in winners if 1 in h["grades"]),
        "names": [h["name"] for h in horses],
    }


def dam_section(lines):
    if not lines:
        return None
    text = text_of(lines)
    out = {}
    m = DAM_OF.search(text)
    if m is None and "This is her first foal" in text:
        out["foals"] = 1
    if m:
        out["foals"] = int(m.group(1) or m.group(2))
        for key, group in (("racing_age", 3), ("to_race", 4), ("winners", 5)):
            if m.group(group):
                out[key] = int(m.group(group))
    # Drop the "1st dam" heading; it may share a line with the dam's name.
    head = lines[0][2:] if lines[0][0]["text"] in ("1st", "2nd", "3rd", "4th") else lines[0]
    lines = ([head] if head else []) + lines[1:]
    if not lines:
        return out
    # The dam's name opens the section, up to ", by" (kept for cross-checks).
    name = re.split(r"\s*,\s*by\b", text_of([lines[0]]))[0]
    out["name"] = re.sub(r"\s+", " ", name).strip()
    # Her name is bold only if she earned black type.
    horses = black_type(lines)
    own = lines[0][0]
    out["dam_black_type"] = None
    if is_bold(own) and horses and horses[0]["x"] == own["x0"]:
        out["dam_black_type"] = "winner" if horses[0]["winner"] else "placed"
        horses = horses[1:]
    # Direct produce start their own line at the shallowest entry indent.
    entry_x = min((l[0]["x0"] for l in lines[1:] if re.match(r"\S.*\((?:c|f|g|r|h)\. by", text_of([l]))),
                  default=None)
    direct = [h for h in horses if entry_x is not None and h["starts_line"] and abs(h["x"] - entry_x) < 3]
    out["produce"] = summarize(direct)
    out["family"] = summarize(horses)
    return out


def sire_section(lines):
    text = text_of(lines)
    # Figures after "Son of ..." belong to the sire's sire, and "Sire of dams
    # of ..." counts his daughters' foals; keep only the sire's own record.
    own = re.split(r"\bSon of\b|\bSire of dams of\b", text)[0]
    out = {}
    for key, pattern in SIRE_STATS.items():
        m = pattern.search(own)
        if m:
            out[key] = int(m.group(1))
    if re.search(r"first foals are (?:weanlings|yearlings|two-year-olds|2-?\s?year-?\s?olds)", text, re.IGNORECASE):
        out["first_crop"] = True
    return out


def parse_page(page):
    words = page.extract_words(extra_attrs=["fontname", "size"])
    lines = page_lines(words)
    if not lines:
        return None
    hip = number_under(words, "Hip")
    if hip is None:
        return None
    sections = split_sections(lines)
    # Supplementary hips are numbered like "224A".
    record = {"hip": int(hip) if hip.isdigit() else hip, "barn": number_under(words, "Barn"), "page_index": page.page_number - 1}
    record["sire"] = sire_section(sections.get("sire", []))
    for key, name in (("dam1", "1st dam"), ("dam2", "2nd dam"), ("dam3", "3rd dam")):
        section = dam_section(sections.get(name, []))
        if section:
            record[key] = section
    if "race record" in sections:
        text = text_of(sections["race record"])
        earned = re.search(r"Earned \$([\d,]+)", text)
        record["race_record"] = {"text": text.removeprefix("RACE RECORD:").strip()}
        if earned:
            record["race_record"]["earned"] = int(earned.group(1).replace(",", ""))
    if "produce record" in sections:
        record["own_produce"] = summarize(black_type(sections["produce record"]))
    if "mating" in sections:
        text = text_of(sections["mating"])
        mated = re.search(r"Mated to ([^(]+?)\s*\(", text)
        record["mating"] = {
            "covering_sire": mated.group(1).strip() if mated else None,
            "pregnant": "PREGNANT" in text,
            "text": text,
        }
    return record


def main():
    src, dst = sys.argv[1], sys.argv[2]
    first, last = 1, None
    if "--pages" in sys.argv:
        a, b = sys.argv[sys.argv.index("--pages") + 1].split("-")
        first, last = int(a), int(b)
    records, failed = [], []
    with pdfplumber.open(src) as pdf:
        pages = pdf.pages[first - 1 : last]
        for page in pages:
            try:
                record = parse_page(page)
            except Exception as error:  # one bad page must not stop the book
                failed.append({"page": page.page_number, "error": str(error)})
                continue
            if record:
                records.append(record)
            else:
                failed.append({"page": page.page_number, "error": "no hip number"})
            page.flush_cache()
    with open(dst, "w") as f:
        json.dump({"hips": records, "failed_pages": failed}, f, indent=1)
    print(f"{len(records)} hips, {len(failed)} pages without a hip")


if __name__ == "__main__":
    main()
