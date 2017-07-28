
#
# Process a data directory
#

import sys
import pprint

from common import process_data_files
from common import process_timer_file

if len(sys.argv) != 2:
	print("Usage: process_data_directory.py <path-to-file>")
	exit(1)

pp = pprint.PrettyPrinter(indent=4)
datafiles = process_data_files(sys.argv[1])
timerfile = process_timer_file(sys.argv[1]+'/timer.txt')
pp.pprint(timerfile)
pp.pprint(datafiles)
