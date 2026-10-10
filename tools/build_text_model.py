"""Character n-gram model over written Japanese (kanji + kana), used to rerank kanji
conversion candidates. Trained on Tatoeba sentences (CC-BY 2.0 FR) whose text hash
is not 0 (held-out eval) or 1 (tuning).

usage: python build_text_model.py <ja_tokens.jsonl> <out.txt> [min_count]
out lines: <a><b><c>\t<count>  (^ start, $ end)
"""
import hashlib
import json
import sys
from collections import Counter

path, out_path, *rest = sys.argv[1:]
min_count = int(rest[0]) if rest else 3


def bucket(text):
    return int(hashlib.sha1(text.encode()).hexdigest(), 16) % 10


counts = Counter()
n = 0
for line in open(path, encoding="utf-8"):
    d = json.loads(line)
    if bucket(d["text"]) in (0, 1):
        continue
    text = "".join(t["surface"] for t in d["tokens"])
    seq = ["^", "^", *text, "$"]
    for i in range(2, len(seq)):
        counts[seq[i - 2] + seq[i - 1] + seq[i]] += 1
    n += 1

kept = 0
with open(out_path, "w", encoding="utf-8") as f:
    for tri, c in sorted(counts.items()):
        if c >= min_count:
            f.write(f"{tri}\t{c}\n")
            kept += 1
print(f"sentences={n} trigrams={len(counts)} kept(>= {min_count})={kept}")
