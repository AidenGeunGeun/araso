"""Held-out evaluation words for the decision heuristic: keys<TAB>previous<TAB>label<TAB>reading.

English and Korean: the most frequent words of each list, Korean reverse-mapped to the 2-set
keys that type them; a tenth of the distinct key strings (by a fixed shuffle) are held out.
Japanese: 2-5 morpheme romaji phrases from Tatoeba sentences whose hash bucket is 0; the kana
model (build_kana_model.py) trains on buckets 1-9, so none of these sentences. Bucket 1 is
skipped here only so the random stream matches the original dataset. The previous word is
drawn the way people write: mostly the same language.

The random streams match the dataset this project was measured on, so the same words come out.

usage: python3 make_eval.py <seamtype-cli> <ko_50k.txt> <en_50k.txt> <ja_tokens.jsonl> <out.tsv>
"""
import hashlib
import json
import random
import re
import subprocess
import sys
from pathlib import Path

from romaji_join import ends_mid_sokuon, typed

CHO = "ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ"
JUNG = "ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ"
JONG = ["", *"ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ"]
SPLIT = {"ㅘ": "ㅗㅏ", "ㅙ": "ㅗㅐ", "ㅚ": "ㅗㅣ", "ㅝ": "ㅜㅓ", "ㅞ": "ㅜㅔ", "ㅟ": "ㅜㅣ", "ㅢ": "ㅡㅣ",
         "ㄳ": "ㄱㅅ", "ㄵ": "ㄴㅈ", "ㄶ": "ㄴㅎ", "ㄺ": "ㄹㄱ", "ㄻ": "ㄹㅁ", "ㄼ": "ㄹㅂ", "ㄽ": "ㄹㅅ",
         "ㄾ": "ㄹㅌ", "ㄿ": "ㄹㅍ", "ㅀ": "ㄹㅎ", "ㅄ": "ㅂㅅ"}
KEY = dict(zip("ㅂㅈㄷㄱㅅㅛㅕㅑㅐㅔㅁㄴㅇㄹㅎㅗㅓㅏㅣㅋㅌㅊㅍㅠㅜㅡㅃㅉㄸㄲㅆㅒㅖ",
               "qwertyuiopasdfghjklzxcvbnmQWERTOP"))
HANGUL_WORD = re.compile(r"^[가-힣]+$")
ENGLISH_WORD = re.compile(r"^[a-z]+$")
SEED = 7
PER_LANG = 20000
JA_TRAIN, JA_EVAL = 20000, 2000


def keys_for(word: str) -> str:
    out = []
    for ch in word:
        code = ord(ch) - 0xAC00
        for jamo in (CHO[code // 588], JUNG[(code % 588) // 28], JONG[code % 28]):
            out.extend(KEY[j] for j in SPLIT.get(jamo, jamo))
    return "".join(out)


def read_freq(path: str, pattern: re.Pattern) -> list[str]:
    words = []
    for line in Path(path).read_text(encoding="utf-8").splitlines():
        parts = line.split()
        if len(parts) == 2 and pattern.match(parts[0]):
            words.append(parts[0])
        if len(words) >= PER_LANG:
            break
    return words


def japanese_phrases(path: str, rng: random.Random) -> tuple[list[str], list[str]]:
    train, ev = set(), set()
    for line in open(path, encoding="utf-8"):
        d = json.loads(line)
        if any(t["latin"] for t in d["tokens"]):
            continue
        bucket = int(hashlib.sha1(d["text"].encode()).hexdigest(), 16) % 10
        if bucket == 1:
            continue
        tokens = d["tokens"]
        length = min(len(tokens), rng.choice([2, 2, 3, 3, 4, 5]))
        start = rng.randrange(len(tokens) - length + 1)
        span = tokens[start:start + length]
        romaji = typed([t["romaji"] for t in span])
        if ends_mid_sokuon(span) or len(romaji) < 6:
            continue
        (ev if bucket == 0 else train).add(romaji)
    train, ev = sorted(train), sorted(ev)
    rng.shuffle(train)
    rng.shuffle(ev)
    return train[:JA_TRAIN], ev[:JA_EVAL]


def previous_for(label: str, rng: random.Random) -> str | None:
    r = rng.random()
    if r < 0.65:
        return label
    if r < 0.80:
        return "korean" if label == "english" else "english"
    return None


def previous_for_japanese(rng: random.Random) -> str | None:
    r = rng.random()
    return "japanese" if r < 0.65 else None if r < 0.85 else "english" if r < 0.95 else "korean"


def readings(cli: str, mode: str, keys: list[str]) -> dict[str, str]:
    out = subprocess.run([cli, mode], input="\n".join(keys) + "\n",
                         capture_output=True, text=True, check=True).stdout.splitlines()
    if mode == "--compose":
        return dict(line.split("\t", 1) for line in out)
    return {k: line.rsplit("\t", 1)[0] for k, line in zip(keys, out)}


def main():
    cli, ko_path, en_path, ja_path, out_path = sys.argv[1:6]
    rng = random.Random(SEED)
    ja_train, ja_eval = japanese_phrases(ja_path, random.Random(SEED + 1))

    ko = [(keys_for(w), w) for w in read_freq(ko_path, HANGUL_WORD)]
    en = [(w, w) for w in read_freq(en_path, ENGLISH_WORD)]
    hangul = readings(cli, "--compose", sorted({k for k, _ in ko} | {k for k, _ in en}))
    ko = [(k, w) for k, w in ko if hangul.get(k) == w]  # must round-trip through the composer
    kana = readings(cli, "--kana", ja_eval)

    samples = [(k, "korean") for k, _ in ko] + [(k, "english") for k, _ in en]
    unique_keys = sorted({k for k, _ in samples})
    rng.shuffle(unique_keys)
    eval_keys = set(unique_keys[: len(unique_keys) // 10])

    with open(out_path, "w", encoding="utf-8") as tsv:
        rng.shuffle(samples)
        for keys, label in samples:
            prev = previous_for(label, rng)  # drawn for every word, held out or not
            if keys in eval_keys:
                tsv.write(f"{keys}\t{prev or ''}\t{label}\t{hangul[keys]}\n")
        jrng = random.Random(SEED + 2)
        for _ in ja_train:
            previous_for_japanese(jrng)
        for keys in ja_eval:
            tsv.write(f"{keys}\t{previous_for_japanese(jrng) or ''}\tjapanese\t{kana[keys]}\n")


if __name__ == "__main__":
    main()
