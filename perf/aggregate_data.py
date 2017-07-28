
#
# Aggregate and summarize
#

import sys
import pprint
import collections
import numpy as np
import math
from scipy import stats
from pathlib import Path

from common import process_data_files
from common import process_timer_file

if len(sys.argv) < 2 or len(sys.argv) > 3:
	print("Usage: aggregate_data.py <path-to-file> <csv>")
	print("  Supply the directory base only")
	print("  The directory with the suffix .1 will be ignored")
	exit(1)

output_csv = (len(sys.argv) > 2 and sys.argv[2] == 'csv')
base_dir = sys.argv[1]

pp = pprint.PrettyPrinter(indent=4)
#pp.pprint(datafiles)

system_info = None
test_reports = dict()


pathlist = Path(".").glob(base_dir+'*')
for path in pathlist:
	path_str = str(path)
	if path_str.endswith(".1"):
		if not output_csv:
			print("Skipping " + path_str)
		continue
	if not output_csv:
		print("Processing " + path_str)
	sysbench_data = process_data_files(path)
	timer_data = process_timer_file(path_str + "/timer.txt")

	# Gather data
	if system_info is None:
		system_info = dict()
		system_info['cluster-size'] = timer_data['system']['primary']['wsrep_cluster_size']
		system_info['applier-threads']= timer_data['system']['primary']['wsrep_slave_threads']
		system_info['fc-interval']= timer_data['system']['primary']['wsrep_flow_control_interval']

	# Verify that the system information all matches up
	if system_info['cluster-size'] != timer_data['system']['primary']['wsrep_cluster_size']:
		raise ValueError("cluster size mismatch! {0} != {1}".format(system_info['cluster-size'], timer_data['system']['primary']['wsrep_cluster_size']))
	if system_info['applier-threads'] != timer_data['system']['primary']['wsrep_slave_threads']:
		raise ValueError("applier threads mismatch! {0} != {1}".format(system_info['applier-threads'], timer_data['system']['primary']['wsrep_slave_threads']))
	if system_info['fc-interval'] != timer_data['system']['primary']['wsrep_flow_control_interval']:
		raise ValueError("flow control interval mismatch! {0} != {1}".format(system_info['fc-interval'], timer_data['system']['primary']['wsrep_flow_control_interval']))

	if system_info['cluster-size'] != timer_data['system']['secondary']['wsrep_cluster_size']:
		raise ValueError("cluster size mismatch! {0} != {1}".format(system_info['cluster-size'], timer_data['system']['secondary']['wsrep_cluster_size']))
	if system_info['applier-threads'] != timer_data['system']['secondary']['wsrep_slave_threads']:
		raise ValueError("applier threads mismatch! {0} != {1}".format(system_info['applier-threads'], timer_data['system']['secondary']['wsrep_slave_threads']))
	if system_info['fc-interval'] != timer_data['system']['secondary']['wsrep_flow_control_interval']:
		raise ValueError("flow control interval mismatch! {0} != {1}".format(system_info['fc-interval'], timer_data['system']['secondary']['wsrep_flow_control_interval']))

	for test in timer_data['test']:
		thread_count = int(test['thread-count'])
		if thread_count not in test_reports:
			test_reports[thread_count] = collections.defaultdict(list)
		report = test_reports[thread_count]
		report['recv-queue-avg'].append(test['secondary']['wsrep_local_recv_queue_avg'])
		report['recv-queue-max'].append(test['secondary']['wsrep_local_recv_queue_max'])
		report['send-queue-avg'].append(test['primary']['wsrep_local_send_queue_avg'])
		report['send-queue-max'].append(test['primary']['wsrep_local_send_queue_max'])
		report['flow-control-recv'].append(test['primary']['wsrep_flow_control_recv'])
		report['flow-control-paused'].append(test['primary']['wsrep_flow_control_paused'])
		report['cert-distance'].append(test['primary']['wsrep_cert_deps_distance'])

		report['cpu-usage'].append( np.mean( [float(x['cpu']) for x in test['timer-ticks']]) );

	for key, data in sysbench_data.items():
		report = test_reports[int(data['Number of threads'])]
		report['query-count'].append( data['queries performed']['total'])
		report['response-time-min'].append(data['response times']['min'])
		report['response-time-avg'].append(data['response times']['avg'])
		report['response-time-max'].append(data['response times']['max'])

		report['ignored-errors'].append(data['oltp statistics']['ignored errors'])

#pp.pprint(system_info)
#pp.pprint(test_reports)

# Ok we have all the data, now generate the statistics for them
results = list()
for test_key in sorted(test_reports.keys()):
	report = test_reports[test_key]
	n, minmax, mean, var, sken, kurt = stats.describe([float(x)/100 for x in report['query-count']])
	ci = stats.t.interval(0.95, n-1, loc=mean, scale=math.sqrt(var/n))
	result = dict()
	result['thread-count'] = test_key
	result['qps-min'] = minmax[0]
	result['qps-max'] = minmax[1]
	result['qps-avg'] = mean
	result['qps-ci'] = (ci[1] - ci[0])/2
	result['qps-std'] = math.sqrt(var)

	result['cpu-usage'] = np.mean(report['cpu-usage'])
	result['recv-queue-avg'] = np.mean([float(x) for x in report['recv-queue-avg']])
	result['fc-paused'] = np.mean( [float(x) for x in report['flow-control-paused']])
	result['fc-events'] = np.mean([float(x) for x in report['flow-control-recv']])

	result['response-time-avg'] = np.mean([float(x[:-2]) for x in report['response-time-avg']])
	results.append(result)

if output_csv:
	print("#thds,qps,qps(sd),cpu,recv-q,rsp-tm,fc-time,fc-msgs")
else:
	print("#thds      qps qps(sd)       cpu    recv-q    rsp-tm  fc-time   fc-msgs")

for result in results:
	if output_csv:
		print("{0},{1:.2f},{2:.2f},{5:.2f},{3:.2f},{7:.2f},{4:.1f},{6:.1f}".format(
			result['thread-count'],
			result['qps-avg'],
			result['qps-std'],
			result['recv-queue-avg'],
			result['fc-paused']*100,
			result['cpu-usage'],
			result['fc-events'],
			result['response-time-avg']))
	else:
		print("{0:3}  {1:9.2f}  {2:6.2f}  {5:7.2f}%  {3:8.2f}   {7:5.2f}ms    {4:4.1f}% {6:9.1f}".format(
			result['thread-count'],
			result['qps-avg'],
			result['qps-std'],
			result['recv-queue-avg'],
			result['fc-paused']*100,
			result['cpu-usage'],
			result['fc-events'],
			result['response-time-avg']))




