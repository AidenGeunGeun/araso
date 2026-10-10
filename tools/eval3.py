"""Three-way (English / Korean / Japanese) evaluation of the heuristic, sweeping the
Japanese score offset.

usage: python3 eval3.py <seamtype-cli> <eval.tsv> [more.tsv ...] [offset ...]
Rows: keys<TAB>previous<TAB>label<TAB>reading, as tools/make_eval.py writes them (held-out
English/Korean words and Tatoeba phrases).
"""
import subprocess
import sys
from collections import Counter


def run(cli, rows, offset):
    res = subprocess.run([cli, "--decide", "--japanese", str(offset)],
                         input="".join(f"{k}\t{p}\n" for k, p, _, _ in rows),
                         capture_output=True, text=True, check=True)
    return [line.split("\t") for line in res.stdout.splitlines()]


def read_rows(paths):
    return [l.rstrip("\n").split("\t") for p in paths for l in open(p, encoding="utf-8")]


def main():
    cli, *rest = sys.argv[1:]
    rows = read_rows(t for t in rest if t.endswith(".tsv"))
    for offset in [float(o) for o in rest if not o.endswith(".tsv")] or [0.5]:
        out = run(cli, rows, offset)
        confusion = Counter()
        for (keys, _, label, _), r in zip(rows, out):
            got = "korean" if r[1] == "mixed" else r[1]
            confusion[(label, got)] += 1
        totals = Counter(label for _, _, label, _ in rows)
        correct = sum(confusion[(l, l)] for l in totals)
        print(f"\noffset {offset:+.2f}: accuracy {correct / len(rows):.4f}")
        for label in ("english", "korean", "japanese"):
            cells = "  ".join(f"→{g[:2]} {confusion[(label, g)]:5d}" for g in ("english", "korean", "japanese"))
            print(f"  {label:9} (n={totals[label]:5d})  {cells}")


if __name__ == "__main__":
    main()
