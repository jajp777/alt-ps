function Get-DllExports {
  <#
    .SYNOPSIS
        Locates exported functions inside specified system module (DLL).
    .EXAMPLE
        PS C:\> Get-DllExports ntdll
        Finds functions names into ntdll.dll module.
  #>
  param(
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateNotNullOrEmpty()]
    [String]$Module
  )
  
  begin {
    #check that module has extension and exists in system directory
    if (!$Module.EndsWith('.dll')) { $Module += '.dll' }
    $Module = "$([Environment]::SystemDirectory)\$Module"
    
    if (!(Test-Path $Module)) {
      Write-Error 'Module has not been found.'
      break
    }
    #accelerate Marshal type
    if (($ta = [PSObject].Assembly.GetType(
      'System.Management.Automation.TypeAccelerators'
    ))::Get.Keys -notcontains 'Marshal') {
      $ta::Add('Marshal', [Runtime.InteropServices.Marshal])
    }
    #locates exports data without creation additional assembly
    function Find-Exports([String]$Path) {
      try {
        $fs = [IO.File]::OpenRead($Path)
        $br = New-Object IO.BinaryReader($fs)
        
        $e_magic = $br.ReadUInt16() #MZ
        $fs.Position = 0x3C
        $fs.Position = $br.ReadUInt16()
        $pe_sign = $br.ReadUInt32() #PE\0\0
        
        if ($e_magic -ne 23117 -and $pe_sign -ne 17744) {
          throw New-Object Exception('Unknown file format.')
        }
        
        #number of sections
        $fs.Position += 0x02
        $pe_sec = $br.ReadUInt16()
        #size of optional header
        $fs.Position += 0x0C
        $pe_ioh = $br.ReadUInt16()
        #PE or PE+
        $fs.Position += 0x02
        $buf = $fs.Position #begin of optional header
        switch ($br.ReadUInt16()) {
          0x10B {
            $fs.Position += 0x1A
            $img_base = $br.ReadUInt32()
          }
          0x20B {
            $fs.Position += 0x16
            $img_base = $br.ReadUInt64()
          }
          default {
            throw New-Object Exception('Unknown machine type.')
          }
        }
        #check that export directory exists
        $fs.Position = $buf + ($pe_ioh - 0x80)
        $rva_addr = $br.ReadUInt32()
        $rva_size = $br.ReadUInt32()
        
        if ($rva_addr -eq 0 -and $rva_size -eq 0) {
          throw New-Object Exception('Does not contain exports.')
        }
        
        #IMAGE_EXPORT_DIRECTORY
        $fs.Position += 0x78
        0..($pe_sec - 1) | ForEach-Object {
          [void]$br.ReadUInt64()
          $vrt_size = $br.ReadUInt32()
          $vrt_addr = $br.ReadUInt32()
          $fs.Position += 0x04
          $ptr_data = $br.ReadUInt32()
          
          if (($off = $rva_addr - $vrt_addr) -ge 0 -and $off -lt $vrt_size) {
            $ptr_strc = $ptr_data + $off
          }
          $fs.Position += 0x10 #move to the next section
        }
        $fs.Position = $ptr_strc
        New-Object PSObject -Property @{
          Characteristics       = $br.ReadUInt32()
          TimeDateStamp         = $br.ReadUInt32()
          MajorVersion          = $br.ReadUInt16()
          MinorVersion          = $br.ReadUInt16()
          Name                  = $br.ReadUInt32()
          Base                  = $br.ReadUInt32()
          NumberOfFunctions     = $br.ReadUInt32()
          NumberOfNames         = $br.ReadUInt32()
          AddressOfFunctions    = $br.ReadUInt32()
          AddressOfNames        = $br.ReadUint32()
          AddressOfNameOrdinals = $br.ReadUInt32()
        }
      }
      catch { $_.Exception }
      finally {
        if ($br -ne $null) { $br.Close() }
        
        if ($fs -ne $null) {
          $fs.Dispose()
          $fs.Close()
        }
      }
    }
    #locate and load latest Microsoft.Build.Tasks assembly
    $al = New-Object Collections.ArrayList
    
    [Object].Assembly.GetType(
      'Microsoft.Win32.Fusion'
    ).GetMethod(
      'ReadCache'
    ).Invoke($null, @(
      [Collections.ArrayList]$al, $null, [UInt32]2
    ))
    
    Add-Type -AssemblyName ($$ = ($al | Where-Object {
      $_ -cmatch '(?=Microsoft.Build.Tasks)(?!.*(?>resources)).+'
    })[-1].Split(',')[0])
    #locate Microsoft.Build.Tasks in current domain
    $asm = [AppDomain]::CurrentDomain.GetAssemblies() |
    Where-Object {$_.ManifestModule.ScopeName.Equals("$$.dll")}
  }
  process {
    #no exports found
    if (($ied = Find-Exports $Module).Name -eq $null) {
      Write-Error $ied.Message
      return
    }
    #required functions and fields
    ($$ = $asm.GetType(
      'Microsoft.Build.Tasks.NativeMethods'
    )).GetMethods(
      [Reflection.BindingFlags]40
    ) | Where-Object {
      $_.Name -cmatch '\A(Close|CreateFile|Image|Map|Unmap).*\Z'
    } | ForEach-Object {
      Set-Variable $_.Name $_
    }
    
    $$.GetFields([Reflection.BindingFlags]40) |
    Where-Object { $_.Name -cmatch 'READ' } |
    ForEach-Object { Set-Variable $_.Name $_.GetValue($null) }
    #read exported functions names
    try {
      $file = $CreateFile.Invoke($null, @(
        $Module, $GENERIC_READ, [IO.File]::Read, [IntPtr]::Zero,
        [IO.FileMode]::Open, [UInt32]0, [IntPtr]::Zero
      ))
      $fmap = $CreateFileMapping.Invoke($null, @(
        $file, [IntPtr]::Zero, $PAGE_READONLY, [UInt32]0, [UInt32]0, $null
      ))
      $vmap = $MapViewOfFile.Invoke($null, @(
        $fmap, $FILE_MAP_READ, [UInt32]0, [UInt32]0, [IntPtr]::Zero
      ))
      $inth = $ImageNtHeader.Invoke($null, @($vmap))
      $rtva = $ImageRvaToVa.Invoke($null, @(
        $inth, $vmap, $ied.AddressOfNames, [IntPtr]::Zero
      ))
      $eptr = $ImageRvaToVa.Invoke($null, @(
        $inth, $vmap, [UInt32][Marshal]::ReadInt32($rtva), [IntPtr]::Zero
      ))
      0..($ied.NumberOfNames - 1) | ForEach-Object {
        $func = [Marshal]::PtrToStringAnsi($eptr)
        $eptr = [IntPtr]($eptr.ToInt64() + $func.Length + 1)
        $func
      }
    }
    catch { $_.Exception }
    finally {
      [void]$UnmapViewOfFile.Invoke($null, @($vmap))
      [void]$CloseHandle.Invoke($null, @($fmap))
      [void]$CloseHandle.Invoke($null, @($file))
      [void]$ta::Remove('Marshal')
    }
  }
  end {}
}
