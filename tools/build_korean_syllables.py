"""Hangul syllable counts from Korean sentences, for the heuristic's Korean model.

usage: python3 build_korean_syllables.py <kor_sentences.tsv> <korean_syllables.txt>
Input: Tatoeba's per-language export (id<TAB>lang<TAB>text). Output: syllable<TAB>count, most
frequent first.
"""
import sys
from collections import Counter

counts = Counter()
for line in open(sys.argv[1], encoding="utf-8"):
    counts.update(ch for ch in line.rstrip("\n").split("\t")[-1] if "가" <= ch <= "힣")
with open(sys.argv[2], "w", encoding="utf-8") as out:
    for syllable, n in counts.most_common():
        out.write(f"{syllable}\t{n}\n")
