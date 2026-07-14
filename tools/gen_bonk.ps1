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
$rand = New-Object System.Random(3)

# bonk: rubbery body-collision thump - pitch-dropping sine + click transient
$dur = 0.14; $n = [int]($rate * $dur); $s = New-Object double[] $n; $ph = 0.0
for ($i = 0; $i -lt $n; $i++) {
    $t = $i / $rate
    $f = 190 - 100 * ($t / $dur)
    $ph += 2 * [Math]::PI * $f / $rate
    $env = [Math]::Exp(-26 * $t)
    $click = 0.0
    if ($i -lt 60) { $click = ($rand.NextDouble() * 2 - 1) * 0.35 * (1.0 - $i / 60.0) }
    $s[$i] = [Math]::Sin($ph) * 0.55 * $env + $click
}
Write-Wav "$sfxDir\bonk.wav" $s $rate
Write-Output "bonk written"
