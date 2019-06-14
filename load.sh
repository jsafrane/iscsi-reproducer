#!/bin/bash

# Create $IQN at the beginning and then attach / detach it in an endless loop.
# touch "finish" to stop the test.

. ./lib.sh

/bin/rm finish

startTarget

I=0
while ! test -e finish; do
	I=$(( $I+1 ))
	write $I
	check $I
done

stopTarget
