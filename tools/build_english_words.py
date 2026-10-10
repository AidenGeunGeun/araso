"""English words with how common they are, for the heuristic's English model.

From SCOWL (Spell Checker Oriented Word Lists, http://wordlist.aspell.net, permissive
license; see scripts/third-party/scowl-Copyright): the size of the smallest list a word
appears in, 10 (the most common) to 60. Words of letters and apostrophes, lowercased; names
and capitalized words (jane, american) are in, abbreviations are left out.

usage: python3 build_english_words.py <scowl>/final <out.txt> [max_level=60]
Output: word<TAB>level, sorted by level then word.
"""
import re
import sys
from pathlib import Path

final, out_path = Path(sys.argv[1]), sys.argv[2]
max_level = int(sys.argv[3]) if len(sys.argv) > 3 else 60
WORD = re.compile(r"^[A-Za-z][a-z']*$")
level: dict[str, int] = {}
for path in final.iterdir():
    m = re.match(r"^(english|american)-(words|contractions|upper|proper-names)\.(\d+)$", path.name)
    if not m or int(m.group(3)) > max_level:
        continue
    for line in path.read_text(encoding="latin-1").splitlines():
        w = line.strip()
        if WORD.match(w):
            w = w.lower()
            level[w] = min(level.get(w, 99), int(m.group(3)))
with open(out_path, "w", encoding="utf-8") as out:
    for w, lv in sorted(level.items(), key=lambda kv: (kv[1], kv[0])):
        out.write(f"{w}\t{lv}\n")
print(f"{len(level)} words")
