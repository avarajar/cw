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
    r"|[A-Za-z_][A-Za-z0-9_]*=(?:\"[^\"]*\"|'[^']*'|\S*)"
    r"|\$\{[^}]*\}"
    r"|\$[A-Za-z_][A-Za-z0-9_]*)"
)

COMMAND = re.compile(
    r"^\s*(?:" + KEYWORD + r"\s+)*"
    r"(?:" + PREFIX_TOKEN + r"\s+)*"
    r"(" + "|".join(BINARIES) + r")(?:\s|$)"
)


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


def hits(path):
    for n, line in code_lines(path):
        for segment in SPLIT.split(mask_params(line)):
            if COMMAND.match(segment):
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
