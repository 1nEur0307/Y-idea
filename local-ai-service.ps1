$ErrorActionPreference = 'Stop'
$port = 8765
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$apiKey = $env:OPENAI_API_KEY
if (-not $apiKey) {
  Write-Host "Enter your OpenAI API key (it will not be saved):" -ForegroundColor Yellow
  $secure = Read-Host "OPENAI_API_KEY" -AsSecureString
  $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try { $apiKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}
if (-not $apiKey) { throw 'No API key entered; service was not started.' }
$model = if ($env:OPENAI_MODEL) { $env:OPENAI_MODEL } else { 'gpt-4.1-mini' }
$prompt = 'Read a Chinese or English recruiting, job-description, or offer screenshot. Return only one JSON object (no Markdown) with these complete keys: name, status, salary, probationSalary, probationLength, location, workingHours, nature, insuranceFund, housingFund, jobContent, notes. Use empty strings when unknown and do not guess. status must be exactly one of: not_applied, applied, written_test, interview, verbal_offer, formal_offer, no_response, rejected, withdrawn. Use applied if no status is shown. salary is regular salary after probation. Keep jobContent and notes concise.'
function Send-Json($context, [int]$status, $value) {
  $bytes = [Text.Encoding]::UTF8.GetBytes(($value | ConvertTo-Json -Depth 8 -Compress))
  $context.Response.StatusCode = $status
  $context.Response.ContentType = 'application/json; charset=utf-8'
  $context.Response.ContentLength64 = $bytes.Length
  $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
  $context.Response.Close()
}
function Serve-File($context) {
  $name = [uri]::UnescapeDataString($context.Request.Url.AbsolutePath.TrimStart('/'))
  if ($name) { $context.Response.StatusCode = 404; $context.Response.Close(); return }
  $path = Get-ChildItem -LiteralPath $root -Filter '*.html' | Select-Object -First 1 -ExpandProperty FullName
  $bytes = [IO.File]::ReadAllBytes($path)
  $context.Response.ContentType = 'text/html; charset=utf-8'
  $context.Response.ContentLength64 = $bytes.Length
  $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
  $context.Response.Close()
}
$listener = [Net.HttpListener]::new()
$listener.Prefixes.Add("http://127.0.0.1:$port/")
$listener.Start()
Write-Host "`nLocal service started: http://127.0.0.1:$port" -ForegroundColor Green
Write-Host 'The tracker will open in your browser. Keep this window open while using AI recognition.' -ForegroundColor Green
Start-Process "http://127.0.0.1:$port/"
while ($listener.IsListening) {
  $context = $listener.GetContext()
  try {
    if ($context.Request.HttpMethod -eq 'GET') { Serve-File $context; continue }
    if ($context.Request.HttpMethod -ne 'POST' -or $context.Request.Url.AbsolutePath -ne '/api/extract') { $context.Response.StatusCode = 404; $context.Response.Close(); continue }
    if ($context.Request.ContentLength64 -le 0 -or $context.Request.ContentLength64 -gt 12582912) { throw 'Image data is empty or too large. Choose a smaller screenshot.' }
    $reader = [IO.StreamReader]::new($context.Request.InputStream, $context.Request.ContentEncoding)
    $incoming = $reader.ReadToEnd() | ConvertFrom-Json
    if (-not $incoming.image -or -not $incoming.image.StartsWith('data:image/')) { throw 'Upload a PNG, JPG, WEBP, or GIF image.' }
    $payload = @{ model = $model; input = @(@{ role = 'user'; content = @(@{type='input_text';text=$prompt}, @{type='input_image';image_url=$incoming.image;detail='high'}) }) }
    $headers = @{ Authorization = "Bearer $apiKey"; 'Content-Type' = 'application/json' }
    $result = Invoke-RestMethod -Uri 'https://api.openai.com/v1/responses' -Method Post -Headers $headers -Body ($payload | ConvertTo-Json -Depth 8 -Compress) -TimeoutSec 90
    $fields = $result.output_text | ConvertFrom-Json
    if (-not $fields) { throw 'AI returned no usable information. Try a clearer screenshot.' }
    Send-Json $context 200 @{fields=$fields}
  } catch {
    $message = $_.Exception.Message
    if ($message -match '401|403') { $message = 'API key is invalid or lacks permission. Restart and enter the correct key.' }
    elseif ($message -match '429') { $message = 'API quota is insufficient or requests are too frequent. Try again later.' }
    Send-Json $context 502 @{error=$message}
  }
}
