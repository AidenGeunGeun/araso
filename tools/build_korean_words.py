"""Korean words with their counts, for the heuristic's Korean model.

usage: python3 build_korean_words.py <kor_sentences.tsv> <korean_words.txt> [min_count=1]
Input: Tatoeba's per-language export (id<TAB>lang<TAB>text). Output: word<TAB>count, the
Hangul runs between spaces and punctuation, most frequent first.
"""
import re
import sys
from collections import Counter

min_count = int(sys.argv[3]) if len(sys.argv) > 3 else 1
counts = Counter()
for line in open(sys.argv[1], encoding="utf-8"):
    counts.update(re.findall(r"[가-힣]+", line.rstrip("\n").split("\t")[-1]))
with open(sys.argv[2], "w", encoding="utf-8") as out:
    for word, n in counts.most_common():
        if n >= min_count:
            out.write(f"{word}\t{n}\n")
