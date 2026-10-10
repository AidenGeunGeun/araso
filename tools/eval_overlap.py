"""Words that are both English and Japanese romaji, typed right after Japanese text.

Japanese side: the most frequent Tatoeba tokens (3+ letters) whose romaji is also an English
word — made, tame, dare, kite, sore, kore, mono — should stay Japanese after Japanese.
English side: the most frequent English words whose romaji is clean kana — you, sense,
machine, demo — are what English writers type there. Both counts are reported, so a change
that rescues English words can be weighed against the Japanese words it breaks.

usage: python3 eval_overlap.py <seamtype-cli> <ja_tokens.jsonl> <en_50k.txt> [n=300]
"""
import json
import re
import subprocess
import sys
from collections import Counter

cli, tokens_path, en_path = sys.argv[1:4]
n = int(sys.argv[4]) if len(sys.argv) > 4 else 300

english = []
for line in open(en_path, encoding="utf-8"):
    parts = line.split()
    if len(parts) == 2 and re.fullmatch(r"[a-z]+", parts[0]):
        english.append(parts[0])
english_set = set(english[:20000])

ja = Counter()
for line in open(tokens_path, encoding="utf-8"):
    for t in json.loads(line)["tokens"]:
        r = t["romaji"]
        if not t["latin"] and len(r) >= 3 and r.isalpha() and r in english_set:
            ja[r] += 1
ja_words = [w for w, _ in ja.most_common(n)]


def decide(keys):
    out = subprocess.run([cli, "--decide", "--japanese", "0.5"], input="".join(f"{k}\tjapanese\n" for k in keys),
                         capture_output=True, text=True, check=True).stdout.splitlines()
    return [line.split("\t") for line in out]


clean = subprocess.run([cli, "--kana"], input="\n".join(english[:5000]) + "\n",
                       capture_output=True, text=True, check=True).stdout.splitlines()
en_words = [w for w, k in zip(english[:5000], clean) if k.endswith("\t0")][:n]

ja_wrong = [(w, r[3]) for w, r in zip(ja_words, decide(ja_words)) if r[1] != "japanese"]
en_wrong = [(w, r[3]) for w, r in zip(en_words, decide(en_words)) if r[1] != "english"]
print(f"after Japanese: Japanese words left as English {len(ja_wrong)}/{len(ja_words)}, "
      f"English words turned Japanese {len(en_wrong)}/{len(en_words)}")
if "--list" in sys.argv:
    print("  ja→en:", ", ".join(w for w, _ in ja_wrong[:30]))
    print("  en→ja:", ", ".join(f"{w}→{o}" for w, o in en_wrong[:30]))
