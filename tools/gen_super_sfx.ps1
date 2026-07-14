$ErrorActionPreference = 'Stop'
$sfxDir = 'C:\Users\super\ee2\assets\sfx'

function Write-Wav([string]$path, [double[]]$samples, [int]$rate) {
    $n = $samples.Count
    $ms = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter($ms)
    $bw.Write([System.Text.Encoding]::ASCII.GetBytes('RIFF'))
    $bw.Write([int](36 + $n * 2))
    $bw.Write([System.Text.Encoding]::ASCII.GetBytes('WAVEfmt '))
    $bw.Write([int]16); $bw.Write([int16]1); $bw.Write([int16]1)
    $bw.Write([int]$rate); $bw.Write([int]($rate * 2)); $bw.Write([int16]2); $bw.Write([int16]16)
    $bw.Write([System.Text.Encoding]::ASCII.GetBytes('data'))
    $bw.Write([int]($n * 2))
    foreach ($s in $samples) {
        $v = [Math]::Max(-1.0, [Math]::Min(1.0, $s))
        $bw.Write([int16]($v * 32000))
    }
    $bw.Flush()
    [System.IO.File]::WriteAllBytes($path, $ms.ToArray())
    $bw.Close()
}

$rate = 22050
$rand = New-Object System.Random(7)

# doom_spawn: 1.8s dramatic riser (sweep up + shimmer + swell)
$dur = 1.8; $n = [int]($rate * $dur); $s = New-Object double[] $n; $ph = 0.0; $ph2 = 0.0
for ($i = 0; $i -lt $n; $i++) {
    $t = $i / $rate
    $prog = $t / $dur
    $f = 70 + 850 * $prog * $prog
    $ph += 2 * [Math]::PI * $f / $rate
    $ph2 += 2 * [Math]::PI * ($f * 1.5 + 6 * [Math]::Sin($t * 9)) / $rate
    $env = 0.12 + 0.75 * $prog
    if ($prog -gt 0.94) { $env *= (1.0 - ($prog - 0.94) / 0.06) * 0.9 + 0.1 }
    $s[$i] = ([Math]::Sin($ph) * 0.5 + [Math]::Sin($ph2) * 0.25 + ($rand.NextDouble() * 2 - 1) * 0.10 * $prog) * $env * 0.55
}
Write-Wav "$sfxDir\doom_spawn.wav" $s $rate

# doom_beam: 0.4s constant-level hum (looped in code while firing)
$dur = 0.4; $n = [int]($rate * $dur); $s = New-Object double[] $n; $ph = 0.0; $ph2 = 0.0; $ph3 = 0.0
for ($i = 0; $i -lt $n; $i++) {
    $t = $i / $rate
    $ph += 2 * [Math]::PI * 55 / $rate
    $ph2 += 2 * [Math]::PI * 220 / $rate
    $ph3 += 2 * [Math]::PI * (440 + 25 * [Math]::Sin($t * 40)) / $rate
    $saw = 2.0 * (($ph / (2 * [Math]::PI)) % 1.0) - 1.0
    $s[$i] = ($saw * 0.28 + [Math]::Sin($ph2) * 0.22 + [Math]::Sin($ph3) * 0.12 + ($rand.NextDouble() * 2 - 1) * 0.08) * 0.5
}
Write-Wav "$sfxDir\doom_beam.wav" $s $rate

Write-Output "Super SFX written"
