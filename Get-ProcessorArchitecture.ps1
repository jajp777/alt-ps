$$ = ($GetProcessorArchitecture = [PSObject].Assembly.GetType(
  'System.Management.Automation.PsUtils'
).GetMethod(
  'GetProcessorArchitecture', [Reflection.BindingFlags]40
)).GetParameters() | Select-Object -ExpandProperty ParameterType

if ($$ -ne $null) {
  $p = $p -as ($$.Name.Substring(0, $$.Name.Length - 1) -as [Type])
  $GetProcessorArchitecture.Invoke($null, @($p))
}
else { $GetProcessorArchitecture.Invoke($null, @()) }
