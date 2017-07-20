
#
# Process a single data file
#

import sys
import pprint

from common import process_single_data_file

if len(sys.argv) != 2:
	print("Usage: process_single_data.py <path-to-file>")
	exit(1)

pp = pprint.PrettyPrinter(indent=4)
data = process_single_data_file(sys.argv[1])
pp.pprint(data)
