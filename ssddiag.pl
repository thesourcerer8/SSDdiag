#!/usr/bin/perl -w
use strict;
use IO::Socket::INET;

my $debug=$ARGV[0] || 0;

print "Restarting OpenOCD ...\n";
system "killall openocd ".($debug?"":"2>/dev/null");
sleep(1);
system "/usr/local/bin/openocd -f mex1.conf ".($debug?"":"2>/dev/null")."&";
sleep(5);


my $openocd=IO::Socket::INET->new(PeerAddr=>"localhost:6666");
#my $header=<$openocd>;
#print $header."\n";
#$/="\n>";

print "Connecting to OpenOCD:\n";

sub ocd($)
{
  print STDERR "-> $_[0]\n" if($debug);
  $openocd->send("$_[0]\x1a");
  $/="\x1a";
  my $v="";
  my $ende=0;
  while(!$ende)
  {
    my $a="";
    $openocd->recv($a,1);
    #print "a: $a\nb: $b\n";
    if($a eq "\x1a")
    {
      $ende=1;
    }
    else
    {
      $v.=$a;
    }
  }
  print STDERR "<- $v\n" if($debug);
  return $v;
}

sub halt($)
{
  print "Halting $_[0] ...\n";
  ocd("targets $_[0]");
  ocd("halt");
  print "Halted\n" if($debug);
}

sub resume($)
{
  print "Resuming ...\n" if($debug);
  ocd("targets $_[0]");
  ocd("resume");
  print "Resumed.\n" if($debug);
}
sub getMem($)
{
  return "unknown" if($_[0]=~m/unknown/);
  my $v=ocd("ocd_mdw $_[0]");
  #print STDERR "mdw: $v\n";
  my $val=substr($v,12,8);
  if($val!~m/^[0-9a-f]{8}$/)
  {
    print "Error: $v\n";
    return "unknown";
  }
  #print STDERR "val: $val\n";
  return $val;
}
sub getMemDump($$)
{
  my $v=ocd("ocd_mdb $_[0] $_[1]");
  return $v;
}

sub getPC($)
{
  #print "Getting Program Counter...\n";
  ocd("targets $_[0]");
  my $val=ocd("ocd_poll");
  print "Problem with the firmware: $_[0] has hit an Undefined instruction\n" if($val=~m/current mode: Undefined instruction/s);
  my $v=$1 if($val=~m/pc: 0x(\w+)/);
  print "Program counter $_[0]: $v\n";
  return $v;
}

ocd("targets 0");
halt("mex1");

# This only correlates to the core power, I am not sure, what it is.
my $corepower=getMem(0x20504000);
print "CPU Core power: $corepower\n";

my $mex2awake=$corepower eq "unknown"?0:hex($corepower)?1:0;
my $mex3awake=$corepower eq "unknown"?0:hex($corepower)?1:0;

print $mex2awake?"MEX2 is awake!\n":"MEX2 seems to be still sleeping.\n";
print $mex3awake?"MEX3 is awake!\n":"MEX3 seems to be still sleeping.\n";

ocd("mex2 arp_examine") if($mex2awake);
ocd("mex3 arp_examine") if($mex3awake);

halt("mex2") if($mex2awake);
halt("mex3") if($mex3awake);

ocd("targets 0");

my $firmware=getMem(0x10000);

my %firmwarename=("01a204a4"=>"EVO 840 SAFE-Mode ROM Firmware","e2800b02"=>"EXT0CB6Q","68026002"=>"EXT0BB6Q","46d92030"=>"EXT0CB6Q MEX3");
print "Firmware Identifier: ".$firmware." ".(defined($firmwarename{$firmware})?"identified: ".$firmwarename{$firmware}:"")."\n";

my $mex1pc=getPC("mex1");
my $mex2pc=""; $mex2pc=getPC("mex2") if($mex2awake);
my $mex3pc=""; $mex3pc=getPC("mex3") if($mex3awake);

my %ipccode=("00000000"=>"NULL","4d524453"=>"SDRM","4d435442"=>"BTCM","88883164"=>"8888");

sub ipc($)
{
  return $_[0]."/".($ipccode{$_[0]}||"unknown");
}

my $ipc0=getMem(0x10020800);
my $ipc4=getMem(0x10020804);
my $ipc8=getMem(0x10020808);
my $ipcC=getMem(0x1002080C);
my $ipc10=getMem(0x10020810);

print "IPC0: ".ipc($ipc0)."\n";
print "IPC4 (MEX2): ".ipc($ipc4)."\n";
print "IPC8 (MEX3): ".ipc($ipc8)."\n";
print "IPCC (MEX2): ".ipc($ipcC)."\n";
print "IPC10 (MEX3): ".ipc($ipc10)."\n";


if($firmware eq "e2800b02" || $firmware eq "68026002" || $firmware eq "46d92030")
{
  if($ipccode{$ipcC} eq "NULL" && $ipccode{$ipc10} eq "NULL")
  {
    print "MEX1 seems to have a problem with its initialisation\n";
  }
  if($ipccode{$ipcC} eq "SDRM" && $ipccode{$ipc10} eq "SDRM")
  {
    print "MEX2 and MEX3 both still have to complete their initialisation\n";
  }
  if($ipccode{$ipcC} eq "BTCM" && $ipccode{$ipc10} eq "SDRM")
  {
    print "MEX2 has completed its initialisation, but MEX3 has not completed its initialisation yet\n";
  }
  if($ipccode{$ipcC} eq "SDRM" && $ipccode{$ipc10} eq "BTCM")
  {
    print "MEX3 has completed its initialisation, but MEX2 has not completed its initialisation yet\n";
  }
  if($ipccode{$ipcC} eq "BTCM" && $ipccode{$ipc10} eq "BTCM")
  {
    print "MEX2 and MEX3 have completed their initialisation successfully\n";
  }
  print "MEX1 is waiting for MEX2 and/or MEX3 to complete the initialisation.\n" if($mex1pc =~m/^000108d[8ace]$/);
  print "MEX3 crashed, had run the error handler and is now in an endless loop.\n" if($mex3pc eq "80081576");
}


my @indicators=(0x0080471C,0x008049AC,0x00808020,0x00808094,0x0080C160,0x0080C428,0x0080C42C,0x825BEC,0x00804E1C,0x00804564,0x2050F024,0x20440018,0x825C00,0x100205B0,0x800a1ad4,0x800a1a10,0x801070,0x80131C,0x2048000C,0x2049000C,0x204A000C,0x204B000C,0x2048012C,0x2049012C,0x204A012C,0x204B012C,0x2038000C,0x2039000C,0x203A000C,0x203B000C,0x2038012C,0x2039012C,0x203A012C,0x203B012C);

print "Indicator ".sprintf("0x%X",$_).": ".getMem($_)."\n" foreach(sort @indicators);

my $satastatus=getMem(0x200000AC);
print "SATA PHY Status: ".((hex($satastatus)&0x1000)?"Connected":"Not connected")." ($satastatus)\n";
print "".((hex($satastatus)&1)?"There is/was a SATA connection request\n":"There is currently no SATA connection request\n");

my $maxtemp=getMem(0x0081C6A4);
print "Maximum Temperature: $maxtemp\n";
my $mintemp=getMem(0x0081C6A8);
print "Minimum Temperature: $mintemp\n";
my $meltdown=getMem(0x0081C6C0);
print "Meltdown Counter: $meltdown\n";
my $interrupts=getMem(0x0081C6B8);
print "Interrupt Counter: $interrupts\n";


foreach my $chan(0 .. 7)
{
  my $addr=0x2038000C+($chan>>2<<20)+(($chan&3)<<16);
  my $status=getMem($addr);
  print "Flash Channel #$chan Status: ".((substr($status,0,4) eq "0fff")?"GOOD":"HAS A PROBLEM!")." ($status)\n";
}


sub Hex2String($)
{
  my $d=$_[0]; $d=~s/0x\w+: //;
  my $r="";
  while($d=~s/([0-9a-f][0-9a-f]) //)
  {
    $r.=sprintf("%c",hex($1));
  }
  $r=~s/\x00.*$//s;
  return $r;
}

foreach my $core(0 .. 2)
{
  my $mode=Hex2String(getMemDump(0x801008+24*$core+4,19));
  print "Mode $core: $mode\n";
  my $v=getMemDump(0x801008+24*$core+1,1);
  print "Byte=1: $v\n";
}



my $eman=getMem(0x008010A0);
my $v3=0;
if($eman ne "unknown")
{
  print "Exception Manager: $eman\n";
  foreach my $exception(0  .. 3)
  {  
    my $addr=hex($eman)+4*(127*$exception+($exception<<8))+172;
    print "eman: ".hex($eman)." ($eman) + 172 = $addr\n";
    print "addr: ".sprintf("0x%X",$addr)."\n";
    my $v5=getMem(sprintf("0x%X",$addr));
    print "v5: $v5\n";
    print "<EXCEPTION_$exception>\n";
    print "<DEFENCECODE_RUNCOUNT>".getMem($addr)."</DEFENCECODE_RUNCOUNT>\n";
    print "<DEFENCECODE_META_RUNCOUNT>".getMem($addr+8)."</DEFENCECODE_META_RUNCOUNT>\n";
    print "<RECLAIM_LOG_COUNT>".getMem($addr+57132)."</RECLAIM_LOG_COUNT>\n";
  }
}

my $cmdarr=getMem(0x808094);
print "Commando Array: $cmdarr\n";
if($cmdarr ne "unknown" && hex($cmdarr)>=0x800000 && hex($cmdarr)<0x80000000)
{
  foreach my $cmd(0 .. 63)
  {
    my $base=hex($cmdarr)+32*$cmd;
    print "CMD:$cmd IDX: ".getMem(sprintf("0x%X",$base+0))." TIME:".getMem($base+4)." LBA:".getMem($base+8)." SCTCNT:".getMem($base+12)." CMDQR:".getMem($base+16)." CMDQW:".getMem($base+18)." CMD:".getMem($base+20)." TAG:".getMem($base+24)." CMD_STEP:".getMem($base+28)."\n"; 
  }
}
else
{
  print "Commando Array seems to be out of range, therefore we do not dump it.\n";
}

my $sfrcount=getMem(0x801000);
my $sfrpointer=getMem(0x801004);
print "SFR POINTER: $sfrpointer\n";
print "SFR COUNT: $sfrcount\n";
if($sfrpointer ne "unknown" && hex($sfrpointer)>=0x80000 && hex($sfrpointer)<=0x8FFFFFFF && hex($sfrcount)<=200)
{
  foreach my $sfr(0 .. hex($sfrcount)-1)
  {  
    my $sfrpos=hex($sfrpointer)+8*$sfr;
    print "SFR ID:$sfr ";
    my $base=getMem($sfrpos);
    my $size=getMem($sfrpos+4);
    print "BASE:$base SIZE:$size\n";
    print getMemDump("0x$base","0x$size")."\n" if($debug);
  }
  print "You can get mem dumps of the SFR regions in the debug mode of this diagnostic tool if needed. (2 MB of output and it takes approx. an hour)\n" if(!$debug);
}
else
{
  print "SFR Data does not seem to be valid\n";
}

my @stacks=(
["SVC",0x826C00,0x827C00,"25"],
["FIQ",0x827C00,0x827C80,"21"],
["IRQ",0x827C80,0x827D80,"23"],
["UND",0x827D80,0x827E00,"29"],
["ABT",0x827E00,0x827F00,"27"],
#["USR",0x0E21E99B,0x0E21E99B,"13"] # Yes, this is the tragedy, the UserSpace Stack, but GCC seems to use it anyway.
);

ocd("targets mex3");

foreach my $s(@stacks)
{
  #print "reg: $s->[3]\n";
  my $sp="unknown"; $sp=$1 if(ocd("ocd_reg ".($s->[3]))=~m/0x(\w+)/);
  print "Stack Pointer $s->[0]: $sp\n";
  if($sp ne "unknown" && hex($sp)>=$s->[1] && hex($sp)<=$s->[2])
  {
    my $i;
    foreach($i=hex($sp); $i<$s->[2];$i+=4)
    {
      my $pos=getMem($i);
      my $h=hex($pos);
      my $d=""; $d="*" if(($h>=0x64 && $h<=0x20000) || ($h>=0x80080000 && $h<=0x800B0000));
      print "Stack Value: $i : ".getMem($i)." $d\n";
    }
  }
}



# All RAM access must be done as late as possible, since this can crash it when the firmware is completely damaged
ocd("targets mex3");
my $magic=getMem(0x80000024);
print "SA is loaded correctly: ".($magic eq "29135201" ? "yes":$magic eq "00000000"?"no":"unknown")." (magic:$magic)\n";

my $base8=getMem(0x8000DCE3);
print "Base8: $base8\n";

resume("mex1");
resume("mex2") if($mex2awake);
resume("mex3") if($mex3awake);

sleep(1);
$openocd->close();
system "killall openocd";

