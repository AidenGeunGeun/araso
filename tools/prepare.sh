#!/bin/zsh
# Data for the heuristic's models and its held-out evaluation, then the accuracy:
# word lists + Tatoeba + SCOWL → typed romaji → [--models: rebuild Sources/SeamtypeCore/Data] →
# eval.tsv → accuracy, then the most frequent words after each language.
# Needs only python3 and the Swift toolchain. Downloads go to tools/data (not in git).
#
#   tools/prepare.sh            evaluate the current models
#   tools/prepare.sh --models   rebuild the kana, written-Japanese, Korean and English data first
set -euo pipefail
cd "${0:A:h}"
mkdir -p data

words=https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018
[[ -f data/ko_50k.txt ]] || curl -sSfL -o data/ko_50k.txt $words/ko/ko_50k.txt
[[ -f data/en_50k.txt ]] || curl -sSfL -o data/en_50k.txt $words/en/en_50k.txt
for lang in jpn kor; do
  if [[ ! -f data/${lang}_sentences.tsv ]]; then
    curl -sSfL -o data/${lang}_sentences.tsv.bz2 https://downloads.tatoeba.org/exports/per_language/$lang/${lang}_sentences.tsv.bz2
    bunzip2 -f data/${lang}_sentences.tsv.bz2
  fi
done

if [[ ! -d data/scowl ]]; then
  curl -sSfL -o data/scowl.tar.gz https://downloads.sourceforge.net/project/wordlist/SCOWL/2020.12.07/scowl-2020.12.07.tar.gz
  mkdir -p data/scowl && tar -xzf data/scowl.tar.gz -C data/scowl --strip-components 1
fi

(cd .. && swift build -c release --product seamtype-cli)
cli=../.build/release/seamtype-cli
if [[ ! -f data/ja_tokens.jsonl ]]; then
  swiftc -O -o data/ja_romaji ja_romaji.swift
  cut -f3 data/jpn_sentences.tsv | data/ja_romaji > data/ja_tokens.jsonl
fi
if [[ "${1:-}" == "--models" ]]; then
  python3 build_kana_model.py $cli data/ja_tokens.jsonl ../Sources/SeamtypeCore/Data/kana_trigrams.txt data/ja_eval.tsv
  python3 build_text_model.py data/ja_tokens.jsonl ../Sources/SeamtypeCore/Data/text_trigrams.txt 2
  python3 build_korean_syllables.py data/kor_sentences.tsv ../Sources/SeamtypeCore/Data/korean_syllables.txt
  python3 build_korean_words.py data/kor_sentences.tsv ../Sources/SeamtypeCore/Data/korean_words.txt
  python3 build_english_words.py data/scowl/final ../Sources/SeamtypeCore/Data/english_words.txt
  (cd .. && swift build -c release --product seamtype-cli)
fi

python3 make_eval.py $cli data/ko_50k.txt data/en_50k.txt data/ja_tokens.jsonl data/eval.tsv
python3 eval3.py $cli data/eval.tsv
python3 eval_context.py $cli data/ko_50k.txt data/en_50k.txt 10000   # top words after each language
python3 eval_overlap.py $cli data/ja_tokens.jsonl data/en_50k.txt   # English/Japanese look-alikes
