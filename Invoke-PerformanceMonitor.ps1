mshta ("about:<html>$(ConvertTo-Html -Head @'
<title>PerformanceMonitor</title>
<hta:Application ID="PerformanceModinor"
     Border="thick"
     BorderStyle="normal"
     ContextMenu="no"
     MaximizeButton="no"
     MinimizeButton="no"
     Scroll="no"
     SingleInstance="yes"
     WindowState="normal" />
<style type="text/css">
  body {
    background-color: #000;
    font-family: tahoma;
    font-size: 80%;
    margin: 0;
    padding: 0;
  }
</style>
<script language="JScript">
  function resize() { window.window.resizeTo(600, 400); }
</script>
'@ -Body @'
<object classID="clsid:C4D2D8E0-D1DD-11CE-940F-008029004347"
        ID="PerformanceMonitor"
        Height="100%"
        Width="100%" />
'@ | Select-Object -Skip 2)" -replace '\<body', '<body onload="resize();"')
