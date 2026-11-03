<# Examples (no external PowerShell modules required):
 .\terminal_serial.ps1 -Port COM5 -Action Publish -Id 101 -Type Fire -Level 2
 .\terminal_serial.ps1 -Port COM5 -Action Ack -Id 101
 .\terminal_serial.ps1 -Port COM5 -Action Clear -Id 101
 .\terminal_serial.ps1 -Port COM5 -Action Listen -Seconds 60
 .\terminal_serial.ps1 -Port COM5 -Action AudioOn
#>
[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][string]$Port,
 [ValidateSet('Publish','Ack','Clear','Query','AudioOn','AudioOff','Listen')][string]$Action='Query',
 [ValidateRange(0,65535)][int]$Id=1,
 [ValidateSet('Fire','Quake','Flood','Evac')][string]$Type='Fire',
 [ValidateRange(0,3)][int]$Level=2,
 [ValidateRange(1,86400)][int]$Seconds=3,
 [switch]$DryRun
)
$ErrorActionPreference='Stop'
$op=@{Publish=1;Ack=2;Clear=3;Query=4;AudioOn=5;AudioOff=5;Listen=0}[$Action]
$types=@('Fire','Quake','Flood','Evac')
$kind=[array]::IndexOf($types,$Type)
if($Action -eq 'AudioOn'){$kind=1}
if($Action -eq 'AudioOff'){$kind=0}
if($Action -eq 'Publish' -and $Id -eq 0){throw 'Publish requires a nonzero event ID.'}
[byte[]]$packet=@(0xAA,0x55,$op,($Id -band 255),($Id -shr 8),$kind,$Level,0)
$check=0
for($n=2;$n -le 6;$n++){$check=$check -bxor $packet[$n]}
$packet[7]=[byte]$check
if($DryRun){[BitConverter]::ToString($packet);return}
$serial=New-Object System.IO.Ports.SerialPort($Port,115200,[System.IO.Ports.Parity]::None,8,[System.IO.Ports.StopBits]::One)
$serial.DtrEnable=$false;$serial.RtsEnable=$false;$serial.ReadTimeout=100
$buffer=New-Object 'System.Collections.Generic.List[byte]'
$last=''
try{
 $serial.Open()
 if($op -ne 0){$serial.Write($packet,0,$packet.Length);Write-Host ('TX '+[BitConverter]::ToString($packet))}
 $until=[DateTime]::UtcNow.AddSeconds($Seconds)
 while([DateTime]::UtcNow -lt $until){
  try{$value=$serial.ReadByte()}catch [System.TimeoutException]{continue}
  $buffer.Add([byte]$value)
  while($buffer.Count -ge 9){
   if($buffer[0] -ne 0xAA -or $buffer[1] -ne 0x55 -or $buffer[2] -ne 0x80){$buffer.RemoveAt(0);continue}
   $xor=0;for($n=2;$n -le 7;$n++){$xor=$xor -bxor $buffer[$n]}
   if($xor -ne $buffer[8]){$buffer.RemoveAt(0);continue}
   $ident=[int]$buffer[3]+256*[int]$buffer[4];$f=$buffer[6]
   $line='ID={0} TYPE={1} emergency={2} displayed={3} acknowledged={4} image_ready={5} auto={6} result={7}' -f $ident,$types[$buffer[5]],(($f -band 2)-ne 0),(($f -band 4)-ne 0),(($f -band 8)-ne 0),(($f -band 16)-ne 0),(($f -band 32)-ne 0),$buffer[7]
   if($line -ne $last){Write-Host ('RX '+$line);$last=$line}
   $buffer.RemoveRange(0,9)
  }
 }
 if($last -eq ''){Write-Warning 'No valid FPGA status packet received. Check COM port, wiring and firmware.'}
}finally{if($serial.IsOpen){$serial.Close()};$serial.Dispose()}
