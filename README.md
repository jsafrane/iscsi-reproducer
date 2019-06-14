Reproducer for https://github.com/kubernetes/kubernetes/issues/78987

Usage:

1. Create 10 IQNs and run 10 loops that just attach / mount / (write or check) / detach / unmount each IQN in endless loop:
    ```
    $ for i in {1..10}; do ./load.sh $i &>log-$i & done
    ```
    This should work without any issue (and error in `dmesg`).

2. Create a new IQN while the previous endless loops are still running:
    ```
    $ ./poke.sh 666
    ```
    This will only add a new IQN to the target and delete it. Nobody uses the IQN!

3. Check that the **other IQNs** were not happy about 2.
    ```
    $ dmesg | grep error
    [77922.686359] Buffer I/O error on dev sdc, logical block 123896, async page read
    [77922.706699] Buffer I/O error on dev sdc, logical block 123897, async page read
    [77922.724978] Buffer I/O error on dev sdc, logical block 123898, async page read
    [77922.730593] Buffer I/O error on dev sdc, logical block 123899, async page read
    ```

4. (cleanup). Stop the endless loops from 1.
    ```
    $ touch finish
    ```

    This should stop and clean up everything. Use `clean.sh` if not.

System load may be important factor in reproducing this bug. Some iscsiadm timeouts are expected, they're retried shortly. `5` parallel loops are enough for single core VM, try with higher numbers if you can't reproduce it.
