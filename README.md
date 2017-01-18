# SSDdiag
Diagnostics software for Samsung SSD EVO 840 problems

System requirements:
OpenOCD.org and a supported JTAG adapter (at the moment only Novena is a certified JTAG adapter)
Perl.org

It was designed and tested on EVO 840 with EXT0BB6Q and EXT0CB6Q firmware versions.

Usage:
Adapt mex1.conf to your JTAG adapter
Run ssddiag.pl

If you want additional diagnostics, run it with --debug parameter, but this can increase the runtime from 1 minute to 60 minutes.


If you need more information, please read the Repair Manual:
http://www2.futureware.at/~philipp/ssd/TheMissingManual.pdf

Sample diagnostics can be found here:
http://www2.futureware.at/~philipp/ssd/diag/
