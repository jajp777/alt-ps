function Get-ArchiveContent {
  <#
    .SYNOPSIS
        Gets content of a compressed (zip) file.
  #>
  param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({Test-Path $_})]
    [String]$Path
  )
  
  begin {
    if (($zip = [IO.FileInfo](Convert-Path $Path)).Length -le 22) {
      throw "Archive $zip does not contains items."
    }
    
    $edc, $cdf = 0x6054B50, 0x2014B50
    
    function Set-ShiftMethod {
      param(
        [Parameter(Position=0)]
        [ValidateNotNullOrEmpty()]
        [ValidateSet('Left', 'Right')]
        [String]$Direction = 'Right',
        
        [Parameter(Position=1)]
        [ValidateNotNull()]
        [Object]$Type = [Int32]
      )
      
      @(
        'Ldarg_0'
        'Ldarg_1'
        'Ldc_I4_S, 31'
        'And'
        $(if ($Direction -eq 'Right') { 'Shr' } else { 'Shl' })
        'Ret'
      ) | ForEach-Object {
        $def = New-Object Reflection.Emit.DynamicMethod(
          $Direction, $Type, @($Type, $Type)
        )
        $il = $def.GetILGenerator()
      }{
        if ($_ -notmatch ',') { $il.Emit([Reflection.Emit.OpCodes]::$_) }
        else {
          $il.Emit(
            [Reflection.Emit.OpCodes]::(
              ($$ = $_.Split(','))[0]), ($$[1].Trim() -as $Type
            )
        )}
      }
      
      $def.CreateDelegate((
        Invoke-Expression "[Func[$($Type.Name), $($Type.Name), $($Type.Name)]]"
      ))
    }
    
    function ConvertFrom-TimeStamp {
      param(
        [Parameter(Mandatory=$true, Position=0)]
        [UInt16]$Time,
        
        [Parameter(Mandatory=$true, Position=1)]
        [UInt16]$Date
      )
      
      $shr = Set-ShiftMethod
      New-Object DateTime(
        ($shr.Invoke($Date, 9) + 1980),
        ($shr.Invoke($Date, 5) -band 0xF),
        ($Date -band 0x1F),
        $shr.Invoke($Time, 11),
        ($shr.Invoke($Time, 5) -band 0x3F),
        (($Time -band 0x1F) * 2)
      )
    }
  }
  process {
    try {
      $fs = [IO.File]::OpenRead($zip.FullName)
      $br = New-Object IO.BinaryReader($fs)
      
      $fs.Position = $fs.Length - 22
      if ($br.ReadUInt32() -ne $edc) {
        $comment = [Math]::Max((
          $fs.Length - (Set-ShiftMethod Left).Invoke(1, 16) - 22
        ), 0)
        $fs.Position = $comment
        
        $buf = New-Object Byte[]($fs.Length - $comment)
        [void]$fs.Read($buf, 0, $buf.Length)
        $fs.Position = ([Regex]'PK\x05\x06').Match(
          [Text.Encoding]::Default.GetString($buf)
        ).Index + $comment
        
        if ($br.ReadUInt32() -ne $edc) {
          throw "File $zip has invalid format."
        }
      }
      $fs.Position += 12
      $fs.Position = $br.ReadUInt32()
      
      $(while ($true) {
        if ($br.ReadUint32() -ne $cdf) { break }
        
        $fs.Position += 8
        $time, $date = $br.ReadUInt16(), $br.ReadUInt16()
        $fs.Position += 4
        $csz, $usz = $br.ReadUint32(), $br.ReadUInt32()
        $nsz = $br.ReadUInt16()
        
        $skip = [Int64]($br.ReadUInt16() + $br.ReadUInt16())
        $fs.Position += 4
        $atr = [IO.FileAttributes]$br.ReadUInt32()
        $fs.Position += 4
        $name = -join $br.ReadChars($nsz)
        
        New-Object PSObject -Property @{
          DateTime = ConvertFrom-TimeStamp $time $date
          Attributes = $atr
          Size = $usz
          Compressed = $csz
          Name = $name
        }
        
        $fs.Position += $skip
      }) |
      Select-Object DateTime, Attributes, Size, Compressed, Name |
      Format-Table -AutoSize
    }
    finally {
      if ($br) { $br.Close() }
      
      if ($fs) {
        $fs.Dispose()
        $fs.Close()
      }
    }
  }
  end {}
}
