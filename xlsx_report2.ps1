$viservers = "vc.domain.ru", "vc2.domain.ru", "vc-msc.domain.ru", "vc-msc3.domain.ru"
$usr = 'administrator@vsphere.local' #используется админская учётка, что бы собирать What if the most consumed host fails
$pas = 'pass'
$recipients="recipient1@domain.ru","recipient2@domain.ru"

Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false


$start = (Get-Date).AddDays(-7)
$stat = 'cpu.usagemhz.average','mem.usage.average'
$body="Average. VSAN. Выключенные машины. Свободные ресурсы <br>"

Foreach ($viserver in $viservers){

Connect-VIServer -Server $viserver -Protocol https -User $usr -Password $pas

$entity = (Get-Cluster)

$allperf=(Get-Stat -Entity $entity -Stat $stat -Start $start |

Group-Object -Property Timestamp |

Sort-Object -Property Name |

Select @{N='Cluster';E={$viserver}},

    @{N='TimeStampCheck';E={$_.Group[0].Timestamp}},

    @{N='CPU GHz Capacity';E={$script:capacity = [int]($entity.ExtensionData.Summary.TotalCPU/1000); $script:capacity}},

    @{N='CPU GHz Used';E={$script:used = [int](($_.Group | where{$_.MetricId -eq 'cpu.usagemhz.average'} | select -ExpandProperty Value)/1000); $script:used}},

    @{N='CPU % Free';E={[int](100 - $script:used/$script:capacity*100)}},

    @{N='Mem Capacity GB';E={$script:mcapacity = [int]($entity.ExtensionData.Summary.TotalMemory/1GB); $script:mcapacity}},

    @{N='Mem Used GB';E={$script:mused = [int](($_.Group | where{$_.MetricId -eq 'mem.usage.average'} | select -ExpandProperty Value) * $script:mcapacity/100); $script:mused}},

    @{N='Mem % Free';E={[int](100 - $script:mused/$script:mcapacity*100)}} ) 
  


$datastore=(Get-Datastore | where {$_.name -like "*vsan*"} | Select Name,@{N="TotalSpaceTB";E={[Math]::Round(($_.ExtensionData.Summary.Capacity)/1TB,0)}},@{N="UsedSpaceTB";E={[Math]::Round(($_.ExtensionData.Summary.Capacity - $_.ExtensionData.Summary.FreeSpace)/1TB,0)}}, @{N="ProvisionedSpaceTB";E={[Math]::Round(($_.ExtensionData.Summary.Capacity - $_.ExtensionData.Summary.FreeSpace + $_.ExtensionData.Summary.Uncommitted)/1TB,0)}},@{N='Used Space(%)';E={[math]::Round((($_.ExtensionData.Summary.Capacity - $_.ExtensionData.Summary.FreeSpace)/$_.ExtensionData.Summary.Capacity*100),0)}},@{N="FreeSpaceTB";E={[Math]::Round(($_.ExtensionData.Summary.FreeSpace)/1TB,0)}},@{N="CountVMs";E={@($_ | Get-VM).Count}})

$poweroffvm=(Get-VM | Where {$_.Powerstate -ne “PoweredOn”} | Select Name, @{N="ProvisionedSpaceGB";E={[Math]::Round(($_.ProvisionedSpaceGB),0)}},@{N="UsedSpaceGB";E={[Math]::Round(($_.UsedSpaceGB),0)}}, Notes)


$maxram=$allperf | sort 'Mem Used GB' -Descending | select -First 1
$maxcpu=$allperf | sort 'CPU GHz Used' -Descending | select -firs 1
$maxperf=$maxram, $maxcpu

$freeram=($maxram.'Mem Capacity GB' - $maxram.'Mem Used GB')
$freerampercent=($maxram.'Mem % Free')

$freecpu=($maxcpu.'CPU GHz Capacity' - $maxcpu.'CPU GHz Used')
$freecpupercent=($maxcpu.'CPU % Free')

$freespace=($datastore.FreeSpaceTB)
$freespacepercent=(100 - $datastore.'Used Space(%)')
$spacereserv=[math]::Round($freespace - ($datastore.TotalSpaceTB - ($datastore.TotalSpaceTB * 0.7)))

$freespaceprov=($datastore.TotalSpaceTB - $datastore.ProvisionedSpaceTB)
$freespacepercentprov=[math]::Round(($freespaceprov * 100) / $datastore.TotalSpaceTB)
$spacereservprov=[math]::Round($freespaceprov - ($datastore.TotalSpaceTB - ($datastore.TotalSpaceTB * 0.7)))

$maxperf | Export-Excel -Path .\xlsx_reports\$viserver.xlsx -WorkSheetname 'MaxPerfomance' -AutoSize -FreezeTopRow -AutoFilter
$datastore  | Export-Excel -Path .\xlsx_reports\$viserver.xlsx -WorkSheetname 'Datastore' -AutoSize -FreezeTopRow -AutoFilter
$poweroffvm | Export-Excel -Path .\xlsx_reports\$viserver.xlsx -WorkSheetname 'PowerOffVms' -AutoSize -FreezeTopRow -AutoFilter
$allperf | Export-Excel -Path .\xlsx_reports\$viserver.xlsx -WorkSheetname 'PerfomanceALL' -AutoSize -FreezeTopRow -AutoFilter


$vmhost=Get-VMHost -State Connected | select -last 1
$esxcli=Get-EsxCli -VMHost $vmhost -v2
$arg=$esxcli.vsan.health.cluster.get.CreateArgs() 
$arg.test='What if the most consumed host fails' 
$limit1hf=$esxcli.vsan.health.cluster.get.Invoke($arg) 
$limit1hf=($limit1hf.Split("`n") | Select-String -Pattern 'Disk space utilization').ToString()
$limit1hf=$limit1hf.Remove('30') 
$limit1hf=$limit1hf.Substring(28) 


if ($spacereserv -le 0) {$spacereserv="<font color='red'>$spacereserv</font>"}
else {$spacereserv="<font color='green'>$spacereserv</font>"}

if ($spacereservprov -le 0) {$spacereservprov="<font color='red'>$spacereservprov</font>"}
else {$spacereservprov="<font color='green'>$spacereservprov</font>"}

if ($limit1hf -ge 80) {$limit1hf="<font color='red'>$limit1hf</font>"}
else {$limit1hf="<font color='green'>$limit1hf</font>"}

$body+="<br>
<style type='text/css'>
.tg  {border-collapse:collapse;border-spacing:0;}
.tg td{border-color:black;border-style:solid;border-width:1px;font-family:Arial, sans-serif;font-size:14px;
  overflow:hidden;padding:10px 5px;word-break:normal;}
.tg th{border-color:black;border-style:solid;border-width:1px;font-family:Arial, sans-serif;font-size:14px;
  font-weight:normal;overflow:hidden;padding:10px 5px;word-break:normal;}
.tg .tg-cly1{text-align:left;vertical-align:middle}
.tg .tg-amwm{font-weight:bold;text-align:center;vertical-align:top}
</style>
<table class='tg'>
<thead>
  <tr>
    <th class='tg-amwm' colspan='3'>$viserver 	</th>
  </tr>
</thead>
<tbody>
  <tr>
    <td class='tg-cly1'>Free CPU:</td>
    <td class='tg-cly1' colspan='2'> $freecpu'Ghz	$freecpupercent%</td>
  </tr>
  <tr>
    <td class='tg-cly1'>Free RAM: </td>
    <td class='tg-cly1' colspan='2'>$freeram'GB $freerampercent%</td>
  </tr>
  <tr>
    <td class='tg-cly1'>Free Space:</td>
    <td class='tg-cly1'>$freespace'TB $freespacepercent%</td>
    <td class='tg-cly1' rowspan='2'>(Если учитывать Used)</td>
  </tr>
  <tr>
    <td class='tg-cly1'>Резервация:</td>
    <td class='tg-cly1'>$spacereserv'TB</td>
  </tr>
  <tr>
    <td class='tg-cly1'>Free Space:</td>
    <td class='tg-cly1'>$freespaceprov'TB $freespacepercentprov%</td>
    <td class='tg-cly1' rowspan='2'>(Если учитывать Provision)</td>
  </tr>
  <tr>
    <td class='tg-cly1'>Резервация:</td>
    <td class='tg-cly1'>$spacereservprov'TB</td>
  </tr>
  <tr>
    <td class='tg-cly1' colspan='3'>What if the most consumed host fails $limit1hf%</td>
  </tr>
</tbody>
</table>
"


Disconnect-VIServer $viserver -Confirm:$false


}

Send-MailMessage -To $recipients -From "boss@vcenter-bot.ws" -Subject "Рассылка о состоянии Vcenter за неделю." -Attachments (Get-ChildItem -Path .\xlsx_reports\*.xlsx | sort name) -SmtpServer "smtp.domain.ru" -Body $body -Encoding UTF8 -BodyAsHtml

