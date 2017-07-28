
#
# Process a single timer file
#

import sys
import pprint

from common import process_timer_file

if len(sys.argv) != 2:
	print("Usage: process_timer.py <path-to-file>")
	exit(1)

pp = pprint.PrettyPrinter(indent=4)
data = process_timer_file(sys.argv[1])
pp.pprint(data)
