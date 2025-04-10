# multipasskubeadm
Create Kubeadm cluster with Cilium using Multipass

Make sure to install multipass on your linux VM:
`sudo snap install multipass`

Clone the repo and run: `./master.sh` to create a cluster with single controlplane and 2 dataplane nodes
Edit `CILIUM_VERSION=""` within master.sh as needed. Default is `1.16.8`

To clean-up, run `./cleanup.sh`

This installs Cilium OSS. 

