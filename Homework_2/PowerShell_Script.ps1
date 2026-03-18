#Requires -Version 5.1
<#
.SYNOPSIS
    Hardware Inventory - Thu thap thong tin phan cung (Phan 1-7)
.DESCRIPTION
    Thu thap: System/OS, BIOS, Motherboard, CPU, RAM, Disk, Network Interface
.NOTES
    Chay voi quyen Administrator de lay du thong tin
    PowerShell -ExecutionPolicy Bypass -File hardware_inventory.ps1
#>

# ─────────────────────────────────────────────
# SETUP
# ─────────────────────────────────────────────
$ErrorActionPreference = "SilentlyContinue"
$TIMESTAMP = Get-Date -Format "yyyyMMdd_HHmmss"
$OUTDIR    = ".\HW_Report_$TIMESTAMP"
$TXTFILE   = "$OUTDIR\report.txt"
$CSVDIR    = "$OUTDIR\csv"

New-Item -ItemType Directory -Path $OUTDIR -Force | Out-Null
New-Item -ItemType Directory -Path $CSVDIR -Force | Out-Null

function Write-Section {
    param([string]$Title)
    $line = "=" * 60
    $msg  = "`n$line`n  $Title`n$line"
    Write-Host $msg -ForegroundColor Cyan
    Add-Content -Path $TXTFILE -Value $msg
}

function Write-Sub {
    param([string]$Title)
    $msg = "`n--- $Title ---"
    Write-Host $msg -ForegroundColor Yellow
    Add-Content -Path $TXTFILE -Value $msg
}

function Out-Both {
    param($Data, [string]$CsvName = "")
    $text = $Data | Format-List | Out-String
    Write-Host $text
    Add-Content -Path $TXTFILE -Value $text
    if ($CsvName -and $Data) {
        try { $Data | Export-Csv -Path "$CSVDIR\$CsvName.csv" -NoTypeInformation -Encoding UTF8 } catch {}
    }
}

Write-Host "`n[START] Hardware Inventory - $TIMESTAMP" -ForegroundColor Green
Add-Content -Path $TXTFILE -Value "HARDWARE INVENTORY`nGenerated: $(Get-Date)`nComputer : $env:COMPUTERNAME`nUser     : $env:USERNAME`n"

# ─────────────────────────────────────────────
# 1. SYSTEM OVERVIEW
# ─────────────────────────────────────────────
Write-Section "1. SYSTEM OVERVIEW"

Write-Sub "Computer System"
$cs = Get-WmiObject Win32_ComputerSystem
Out-Both ([PSCustomObject]@{
    Manufacturer       = $cs.Manufacturer
    Model              = $cs.Model
    SystemFamily       = $cs.SystemFamily
    SystemSKUNumber    = $cs.SystemSKUNumber
    TotalRAM_GB        = [math]::Round($cs.TotalPhysicalMemory/1GB, 2)
    Domain             = $cs.Domain
    NumberOfProcessors = $cs.NumberOfProcessors
    PCSystemType       = switch($cs.PCSystemType){1{"Desktop"} 2{"Mobile/Laptop"} 3{"Workstation"} 4{"Enterprise Server"} default{"Other"}}
}) "01_system"

Write-Sub "Operating System"
$os = Get-WmiObject Win32_OperatingSystem
Out-Both ([PSCustomObject]@{
    Caption          = $os.Caption
    Version          = $os.Version
    BuildNumber      = $os.BuildNumber
    Architecture     = $os.OSArchitecture
    InstallDate      = $os.ConvertToDateTime($os.InstallDate)
    LastBootUpTime   = $os.ConvertToDateTime($os.LastBootUpTime)
    Uptime           = (Get-Date) - $os.ConvertToDateTime($os.LastBootUpTime)
    SystemDrive      = $os.SystemDrive
    WindowsDir       = $os.WindowsDirectory
    RegisteredUser   = $os.RegisteredUser
    SerialNumber     = $os.SerialNumber
}) "01_os"

# ─────────────────────────────────────────────
# 2. BIOS / FIRMWARE
# ─────────────────────────────────────────────
Write-Section "2. BIOS / FIRMWARE"
$bios = Get-WmiObject Win32_BIOS
Out-Both ([PSCustomObject]@{
    Manufacturer      = $bios.Manufacturer
    Name              = $bios.Name
    Version           = $bios.Version
    SMBIOSVersion     = "$($bios.SMBIOSMajorVersion).$($bios.SMBIOSMinorVersion)"
    ReleaseDate       = $bios.ConvertToDateTime($bios.ReleaseDate)
    SerialNumber      = $bios.SerialNumber
    PrimaryBIOS       = $bios.PrimaryBIOS
    SoftwareElementID = $bios.SoftwareElementID
}) "02_bios"

# ─────────────────────────────────────────────
# 3. MOTHERBOARD / BASEBOARD
# ─────────────────────────────────────────────
Write-Section "3. MOTHERBOARD / BASEBOARD"
$mb = Get-WmiObject Win32_BaseBoard
Out-Both ([PSCustomObject]@{
    Manufacturer = $mb.Manufacturer
    Product      = $mb.Product
    Version      = $mb.Version
    SerialNumber = $mb.SerialNumber
    Tag          = $mb.Tag
    HostingBoard = $mb.HostingBoard
}) "03_motherboard"

# ─────────────────────────────────────────────
# 4. CPU
# ─────────────────────────────────────────────
Write-Section "4. CPU (PROCESSOR)"
$cpus = Get-WmiObject Win32_Processor
foreach ($cpu in $cpus) {
    Out-Both ([PSCustomObject]@{
        DeviceID                  = $cpu.DeviceID
        Name                      = $cpu.Name.Trim()
        Manufacturer              = $cpu.Manufacturer
        Description               = $cpu.Description
        Architecture              = switch($cpu.Architecture){0{"x86"} 9{"x64"} 12{"ARM64"} default{$cpu.Architecture}}
        AddressWidth              = "$($cpu.AddressWidth)-bit"
        NumberOfCores             = $cpu.NumberOfCores
        NumberOfLogicalProcessors = $cpu.NumberOfLogicalProcessors
        ThreadsPerCore            = [math]::Floor($cpu.NumberOfLogicalProcessors / $cpu.NumberOfCores)
        MaxClockSpeed_MHz         = $cpu.MaxClockSpeed
        CurrentClockSpeed_MHz     = $cpu.CurrentClockSpeed
        ExtClock_MHz              = $cpu.ExtClock
        L2Cache_KB                = $cpu.L2CacheSize
        L3Cache_KB                = $cpu.L3CacheSize
        Socket                    = $cpu.SocketDesignation
        ProcessorId               = $cpu.ProcessorId
        Stepping                  = $cpu.Stepping
        Status                    = $cpu.Status
        LoadPercentage            = $cpu.LoadPercentage
    }) "04_cpu"
}

Write-Sub "CPU Realtime Usage"
$cpuLoad = (Get-WmiObject Win32_PerfFormattedData_PerfOS_Processor |
    Where-Object {$_.Name -eq "_Total"}).PercentProcessorTime
$msg = "Current CPU Load: $cpuLoad%"
Write-Host $msg -ForegroundColor White
Add-Content -Path $TXTFILE -Value $msg

# ─────────────────────────────────────────────
# 5. RAM
# ─────────────────────────────────────────────
Write-Section "5. RAM (MEMORY)"

Write-Sub "Each Memory Stick"
$ramSticks = Get-WmiObject Win32_PhysicalMemory | ForEach-Object {
    [PSCustomObject]@{
        BankLabel          = $_.BankLabel
        DeviceLocator      = $_.DeviceLocator
        Manufacturer       = $_.Manufacturer
        PartNumber         = $_.PartNumber.Trim()
        SerialNumber       = $_.SerialNumber
        CapacityGB         = [math]::Round($_.Capacity/1GB, 1)
        SpeedMHz           = $_.Speed
        ConfiguredSpeedMHz = $_.ConfiguredClockSpeed
        MemoryType         = switch($_.MemoryType){21{"DDR2"} 24{"DDR3"} 26{"DDR4"} 34{"DDR5"} default{"Unknown($($_.MemoryType))"}}
        FormFactor         = switch($_.FormFactor){8{"DIMM"} 12{"SO-DIMM"} 13{"CSRAM"} default{$_.FormFactor}}
        DataWidth          = $_.DataWidth
        TotalWidth         = $_.TotalWidth
        Voltage_mV         = $_.ConfiguredVoltage
    }
}
Out-Both $ramSticks "05_ram_sticks"

Write-Sub "Memory Summary"
$os2      = Get-WmiObject Win32_OperatingSystem
$totalRam = $cs.TotalPhysicalMemory
$freeRam  = $os2.FreePhysicalMemory * 1KB
$usedRam  = $totalRam - $freeRam
Out-Both ([PSCustomObject]@{
    TotalRAM_GB      = [math]::Round($totalRam/1GB, 2)
    UsedRAM_GB       = [math]::Round($usedRam/1GB, 2)
    FreeRAM_GB       = [math]::Round($freeRam/1GB, 2)
    UsedPercent      = [math]::Round($usedRam/$totalRam*100, 1)
    TotalSwap_GB     = [math]::Round($os2.TotalVirtualMemorySize*1KB/1GB, 2)
    FreeSwap_GB      = [math]::Round($os2.FreeVirtualMemory*1KB/1GB, 2)
    Slots_Populated  = ($ramSticks | Measure-Object).Count
    TotalCapacity_GB = ($ramSticks | Measure-Object -Property CapacityGB -Sum).Sum
}) "05_ram_summary"

# ─────────────────────────────────────────────
# 6. STORAGE / DISK
# ─────────────────────────────────────────────
Write-Section "6. STORAGE / DISK"

Write-Sub "Physical Disks"
$physDisks = Get-PhysicalDisk | ForEach-Object {
    [PSCustomObject]@{
        DeviceID          = $_.DeviceId
        FriendlyName      = $_.FriendlyName
        MediaType         = $_.MediaType
        BusType           = $_.BusType
        SizeGB            = [math]::Round($_.Size/1GB)
        HealthStatus      = $_.HealthStatus
        OperationalStatus = $_.OperationalStatus
        SpindleSpeed      = $_.SpindleSpeed
        FirmwareVersion   = $_.FirmwareVersion
        UniqueId          = $_.UniqueId
    }
}
Out-Both $physDisks "06_physical_disks"

Write-Sub "Disk Drives (WMI Detail)"
$diskDrives = Get-WmiObject Win32_DiskDrive | ForEach-Object {
    [PSCustomObject]@{
        Model            = $_.Model
        Manufacturer     = $_.Manufacturer
        InterfaceType    = $_.InterfaceType
        SerialNumber     = $_.SerialNumber.Trim()
        FirmwareRevision = $_.FirmwareRevision
        SizeGB           = [math]::Round($_.Size/1GB)
        Partitions       = $_.Partitions
        BytesPerSector   = $_.BytesPerSector
        Status           = $_.Status
    }
}
Out-Both $diskDrives "06_disk_drives"

Write-Sub "Logical Disks"
$logDisks = Get-WmiObject Win32_LogicalDisk | Where-Object {$_.DriveType -eq 3} | ForEach-Object {
    [PSCustomObject]@{
        Drive          = $_.DeviceID
        VolumeName     = $_.VolumeName
        FileSystem     = $_.FileSystem
        SizeGB         = [math]::Round($_.Size/1GB, 1)
        FreeGB         = [math]::Round($_.FreeSpace/1GB, 1)
        UsedGB         = [math]::Round(($_.Size - $_.FreeSpace)/1GB, 1)
        FreePercent    = [math]::Round($_.FreeSpace/$_.Size*100, 1)
        VolumeSerialNo = $_.VolumeSerialNumber
        Compressed     = $_.Compressed
    }
}
Out-Both $logDisks "06_logical_disks"

# ─────────────────────────────────────────────
# 7. NETWORK INTERFACES
# ─────────────────────────────────────────────
Write-Section "7. NETWORK INTERFACES"

Write-Sub "Adapters"
$adapters = Get-NetAdapter | ForEach-Object {
    [PSCustomObject]@{
        Name                 = $_.Name
        Description          = $_.InterfaceDescription
        MacAddress           = $_.MacAddress
        Status               = $_.Status
        LinkSpeed            = $_.LinkSpeed
        MediaType            = $_.MediaType
        MediaConnectionState = $_.MediaConnectionState
        DriverName           = $_.DriverName
        DriverVersion        = $_.DriverVersionString
        DriverDate           = $_.DriverDate
        InterfaceIndex       = $_.InterfaceIndex
        FullDuplex           = $_.FullDuplex
        AdminStatus          = if($_.AdminStatus -eq 1){"Enabled"}else{"Disabled"}
        PhysicalMediaType    = $_.PhysicalMediaType
        HardwareInterface    = $_.HardwareInterface
    }
}
Out-Both $adapters "07_adapters"

Write-Sub "IP Configuration"
$ipConf = Get-NetIPConfiguration | ForEach-Object {
    [PSCustomObject]@{
        InterfaceAlias = $_.InterfaceAlias
        IPv4Address    = ($_.IPv4Address    | Select-Object -First 1).IPAddress
        IPv4PrefixLen  = ($_.IPv4Address    | Select-Object -First 1).PrefixLength
        IPv4DefaultGW  = ($_.IPv4DefaultGateway | Select-Object -First 1).NextHop
        IPv6Address    = ($_.IPv6Address    | Select-Object -First 1).IPAddress
        DNSServers     = ($_.DNSServer.ServerAddresses -join ", ")
        DHCPEnabled    = $_.NetIPv4Interface.Dhcp
    }
}
Out-Both $ipConf "07_ip_config"

Write-Sub "DNS Client Config"
Get-DnsClientServerAddress | Select-Object InterfaceAlias, AddressFamily, ServerAddresses |
    ForEach-Object { Add-Content -Path $TXTFILE -Value ($_ | Out-String) }

Write-Sub "ARP Table"
$arpTable = Get-NetNeighbor -AddressFamily IPv4 |
    Where-Object {$_.State -ne "Unreachable"} |
    Select-Object InterfaceAlias, IPAddress, LinkLayerAddress, State
Out-Both $arpTable "07_arp_table"

Write-Sub "Active TCP Connections"
$tcpConns = Get-NetTCPConnection | Where-Object {$_.State -eq "Established"} |
    Select-Object LocalAddress, LocalPort, RemoteAddress, RemotePort, State, OwningProcess |
    Sort-Object LocalPort
Out-Both $tcpConns "07_tcp_connections"

# ─────────────────────────────────────────────
# DONE
# ─────────────────────────────────────────────
$line = "=" * 60
Write-Host "`n$line" -ForegroundColor Green
Write-Host "  HOAN THANH!  Output: $OUTDIR" -ForegroundColor Green
Write-Host $line -ForegroundColor Green
Write-Host "  report.txt  - Full text"
Write-Host "  csv\        - CSV theo tung hang muc"
Write-Host "$line`n" -ForegroundColor Green
