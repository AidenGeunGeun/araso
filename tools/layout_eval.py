"""Rewrites eval.tsv for another English layout: Korean rows are typed on the same keys, so their
keys become that layout's letters; English and Japanese rows are the same letters on any layout.
Run eval3.py on the output with ARASO_LAYOUT set (docs/keyboard-layouts.md).

usage: python3 layout_eval.py colemak|colemakDH < eval.tsv > eval-colemak.tsv
"""
import sys

QWERTY = ["qwertyuiop", "asdfghjkl;", "zxcvbnm"]
LAYOUTS = {
    "colemak": ["qwfpgjluy;", "arstdhneio", "zxcvbkm"],
    "colemakDH": ["qwfpbjluy;", "arstgmneio", "zxcdvkh"],
}


def shift(c):
    return ":" if c == ";" else c.upper()


def table(rows):
    t = {}
    for q, l in zip(QWERTY, rows):
        for a, b in zip(q, l):
            t[a] = b
            t[shift(a)] = shift(b)
    return t


def main():
    t = table(LAYOUTS[sys.argv[1]])
    for line in sys.stdin:
        keys, prev, label, reading = line.rstrip("\n").split("\t")
        if label == "korean":
            keys = "".join(t.get(c, c) for c in keys)
        print("\t".join([keys, prev, label, reading]))


if __name__ == "__main__":
    main()
