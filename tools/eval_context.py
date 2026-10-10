"""How often the most frequent words come out wrong, by what came before them.

The held-out set (make_eval.py) counts each word once and rarely puts it after the other
language. Real text is the opposite: the top words make up most of it, and switching
language mid-sentence is the point. This scores the top N English and Korean words (by
frequency rank) after: nothing, the same language, the other language, and Japanese.

usage: python3 eval_context.py <seamtype-cli> <ko_50k.txt> <en_50k.txt> [N=10000] [--list]
Prints wrong counts within the top 1k and top N; --list also prints the worst words.
"""
import subprocess
import sys

from make_eval import ENGLISH_WORD, HANGUL_WORD, keys_for


def top_words(path, pattern, n):
    words = []
    for line in open(path, encoding="utf-8"):
        parts = line.split()
        if len(parts) == 2 and pattern.match(parts[0]):
            words.append(parts[0])
            if len(words) >= n:
                break
    return words


def decide(cli, keys, previous):
    out = subprocess.run([cli, "--decide", "--japanese", "0.5"],
                         input="".join(f"{k}\t{previous}\n" for k in keys),
                         capture_output=True, text=True, check=True).stdout.splitlines()
    return [line.split("\t") for line in out]


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    cli, ko_path, en_path = args[:3]
    n = int(args[3]) if len(args) > 3 else 10000
    show = "--list" in sys.argv
    sets = {
        "korean": [(keys_for(w), w) for w in top_words(ko_path, HANGUL_WORD, n)],
        "english": [(w, w) for w in top_words(en_path, ENGLISH_WORD, n)],
    }
    other = {"korean": "english", "english": "korean"}
    total_1k = total_n = 0
    for label, words in sets.items():
        for previous in ("", label, other[label], "japanese"):
            rows = decide(cli, [k for k, _ in words], previous)
            wrong = [(rank + 1, words[rank][1], r[1], r[3]) for rank, r in enumerate(rows)
                     if ("korean" if r[1] == "mixed" else r[1]) != label]
            in_1k = sum(rank <= 1000 for rank, *_ in wrong)
            total_1k += in_1k
            total_n += len(wrong)
            print(f"{label:8} after {previous or 'nothing':9} wrong: top1k {in_1k:4d}   top{n // 1000}k {len(wrong):5d}")
            if show:
                print("    " + ", ".join(f"{w}#{rank}→{out}" for rank, w, _, out in wrong[:20]))
    print(f"total wrong: top1k {total_1k}, top{n // 1000}k {total_n}")


if __name__ == "__main__":
    main()
