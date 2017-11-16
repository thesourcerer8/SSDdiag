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

print "Connecting to OpenOCD:\n";

sub min($$)
{
  return $_[0]<$_[1]?$_[0]:$_[1];
}

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
  print STDERR "mdw: $v\n" if($debug);
  my $val=substr($v,12,8);
  if($val!~m/^[0-9a-f]{8}$/)
  {
    print "Error: $v\n";
    if($v=~m/Target not examined yet/)
    {
      print "SSD does not seem to be powered up or properly connected, or the debug interface crashed. Please check the connection and OpenOCD settings in mex1.conf, and restart the SSD if necessary\n";
      exit;
    }
    return "unknown";
  }
  #print STDERR "val: $val\n";
  return $val;
}
sub getMemByte($)
{
  return "unknown" if($_[0]=~m/unknown/);
  my $v=ocd("ocd_mdb $_[0]");
  #print STDERR "mdb: $v\n";
  my $val=substr($v,12,2);
  if($val!~m/^[0-9a-f]{2}$/)
  {
    print "Error: $v\n";
    if($v=~m/Target not examined yet/)
    {
      print "SSD does not seem to be powered up or properly connected, or the debug interface crashed. Please check the connection and OpenOCD settings in mex1.conf, and restart the SSD if necessary\n";
      exit;
    }
    return "unknown";
  }
  #print STDERR "val: $val\n";
  return $val;
}
sub getMemWord($)
{
  return "unknown" if($_[0]=~m/unknown/);
  my $v=ocd("ocd_mdh $_[0]");
  #print STDERR "mdh: $v\n";
  my $val=substr($v,12,4);
  if($val!~m/^[0-9a-f]{4}$/)
  {
    print "Error: $v\n";
    if($v=~m/Target not examined yet/)
    {
      print "SSD does not seem to be powered up or properly connected, or the debug interface crashed. Please check the connection and OpenOCD settings in mex1.conf, and restart the SSD if necessary\n";
      exit;
    }
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

sub getPC($) # Side-effect: Switches to the specified core
{
  #print "Getting Program Counter...\n";
  ocd("targets $_[0]");
  my $val=ocd("ocd_poll");
  print "Problem with the firmware: $_[0] has hit an Undefined instruction\n" if($val=~m/current mode: Undefined instruction/s);
  my $v=""; $v=$1 if($val=~m/pc: 0x(\w+)/);
  print "Program counter $_[0]: $v\n";
  return $v;
}

ocd("targets mex1");
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

ocd("targets mex1");

my $firmware=getMem(0x10000);


my %firmwarename=("01a204a4"=>"EVO 840 SAFE-Mode ROM Firmware","e2800b02"=>"EXT0CB6Q","68026002"=>"EXT0BB6Q","46d92030"=>"EXT0CB6Q MEX3");
print "Firmware Identifier: ".$firmware." ".(defined($firmwarename{$firmware})?"identified: ".$firmwarename{$firmware}:"")."\n";

my $mex1pc=getPC("mex1");
my $mex2pc=""; $mex2pc=getPC("mex2") if($mex2awake);
my $mex3pc=""; $mex3pc=getPC("mex3") if($mex3awake);
ocd("targets mex1"); # Needs to be reset after getPC



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


my $rangestate1=getMem(0x800200F4);
my $rangestate2=getMem(0x800200F8);
if($rangestate1 eq "00000000" && $rangestate2 eq "000000ff")
{
  print "Crypto ranges are in PREACTIVE state\n";
}
elsif($rangestate1 eq "00000000" && $rangestate2 eq "00000000")
{
  print "Crypto ranges are in POSTACTIVE state\n";
}
elsif($rangestate1 eq "00000001" && $rangestate2 eq "00000000")
{
  print "Crypto ranges are in ACTIVE state\n";
}
elsif($rangestate1 eq "3f3f3f3f" && $rangestate2 eq "3f3f3f3f")
{
  print "Crypto ranges are in SAFE state\n";
}
else
{
  print "Unknown crypto range state: $rangestate1 $rangestate2\n";
}

my $ivpointer1=getMem(0x825E08);
my $ivpointer2=getMem(0x8003047C);
print "IVPointers: $ivpointer1 (".($ivpointer1 eq "803b5200" ? "GOOD":"BAD")."), $ivpointer2 (".($ivpointer2 eq "803b5200" ? "GOOD":"BAD").")\n";
print "IV for User Data: ".getMemDump(0x803B5200,32);


my $ssdsize=getMem(0x8232FC);
print "SSD Size: ".hex($ssdsize)." 512-Byte Blocks = ".(hex($ssdsize)/2/1024/1024)." GiB = ".(hex($ssdsize)/2/1000/1000)." GB\n";


my $satastatus=getMem(0x200000AC);
print "SATA PHY Status: ".((hex($satastatus)&0x1000)?"Connected":"Not connected")." ($satastatus)\n";
print "".((hex($satastatus)&1)?"There is/was a SATA connection request\n":"There is currently no SATA connection request\n");

my $temp=getMemByte(0x0081C6A0);
print "Current Temperature: $temp\n";
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
  my $addr8=0x2038000C+($chan>>2<<20)+(($chan&3)<<16);
  my $addr0=0x20300118+($chan>>2<<20)+(($chan&3)<<16);
  my $addrc=0x203C005C+($chan>>2<<20)+(($chan&3)<<16);
  my $status=getMem($addr8);
  my $statusC=getMem($addrc);
  print "Flash Channel #$chan Status: ".((substr($status,0,4) eq "ffff")?"GOOD":"HAS A PROBLEM!")." ($status)  4-Status: ".($addr0 & 4)." ($addr0) (203C005C:$statusC)\n";
}

my $curtime4k=getMem(0x20506044);
my $ssdtime4k=2**32-hex($curtime4k);
my $seconds4k=int($ssdtime4k/4000);
my $minutes4k=int($seconds4k/60);
my $hours4k=int($minutes4k/60);
my $days4k=int($hours4k/24);

my $curtime1k=getMem(0x20501204);
my $ssdtime1k=2**32-hex($curtime1k);
my $seconds1k=int($ssdtime1k/1000);
my $minutes1k=int($seconds1k/60);
my $hours1k=int($minutes1k/60);
my $days1k=int($hours1k/24);

my $cputime=time();  
print "Current SSD time 1KHz: $ssdtime1k ($curtime1k) uptime: $seconds1k seconds => $minutes1k minutes => $hours1k hours\n";
print "Current SSD time 4KHz: $ssdtime4k ($curtime4k) uptime: $seconds4k seconds => $minutes4k minutes => $hours4k hours\n";

sub Hex2String($)
{
  my $d=$_[0]; $d=~s/0x\w+: //;
  my $r="";
  while($d=~s/([0-9a-f][0-9a-f]) //)
  {
    $r.=sprintf("%c",hex($1)) if(hex($1)>=32 && hex($1)<=127);
  }
  $r=~s/\x00.*$//s;
  return $r;
}

foreach my $cpu("mex2","mex3")
{
  ocd("targets $cpu");
  foreach my $core(0 .. 2)
  {
    my $mode=Hex2String(getMemDump(0x801008+24*$core+4,19));
    print "Core: $cpu Mode $core: $mode   ";
    my $v=getMemDump(0x801008+24*$core+1,1);
    print "Byte=1: $v";
  }
}
ocd("targets mex1");

print "Encryption Ranges table:\n";
foreach(0 .. 19)
{
  my $base=0x800200f4+$_*16;
  print "Entry:".sprintf("%02X",$_)." Enabled:".getMem($base)." KeySlotId:".getMem($base+4)." LbaStart:".getMem($base+8)." LbaEnd:".getMem($base+12)."\n";
}
print "KeySlotIdTable:\n";
foreach(0 .. 7)
{
  print "Entry:$_ KeySlotId:".getMemByte(0x800200D4+$_)."\n";
}
print "RangeIdArray:\n";
foreach(0 .. 15)
{
  print "Entry:$_ RangeId:".getMemByte(0x800200E4+$_)."\n";
}


my $satarequestbase=getMem(0x81C648);
print "SATA Request base: $satarequestbase ".($satarequestbase eq "00800c00"?"(GOOD)":"(seems to be unavailable)")."\n";
my $satarequestnum=getMem(hex($satarequestbase)+536);
print "SATA Request number: $satarequestnum ".(hex($satarequestnum)<34?"(GOOD)":"(OUT OF RANGE)")."\n";
print "SATA Request mybase: ".sprintf("0x%X",hex($satarequestbase)+16*hex($satarequestnum))."\n";

my $cmdarr=getMem(0x808094);
my $cmdmax=getMem(0x81CB58);

print "Command Array: $cmdarr ".(($cmdarr eq "0081cb7c")?"(GOOD)":"(seems to be unavailable)")."\n";
print "Command max: $cmdmax\n";
#$cmdarr=0x0081CB7C; # to override the pointer and read it out anyway
if($cmdarr ne "unknown" && hex($cmdarr)>=0x800000 && hex($cmdarr)<0x80000000)
{
  foreach my $cmd(0 .. 63)
  {
    my $base=hex($cmdarr)+32*$cmd;
    print "CMD:".sprintf("%2d",$cmd)." IDX:".getMem(sprintf("0x%X",$base+0))." TIME:".getMem($base+4)." LBA:".getMem($base+8)." SECTORCNT:".getMem($base+12)." CMDQR:".getMemWord($base+16)." CMDQW:".getMemWord($base+18)." CMD:".getMem($base+20)." TAG:".getMem($base+24)." CMD_STEP:".getMemByte($base+28)."\n"; 
  }
}
else
{
  print "Command Array seems to be out of range, therefore we do not dump it.\n";
}

ocd("targets mex1");
if(getMem(0x808004)=~m/0081BDFC/i)
{
  print "WriteHash where LBA4k writes are stored:\n";
  foreach my $mod(0 .. 510)
  {
    my $vHashValue=getMemWord(4 * $mod + 0x0081BDFC);
    my $base=0x80FE5C+12*hex($vHashValue);
    my $LBA4k=getMem($base+4); 
    my $a=(hex($vHashValue)==0xFFFF)?"(empty)":"-> base=".sprintf("0x%X",$base)." -> LBA4k:$LBA4k";
    print "HASHmod511[$mod]=$vHashValue $a\n";
  }
}
else
{
  print "WriteHash not found.\n";
}
#foreach my $i (0 .. 510)
#{
#  print "\nFTL Map $i..".($i+9).": " if($i%10==0);
#  my $v=getMemWord(0x81BDFC+4*$i);
#  print "$v ";
#}
#print "\n";

ocd("targets mex2");
if(getMem(0x80106C)=~m/00801520/i)
{
  print "FTL Map (0x80106C=>0x801520) using LBA8Kmod4:\n";
  foreach my $mod(0 .. 3)
  {
    my $base=0x00801520 + 76*$mod;
    print "mod $mod:\n".getMemDump($base,76)."\n";
  }
}
else
{
  print "FTL Map not found.\n";
}
# TODO: We should likely do that for MEX3 too, the base address for MEX3 needs to be researched


#if(getMem(0x824F40)=~m/4[12]800000/i)
{
  print "Command delegation structure using m32M62 counter:\n";
  foreach my $core("mex2","mex3")
  {
    ocd("targets mex1");
    my $base=($core eq "mex2")?0x41800000:0x42800000;
    my $counter=getMem($base+0x874);
    print "Requests that were delegated to core:\n";
    print "Current ringbuffer element: ".hex($counter)."0x$counter\n"; 
    foreach my $mod(0 .. 61)
    {
      my $mybase=$base+0x90+32*$mod;
      print "".sprintf("%02d",$mod).((hex($counter)==$mod)?"**":": ")."LBA8K: ".getMem($mybase+8)." M:".getMem($mybase+20)." ".getMemDump($mybase,32);
    }
  }
}
#else
{
  print "Command delegation not found: ".getMem(0x824F40)."\n";
}




foreach my $core("mex2","mex3")
{
  ocd("targets $core");
  my $sfrcount=getMem(0x801000);
  my $sfrpointer=getMem(0x801004);
  print "SFR POINTER $core: $sfrpointer\n";
  print "SFR COUNT $core: $sfrcount\n";
  if($sfrpointer ne "unknown" && hex($sfrpointer)>=0x80000 && hex($sfrpointer)<=0x8FFFFFFF && hex($sfrcount)<=200)
  {
    foreach my $sfr(0 .. hex($sfrcount)-1)
    {  
      my $sfrpos=hex($sfrpointer)+8*$sfr;
      print "SFR $core ID:".sprintf("%2d",$sfr)." ";
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
}
ocd("targets mex1");


my @stacks=(
["SVC",0x826C00,0x827C00,"25"],
["FIQ",0x827C00,0x827C80,"21"],
["IRQ",0x827C80,0x827D80,"23"],
["UND",0x827D80,0x827E00,"29"],
["ABT",0x827E00,0x827F00,"27"],
#["USR",0x0E21E99B,0x0E21E99B,"13"] # Yes, this is the tragedy, the UserSpace Stack, but GCC seems to use it anyway.
);

foreach my $core("mex1","mex2","mex3")
{
  print "Stacks of core $core:\n";
  ocd("targets $core");
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
}
ocd("targets mex1");


foreach my $i (0 .. 3)
{
  my $v=getMem(0x823350 + 40 + 32 * $i + 2028);
  print "LBA cache $i: $v\n";
}


ocd("targets mex1");
my $nBlocks=getMem(0x81D39C);
print "Available Memory Blocks: $nBlocks\n";
if(hex($nBlocks)==26)
{
  foreach(0 .. hex($nBlocks)-1)
  {
    my $allocated=getMemByte(8 * $_ + 0x81D3A0 + 0);
    my $nBlocks=getMemWord(8 * $_ + 0x81D3A0 + 2);
    my $BlockAddr=getMem(8 * $_ + 0x81D3A0 + 4);
    print "Block #".sprintf("%02d",$_)." : allocated:$allocated nBlocks:$nBlocks Addr:$BlockAddr\n"; 
  }
}






# All RAM access must be done as late as possible, since this can crash it when the firmware is completely damaged
# So I have moved all the potentially crashing memory accesses (reading from >0x80000000 if RAM is not available) below this line, everything safe should be done above.

foreach my $core ("mex2","mex3")
{
  print "Looking for exceptions on $core\n";
  ocd("targets $core");
  my $eman=getMem(0x008010A0);
  #mex3: [0x008010a0]=0x800A2378
  if($eman ne "unknown")
  {
    print "Exception Manager for $core: $eman\n";
    foreach my $exception(0  .. 3)
    {  
      my $xbase=hex(getMem(hex($eman)+4*(127*$exception+($exception<<8))+172));
      print "xbase: ".sprintf("0x%X",$xbase)."\n";
      my $exceptionbase=getMem(sprintf("0x%X",$xbase));
      print "v5: $exceptionbase\n";
      print "<EXCEPTION_$exception>\n";
      print "<DEFENCECODE_RUNCOUNT>".hex(getMem($xbase))."</DEFENCECODE_RUNCOUNT>\n";
      print "<DEFENCECODE_META_RUNCOUNT>".hex(getMem($xbase+8))."</DEFENCECODE_META_RUNCOUNT>\n";
      print "<RECLAIM_LOG_COUNT>".hex(getMem($xbase+57132))."</RECLAIM_LOG_COUNT>\n";
      print "<RECOVERY_FAIL_COUNT>".hex(getMem($xbase+24))."</RECOVERY_FAIL_COUNT>\n";
      my $faillogs=hex(getMem($xbase+57840));
      print "<RECOVERY_FAIL_LOG>$faillogs</RECOVERY_FAIL_LOG>\n";
      if($faillogs && $faillogs<40)
      {
        print "<FAIL_DESCRIPTION>\n";
        my $st=($faillogs>16)?$faillogs-16:0;
        foreach my $failnum(0 .. min($faillogs,16)-1)
        {
          my $failbase=$xbase + 44 * (($st + $failnum) % 16);
          print "FailBase: $failbase (".sprintf("0x%X",$failbase).")\n";
          print "FAILCOUNT:".sprintf("%02d",$failnum)." ";
          print "EXCEPTIONOP_ID:".hex(getMem($failbase + 57846))." ";
          print "ZONE:".hex(getMem($failbase + 57848))." ";
          print "PBN:".hex(getMem($failbase + 57852))." ";
          print "PAGEOFFSET:".hex(getMem($failbase + 57850))." ";
          print "LPN:".hex(getMem($failbase + 57856))." \n";
          print "ERASECOUNT:".hex(getMem($failbase + 57868))." ";
          print "READCOUNT:".hex(getMem($failbase + 57876))."\n";
        }
        print "</FAIL_DESCRIPTION>\n";
      }
      print "</EXCEPTION_$exception>\n";
    }
  }
  print "\n";
}

ocd("targets mex2");
my $v801090=getMem(0x801090);
if(hex($v801090)>=0x800000 && hex($v801090)<=0x900000)
{
  print "Base address 801090: $v801090\n";
  print "Dumping Physical Block records:\n";
  my @bases=(0x844ff000,0x845a2ac0,0x92eff000,0x92fa2ac);
  foreach my $base (@bases)
  {
    print "Base: $base\n";
    foreach my $PBN(0 .. 8379)
    {
      last if($PBN>100);
      my $Erasecount2=getMemWord($base+$PBN*80+4);
      my $Erasecount=getMem($base+$PBN*80+8);
      my $Readcount=getMem($base+$PBN*80+12);
      print "PBN:$PBN EC2:$Erasecount2 Erasecount:$Erasecount Readcount:$Readcount ".getMemDump($base+$PBN*80,80);
    }
  }
}



my @indicators=(0x801090,0x008010A0,0x008010e0,0x008010f0,0x0080471C,0x008049AC,0x00808020,0x00808094,0x0080C160,0x0080C428,0x0080C42C,0x825BEC,0x00804E1C,0x00804564,0x2050F024,0x20440018,0x825C00,0x100205B0,0x800a1ad4,0x800a1a10,0x801070,0x80131C,0x2048000C,0x2049000C,0x204A000C,0x204B000C,0x2048012C,0x2049012C,0x204A012C,0x204B012C,0x2038000C,0x2039000C,0x203A000C,0x203B000C,0x2038012C,0x2039012C,0x203A012C,0x203B012C,0x824850,0x805EBC,0x80BC08,0x20000044,0x80106C,0x20000054,0x20000070,0x20102010,0x20205359,0x41827FFC,0x42827FFC,0x0080007C,0x80062360,0x8006240C,0x0081ba98,0x0081ba9c,0x0081baa0,0x0081baa4,0x0081baa8,0x0081baac,0x0081bab0,0x8010a4,0x825C08,0x82576C,0x825764,0x825760,0x8010a8,0x82577C,0x824EB4,0x81c6a1,0x81c6a0,0x1001004C,0x10010050,0x822E14,0x822E13,0x822E1C,0x822E20,0x822E15,0x8046EC,0x20502000,0x2050200C,0x20502004,0x20502010,0x20501020,0x20501000,0x20501008,0x804714,0x100201AC,0x100201B0,0x100201B4,0x80000024,0x81C63C,0x20104010,0x81C76C,0x81C67C,0x801000,0x802fe4,0x823050,0x823048,0x81E4C0,0x823310,0x823038,0x81CAF8,0x8003047C,0x825E08,0x20501038);
foreach(sort @indicators)
{
  print "indicator ".sprintf("0x%X",$_)." ";
  foreach my $core ("mex1","mex2","mex3")
  {
    ocd("targets $core");
    print "$core:".getMem($_)." ";
  }
  print "\n";
}

foreach my $core ("mex1","mex2","mex3")
{
  ocd("targets $core");
  my $magic=getMem(0x80000024);
  print "$core thinks SA is loaded correctly: ".($magic eq "29135201" ? "yes":$magic eq "00000000"?"no":"unknown")." (magic:$magic)\n";
}

my $base8=getMem(0x8000DCE3);
print "Base8: $base8\n";

resume("mex1");
resume("mex2") if($mex2awake);
resume("mex3") if($mex3awake);

sleep(1);
$openocd->close();
system "killall openocd";

