# SSDdiag
Diagnostics software for Samsung SSD EVO 840 problems

Features:
* detects the firmware version from the running code.
* looks whether the controller is able to see a SATA connection, and whether the firmware was able to establish the connection.
* checks the 8 Flash channels
* analyzes Stack-Traces
* analyzes the Inter-Process-Communication between the ARM cores, and explains their meaning
* takes approximately 1 minute to execute

System requirements:
* OpenOCD.org and a supported JTAG adapter (at the moment only Novena is a certified JTAG adapter)
* Perl.org

Supported SSDs:
* SAMSUNG EVO 840 

Supported controllers:
* SAMSUNG S4LN045X01-8030 (MEX)

Supported Firmware:
* EXT0BB6Q 
* EXT0CB6Q

Supported JTAG adapters:
* Altera USB Blaster (cheaper, slower)
* http://www.kosagi.com/w/index.php?title=Novena_Main_Page (more expensive, faster)



Usage:
Adapt mex1.conf to your JTAG adapter
Run ssddiag.pl

If you want additional diagnostics, run it with --debug parameter, but this can increase the runtime from 1 minute to 60 minutes.


If you need more information, please read the Repair Manual:
http://www2.futureware.at/~philipp/ssd/TheMissingManual.pdf

Sample diagnostics can be found here:
http://www2.futureware.at/~philipp/ssd/diag/
