# Screenshot Resizing Scripts

This directory contains bash scripts to batch resize screenshots for the MuteVideo app to meet App Store requirements.

## Prerequisites

You need ImageMagick installed on your system:

```bash
# Install via Homebrew (recommended)
brew install imagemagick

# Or download from official website
# https://imagemagick.org/script/download.php
```

## Scripts

### `resize_screenshots.sh`
Main script that resizes all images in iPhone and iPad directories to the correct dimensions.

**Target sizes:**
- iPhone: 2688×1242px (iPhone 14 Pro Max landscape)
- iPad: 2048×2732px (iPad Pro 12.9" portrait)

**Usage:**
```bash
# Navigate to Screenshot directory
cd Screenshot

# Run the resize script
./resize_screenshots.sh
```

**Features:**
- ✅ Automatically detects ImageMagick installation
- ✅ Creates backup files before resizing (.backup extension)
- ✅ High-quality resizing with 95% JPEG quality
- ✅ Progress indicator and colored output
- ✅ Error handling and validation
- ✅ Confirmation prompt before processing

### `clean_backups.sh`
Utility script to remove backup files created during the resize process.

**Usage:**
```bash
./clean_backups.sh
```

## Directory Structure

```
Screenshot/
├── iPhone/          # Place iPhone screenshots here
├── iPad/            # Place iPad screenshots here
├── resize_screenshots.sh
├── clean_backups.sh
└── README.md
```

## App Store Screenshot Requirements

### iPhone Screenshots
- **Size:** 2688×1242 pixels
- **Format:** PNG or JPEG
- **Device:** iPhone 14 Pro Max (landscape)

### iPad Screenshots  
- **Size:** 2048×2732 pixels
- **Format:** PNG or JPEG
- **Device:** iPad Pro 12.9" (portrait)

## Tips

1. **Backup First:** The script automatically creates backups, but consider making your own backup of important images.

2. **Supported Formats:** Script works with PNG, JPG, and JPEG files.

3. **Quality:** Images are resized with high quality (95%) to maintain visual fidelity.

4. **Aspect Ratio:** Images are centered and cropped to fit exact dimensions while maintaining aspect ratio.

5. **Remove Backups:** After confirming the resized images look good, use `clean_backups.sh` to remove backup files.

## Troubleshooting

**ImageMagick not found:**
```bash
brew install imagemagick
```

**Permission denied:**
```bash
chmod +x resize_screenshots.sh
chmod +x clean_backups.sh
```

**No images found:**
- Make sure images are in the correct iPhone/ or iPad/ subdirectories
- Check file extensions are .png, .jpg, or .jpeg

## Example Output

```
🔄 Starting screenshot resizing process...

📍 Working directory: /path/to/Screenshot
🎯 Target sizes:
  📱 iPhone: 2688×1242px
  📱 iPad: 2048×2732px

📱 Processing iPhone images (target: 2688×1242px)
Found 5 image(s) in iPhone
[1/5] Processing screenshot1.png... ✓ Done (1334×750 → 2688×1242)
[2/5] Processing screenshot2.png... ✓ Done (1334×750 → 2688×1242)
...

🎉 All done! Screenshot resizing completed.
💡 Note: Original files have been backed up with .backup extension
```