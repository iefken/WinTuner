#========================================================================
# File-Functions.ps1 — local file utilities.
#
# Auto-loaded by Import-Functions.ps1, so these are also callable straight
# from the Local PS tab (e.g. Get-FileEncoding -FilePath C:\foo.ps1).
#========================================================================

# Returns the process(es) holding a lock on a file (Windows Restart Manager).
# Returns a List[Process]; empty list if nothing has it open.
function Get-FileLockProcess {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $True)]
        [string]$FilePath
    )

    if (-not (Test-Path $FilePath)) {
        Write-Error "Get-FileLockProcess: path not found: $FilePath"
        return
    }

    $typeName = 'PcMgmt.Utils.FileLockUtil'
    $alreadyLoaded = [System.AppDomain]::CurrentDomain.GetAssemblies() |
        Where-Object { $_.ExportedTypes -like "$typeName*" }

    if (-not $alreadyLoaded) {
        $typeDefinition = @"
        using System;
        using System.Collections.Generic;
        using System.Diagnostics;
        using System.Runtime.InteropServices;

        namespace PcMgmt.Utils
        {
            static public class FileLockUtil
            {
                [StructLayout(LayoutKind.Sequential)]
                struct RM_UNIQUE_PROCESS
                {
                    public int dwProcessId;
                    public System.Runtime.InteropServices.ComTypes.FILETIME ProcessStartTime;
                }

                const int RmRebootReasonNone = 0;
                const int CCH_RM_MAX_APP_NAME = 255;
                const int CCH_RM_MAX_SVC_NAME = 63;

                enum RM_APP_TYPE
                {
                    RmUnknownApp = 0, RmMainWindow = 1, RmOtherWindow = 2,
                    RmService = 3, RmExplorer = 4, RmConsole = 5, RmCritical = 1000
                }

                [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
                struct RM_PROCESS_INFO
                {
                    public RM_UNIQUE_PROCESS Process;
                    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = CCH_RM_MAX_APP_NAME + 1)]
                    public string strAppName;
                    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = CCH_RM_MAX_SVC_NAME + 1)]
                    public string strServiceShortName;
                    public RM_APP_TYPE ApplicationType;
                    public uint AppStatus;
                    public uint TSSessionId;
                    [MarshalAs(UnmanagedType.Bool)]
                    public bool bRestartable;
                }

                [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)]
                static extern int RmRegisterResources(uint pSessionHandle, UInt32 nFiles, string[] rgsFilenames,
                    UInt32 nApplications, [In] RM_UNIQUE_PROCESS[] rgApplications, UInt32 nServices, string[] rgsServiceNames);

                [DllImport("rstrtmgr.dll", CharSet = CharSet.Auto)]
                static extern int RmStartSession(out uint pSessionHandle, int dwSessionFlags, string strSessionKey);

                [DllImport("rstrtmgr.dll")]
                static extern int RmEndSession(uint pSessionHandle);

                [DllImport("rstrtmgr.dll")]
                static extern int RmGetList(uint dwSessionHandle, out uint pnProcInfoNeeded, ref uint pnProcInfo,
                    [In, Out] RM_PROCESS_INFO[] rgAffectedApps, ref uint lpdwRebootReasons);

                static public List<Process> WhoIsLocking(string path)
                {
                    uint handle;
                    string key = Guid.NewGuid().ToString();
                    List<Process> processes = new List<Process>();

                    int res = RmStartSession(out handle, 0, key);
                    if (res != 0) throw new Exception("Could not begin restart session.");

                    try
                    {
                        const int ERROR_MORE_DATA = 234;
                        uint pnProcInfoNeeded = 0, pnProcInfo = 0, lpdwRebootReasons = RmRebootReasonNone;
                        string[] resources = new string[] { path };

                        res = RmRegisterResources(handle, (uint)resources.Length, resources, 0, null, 0, null);
                        if (res != 0) throw new Exception("Could not register resource.");

                        res = RmGetList(handle, out pnProcInfoNeeded, ref pnProcInfo, null, ref lpdwRebootReasons);
                        if (res == ERROR_MORE_DATA)
                        {
                            RM_PROCESS_INFO[] processInfo = new RM_PROCESS_INFO[pnProcInfoNeeded];
                            pnProcInfo = pnProcInfoNeeded;
                            res = RmGetList(handle, out pnProcInfoNeeded, ref pnProcInfo, processInfo, ref lpdwRebootReasons);
                            if (res == 0)
                            {
                                processes = new List<Process>((int)pnProcInfo);
                                for (int i = 0; i < pnProcInfo; i++)
                                {
                                    try { processes.Add(Process.GetProcessById(processInfo[i].Process.dwProcessId)); }
                                    catch (ArgumentException) { }
                                }
                            }
                            else throw new Exception("Could not list processes locking resource.");
                        }
                        else if (res != 0) throw new Exception("Could not list processes locking resource (size query failed).");
                    }
                    finally { RmEndSession(handle); }

                    return processes;
                }
            }
        }
"@
        try {
            Add-Type -TypeDefinition $typeDefinition -ErrorAction Stop
        }
        catch {
            Write-Error "Get-FileLockProcess: failed to compile helper type: $_"
            return
        }
    }

    return [PcMgmt.Utils.FileLockUtil]::WhoIsLocking($FilePath)
}

# Detects a text file's encoding by inspecting its byte-order mark (BOM).
# Returns one of: UTF8-BOM, UTF16-LE, UTF16-BE, UTF32-LE, UTF32-BE, UTF7,
# or "No BOM (UTF-8 / ANSI)" when no BOM is present.
function Get-FileEncoding {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $True)]
        [String]$FilePath
    )

    if (-not (Test-Path $FilePath -PathType Leaf)) {
        Write-Error "Get-FileEncoding: file not found: $FilePath"
        return
    }

    try {
        $bytes = [System.IO.File]::ReadAllBytes($FilePath)
    }
    catch {
        Write-Error "Get-FileEncoding: cannot read file: $_"
        return
    }

    if ($bytes.Length -ge 4 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE -and $bytes[2] -eq 0x00 -and $bytes[3] -eq 0x00) { return 'UTF32-LE' }
    if ($bytes.Length -ge 4 -and $bytes[0] -eq 0x00 -and $bytes[1] -eq 0x00 -and $bytes[2] -eq 0xFE -and $bytes[3] -eq 0xFF) { return 'UTF32-BE' }
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { return 'UTF8-BOM' }
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) { return 'UTF16-LE' }
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) { return 'UTF16-BE' }
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0x2B -and $bytes[1] -eq 0x2F -and $bytes[2] -eq 0x76) { return 'UTF7' }

    return 'No BOM (UTF-8 / ANSI)'
}
