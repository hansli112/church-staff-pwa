"""Writes assets/fonts/MarthaLatin.ttf, the app's font for letters and digits
on Android (lib/core/design/tokens.dart, appFontFamily).

It is Source Sans 3 (SIL Open Font License, assets/fonts/OFL.txt) drawn
1000/900 larger: the size Noto Sans CJK draws the same letters at beside its
Chinese. The license keeps the name "Source" for Adobe's own, so the copy is
renamed.

    python3 -m venv /tmp/fonts && /tmp/fonts/bin/pip install fonttools
    curl -L -o /tmp/SourceSans3.ttf 'https://github.com/google/fonts/raw/main/ofl/sourcesans3/SourceSans3%5Bwght%5D.ttf'
    cd app && /tmp/fonts/bin/python tool/martha_latin.py /tmp/SourceSans3.ttf
"""
import sys

from fontTools.ttLib import TTFont

font = TTFont(sys.argv[1])
font['head'].unitsPerEm = 900
for record in font['name'].names:
    record.string = record.toUnicode().replace('Source Sans 3', 'Martha Latin').replace('SourceSans3', 'MarthaLatin')
font.save('assets/fonts/MarthaLatin.ttf')
