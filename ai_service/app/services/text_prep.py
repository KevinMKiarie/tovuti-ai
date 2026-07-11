import re


_MULTI_PUNCT = re.compile(r'([!?])\1+')
_ALL_CAPS_WORD = re.compile(r'\b([A-Z]{3,})\b')
_ELLIPSIS = re.compile(r'\.{3,}')
_MULTI_SPACE = re.compile(r' {2,}')

# Insert a comma before coordinating conjunctions that lack one, but only when
# the preceding clause is long enough (>=4 words) to warrant a breath pause.
_CONJUNCTION = re.compile(
    r'(?P<pre>(?:\w+\s+){4,}\w+)'   # 4+ words before
    r'(?P<gap>\s+)'
    r'(?P<conj>but|and|so|yet|or|nor|because|although|though|while|whereas)'
    r'(?P<post>\s)',
    re.IGNORECASE,
)


def _maybe_add_comma(m: re.Match) -> str:
    pre = m.group('pre')
    if pre.rstrip()[-1] in ',;:—–':
        return m.group(0)
    return f"{pre},{m.group('gap')}{m.group('conj')}{m.group('post')}"


def preprocess(text: str) -> str:
    """Make text more prosodically natural for TTS synthesis."""
    # Reduce repeated punctuation: !!! → !
    text = _MULTI_PUNCT.sub(r'\1', text)

    # ALL-CAPS words → Title Case (keeps acronyms like "AI", "URL" short enough to skip)
    text = _ALL_CAPS_WORD.sub(lambda m: m.group(1).capitalize(), text)

    # Ellipsis → em dash (produces a measured pause rather than a trailing fade)
    text = _ELLIPSIS.sub(' — ', text)

    # Add comma before conjunctions when the preceding clause is long
    text = _CONJUNCTION.sub(_maybe_add_comma, text)

    # Newlines → comma-space so multi-line prompts flow as one utterance
    text = text.replace('\n', ', ')

    text = _MULTI_SPACE.sub(' ', text)
    return text.strip()
