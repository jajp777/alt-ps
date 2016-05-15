function Find-Pinvoke {
  <#
    .SYNOPSIS
        Finds PInvokes in the specified assembly which has been loaded in
        current AppDomain.
    .PARAMETER TypeName
        A public type name, e.g. PSObject.
    .EXAMPLE
        PS C:\> Find-Pinvoke Regex
        Finds information on all the PInvokes in the System.dll assembly.
  #>
  param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [String]$TypeName
  )
  
  begin {
    if (($base = $TypeName -as [Type]) -eq $null) {
      Write-Warning "specified type has not been found in current AppDomain."
      break
    }
  }
  process {
    foreach ($type in $base.Assembly.GetTypes()) {
      $type.GetMethods([Reflection.BindingFlags]60) | ForEach-Object {
        if (($_.Attributes -band 0x2000) -eq 0x2000) {
          $sig = [Reflection.CustomAttributeData]::GetCustomAttributes(
            $_ #pinvoke data
          ) | Where-Object {$_.ToString() -cmatch 'DllImportAttribute'}
          New-Object PSObject -Property @{
            Module     = if (![IO.Path]::HasExtension(
              ($$ = $sig.ConstructorArguments[0].Value)
            )) { "$$.dll" } else { $$ }
            EntryPoint = ($sig.NamedArguments | Where-Object {
              $_.MemberInfo.Name -eq 'EntryPoint'
            }).TypedValue.Value
            MethodName = $_.Name
            Attributes = $_.Attributes
            TypeName   = $type.FullName
            Signature  = $_.ToString() -replace '(\S+)\s+(.*)', '$2 as $1'
            DllImport  = $sig
          } | Select-Object Module, EntryPoint, MethodName, Attributes, `
          Signature, DllImport
        }
      } #foreach
    } #foreach
  }
  end {}
}
