"""Join tokenizer romaji the way a person would type it.

- ん before a vowel, y or n is typed unambiguously: taihen + isogashii → taihen'isogashii
- the tokenizer's づ/ぢ spelling dzu/dzi is typed du/di
"""


def typed(romaji: list[str]) -> str:
    out = ""
    for i, r in enumerate(romaji):
        r = r.replace("dzu", "du").replace("dzi", "di")
        if out.endswith("n") and not out.endswith("nn") and r[:1] in ("a", "i", "u", "e", "o", "y", "n"):
            out += "'"
        out += r
    return out


def ends_mid_sokuon(tokens: list[dict]) -> bool:
    """A span cut right after っ carries the next word's doubled consonant (yokat)."""
    return tokens[-1]["surface"].endswith(("っ", "ッ"))
