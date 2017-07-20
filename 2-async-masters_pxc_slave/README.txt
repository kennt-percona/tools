This creates the conditions for 2 async masters feeding data into a 1-node PXC cluster

This script will create a multi-source async replication environment.
This will have two async masters replicating to a single PXC node.

Two async masters feeding into a single PXC node. 
There are three mysqld processes:
    Async Master A
    Async Master B
    PXC Node #1 - Async Slave

Procedure:
  Machine 1:  init_master
              start_master
              init_pxc
              start_pxc
              init_channels

(afterwards)
  Machine 1:  stop_pxc
              stop_master

(cleanup)
  Machine 1:  wipe

