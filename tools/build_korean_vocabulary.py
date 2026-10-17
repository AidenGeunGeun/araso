"""Korean words (two or more syllables) for splitting English + Korean typed together, and
for the heuristic's Korean word floor.

usage: python3 build_korean_vocabulary.py <ko_full.txt> <korean_vocabulary.txt> [min count=2]
Input: hermitdave/FrequencyWords ko_full (word<SPACE>count). Output: word<TAB>count,
most frequent first; KoreanModel uses the words below 10 only for the heuristic's floor. Wider than korean_words.txt (loanwords like 월드, 서버, 버튼; rarer
nouns like 촉매, seen twice in the subtitles). Words seen once are left out: half the list,
and mostly typos and names, which turned more English keys into Korean (ando, corp, tian).
"""
import re
import sys

min_count = int(sys.argv[3]) if len(sys.argv) > 3 else 2
with open(sys.argv[2], "w", encoding="utf-8") as out:
    for line in open(sys.argv[1], encoding="utf-8"):
        word, count = line.split(" ")
        if re.fullmatch(r"[가-힣]{2,}", word) and int(count) >= min_count:
            out.write(f"{word}\t{int(count)}\n")
