#!/bin/bash
#Owner Sandesh KV
# List of node names
NODES=("k8s-master" "k8s-worker1" "k8s-worker2")

# Function to delete nodes
cleanup_nodes() {
    for NODE in "${NODES[@]}"; do
        echo "Deleting node: $NODE"
        if multipass list | grep -q $NODE; then
            multipass stop $NODE
            multipass delete $NODE
        else
            echo "Node $NODE does not exist."
        fi
    done
    multipass purge
    echo "All specified nodes have been deleted."
}

# Run the cleanup function
cleanup_nodes
