"""English word + particle accuracy, typed through a real session (seamtype-cli --type).

English words (300 common ones from en_50k, tech words, names and acronyms typed with their
capitals) with a Korean particle (github에) or a Japanese one (githubで) and Space; the word
alone must stay English. Korean particles are typed with Japanese off and on, Japanese ones
with Japanese on. Japanese is checked as kana (no converter).

usage: python3 eval_particles.py <seamtype-cli> <en_50k.txt> [failures per row]
"""
import random
import re
import subprocess
import sys
from collections import Counter, defaultdict

from make_eval import keys_for

TECH = """github slack docker python server google chrome commit branch merge build deploy cache query
login token bug test code file folder update api json script kotlin swift react node linux windows
iphone android notion figma zoom youtube excel email message laptop mouse keyboard browser router
cloud backup install release issue review editor terminal vim emacs git npm array string class""".split()
CAPS = "API UI OS AWS PR CI URL SQL GitHub Slack TextEdit VSCode macOS iPhone YouTube Notion Figma Docker Python Chrome".split()
KOREAN = "에 에서 에게 을 를 은 는 이 가 도 로 으로 와 과 의 만 까지 부터 처럼 한테 랑 해서 했어 하는 같은".split()
JAPANESE = {"で": "de", "に": "ni", "を": "wo", "は": "ha", "が": "ga", "の": "no", "と": "to", "も": "mo",
            "から": "kara", "まで": "made", "より": "yori"}


def common_words(path, n=300, top=3000):
    words = []
    for line in open(path, encoding="utf-8"):
        w = line.split()[0]
        if re.fullmatch(r"[a-z]{3,}", w):
            words.append(w)
        if len(words) >= top:
            break
    return random.Random(3).sample(words, n)


def typed(cli, keys, japanese):
    res = subprocess.run([cli, "--type", *(["--japanese"] if japanese else [])], input="".join(k + "\n" for k in keys),
                         capture_output=True, text=True, check=True)
    return dict(line.split("\t", 1) for line in res.stdout.splitlines())


def main():
    cli, path, *rest = sys.argv[1:]
    shown = int(rest[0]) if rest else 8
    cases = []  # (kind, group, keys, expected)
    for group, words in [("common", common_words(path)), ("tech", TECH), ("caps", CAPS)]:
        for w in words:
            cases.append(("plain", group, w, w))
            cases += [("korean", group, w + keys_for(p), w + p) for p in KOREAN]
            cases += [("japanese", group, w + r, w + p) for p, r in JAPANESE.items()]
    outputs = {ja: typed(cli, [c[2] for c in cases if ja or c[0] != "japanese"], ja) for ja in (False, True)}
    total, right, failures = Counter(), Counter(), defaultdict(list)
    for kind, group, keys, expected in cases:
        for ja in ((True,) if kind == "japanese" else (False, True)):
            row = (kind, "ja on" if ja else "ja off", group)
            got = outputs[ja][keys].rstrip(" ")
            total[row] += 1
            right[row] += got == expected
            if got != expected:
                failures[row].append(f"{keys}→{got}")
    for row in sorted(total):
        print(f"{' '.join(row):28} {right[row]:5}/{total[row]:<5} {100 * right[row] / total[row]:5.1f}%")
    for row in sorted(failures):
        print(f"\n{' '.join(row)}: " + "  ".join(failures[row][:shown]))


if __name__ == "__main__":
    main()
