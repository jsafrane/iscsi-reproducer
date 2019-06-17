if [ -z "$1" ]; then
    echo "Usage: $0 <unique number>"
    exit 1
fi

mkdir -p /srv/iscsi

# Global variables, yay!
# Unique IQN. $1 is expected to be a short string, e.g. "1"
IQN=iqn.2003-01.io.k8s:e2e.volume-$1
# Sanitized IQN, usable as docker container name.
SANITIZED_IQN=$(echo $IQN | tr : - )
# Device for given $IQN
DEV=/dev/disk/by-path/ip-127.0.0.1:3260-iscsi-$IQN-lun-0
# Mount path for given $IQN
MNT=/mnt/test/$IQN

# "Start" iSCSI target, using a container.
# The container is Fedora 28. It just bind-mounts various directories
# from the host and runs script [1] that adds a new IQN to kernel on the host.
# Every test uses unique IQN, because they're idependent and run in parallel
# and I don't want to maintain a state that would make sure the first test
# creates IQN, subsequent tests just add a LUN there and the last test removes
# the shared IQN.
# Container is used because that's the only thing that's available in
# Kubernetes e2e test framework.
# 1: https://github.com/kubernetes/kubernetes/blob/master/test/images/volume/iscsi/run_iscsi_target.sh#L28
function startTarget()
{
	# Remove any old container
	docker rm test-$SANITIZED_IQN

	docker run -d --name=test-$SANITIZED_IQN --network=host --privileged -v /lib/modules:/lib/modules -v /sys/kernel:/sys/kernel -v /srv/iscsi:/srv/iscsi gcr.io/kubernetes-e2e-test-images/volume/iscsi:2.0 $IQN
	# Wait for the container to finish target preparation
	while ! docker logs test-$SANITIZED_IQN | grep "iscsi target started"; do
		sleep 0.1
	done
}

# Remove the IQN by sending SIGTERM to the script in the container, see
# [1] above.
function stopTarget()
{
	docker stop -t 90 test-$SANITIZED_IQN
}

# Attach $IQN and mount it. Make a filesystem there if necessary.
function attach()
{
	iscsiadm -m iface -I default -o show
	while ! iscsiadm -m discoverydb -t sendtargets -p 127.0.0.1:3260 -I default -o new; do sleep 1; done
	while ! iscsiadm -m discoverydb -t sendtargets -p 127.0.0.1:3260 -I default --discover; do sleep 1; done
	while ! iscsiadm -m node -p 127.0.0.1:3260 -T $IQN -I default --login; do sleep 1; done
	while ! iscsiadm -m node -p 127.0.0.1:3260 -T $IQN -o update -n node.startup -v manual; do sleep 1; done
	
	# Wait for the device to appear
	while ! test -e $DEV; do
		sleep 0.1
	done

	mkdir -p $MNT
	# Create a filesystem if the device is empty
	blkid $DEV | grep ext3 || mkfs.ext3 -F $DEV

	# Always do fsck
	fsck -a $DEV

	mount $DEV $MNT
}

# Unmount $IQN and detach it.
function detach()
{
	umount $MNT
	rmdir $MNT

	# Delete the device
	D=$(basename $( readlink $DEV ) )
	echo 1 > /sys/block/$D/device/delete

	while ! iscsiadm -m node -p 127.0.0.1:3260 -T $IQN --logout -I default; do sleep 1; done
	while ! iscsiadm -m node -p 127.0.0.1:3260 -T $IQN -o delete -I default; do sleep 1; done
}

# Simulation of a writer pod: attach + mount + write + umount + detach.
function write()
{
	attach
	echo "Hello from $IQN: $1" > $MNT/file
	# store non-trivial amount of data to the volume
	dd if=/dev/urandom of=$MNT/random bs=1M count=10
	detach
}

# Simulation of a reader pod: attach + mount + check the data + umount + detach.
function check()
{
	attach $IQN
	CNT=$( cat $MNT/file )
	if [ "$CNT" != "Hello from $IQN: $1" ]; then
		echo "test mismatch, got '$CNT' instead of $IQN"
	else
		echo "test OK for $IQN"
	fi
	detach
}
