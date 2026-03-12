#!/bin/bash
# Simulated typing for demo recording
# Uses the mock cw in docs/assets/

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export PATH="$SCRIPT_DIR:$PATH"

type_and_run() {
  local cmd="$1"
  local pause_after="${2:-2}"

  # Simulate typing character by character
  for (( i=0; i<${#cmd}; i++ )); do
    printf "%s" "${cmd:$i:1}"
    sleep 0.04
  done
  sleep 0.3
  echo ""  # press enter
  eval "$cmd"
  sleep "$pause_after"
}

clear
sleep 0.5

# --- Setup flow ---
type_and_run "cw init" 2

type_and_run "cw account add work" 2

type_and_run "cw account add personal" 2

type_and_run "cw project register ~/code/noteflow --account work" 2

type_and_run "cw project register ~/code/api-gateway --account work" 2

type_and_run "cw project register ~/code/dotfiles --account personal" 2

# --- Show what we have ---
type_and_run "cw account list" 2

type_and_run "cw project list" 2.5

# --- Work on a Linear ticket ---
type_and_run "cw work noteflow https://linear.app/team/issue/AUTH-247" 3

# --- Review a PR ---
type_and_run "cw review noteflow 42" 3

# --- Check active spaces ---
type_and_run "cw spaces" 3

# --- Close the review ---
type_and_run "cw review noteflow 42 --done" 2

# --- Create a new project ---
type_and_run 'cw create "Habit tracker with streaks and analytics"' 3

sleep 1
