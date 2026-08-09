#========================================================================
# Hardware Functions - local hardware inventory
#
# Read-only CIM / registry queries that describe THIS machine: graphics
# adapters (with a VRAM figure that survives cards above 4 GB), CPU,
# memory modules and motherboard / BIOS. Nothing in here writes anything.
#========================================================================

#========================================================================
# Size formatting helper
#========================================================================
Function ConvertTo-HumanSize {
    <#
    .SYNOPSIS
        Formats a byte count as a short human-readable string.
    .PARAMETER Bytes
        Size in bytes. Zero, negative or unusable values return "Unknown".
    .OUTPUTS
        String, e.g. "12.00 GB", "512 MB", "Unknown".
    #>
    param(
        [Parameter(Mandatory = $false)]
        [double]$Bytes = 0
    )

    if ($Bytes -le 0) { return "Unknown" }
    if ($Bytes -ge 1GB) { return ("{0:N2} GB" -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ("{0:N0} MB" -f ($Bytes / 1MB)) }
    return ("{0:N0} KB" -f ($Bytes / 1KB))
}

#========================================================================
# Registry value -> byte count
#========================================================================
Function ConvertTo-VramBytes {
    <#
    .SYNOPSIS
        Normalises a driver registry memory-size value into a byte count.
    .DESCRIPTION
        Display drivers store their VRAM size either as a QWORD/DWORD number
        or as a little-endian REG_BINARY blob, depending on driver vintage.
        This flattens both into a plain number.
    .PARAMETER RawValue
        The value straight out of Get-ItemProperty.
    .OUTPUTS
        [double] byte count, 0 when the value is missing or unusable.
    #>
    param(
        [Parameter(Mandatory = $false)]
        $RawValue
    )

    try {
        if ($null -eq $RawValue) { return 0 }

        if ($RawValue -is [byte[]]) {
            if ($RawValue.Length -eq 0) { return 0 }

            # Pad into a fixed 8-byte buffer so BitConverter always has enough
            # to read, regardless of whether the blob was 4 or 8 bytes.
            $buffer = New-Object byte[] 8
            $count  = [Math]::Min(8, $RawValue.Length)
            [Array]::Copy($RawValue, 0, $buffer, 0, $count)
            return [double][BitConverter]::ToUInt64($buffer, 0)
        }

        return [double]$RawValue
    }
    catch {
        # A malformed registry value is not worth failing the whole scan over.
        return 0
    }
}

#========================================================================
# VRAM size for one adapter
#========================================================================
Function Get-GpuVramBytes {
    <#
    .SYNOPSIS
        Returns the VRAM size in bytes for a display adapter.
    .DESCRIPTION
        Win32_VideoController.AdapterRAM is a UInt32, so any card with more
        than 4 GB reports a wrapped ~4095 MB. The driver's own key under the
        "Display adapters" setup class carries the real size in
        'HardwareInformation.qwMemorySize' (or the older
        'HardwareInformation.MemorySize'), which is what we prefer.
    .PARAMETER AdapterName
        Adapter name from Win32_VideoController, matched against the driver
        key's DriverDesc value.
    .PARAMETER FallbackBytes
        AdapterRAM value to fall back on when the registry yields nothing
        (typical for shared-memory integrated GPUs).
    .OUTPUTS
        [double] byte count, 0 when nothing could be determined.
    #>
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$AdapterName = "",

        [Parameter(Mandatory = $false)]
        [double]$FallbackBytes = 0
    )

    # Device setup class GUID for "Display adapters".
    $classKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'

    if ([String]::IsNullOrWhiteSpace($AdapterName)) { return $FallbackBytes }

    try {
        if (Test-Path $classKey) {
            # Only the numbered subkeys (0000, 0001, ...) describe an adapter;
            # the class key also holds Configuration/Properties children.
            $driverKeys = Get-ChildItem -Path $classKey -ErrorAction SilentlyContinue |
                          Where-Object { $_.PSChildName -match '^\d{4}$' }

            foreach ($key in $driverKeys) {
                $props = Get-ItemProperty -Path $key.PSPath -ErrorAction SilentlyContinue
                if ($null -eq $props) { continue }
                if ($props.DriverDesc -ne $AdapterName) { continue }

                # Preferred: 64-bit size written by modern WDDM drivers.
                $bytes = ConvertTo-VramBytes -RawValue $props.'HardwareInformation.qwMemorySize'
                if ($bytes -gt 0) { return $bytes }

                # Older drivers: DWORD or REG_BINARY under a different name.
                $bytes = ConvertTo-VramBytes -RawValue $props.'HardwareInformation.MemorySize'
                if ($bytes -gt 0) { return $bytes }
            }
        }
    }
    catch {
        # An unreadable / ACL-protected driver key is not fatal - use AdapterRAM.
        Write-Verbose "Get-GpuVramBytes: registry lookup failed for '$AdapterName': $_"
    }

    return $FallbackBytes
}

#========================================================================
# Graphics adapters
#========================================================================
Function Get-GpuInfo {
    <#
    .SYNOPSIS
        Returns one row per installed display adapter.
    .OUTPUTS
        Array of PSCustomObject: Name, Vendor, VRAM, VRAMBytes, Processor,
        Driver, DriverDate, Mode, Status.
    #>
    try {
        $controllers = @(Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop)
        $rows = @()

        foreach ($gpu in $controllers) {
            # AdapterRAM is only a fallback - see Get-GpuVramBytes for why.
            $fallback = 0
            if ($null -ne $gpu.AdapterRAM) { $fallback = [double]$gpu.AdapterRAM }

            $name      = if ($gpu.Name) { [string]$gpu.Name } else { "Unknown adapter" }
            $vramBytes = Get-GpuVramBytes -AdapterName $name -FallbackBytes $fallback

            # Current display mode - blank on a headless / disabled adapter.
            $mode = "Not active"
            if ($gpu.CurrentHorizontalResolution -and $gpu.CurrentVerticalResolution) {
                $mode = "{0} x {1}" -f $gpu.CurrentHorizontalResolution, $gpu.CurrentVerticalResolution
                if ($gpu.CurrentRefreshRate) { $mode = "$mode @ $($gpu.CurrentRefreshRate) Hz" }
            }

            $driverDate = ""
            if ($gpu.DriverDate -is [datetime]) { $driverDate = $gpu.DriverDate.ToString('yyyy-MM-dd') }

            $rows += [PSCustomObject]@{
                Name       = $name
                Vendor     = $gpu.AdapterCompatibility
                VRAM       = ConvertTo-HumanSize -Bytes $vramBytes
                VRAMBytes  = $vramBytes
                Processor  = $gpu.VideoProcessor
                Driver     = $gpu.DriverVersion
                DriverDate = $driverDate
                Mode       = $mode
                Status     = $gpu.Status
            }
        }

        return $rows
    }
    catch {
        throw "Failed to query graphics adapters: $_"
    }
}

#========================================================================
# Processor
#========================================================================
Function Get-CpuInfo {
    <#
    .SYNOPSIS
        Returns one row per physical processor package.
    .OUTPUTS
        Array of PSCustomObject with CPU name, core/thread counts, clock and
        cache sizes.
    #>
    try {
        $cpus = @(Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop)
        $rows = @()

        foreach ($cpu in $cpus) {
            $rows += [PSCustomObject]@{
                Name          = $cpu.Name
                Manufacturer  = $cpu.Manufacturer
                Socket        = $cpu.SocketDesignation
                Cores         = $cpu.NumberOfCores
                Threads       = $cpu.NumberOfLogicalProcessors
                MaxClockMHz   = $cpu.MaxClockSpeed
                L2CacheKB     = $cpu.L2CacheSize
                L3CacheKB     = $cpu.L3CacheSize
                Architecture  = $cpu.AddressWidth
                Virtualization = $cpu.VirtualizationFirmwareEnabled
            }
        }

        return $rows
    }
    catch {
        throw "Failed to query processor: $_"
    }
}

#========================================================================
# Physical memory
#========================================================================
Function Get-MemoryInfo {
    <#
    .SYNOPSIS
        Returns installed memory modules plus the machine's total RAM.
    .OUTPUTS
        PSCustomObject with TotalBytes, TotalText, SlotsUsed, SlotsTotal and
        a Modules array (one entry per stick).
    #>
    try {
        $sticks = @(Get-CimInstance -ClassName Win32_PhysicalMemory -ErrorAction Stop)
        $system = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
        $arrays = @(Get-CimInstance -ClassName Win32_PhysicalMemoryArray -ErrorAction SilentlyContinue)

        $modules = @()
        foreach ($stick in $sticks) {
            $capacity = 0
            if ($null -ne $stick.Capacity) { $capacity = [double]$stick.Capacity }

            # ConfiguredClockSpeed is what the stick actually runs at; Speed is
            # what it is rated for. Both are useful, they often differ (XMP off).
            $modules += [PSCustomObject]@{
                Slot         = $stick.DeviceLocator
                Bank         = $stick.BankLabel
                Capacity     = ConvertTo-HumanSize -Bytes $capacity
                RatedMHz     = $stick.Speed
                RunningMHz   = $stick.ConfiguredClockSpeed
                Manufacturer = $stick.Manufacturer
                PartNumber   = if ($stick.PartNumber) { $stick.PartNumber.Trim() } else { "" }
            }
        }

        $totalBytes = 0
        if ($null -ne $system -and $null -ne $system.TotalPhysicalMemory) {
            $totalBytes = [double]$system.TotalPhysicalMemory
        }

        # Total slots on the board - a laptop with soldered RAM may report 0.
        $slotsTotal = 0
        foreach ($array in $arrays) {
            if ($null -ne $array.MemoryDevices) { $slotsTotal += [int]$array.MemoryDevices }
        }

        return [PSCustomObject]@{
            TotalBytes = $totalBytes
            TotalText  = ConvertTo-HumanSize -Bytes $totalBytes
            SlotsUsed  = $modules.Count
            SlotsTotal = $slotsTotal
            Modules    = $modules
        }
    }
    catch {
        throw "Failed to query memory: $_"
    }
}

#========================================================================
# Motherboard / BIOS / machine
#========================================================================
Function Get-SystemHardware {
    <#
    .SYNOPSIS
        Returns motherboard, BIOS and machine identification details.
    .OUTPUTS
        PSCustomObject with board, BIOS and system fields. Fields that the
        firmware does not report come back empty rather than throwing.
    #>
    try {
        $board  = Get-CimInstance -ClassName Win32_BaseBoard      -ErrorAction SilentlyContinue
        $bios   = Get-CimInstance -ClassName Win32_BIOS           -ErrorAction SilentlyContinue
        $system = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue

        $biosDate = ""
        if ($null -ne $bios -and $bios.ReleaseDate -is [datetime]) {
            $biosDate = $bios.ReleaseDate.ToString('yyyy-MM-dd')
        }

        return [PSCustomObject]@{
            SystemManufacturer = if ($system) { $system.Manufacturer } else { "" }
            SystemModel        = if ($system) { $system.Model } else { "" }
            SystemType         = if ($system) { $system.SystemType } else { "" }
            BoardManufacturer  = if ($board) { $board.Manufacturer } else { "" }
            BoardProduct       = if ($board) { $board.Product } else { "" }
            BoardVersion       = if ($board) { $board.Version } else { "" }
            BoardSerial        = if ($board) { $board.SerialNumber } else { "" }
            BiosVendor         = if ($bios) { $bios.Manufacturer } else { "" }
            BiosVersion        = if ($bios) { $bios.SMBIOSBIOSVersion } else { "" }
            BiosDate           = $biosDate
        }
    }
    catch {
        throw "Failed to query system hardware: $_"
    }
}

#========================================================================
# Flattened summary for the details grid
#========================================================================
Function Get-HardwareSummary {
    <#
    .SYNOPSIS
        Flattens CPU, memory and board/BIOS details into Category/Item/Value
        rows suitable for a DataGrid.
    .DESCRIPTION
        Each section is collected independently so one failing CIM class (for
        example memory on a locked-down VM) still leaves the rest readable.
    .PARAMETER Sections
        Which sections to include. Defaults to all three, which is what the
        text report wants; the GUI asks for 'System' only because CPU and
        memory have their own grid there.
    .OUTPUTS
        Array of PSCustomObject: Category, Item, Value.
    #>
    param(
        [Parameter(Mandatory = $false)]
        [ValidateSet('CPU', 'Memory', 'System')]
        [string[]]$Sections = @('CPU', 'Memory', 'System')
    )

    $rows = @()

    # --- Processor -------------------------------------------------------
    if ($Sections -contains 'CPU') {
        try {
            $index = 0
            foreach ($cpu in @(Get-CpuInfo)) {
                $index++
                $label = if ($index -gt 1) { "CPU $index" } else { "CPU" }

                $rows += [PSCustomObject]@{ Category = $label; Item = "Model";        Value = "$($cpu.Name)" }
                $rows += [PSCustomObject]@{ Category = $label; Item = "Cores";        Value = "$($cpu.Cores) cores / $($cpu.Threads) threads" }
                $rows += [PSCustomObject]@{ Category = $label; Item = "Max clock";    Value = "$($cpu.MaxClockMHz) MHz" }
                $rows += [PSCustomObject]@{ Category = $label; Item = "Socket";       Value = "$($cpu.Socket)" }
                $rows += [PSCustomObject]@{ Category = $label; Item = "L2 / L3 cache"; Value = "$($cpu.L2CacheKB) KB / $($cpu.L3CacheKB) KB" }
                $rows += [PSCustomObject]@{ Category = $label; Item = "Virtualization"; Value = "$($cpu.Virtualization)" }
            }
        }
        catch {
            $rows += [PSCustomObject]@{ Category = "CPU"; Item = "Error"; Value = "$_" }
        }
    }

    # --- Memory ----------------------------------------------------------
    if ($Sections -contains 'Memory') {
        try {
            $memory = Get-MemoryInfo

            $slots = if ($memory.SlotsTotal -gt 0) { "$($memory.SlotsUsed) of $($memory.SlotsTotal)" } else { "$($memory.SlotsUsed)" }
            $rows += [PSCustomObject]@{ Category = "Memory"; Item = "Total installed"; Value = $memory.TotalText }
            $rows += [PSCustomObject]@{ Category = "Memory"; Item = "Slots used";      Value = $slots }

            foreach ($module in $memory.Modules) {
                $slotName = if ($module.Slot) { $module.Slot } else { "Module" }
                $rows += [PSCustomObject]@{ Category = "Memory"; Item = $slotName; Value = (Format-MemoryModuleText -Module $module) }
            }
        }
        catch {
            $rows += [PSCustomObject]@{ Category = "Memory"; Item = "Error"; Value = "$_" }
        }
    }

    # --- Board / BIOS / machine -----------------------------------------
    if ($Sections -contains 'System') {
        try {
            $hw = Get-SystemHardware

            $rows += [PSCustomObject]@{ Category = "System"; Item = "Manufacturer"; Value = "$($hw.SystemManufacturer)" }
            $rows += [PSCustomObject]@{ Category = "System"; Item = "Model";        Value = "$($hw.SystemModel)" }
            $rows += [PSCustomObject]@{ Category = "System"; Item = "Type";         Value = "$($hw.SystemType)" }
            $rows += [PSCustomObject]@{ Category = "Motherboard"; Item = "Manufacturer"; Value = "$($hw.BoardManufacturer)" }
            $rows += [PSCustomObject]@{ Category = "Motherboard"; Item = "Product";      Value = "$($hw.BoardProduct)" }
            $rows += [PSCustomObject]@{ Category = "Motherboard"; Item = "Version";      Value = "$($hw.BoardVersion)" }
            $rows += [PSCustomObject]@{ Category = "Motherboard"; Item = "Serial";       Value = "$($hw.BoardSerial)" }
            $rows += [PSCustomObject]@{ Category = "BIOS"; Item = "Vendor";  Value = "$($hw.BiosVendor)" }
            $rows += [PSCustomObject]@{ Category = "BIOS"; Item = "Version"; Value = "$($hw.BiosVersion)" }
            $rows += [PSCustomObject]@{ Category = "BIOS"; Item = "Date";    Value = "$($hw.BiosDate)" }
        }
        catch {
            $rows += [PSCustomObject]@{ Category = "System"; Item = "Error"; Value = "$_" }
        }
    }

    return $rows
}

#========================================================================
# CPU / memory tree for the collapsible grid
#========================================================================
Function Format-MemoryModuleText {
    <#
    .SYNOPSIS
        Renders one memory module as a single descriptive line.
    .PARAMETER Module
        An entry from (Get-MemoryInfo).Modules.
    .OUTPUTS
        String, e.g. "32.00 GB @ 4800 MHz (rated 5600 MHz) - Kingston KF556C40-32".
    #>
    param(
        [Parameter(Mandatory = $true)]
        $Module
    )

    $text = "$($Module.Capacity)"
    if ($Module.RunningMHz) { $text = "$text @ $($Module.RunningMHz) MHz" }
    if ($Module.RatedMHz -and $Module.RatedMHz -ne $Module.RunningMHz) { $text = "$text (rated $($Module.RatedMHz) MHz)" }
    if ($Module.Manufacturer) { $text = "$text - $($Module.Manufacturer)" }
    if ($Module.PartNumber) { $text = "$text $($Module.PartNumber)" }

    return $text
}

Function New-HardwareNode {
    <#
    .SYNOPSIS
        Builds one row object for the CPU / memory grid.
    .DESCRIPTION
        A node with children renders a caret the user can click to reveal the
        children as extra rows; a node without children is just a plain row.
        Children are ordinary nodes too, only indented and caret-less.
    .PARAMETER Category
        Left-hand grouping label ("CPU", "Memory", ...). Blank on child rows.
    .PARAMETER Item
        Middle column text.
    .PARAMETER Value
        Right-hand column text.
    .PARAMETER Children
        Detail rows revealed by the caret. Empty = no caret.
    .OUTPUTS
        PSCustomObject the DataGrid binds to.
    #>
    param(
        [Parameter(Mandatory = $false)] [AllowEmptyString()] [string]$Category = "",
        [Parameter(Mandatory = $false)] [AllowEmptyString()] [string]$Item     = "",
        [Parameter(Mandatory = $false)] [AllowEmptyString()] [string]$Value    = "",
        [Parameter(Mandatory = $false)] [Object[]]$Children = @()
    )

    $kids    = @($Children)
    $hasKids = ($kids.Count -gt 0)

    # U+25B8 / U+25BE - written as code points so the glyphs survive any
    # editor that re-saves this file without a BOM.
    $caret = if ($hasKids) { [string][char]0x25B8 } else { "" }

    return [PSCustomObject]@{
        Category    = $Category
        Item        = $Item
        Value       = $Value
        Children    = $kids
        HasChildren = $hasKids
        IsExpanded  = $false
        Caret       = $caret
    }
}

Function Expand-HardwareNodes {
    <#
    .SYNOPSIS
        Flattens a node list into the rows a DataGrid should currently show.
    .DESCRIPTION
        Emits every node, followed by its children when that node is expanded.
        The child objects are the same instances held by the parent, so the
        grid and the model never drift apart.
    .PARAMETER Nodes
        Output of Get-CpuMemoryNodes.
    .OUTPUTS
        Array of row objects.
    #>
    param(
        [Parameter(Mandatory = $false)]
        [Object[]]$Nodes = @()
    )

    $rows = @()
    foreach ($node in @($Nodes)) {
        if ($null -eq $node) { continue }
        $rows += $node
        if ($node.HasChildren -and $node.IsExpanded) { $rows += @($node.Children) }
    }

    # Returned un-wrapped on purpose: a comma-wrapped array comes back to the
    # caller as ONE object that @() cannot re-expand. Callers wrap with @().
    return $rows
}

Function Get-CpuMemoryNodes {
    <#
    .SYNOPSIS
        Returns the collapsible CPU + memory rows for the Hardware Info tab.
    .DESCRIPTION
        Identical items are aggregated into one row: a dual-socket machine
        with two matching packages shows "2 x <model>", and matching memory
        sticks collapse into "2 x 32.00 GB". The per-socket / per-slot detail
        moves into that row's children, reachable via the caret.

        CPU and memory are collected independently, so a failing CIM class
        costs you one section rather than the whole grid.
    .OUTPUTS
        Array of node objects (see New-HardwareNode).
    #>
    $nodes = @()

    # --- Processor(s) ----------------------------------------------------
    try {
        $cpus = @(Get-CpuInfo)

        # Group identical packages - a single-socket box just yields one group.
        $cpuGroups = $cpus | Group-Object -Property { "$($_.Name)|$($_.Cores)|$($_.Threads)|$($_.MaxClockMHz)" }

        foreach ($group in @($cpuGroups)) {
            $cpu   = $group.Group[0]
            $count = $group.Count

            $label   = if ($count -gt 1) { "$count x $($cpu.Name)" } else { "$($cpu.Name)" }
            $headline = "$($cpu.Cores) cores / $($cpu.Threads) threads"
            if ($cpu.MaxClockMHz) { $headline = "$headline @ $($cpu.MaxClockMHz) MHz" }

            # Details that would otherwise be six near-empty rows in the grid.
            $children = @()
            $children += New-HardwareNode -Item "    Manufacturer"   -Value "$($cpu.Manufacturer)"
            $children += New-HardwareNode -Item "    Socket"         -Value (($group.Group | ForEach-Object { $_.Socket }) -join ', ')
            $children += New-HardwareNode -Item "    L2 / L3 cache"  -Value "$($cpu.L2CacheKB) KB / $($cpu.L3CacheKB) KB"
            $children += New-HardwareNode -Item "    Address width"  -Value "$($cpu.Architecture)-bit"
            $children += New-HardwareNode -Item "    Virtualization" -Value "$($cpu.Virtualization)"

            $nodes += New-HardwareNode -Category "CPU" -Item $label -Value $headline -Children $children
        }

        if ($cpus.Count -eq 0) {
            $nodes += New-HardwareNode -Category "CPU" -Item "No processor reported" -Value ""
        }
    }
    catch {
        $nodes += New-HardwareNode -Category "CPU" -Item "Error" -Value "$_"
    }

    # --- Memory ----------------------------------------------------------
    try {
        $memory = Get-MemoryInfo

        $slots = if ($memory.SlotsTotal -gt 0) { "$($memory.SlotsUsed) of $($memory.SlotsTotal) slots used" } else { "$($memory.SlotsUsed) slot(s) used" }
        $nodes += New-HardwareNode -Category "Memory" -Item "Total installed" -Value "$($memory.TotalText) - $slots"

        # Sticks that match on every spec that matters collapse into one row.
        $moduleGroups = @($memory.Modules) | Group-Object -Property {
            "$($_.Capacity)|$($_.RunningMHz)|$($_.RatedMHz)|$($_.Manufacturer)|$($_.PartNumber)"
        }

        foreach ($group in @($moduleGroups)) {
            $module = $group.Group[0]
            $count  = $group.Count
            $detail = Format-MemoryModuleText -Module $module

            if ($count -le 1) {
                # One stick of its kind - the row IS the slot, no caret needed.
                $slotName = if ($module.Slot) { $module.Slot } else { "Module" }
                $nodes += New-HardwareNode -Category "Memory" -Item $slotName -Value $detail
                continue
            }

            $children = @()
            foreach ($stick in $group.Group) {
                $slotName = if ($stick.Slot) { $stick.Slot } else { "Module" }
                if ($stick.Bank) { $slotName = "$slotName ($($stick.Bank))" }
                $children += New-HardwareNode -Item "    $slotName" -Value (Format-MemoryModuleText -Module $stick)
            }

            $nodes += New-HardwareNode -Category "Memory" -Item "$count x $($module.Capacity)" -Value $detail -Children $children
        }

        if (@($memory.Modules).Count -eq 0) {
            $nodes += New-HardwareNode -Category "Memory" -Item "No modules reported" -Value ""
        }
    }
    catch {
        $nodes += New-HardwareNode -Category "Memory" -Item "Error" -Value "$_"
    }

    return $nodes
}

#========================================================================
# Plain-text report (clipboard / file)
#========================================================================
Function Format-HardwareReport {
    <#
    .SYNOPSIS
        Renders GPU rows and summary rows as a plain-text report.
    .PARAMETER Gpus
        Output of Get-GpuInfo.
    .PARAMETER Summary
        Output of Get-HardwareSummary.
    .OUTPUTS
        Single multi-line string.
    #>
    param(
        [Parameter(Mandatory = $false)]
        [Object[]]$Gpus = @(),

        [Parameter(Mandatory = $false)]
        [Object[]]$Summary = @()
    )

    $lines = @()
    $lines += "Hardware report - $env:COMPUTERNAME - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $lines += ("=" * 60)
    $lines += ""
    $lines += "GRAPHICS"
    $lines += ("-" * 60)

    if ($Gpus.Count -eq 0) {
        $lines += "  No display adapters reported."
    }
    else {
        foreach ($gpu in $Gpus) {
            $lines += "  $($gpu.Name)"
            $lines += "    VRAM        : $($gpu.VRAM)"
            $lines += "    Vendor      : $($gpu.Vendor)"
            $lines += "    Processor   : $($gpu.Processor)"
            $lines += "    Driver      : $($gpu.Driver) ($($gpu.DriverDate))"
            $lines += "    Mode        : $($gpu.Mode)"
            $lines += "    Status      : $($gpu.Status)"
            $lines += ""
        }
    }

    $lines += "SYSTEM"
    $lines += ("-" * 60)

    foreach ($row in $Summary) {
        $lines += ("  {0,-14}{1,-18}{2}" -f $row.Category, $row.Item, $row.Value)
    }

    return ($lines -join "`r`n")
}
