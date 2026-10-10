"""Build the kana trigram model Seamtype uses to judge how Japanese a romaji string reads,
and a held-out set of Japanese phrases for evaluation.

Input is ja_tokens.jsonl from tools/ja_romaji.swift (Tatoeba sentences, CC-BY 2.0 FR).
Sentences are split 90/10 by a hash of their text: the model is counted only on the
90%, phrases for evaluation come only from the 10%.

usage: python build_kana_model.py <seamtype-cli> <ja_tokens.jsonl> <model_out.txt> <eval_out.tsv>
model_out lines:  <a><b><c>\t<count>   (^ = start, $ = end; a,b,c single kana or marker)
eval_out lines:   <romaji keys>\t<previous>\tjapanese\t<hiragana>
"""
import hashlib
import json
import random
import subprocess
import sys
from collections import Counter

from romaji_join import ends_mid_sokuon, typed


def held_out(text: str) -> bool:
    return int(hashlib.sha1(text.encode()).hexdigest(), 16) % 10 == 0


def to_kana(cli: str, romaji: list[str]) -> list[tuple[str, int]]:
    res = subprocess.run([cli, "--kana"], input="\n".join(romaji) + "\n", capture_output=True, text=True, check=True)
    out = []
    for line in res.stdout.splitlines():
        kana, stray = line.rsplit("\t", 1)
        out.append((kana, int(stray)))
    return out


def main():
    cli, tokens_path, model_out, eval_out = sys.argv[1:5]
    train_sentences, eval_sentences = [], []
    for line in open(tokens_path, encoding="utf-8"):
        d = json.loads(line)
        if any(t["latin"] for t in d["tokens"]):
            continue  # English inside Japanese: phrase segmentation's job, not this model's
        (eval_sentences if held_out(d["text"]) else train_sentences).append(d["tokens"])

    # Trigram counts over whole sentences in kana.
    kana = to_kana(cli, [typed([t["romaji"] for t in s]) for s in train_sentences])
    counts = Counter()
    dropped = 0
    for k, stray in kana:
        if stray:
            dropped += 1
            continue
        seq = ["^", "^", *k, "$"]
        for i in range(2, len(seq)):
            counts[seq[i - 2] + seq[i - 1] + seq[i]] += 1
    with open(model_out, "w", encoding="utf-8") as f:
        for tri, c in sorted(counts.items()):
            if c >= 2:
                f.write(f"{tri}\t{c}\n")
    kept = sum(1 for c in counts.values() if c >= 2)
    print(f"train sentences={len(train_sentences)} (dropped {dropped} with stray letters) trigrams kept={kept}")

    # Eval phrases: what people type before pressing Space to convert — a phrase of a
    # few morphemes (content word + particles/endings), up to a whole short sentence.
    # Single morphemes like "no", "wo", "nite" alone aren't how people type.
    rng = random.Random(11)
    phrases = []
    for s in eval_sentences:
        length = min(len(s), rng.choice([2, 2, 3, 3, 4, 5]))
        start = rng.randrange(len(s) - length + 1)
        span = s[start:start + length]
        if not ends_mid_sokuon(span):
            phrases.append(typed([t["romaji"] for t in span]))
    phrases = sorted(set(p for p in phrases if len(p) >= 6))
    rng.shuffle(phrases)
    phrases = phrases[:4000]
    kana = to_kana(cli, phrases)
    with open(eval_out, "w", encoding="utf-8") as f:
        n = 0
        for p, (k, stray) in zip(phrases, kana):
            if stray:
                continue
            # Mid-Japanese-text most of the time, sometimes the start, rarely after English.
            r = rng.random()
            prev = "japanese" if r < 0.65 else ("" if r < 0.9 else "english")
            f.write(f"{p}\t{prev}\tjapanese\t{k}\n")
            n += 1
    print(f"eval phrases={n}")


if __name__ == "__main__":
    main()
