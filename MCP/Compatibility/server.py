"""Launch the native server for clients configured with the previous Python path."""

import os
import sys
from pathlib import Path

binary = Path(__file__).with_name("splicekit-mcp")
os.execv(binary, [str(binary), *sys.argv[1:]])
