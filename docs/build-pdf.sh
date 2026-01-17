#!/bin/bash
# Blog PDF Build Script
# Usage: ./build-pdf.sh 20251226_タイトル.md

set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <markdown-file>"
    exit 1
fi

MD_FILE="$1"
BASENAME=$(basename "$MD_FILE" .md)
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
HTML_FILE="${SCRIPT_DIR}/${BASENAME}.html"
PDF_FILE="${SCRIPT_DIR}/PDF/${BASENAME}.pdf"

# Ensure PDF directory exists
mkdir -p "${SCRIPT_DIR}/PDF"

# Extract metadata from YAML front matter
TITLE=$(awk '/^title:/{gsub(/^title: *"?|"?$/,""); print}' "$MD_FILE")
SUBTITLE=$(awk '/^subtitle:/{gsub(/^subtitle: *"?|"?$/,""); print}' "$MD_FILE")
AUTHOR=$(awk '/^author:/{gsub(/^author: *"?|"?$/,""); print}' "$MD_FILE")
DATE=$(awk '/^date:/{gsub(/^date: *"?|"?$/,""); print}' "$MD_FILE")

echo "Building PDF: $MD_FILE"
echo "  Title: $TITLE"
echo "  Subtitle: $SUBTITLE"
echo "  Author: $AUTHOR"
echo "  Date: $DATE"

# Generate standalone HTML with pandoc
pandoc "$MD_FILE" \
    --standalone \
    --toc \
    --toc-depth=2 \
    --metadata title="$TITLE" \
    -o "${SCRIPT_DIR}/${BASENAME}_temp.html"

# Create full HTML with cover page
cat > "$HTML_FILE" << EOF
<!DOCTYPE html>
<html lang="ja">
<head>
    <meta charset="UTF-8">
    <title>${TITLE}</title>
    <link rel="stylesheet" href="style.css">
</head>
<body>

<!-- 表紙 -->
<div class="cover">
    <h1>${TITLE}</h1>
    <p class="subtitle">${SUBTITLE}</p>
    <div class="meta">
        <p>${DATE}</p>
        <p>${AUTHOR}</p>
    </div>
</div>

<!-- 目次 -->
<div class="toc">
    <h2>目次</h2>
EOF

# Extract TOC from pandoc output
awk '/<nav[^>]*id="TOC"/{found=1} found; /<\/nav>/{found=0; exit}' "${SCRIPT_DIR}/${BASENAME}_temp.html" | sed '1d;$d' >> "$HTML_FILE"

cat >> "$HTML_FILE" << EOF
</div>

<!-- 本文 -->
<div class="content" data-date="${DATE}">
EOF

# Extract body content (between <body> and </body>, excluding nav#TOC)
awk '/<body>/{found=1; next} /<\/body>/{found=0} found' "${SCRIPT_DIR}/${BASENAME}_temp.html" | \
    awk 'BEGIN{skip=0} /<nav[^>]*id="TOC"/{skip=1} /<\/nav>/{skip=0; next} !skip' >> "$HTML_FILE"

cat >> "$HTML_FILE" << EOF
</div>

</body>
</html>
EOF

# Clean up pandoc temp file
rm -f "${SCRIPT_DIR}/${BASENAME}_temp.html"

# Convert to PDF with weasyprint
echo "Converting to PDF..."
~/.pyenv/versions/3.10.7/bin/python -m weasyprint "$HTML_FILE" "$PDF_FILE" --stylesheet="${SCRIPT_DIR}/style.css" 2>&1 | grep -v "^WARNING:" || true

# Clean up HTML temp file
rm -f "$HTML_FILE"

echo "Done: $PDF_FILE"

# Open PDF
open "$PDF_FILE"
