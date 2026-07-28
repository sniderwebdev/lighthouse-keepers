# Mock sources

The author's Claude Design exports, as delivered. The PNGs one directory up are
rendered from these at 1380x930 with:

    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
      --headless --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
      --virtual-time-budget=8000 --window-size=1380,930 \
      --screenshot=../<name>.png "file://$PWD/<Screen N - ...>.dc.html"

Kept because the HTML is the real source of truth: exact hex values, exact
spacing, and the d-pad order notes under each artboard. Re-render rather than
hand-editing a PNG if a mock changes.
