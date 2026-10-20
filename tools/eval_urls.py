"""Segments of URLs and paths, typed through a real session (araso-cli --type): how many go
in as something other than what was typed (docs/url-run.md).

Each template's {} is a segment: one of the top 5,000 en_50k words of 2–8 letters, or one of all
676 two-letter combinations (query keys, IDs, short paths: not words). A line counts as wrong when
the field doesn't end up with exactly the keys, with Japanese off and on.

usage: python3 eval_urls.py <araso-cli> <en_50k.txt> [failures per row]
"""
import itertools
import re
import subprocess
import sys

TEMPLATES = [
    ("after a marker: path", "https://example.com/{}"),
    ("after a marker: query", "https://a.io/?q={}"),
    ("after a marker: home path", "cd ~/{}"),
    ("no marker: branch", "git checkout fix/{}"),
    ("before a marker: domain", "{}.com"),
    ("before a marker: email", "{}@gmail.com"),
]


def english_words(path, n=5000):
    words = []
    for line in open(path, encoding="utf-8"):
        w = line.split()[0]
        if re.fullmatch(r"[a-z]{2,8}", w):
            words.append(w)
            if len(words) == n:
                break
    return words


def typed(cli, lines, japanese):
    res = subprocess.run([cli, "--type", *(["--japanese"] if japanese else [])], input="".join(k + "\n" for k in lines),
                         capture_output=True, text=True, check=True)
    return dict(line.split("\t", 1) for line in res.stdout.splitlines())


def main():
    cli, path, *rest = sys.argv[1:]
    shown = int(rest[0]) if rest else 6
    segments = {"English words": english_words(path),
                "two letters": ["".join(p) for p in itertools.product("abcdefghijklmnopqrstuvwxyz", repeat=2)]}
    lines = sorted({t.format(s) for _, t in TEMPLATES for group in segments.values() for s in group})
    outputs = {ja: typed(cli, lines, ja) for ja in (False, True)}
    header = "".join(f" | {g} (off / on)" for g in segments)
    print(f"| template{header} |\n|---" + "|---" * len(segments) + "|")
    failures = []
    for name, template in TEMPLATES:
        cells = []
        for group, words in segments.items():
            wrong = {ja: [] for ja in (False, True)}
            for s in words:
                keys = template.format(s)
                for ja in (False, True):
                    got = outputs[ja][keys].rstrip(" ")
                    if got != keys:
                        wrong[ja].append(f"{keys}→{got}")
            cells.append(f"{len(wrong[False])} / {len(wrong[True])}")
            for ja in (False, True):
                if wrong[ja]:
                    failures.append(f"{name}, {group}, ja {'on' if ja else 'off'}: " + "  ".join(wrong[ja][:shown]))
        print(f"| `{template}` {name} | " + " | ".join(cells) + " |")
    print("\n" + "\n".join(failures))


if __name__ == "__main__":
    main()
