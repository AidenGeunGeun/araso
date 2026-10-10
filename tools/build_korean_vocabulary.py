"""Korean words (two or more syllables) for splitting English + Korean typed together.

usage: python3 build_korean_vocabulary.py <ko_50k.txt> <korean_vocabulary.txt>
Input: hermitdave/FrequencyWords ko_50k (word<SPACE>count). Output: one word per line,
most frequent first. Wider than korean_words.txt (loanwords like 월드, 서버, 버튼) and
used only for that split, so the main Korean model keeps its tuned word list.
"""
import re
import sys

with open(sys.argv[2], "w", encoding="utf-8") as out:
    for line in open(sys.argv[1], encoding="utf-8"):
        word = line.split(" ")[0]
        if re.fullmatch(r"[가-힣]{2,}", word):
            out.write(word + "\n")
