#!/usr/bin/env python3
# Flags any line that spawns a coding-agent binary directly.
# Reads like grep: prints `line:text` per hit, exits 1 when there is one.
# Anchors on execution shape, never the bare name, since `pi` is a word fragment.
import re
import sys

BINARIES = ("claude", "codex", "pi", "opencode")

# a heredoc opener, ignoring herestrings
HEREDOC = re.compile(r"<<-?\s*(?!<)(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")

# a parameter expansion, which never runs a command
PARAM = re.compile(r"\$\{[^{}]*\}")

# every operator that can start a fresh command on the same line
SPLIT = re.compile(r"\|\||&&|;;|[;&|(){}]|\$\(|`")

# shell keywords that may precede a command word
KEYWORD = r"(?:!|time|if|then|elif|else|do|while|until|exec|command|builtin)"

# an env assignment, a bare expansion, or the env prefix itself
PREFIX_TOKEN = (
    r"(?:env"
    r"|[A-Za-z_][A-Za-z0-9_]*=(?:\"[^\"]*\"|'[^']*'|[^\s\"']*)"
    r"|\$\{[^}]*\}"
    r"|\$[A-Za-z_][A-Za-z0-9_]*)"
)

# the command word itself, with any surrounding quotes stripped before matching
COMMAND = re.compile(
    r"^\s*(?:" + KEYWORD + r"\s+)*"
    r"(?:" + PREFIX_TOKEN + r"\s+)*"
    r"[\"']?(" + "|".join(BINARIES) + r")[\"']?(?:\s|$)"
)

# a bare case label, e.g. `claude)`, with nothing else in the segment
CASE_LABEL = re.compile(r"^[\"']?(?:" + "|".join(BINARIES) + r")[\"']?$")


# yields executable text only, dropping comments and heredoc bodies
def code_lines(path):
    delim = None
    with open(path, encoding="utf-8") as fh:
        for n, raw in enumerate(fh, 1):
            line = raw.rstrip("\n")
            if delim is not None:
                if line.strip() == delim:
                    delim = None
                continue
            m = HEREDOC.search(line)
            if m:
                delim = m.group(2)
            if line.lstrip().startswith("#"):
                continue
            yield n, line


# collapses parameter expansions so their braces cannot split a segment
def mask_params(line):
    while True:
        masked = PARAM.sub("$_", line)
        if masked == line:
            return masked
        line = masked


# splits text on SPLIT, keeping the delimiter before and after each segment
def split_with_delims(pattern, text):
    segments, delims, pos = [], [], 0
    for m in pattern.finditer(text):
        segments.append(text[pos:m.start()])
        delims.append(m.group(0))
        pos = m.end()
    segments.append(text[pos:])
    return segments, delims


def hits(path):
    for n, line in code_lines(path):
        segments, delims = split_with_delims(SPLIT, mask_params(line))
        for i, segment in enumerate(segments):
            if not COMMAND.match(segment):
                continue
            before = delims[i - 1] if i > 0 else None
            after = delims[i] if i < len(delims) else None
            if after == ")" and before != "$(" and CASE_LABEL.match(segment.strip()):
                continue
            yield n, line.strip()
            break


def main(argv):
    if len(argv) != 2:
        print("usage: scan_launch_sites.py <file>", file=sys.stderr)
        return 2
    found = list(hits(argv[1]))
    for n, text in found:
        print(f"{n}:{text}")
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
