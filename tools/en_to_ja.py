"""How many frequent English words turn into kana, by frequency band.
usage: python en_to_ja.py <cli> <en_50k.txt> [offset]"""
import subprocess
import sys

cli, path, *rest = sys.argv[1:]
offset = rest[0] if rest else "0.5"
words = [l.split()[0] for l in open(path, encoding="utf-8")]
words = [w for w in words if w.isascii() and w.isalpha() and w.islower()][:30000]
for prev in ("", "english", "korean", "japanese"):
    out = subprocess.run([cli, "--decide", "--japanese", offset], input="".join(f"{w}\t{prev}\n" for w in words),
                         capture_output=True, text=True, check=True).stdout.splitlines()
    langs = [l.split("\t")[1] for l in out]
    print(f"previous={prev or 'none'}")
    for lo, hi in ((0, 1000), (1000, 5000), (5000, 30000)):
        band = [(w, l) for w, l in zip(words[lo:hi], langs[lo:hi])]
        ja = [w for w, l in band if l == "japanese"]
        print(f"  top {lo:>5}-{hi:<5}: {len(ja):4d} → kana ({len(ja) / len(band):.2%})  e.g. {' '.join(ja[:12])}")
