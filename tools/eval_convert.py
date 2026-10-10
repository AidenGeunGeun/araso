"""Kanji conversion accuracy on held-out Tatoeba sentences (never used for the kana model).

For each sample the reading comes from the typed romaji (composed by Seamtype) and the
target is the original Japanese text. Reports top-1 exact match and whether the target
is anywhere in the candidate list, for short phrases and whole sentences.

usage: python eval_convert.py <seamtype-cli> <ja_tokens.jsonl> [n]
"""
import hashlib
import json
import random
import subprocess
import sys

from romaji_join import ends_mid_sokuon, typed

cli, path, *rest = sys.argv[1:]
n = int(rest[0]) if rest else 400
bucket_id = int(rest[1]) if len(rest) > 1 else 0          # 0 = eval, 1 = tuning
weights = rest[2].split(",") if len(rest) > 2 else [""]   # rerank weights ("none" = off)


def held_out(text):
    return int(hashlib.sha1(text.encode()).hexdigest(), 16) % 10 == bucket_id


rng = random.Random(5)
sentences = []
for line in open(path, encoding="utf-8"):
    d = json.loads(line)
    if held_out(d["text"]) and not any(t["latin"] for t in d["tokens"]):
        sentences.append(d["tokens"])
rng.shuffle(sentences)

samples = {"phrase": [], "sentence": []}
for tokens in sentences:
    if len(samples["sentence"]) < n and 3 <= len(tokens) <= 12:
        samples["sentence"].append(tokens)
    elif len(samples["phrase"]) < n and len(tokens) >= 3:
        start = rng.randrange(len(tokens) - 1)
        span = tokens[start:start + rng.choice([2, 3])]
        if not ends_mid_sokuon(span):
            samples["phrase"].append(span)
    if all(len(v) >= n for v in samples.values()):
        break


def run(mode, lines, *extra):
    out = subprocess.run([cli, mode, *extra], input="\n".join(lines) + "\n", capture_output=True, text=True, check=True).stdout
    return out.splitlines()  # one line per input, even when empty


for kind, items, weight in [(k, v, w) for k, v in samples.items() for w in weights]:
    romaji = [typed([t["romaji"] for t in toks]) for toks in items]
    targets = ["".join(t["surface"] for t in toks) for toks in items]
    kana = [line.rsplit("\t", 1)[0] for line in run("--kana", romaji)]
    results = run("--convert-all", kana, *([weight] if weight else []))
    top1 = inlist = 0
    misses = []
    for target, line in zip(targets, results):
        cands = line.split("\t")
        if cands and cands[0] == target:
            top1 += 1
        if target in cands:
            inlist += 1
        elif len(misses) < 8:
            misses.append((target, cands[:3]))
    print(f"{kind:9} weight={weight or 'default':7} n={len(items)}  top-1 {top1 / len(items):.1%}  in candidates {inlist / len(items):.1%}")
    for target, cands in misses:
        print(f"    want {target}  got {' | '.join(cands)}")
