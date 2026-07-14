$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$sfxDir = 'C:\Users\super\ee2\assets\sfx'
$sprDir = 'C:\Users\super\ee2\assets\sprites\NEW_BLOCK_SPRITE'
New-Item -ItemType Directory -Force $sfxDir | Out-Null

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
$rand = New-Object System.Random(42)

# Blaster: punchy descending square chirp
$dur = 0.1; $n = [int]($rate * $dur); $s = New-Object double[] $n; $ph = 0.0
for ($i = 0; $i -lt $n; $i++) {
    $t = $i / $rate
    $f = 1500 - 1150 * ($t / $dur)
    $ph += 2 * [Math]::PI * $f / $rate
    $env = [Math]::Exp(-20 * $t)
    $s[$i] = [Math]::Sign([Math]::Sin($ph)) * 0.3 * $env + ($rand.NextDouble() * 2 - 1) * 0.06 * $env
}
Write-Wav "$sfxDir\shoot_blaster.wav" $s $rate

# Scatter: shotgun noise blast with low thump
$dur = 0.16; $n = [int]($rate * $dur); $s = New-Object double[] $n; $prev = 0.0; $ph = 0.0
for ($i = 0; $i -lt $n; $i++) {
    $t = $i / $rate
    $env = [Math]::Exp(-16 * $t)
    $white = ($rand.NextDouble() * 2 - 1)
    $prev = $prev * 0.6 + $white * 0.4
    $ph += 2 * [Math]::PI * (120 - 60 * $t / $dur) / $rate
    $s[$i] = $prev * 0.4 * $env + [Math]::Sin($ph) * 0.25 * $env
}
Write-Wav "$sfxDir\shoot_scatter.wav" $s $rate

# Rail: rising charged zap with sizzle
$dur = 0.24; $n = [int]($rate * $dur); $s = New-Object double[] $n; $ph = 0.0
for ($i = 0; $i -lt $n; $i++) {
    $t = $i / $rate
    $f = 250 + 2400 * ($t / $dur) * ($t / $dur)
    $ph += 2 * [Math]::PI * $f / $rate
    $env = if ($t -lt 0.05) { $t / 0.05 } else { [Math]::Exp(-9 * ($t - 0.05)) }
    $s[$i] = [Math]::Sin($ph) * 0.3 * $env + ($rand.NextDouble() * 2 - 1) * 0.12 * $env * ($t / $dur)
}
Write-Wav "$sfxDir\shoot_rail.wav" $s $rate

# Hit: short pop
$dur = 0.07; $n = [int]($rate * $dur); $s = New-Object double[] $n; $prev = 0.0
for ($i = 0; $i -lt $n; $i++) {
    $t = $i / $rate
    $env = [Math]::Exp(-40 * $t)
    $white = ($rand.NextDouble() * 2 - 1)
    $prev = $prev * 0.5 + $white * 0.5
    $s[$i] = $prev * 0.5 * $env
}
Write-Wav "$sfxDir\hit.wav" $s $rate

# Explode: deep rumbling burst
$dur = 0.5; $n = [int]($rate * $dur); $s = New-Object double[] $n; $prev = 0.0; $ph = 0.0
for ($i = 0; $i -lt $n; $i++) {
    $t = $i / $rate
    $env = [Math]::Exp(-7 * $t)
    $white = ($rand.NextDouble() * 2 - 1)
    $prev = $prev * 0.85 + $white * 0.15
    $ph += 2 * [Math]::PI * (70 - 40 * $t / $dur) / $rate
    $s[$i] = $prev * 0.55 * $env + [Math]::Sin($ph) * 0.3 * $env
}
Write-Wav "$sfxDir\explode.wav" $s $rate

# Pickup: bright two-tone chime
$dur = 0.22; $n = [int]($rate * $dur); $s = New-Object double[] $n
for ($i = 0; $i -lt $n; $i++) {
    $t = $i / $rate
    $f = if ($t -lt 0.09) { 660.0 } else { 990.0 }
    $lt = if ($t -lt 0.09) { $t } else { $t - 0.09 }
    $env = [Math]::Exp(-14 * $lt)
    $s[$i] = [Math]::Sin(2 * [Math]::PI * $f * $t) * 0.26 * $env + [Math]::Sin(2 * [Math]::PI * $f * 2 * $t) * 0.08 * $env
}
Write-Wav "$sfxDir\pickup.wav" $s $rate

Write-Output "SFX written"

# ---- Block sprites (40x40 + 16x16) ----

function Save-Scaled([System.Drawing.Bitmap]$bmp, [string]$path16) {
    $small = New-Object System.Drawing.Bitmap(16, 16)
    $g = [System.Drawing.Graphics]::FromImage($small)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.DrawImage($bmp, 0, 0, 16, 16)
    $g.Dispose()
    $small.Save($path16, [System.Drawing.Imaging.ImageFormat]::Png)
    $small.Dispose()
}

# block_6: "arena plate" - dark gunmetal, cyan energy edge, corner rivets
$b = New-Object System.Drawing.Bitmap(40, 40)
for ($y = 0; $y -lt 40; $y++) {
    for ($x = 0; $x -lt 40; $x++) {
        $edge = [Math]::Min([Math]::Min($x, 39 - $x), [Math]::Min($y, 39 - $y))
        if ($edge -eq 0) { $c = [System.Drawing.Color]::FromArgb(255, 10, 14, 20) }
        elseif ($edge -eq 1) { $c = [System.Drawing.Color]::FromArgb(255, 40, 200, 235) }
        elseif ($edge -eq 2) { $c = [System.Drawing.Color]::FromArgb(255, 22, 80, 100) }
        else {
            $sh = 30 - [int](($y / 39.0) * 10)
            $tone = 26 + $sh
            # brushed metal lines every 4px
            if (($y % 8) -lt 1 -and $edge -gt 3) { $tone += 7 }
            $c = [System.Drawing.Color]::FromArgb(255, $tone, $tone + 4, $tone + 12)
        }
        $b.SetPixel($x, $y, $c)
    }
}
# rivets in corners (inset 5px)
foreach ($rx in 5, 33) { foreach ($ry in 5, 33) {
    for ($dx = 0; $dx -lt 2; $dx++) { for ($dy = 0; $dy -lt 2; $dy++) {
        $b.SetPixel($rx + $dx, $ry + $dy, [System.Drawing.Color]::FromArgb(255, 120, 190, 210))
    } }
    $b.SetPixel($rx, $ry + 2, [System.Drawing.Color]::FromArgb(255, 12, 20, 28))
    $b.SetPixel($rx + 1, $ry + 2, [System.Drawing.Color]::FromArgb(255, 12, 20, 28))
} }
$b.Save("$sprDir\block_6.png", [System.Drawing.Imaging.ImageFormat]::Png)
Save-Scaled $b "$sprDir\block_6_16.png"
$b.Dispose()

# block_7: "core hazard" - dark plate with amber warning stripes + hot edge
$b = New-Object System.Drawing.Bitmap(40, 40)
for ($y = 0; $y -lt 40; $y++) {
    for ($x = 0; $x -lt 40; $x++) {
        $edge = [Math]::Min([Math]::Min($x, 39 - $x), [Math]::Min($y, 39 - $y))
        if ($edge -eq 0) { $c = [System.Drawing.Color]::FromArgb(255, 16, 8, 6) }
        elseif ($edge -eq 1) { $c = [System.Drawing.Color]::FromArgb(255, 255, 150, 40) }
        elseif ($edge -eq 2) { $c = [System.Drawing.Color]::FromArgb(255, 90, 45, 18) }
        else {
            $band = ((($x + $y) % 16) -lt 7)
            if ($band) {
                $glow = 200 + [int](40 * [Math]::Sin(($x + $y) * 0.35))
                $c = [System.Drawing.Color]::FromArgb(255, $glow, [int]($glow * 0.55), 20)
            } else {
                $c = [System.Drawing.Color]::FromArgb(255, 30, 22, 26)
            }
        }
        $b.SetPixel($x, $y, $c)
    }
}
$b.Save("$sprDir\block_7.png", [System.Drawing.Imaging.ImageFormat]::Png)
Save-Scaled $b "$sprDir\block_7_16.png"
$b.Dispose()

Write-Output "Sprites written"
