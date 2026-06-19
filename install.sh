#!/bin/bash

# Solana Consumer Onboarding Skill — Installer
# Installs the skill into ~/.claude/skills/ with recommended defaults.

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$SCRIPT_DIR/skill"

SKILLS_DIR="$HOME/.claude/skills"
SKILL_PATH="$SKILLS_DIR/solana-consumer-onboarding"
CORE_SKILL_PATH="$SKILLS_DIR/solana-dev"

print_banner() {
    echo ""
    echo -e "${MAGENTA}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║${NC}  ${WHITE}Solana Consumer Onboarding — Skill for Claude Code${NC}           ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}║${NC}  ${CYAN}Build Solana apps for people who don't know they're using it${NC} ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_help() {
    echo "Solana Consumer Onboarding Skill — Installer"
    echo ""
    echo "Usage: ./install.sh [OPTIONS]"
    echo ""
    echo "Installs to ~/.claude/skills/solana-consumer-onboarding"
    echo ""
    echo "Options:"
    echo "  -y, --yes      Skip confirmation prompt"
    echo "  -h, --help     Show this help"
    echo ""
}

SKIP_CONFIRM=false
while [[ $# -gt 0 ]]; do
    case $1 in
        -y|--yes) SKIP_CONFIRM=true; shift ;;
        -h|--help) print_help; exit 0 ;;
        *) echo "Unknown option: $1"; echo "Use --help for usage."; exit 1 ;;
    esac
done

print_banner

echo -e "This will install:"
echo -e "  ${BLUE}•${NC} solana-consumer-onboarding → ${CYAN}$SKILL_PATH${NC}"
echo ""

if [ "$SKIP_CONFIRM" = false ]; then
    read -p "Proceed with installation? [Y/n] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        echo -e "${YELLOW}Installation cancelled${NC}"
        exit 0
    fi
fi

echo ""
mkdir -p "$SKILLS_DIR"

echo -e "${CYAN}[1/2]${NC} Installing solana-consumer-onboarding..."
if [ -d "$SKILL_PATH" ]; then
    echo -e "  ${YELLOW}→${NC} Removing existing installation"
    rm -rf "$SKILL_PATH"
fi
mkdir -p "$SKILL_PATH"
cp -r "$SOURCE_DIR"/* "$SKILL_PATH/"
echo -e "  ${GREEN}✓${NC} Installed to $SKILL_PATH"

# This skill extends solana-dev-skill (core programs/frontend/testing). Offer to
# install it if it's not already present — non-fatal if the clone fails.
echo -e "${CYAN}[2/2]${NC} Checking for solana-dev-skill (extended by this skill)..."
if [ -d "$CORE_SKILL_PATH" ]; then
    echo -e "  ${GREEN}✓${NC} solana-dev-skill already present"
else
    temp_dir=$(mktemp -d)
    if git clone --depth 1 --quiet https://github.com/solana-foundation/solana-dev-skill.git "$temp_dir" 2>/dev/null; then
        cp -r "$temp_dir/skill" "$CORE_SKILL_PATH"
        rm -rf "$temp_dir"
        echo -e "  ${GREEN}✓${NC} Installed solana-dev-skill to $CORE_SKILL_PATH"
    else
        rm -rf "$temp_dir"
        echo -e "  ${YELLOW}→${NC} Optional: install manually from https://github.com/solana-foundation/solana-dev-skill"
    fi
fi

echo ""
echo -e "${GREEN}Installation complete.${NC}"
echo ""
echo -e "${CYAN}Try asking Claude:${NC}"
echo -e "  ${BLUE}•${NC} \"Users sign up with email and have no SOL — how do I sponsor their transactions safely?\""
echo -e "  ${BLUE}•${NC} \"Build a fee-payer relay for my Solana app\""
echo -e "  ${BLUE}•${NC} \"One-tap signup that creates the account on the user's first action\""
echo ""
echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}     Built for the Solana AI Kit${NC}"
echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
