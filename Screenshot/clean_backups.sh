#!/bin/bash

# Cleanup script to remove backup files created by resize_screenshots.sh

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${BLUE}🧹 Cleaning up backup files in Screenshot directory...${NC}"

# Count backup files
backup_count=$(find "$SCRIPT_DIR" -name "*.backup" | wc -l | tr -d ' ')

if [ "$backup_count" -eq 0 ]; then
    echo -e "${GREEN}✅ No backup files found. Directory is already clean.${NC}"
    exit 0
fi

echo -e "${YELLOW}Found $backup_count backup file(s):${NC}"
find "$SCRIPT_DIR" -name "*.backup" -exec basename {} \;

echo ""
read -p "Do you want to delete all backup files? This cannot be undone. (y/N): " -n 1 -r
echo

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Operation cancelled.${NC}"
    exit 0
fi

# Delete backup files
deleted_count=0
find "$SCRIPT_DIR" -name "*.backup" | while read -r file; do
    if rm "$file" 2>/dev/null; then
        deleted_count=$((deleted_count + 1))
        echo -e "${GREEN}✓ Deleted: $(basename "$file")${NC}"
    else
        echo -e "${RED}✗ Failed to delete: $(basename "$file")${NC}"
    fi
done

echo -e "${GREEN}🎉 Cleanup completed!${NC}"