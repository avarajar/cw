# CW Demo — Claude Workspace Manager
Output docs/assets/demo.gif

Set Shell "zsh"
Set FontSize 15
Set Width 1200
Set Height 630
Set Theme "Catppuccin Mocha"
Set Padding 20
Set TypingSpeed 40ms
Set CursorBlink false

# Use the mock cw for demo
Env PATH "/Users/joselito/Workspace/personal/cw-repo/docs/assets:$PATH"
Env CW_DEMO "1"

# Help
Sleep 0.5s
Type "cw help"
Enter
Sleep 3s

# Accounts
Type "cw account list"
Enter
Sleep 2.5s

# Projects
Type "cw project list"
Enter
Sleep 2.5s

# Work on a Linear ticket
Type "cw work noteflow https://linear.app/team/issue/AUTH-247"
Enter
Sleep 4s

# Check active spaces
Type "cw spaces"
Enter
Sleep 3s

# Review a PR
Type "cw review noteflow 42"
Enter
Sleep 4s

# Check spaces with everything active
Type "cw spaces"
Enter
Sleep 3s

# Close the review
Type "cw review noteflow 42 --done"
Enter
Sleep 2.5s

# Create a new project
Type 'cw create "Habit tracker with streaks and analytics"'
Enter
Sleep 4s

Sleep 2s
