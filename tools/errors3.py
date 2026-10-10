"""List English/Japanese misclassifications: python3 errors3.py <cli> <eval.tsv> [offset] [n]"""
import sys
from eval3 import read_rows, run

cli, path, *rest = sys.argv[1:]
offset = rest[0] if rest else "0.5"
n = int(rest[1]) if len(rest) > 1 else 30
rows = read_rows([path])
out = run(cli, rows, float(offset))
for want, got in (("english", "japanese"), ("japanese", "english")):
    bad = [(k, p, r[3], r[2]) for (k, p, label, _), r in zip(rows, out) if label == want and r[1] == got]
    print(f"\n{want} → {got}: {len(bad)}")
    for keys, prev, output, conf in bad[:n]:
        print(f"  {keys:24} prev={prev or '-':8} → {output}  conf={conf}")
