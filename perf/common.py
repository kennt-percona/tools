#
# Common utility functions
#
import re
import unittest
from pathlib import Path

header_prog = re.compile(r"\s+\S+")				# any line that starts with a space
timer_prog = re.compile(r"\d\d:\d\d:\d\d\s")	# any line that starts with a time seq
prim_prog = re.compile(r"--\s")
secon_prog = re.compile(r"==\s")
status_prog = re.compile(r"\S+")

def classify_timer_linetype(line):
	"""
	Tries to determine what kind of data this is.

	header  	            PID USER      PR  NI    VIRT    RES    SHR S   CPU  MEM      TIME COMMAND
	timer 	  21:34:27 == 11924 root      20   0 11.355g 220068  11432 S   0.0  0.1   0:01.37 mysqld
	prim 	  -- wsrep_flow_control_interval  [ 5000, 5000 ]
	secon 	  == wsrep_slave_threads  16
	status 	  Starting warmup
	"""
	if header_prog.match(line):
		return "header"
	elif timer_prog.match(line):
		return "timer"
	elif prim_prog.match(line):
		return "prim"
	elif secon_prog.match(line):
		return "secon"
	elif status_prog.match(line):
		return "status"
	else:
		raise ValueError("line type could not be determined:{0}".format(line))

def parse_config_line(line):
	"""
	Takes a string, and returns a tuple (variable_name, variable_value)

	Example:
	('my_name', 42) = parse_config_line('-- my_name 42')
	"""
	pieces = line.split()
	return (pieces[1], ''.join(pieces[2:]))

def add_to_config(data_dict, dict_type, key, value):
	if dict_type not in data_dict:
		data_dict[dict_type] = dict()
	data_dict[dict_type][key] = value

def process_config_line(data_dict, dict_type, line):
	k,v = parse_config_line(line)
	add_to_config(data_dict, dict_type, k, v)

def is_starting_line(line):
	return line.startswith('Starting test')

def is_ending_line(line):
	return line.startswith('Ending test')

def process_header(lines):
	data = dict()
	process_config = True
	for line in lines:
		current_line_type = classify_timer_linetype(line)
		if line.startswith('Starting warmup'):
			# prevents warmup stats from being added to the system
			process_config = False
		elif current_line_type == "prim":
			if process_config:
				process_config_line(data, 'primary', line)
		elif current_line_type == "secon":
			if process_config:
				process_config_line(data, 'secondary', line)
	return data

def process_timer_line(line):
	pieces = line.split()
	# 21:54:55 == 11924 root      20   0 19.386g 7.595g 6.012g S  73.3  3.0  99:12.53 mysqld
	data = dict()
	data['time'] = pieces[0]
	data['vm'] = pieces[6]
	data['res'] = pieces[7]
	data['shr'] = pieces[8]
	data['cpu'] = pieces[10]
	return data

def process_test(lines):
	"""
	Process the values for a single test.
	Creates entries for each line and for the values of the stats at the
	end of the test.
	"""
	data = dict()
	ticks = []
	process_timer = False
	process_config = True

	for line in lines:
		current_line_type = classify_timer_linetype(line)
		if is_starting_line(line):
			matches = re.match(r'\D+=(\d+)', line)
			data['thread-count'] = matches[1]
			process_timer = True
			process_config = False
		elif is_ending_line(line):
			process_timer = False
			process_config = True
		elif current_line_type == 'prim':
			if process_config == True:
				process_config_line(data, 'primary', line)
			else:
				k,v = parse_config_line(line)
				if k == 'wsrep_flow_control_paused_ns':
					add_to_config(data, 'primary', 'wsrep_flow_control_paused_ns (previous)', v)

		elif current_line_type == 'secon':
			if process_config == True:
				process_config_line(data, 'secondary', line)
		elif current_line_type == 'timer':
			if process_timer:
				ticks.append(process_timer_line(line))
		elif current_line_type == 'status':
			pass
	data['timer-ticks'] = ticks
	return data

def process_timer_file(path):
	"""
	Gather the data from the timer.txt file

	Parameters:
		path : string
		Path to the timer.txt file

	Returns:
		A dict containing information gathered from the timer.txt file
	"""
	with open(path) as timer_file:
		lines = timer_file.readlines()

	# Process the file in sections

	# Assign each line to a section (this is mainly to make it easier to break
	# into separate sections for processing rather than in just one big loop)
	#
	# There is a 'header' section
	# Then each test run is in a 'test' section
	#
	# The header section is from the beginning of the file
	# until the first test section, which is a status line with 'Starting test ...'
	#
	start_line = 0
	current_line = 0
	max_line = len(lines)
	while current_line < max_line and not is_starting_line(lines[current_line]):
		current_line += 1

	header_positions = (start_line, current_line)
	tests_positions = []
	data_dict = dict()

	# Now, find the lines for each test
	# Look for the next starting test line (or the end)
	while current_line < max_line:
		start_line = current_line
		current_line += 1
		while current_line < max_line and not is_starting_line(lines[current_line]):
			current_line += 1
		tests_positions.append((start_line, current_line))

	data_dict['system'] = process_header(lines[header_positions[0]:header_positions[1]])
	data_dict['test'] = list()
	for test_pos in tests_positions:
		data_dict['test'].append(process_test(lines[test_pos[0]:test_pos[1]]))

	return data_dict


def process_data_stats_line(data_dict, line):
	k,v = line.split(':')
	data_dict[k.strip()] = v.strip()

def process_single_data_file(path):
	with open(path) as data_file:
		lines = data_file.readlines()

	stats = list()
	current = 0
	max_line = len(lines)
	data_file_dict = dict()

	while current < max_line and not lines[current].startswith('Threads started!'):
		if lines[current].startswith('Number of threads'):
			process_data_stats_line(data_file_dict, lines[current])
		current += 1
	current += 1

	while current < max_line and not lines[current].startswith('OLTP'):
		line = lines[current].strip()
		if len(line) == 0:
			current += 1
			continue
		data = line.split(',')
		data_dict = dict()

		data_dict['elapsed time'] = data[0][1:6].strip()
		process_data_stats_line(data_dict, data[0][7:])

		for datum in data[1:]:
			process_data_stats_line(data_dict, datum)

		stats.append(data_dict)
		current += 1
	data_file_dict['reports'] = stats

	current += 1	# skip the "OLTP test statistics:"
	current += 1	# skip over "queries performed:"
	queries_stats = dict()
	if current+3 < max_line:
		process_data_stats_line(queries_stats, lines[current])
		process_data_stats_line(queries_stats, lines[current+1])
		process_data_stats_line(queries_stats, lines[current+2])
		process_data_stats_line(queries_stats, lines[current+3])
	current += 4
	data_file_dict['queries performed'] = queries_stats

	oltp_stats = dict()
	while current < max_line and len(lines[current].strip()) > 0:
		process_data_stats_line(oltp_stats, lines[current])
		current += 1
	data_file_dict['oltp statistics'] = oltp_stats
	current += 1	# skip blank line

	current += 1	# skip "General statistics"
	general_stats = dict()
	if current+2 < max_line:
		process_data_stats_line(general_stats, lines[current])
		process_data_stats_line(general_stats, lines[current+1])
		process_data_stats_line(general_stats, lines[current+2])
	current += 3
	current += 1	# skip "response time"
	response_stats = dict()
	while current < max_line and len(lines[current].strip()) > 0:
		process_data_stats_line(response_stats, lines[current])
		current += 1
	data_file_dict['response times'] = response_stats
	data_file_dict['general statistics'] = general_stats
	current += 1	# skip blank line

	current += 1	# skip "Threads fairness"
	fairness_stats = dict()
	while current < max_line and len(lines[current].strip()) > 0:
		process_data_stats_line(fairness_stats, lines[current])
		current += 1
	data_file_dict['threads fairness'] = fairness_stats

	return data_file_dict

def process_data_files(path):
	"""
	Gather the data from the *.data files in the directory.

	Parameters:
		path : string
		Path to the directory containing the *.data files.

	Returns:
		A dict containing the information gathered from the *.data files.
	"""
	files_dict = dict()
	pathlist = Path(path).glob('*.data')
	for path in pathlist:
		path_str = str(path)
		files_dict[str(path)] = process_single_data_file(path)
	return files_dict

class TestMethods(unittest.TestCase):
	def test_linetype(self):
		self.assertEqual("header", classify_timer_linetype("  	  PID USER      PR  NI    VIRT    RES    SHR S   CPU  MEM      TIME COMMAND"))
		self.assertEqual("timer", classify_timer_linetype("21:34:27 == 11924 root      20   0 11.355g 220068  11432 S   0.0  0.1   0:01.37 mysqld"))
		self.assertEqual("prim", classify_timer_linetype("-- wsrep_flow_control_interval  [ 5000, 5000 ]"))
		self.assertEqual("secon", classify_timer_linetype("== wsrep_slave_threads  16"))
		self.assertEqual("status", classify_timer_linetype("Starting warmup"))

if __name__ == '__main__':
    unittest.main()

