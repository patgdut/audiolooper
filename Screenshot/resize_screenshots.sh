#!/bin/bash

# Screenshot resizing script for MuteVideo App
# Resizes iPhone screenshots to 2688×1242px and iPad screenshots to 2048×2732px

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if ImageMagick is installed
if ! command -v magick &> /dev/null && ! command -v convert &> /dev/null; then
    echo -e "${RED}Error: ImageMagick is not installed.${NC}"
    echo -e "${YELLOW}Please install ImageMagick first:${NC}"
    echo "  brew install imagemagick"
    echo "  or visit: https://imagemagick.org/script/download.php"
    exit 1
fi

# Determine which command to use (newer ImageMagick uses 'magick', older uses 'convert')
if command -v magick &> /dev/null; then
    CONVERT_CMD="magick"
else
    CONVERT_CMD="convert"
fi

echo -e "${BLUE}🔄 Starting screenshot resizing process...${NC}\n"

# Function to resize images in a directory
resize_images() {
    local dir="$1"
    local width="$2"
    local height="$3"
    local device="$4"
    
    if [ ! -d "$dir" ]; then
        echo -e "${YELLOW}Warning: Directory '$dir' does not exist, skipping...${NC}"
        return
    fi
    
    # Count total images
    local total_images=$(find "$dir" -type f \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" \) | wc -l | tr -d ' ')
    
    if [ "$total_images" -eq 0 ]; then
        echo -e "${YELLOW}No images found in $dir directory${NC}"
        return
    fi
    
    echo -e "${BLUE}📱 Processing $device images (target: ${width}×${height}px)${NC}"
    echo -e "Found $total_images image(s) in $dir"
    
    local count=0
    local success_count=0
    
    # Process each image file
    find "$dir" -type f \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" \) | while read -r file; do
        count=$((count + 1))
        filename=$(basename "$file")
        
        echo -n "[$count/$total_images] Processing $filename... "
        
        # Get original dimensions
        original_size=$($CONVERT_CMD "$file" -format "%wx%h" info: 2>/dev/null)
        
        if [ $? -ne 0 ]; then
            echo -e "${RED}Failed (unable to read image)${NC}"
            continue
        fi
        
        # Create backup
        backup_file="${file}.backup"
        if [ ! -f "$backup_file" ]; then
            cp "$file" "$backup_file"
        fi
        
        # Resize image with high quality
        if $CONVERT_CMD "$file" -resize "${width}x${height}^" -gravity center -extent "${width}x${height}" -quality 95 "$file" 2>/dev/null; then
            success_count=$((success_count + 1))
            echo -e "${GREEN}✓ Done${NC} ($original_size → ${width}×${height})"
        else
            echo -e "${RED}✗ Failed${NC}"
            # Restore backup if resize failed
            if [ -f "$backup_file" ]; then
                cp "$backup_file" "$file"
            fi
        fi
    done
    
    echo -e "${GREEN}✅ $device processing complete: $success_count/$total_images images resized successfully${NC}\n"
}

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Define directories and target sizes
IPHONE_DIR="$SCRIPT_DIR/iPhone"
IPAD_DIR="$SCRIPT_DIR/iPad"

# iPhone screenshots: 2688×1242px (iPhone 14 Pro Max landscape)
IPHONE_WIDTH=1242
IPHONE_HEIGHT=2688

# iPad screenshots: 2048×2732px (iPad Pro 12.9" portrait)
IPAD_WIDTH=2048
IPAD_HEIGHT=2732

echo -e "${BLUE}📍 Working directory: $SCRIPT_DIR${NC}"
echo -e "${BLUE}🎯 Target sizes:${NC}"
echo -e "  📱 iPhone: ${IPHONE_WIDTH}×${IPHONE_HEIGHT}px"
echo -e "  📱 iPad: ${IPAD_WIDTH}×${IPAD_HEIGHT}px"
echo ""

# Ask for confirmation
read -p "Do you want to proceed? This will resize all images and create backups. (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Operation cancelled.${NC}"
    exit 0
fi

echo ""

# Resize iPhone images
resize_images "$IPHONE_DIR" "$IPHONE_WIDTH" "$IPHONE_HEIGHT" "iPhone"

# Resize iPad images
resize_images "$IPAD_DIR" "$IPAD_WIDTH" "$IPAD_HEIGHT" "iPad"

echo -e "${GREEN}🎉 All done! Screenshot resizing completed.${NC}"
echo -e "${BLUE}💡 Note: Original files have been backed up with .backup extension${NC}"
echo -e "${BLUE}💡 To remove backups: find . -name '*.backup' -delete${NC}"