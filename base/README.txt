This directory contains the scripts used to setup a topology.

This works by creating <node-name>.info files.  These files contain the information
about a named node.  This allows the nodes to be manipulated by name.

For instance, one can create nodes on a local machine and remote machines.
	pxc-config.sh node1 sample.cnf 192.168.50.1 4100
	pxc-config.sh node2 sample.cnf 192.168.50.1 4200

	pxc-config.sh node3 sample.cnf 192.168.100.100 4100

Then, startup the cluster
	cluster-start.sh node1 node2

(node3 needs to be started on the remote machine)
	pxc-config.sh node1 sample.cnf 192.168.50.1 4100
	pxc-config.sh node2 sample.cnf 192.168.50.1 4200

	pxc-config.sh node3 sample.cnf 192.168.100.100 4100

	cluster-join.sh node1 node3


Command-lines can be started to any node after that
	node-cl node1
	node-cl node3

To startup a node as a standalone (non-PXC) node:
	mysql-start node3

To setup async replication (node1 as master, node3 as slave)
	init-master.sh node1
	init-slave.sh node1 node3 <optional-channel-name>
	node-query.sh node3 'start slave'
