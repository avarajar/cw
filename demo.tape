# CW Demo — the same ticket opened on two harnesses
# Assumes a real cw on PATH with an initialized ~/.cw
# Assumes "demo-app" is registered under a claude account and a codex account
# Only the claude leg has been run against a real binary as of 0.3.0
# The codex leg is aspirational until codex is installed and this is re-recorded
# Not yet recorded — no vhs binary was available when this script was written
Output docs/assets/demo.gif

Set Shell "zsh"
Set FontSize 15
Set Width 1200
Set Height 630
Set Theme "Catppuccin Mocha"
Set Padding 20
Set TypingSpeed 40ms
Set CursorBlink false

# Open ticket SEI-214 on the account's default harness (claude)
Sleep 0.5s
Type "cw work demo-app SEI-214"
Enter
Sleep 4s

# Open the same ticket on a second account, this time on codex
Type "cw work demo-app SEI-214 --harness codex"
Enter
Sleep 4s

# Both sessions, with their harness column
Type "cw spaces"
Enter
Sleep 3s
