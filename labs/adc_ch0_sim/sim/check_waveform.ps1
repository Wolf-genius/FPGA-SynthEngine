$lines = Get-Content -LiteralPath "$PSScriptRoot\adc_ch0.vcd"
$state = @{}
$changes = @{}
$transactions = [System.Collections.Generic.List[object]]::new()
$valids = [System.Collections.Generic.List[object]]::new()
$script:active = $null
$script:validStart = $null
function Flush-Time([long]$t) {
    $old = @{}
    foreach ($k in $changes.Keys) { $old[$k] = $state[$k]; $state[$k] = $changes[$k] }
    if ($changes.ContainsKey('%') -and $state['%'] -eq '0' -and $old['%'] -ne '0') {
        $script:active = [pscustomobject]@{Start=$t; End=0L; Expected=$state['+']; Rises=[System.Collections.Generic.List[long]]::new(); Edges=[System.Collections.Generic.List[long]]::new(); Bits=''; MisoBits=''; Reset=$false}
    }
    if ($null -ne $script:active) {
        if ($changes.ContainsKey('"') -and $old['"'] -in @('0','1') -and $state['"'] -ne $old['"']) {
            $script:active.Edges.Add($t)
            if ($state['"'] -eq '1' -and $state['%'] -eq '0') {
                $script:active.Rises.Add($t)
                $script:active.Bits += $state['#']
                if ($script:active.Rises.Count -ge 13) { $script:active.MisoBits += $state['*'] }
            }
        }
        if ($changes.ContainsKey('%') -and $state['%'] -eq '1') {
            $script:active.End=$t
            $script:active.Reset=($state['-'] -eq '0')
            $transactions.Add($script:active)
            $script:active=$null
        }
    }
    if ($changes.ContainsKey('!') -and $state['!'] -eq '1' -and $old['!'] -ne '1') {
        $script:validStart = [pscustomobject]@{Time=$t; Data=$state['$']; Width=0L; Busy=$state['&']; CS=$state['%']; SCLK=$state['"']}
        $valids.Add($script:validStart)
    }
    if ($changes.ContainsKey('!') -and $old['!'] -eq '1' -and $state['!'] -eq '0') { $script:validStart.Width = $t-$script:validStart.Time }
    $changes.Clear()
}
$t=0L
$body=$false
foreach ($line in $lines) {
    if ($line -eq '$enddefinitions $end') { $body=$true; continue }
    if (!$body -or !$line -or $line[0] -eq '$') {continue}
    if ($line[0] -eq '#') { Flush-Time $t; $t=[long]$line.Substring(1); continue }
    if ($line -match '^b(\S+) (\S+)$') { $changes[$Matches[2]]=$Matches[1]; continue }
    if ($line -match '^([01xz])(\S+)$') { $changes[$Matches[2]]=$Matches[1] }
}
Flush-Time $t
'TRANSACTIONS (time in us)'
$i=0
foreach ($tr in $transactions) {
    $i++
    $periods=@(for($j=1;$j -lt $tr.Rises.Count;$j++){($tr.Rises[$j]-$tr.Rises[$j-1])/1000000}) | Sort-Object -Unique
    $half=@(for($j=1;$j -lt $tr.Edges.Count;$j++){($tr.Edges[$j]-$tr.Edges[$j-1])/1000000}) | Sort-Object -Unique
    $cmd=if($tr.Bits.Length -eq 24){'{0:X6}' -f [Convert]::ToInt32($tr.Bits,2)}else{'partial'}
    $payload=if($tr.MisoBits.Length -eq 12 -and $tr.MisoBits -notmatch '[xz]'){'{0:X3}' -f [Convert]::ToInt32($tr.MisoBits,2)}else{'partial'}
    $expected='{0:X3}' -f [Convert]::ToInt32($tr.Expected,2)
    "#$i start=$($tr.Start/1000000) end=$($tr.End/1000000) expected=$expected clocks=$($tr.Rises.Count) period_us=$($periods -join ',') half_us=$($half -join ',') command=$cmd miso_payload=$payload reset=$($tr.Reset)"
}
'VALID PULSES'
foreach($v in $valids){$data='{0:X3}' -f [Convert]::ToInt32($v.Data,2); "time_us=$($v.Time/1000000) data=$data width_ns=$($v.Width/1000) busy=$($v.Busy) cs_n=$($v.CS) sclk=$($v.SCLK)"}
"TOTAL transactions=$($transactions.Count) valid_pulses=$($valids.Count) end_us=$($t/1000000)"
