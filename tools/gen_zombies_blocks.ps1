$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$sprDir = 'C:\Users\super\ee2\assets\sprites\NEW_BLOCK_SPRITE'

# UNDEAD BUNKER zone blocks (5016-5025 -> block_17..block_26):
# forest (grass/dirt/bark/leaves), city (brick/concrete/glass/road),
# cave (rock/crystal). 40x40 + bicubic 16x16, same pipeline as the rest.

function Save-Scaled([System.Drawing.Bitmap]$bmp, [string]$path16) {
    $small = New-Object System.Drawing.Bitmap(16, 16)
    $g = [System.Drawing.Graphics]::FromImage($small)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.DrawImage($bmp, 0, 0, 16, 16)
    $g.Dispose()
    $small.Save($path16, [System.Drawing.Imaging.ImageFormat]::Png)
    $small.Dispose()
}
function C([int]$r, [int]$g, [int]$b) {
    $r = [Math]::Max(0, [Math]::Min(255, $r)); $g = [Math]::Max(0, [Math]::Min(255, $g)); $b = [Math]::Max(0, [Math]::Min(255, $b))
    return [System.Drawing.Color]::FromArgb(255, $r, $g, $b)
}

# ── block_17 (5016): FOREST GRASS — mossy blades over rich dark earth ──
$rng = New-Object System.Random(5016)
$b = New-Object System.Drawing.Bitmap(40, 40)
for ($y = 0; $y -lt 40; $y++) {
    for ($x = 0; $x -lt 40; $x++) {
        if ($y -lt 6) {
            $v = 46 + $rng.Next(-8, 14) + [int](6 * [Math]::Sin($x * 0.9))
            $b.SetPixel($x, $y, (C ([int]($v*0.55)) $v ([int]($v*0.4))))
        } else {
            $v = 40 - [int](($y - 6) * 0.55) + $rng.Next(-5, 6)
            $b.SetPixel($x, $y, (C ($v+14) ($v+2) ([int]($v*0.65))))
        }
    }
}
# grass blade tufts poking up + bright top seam
for ($x = 0; $x -lt 40; $x++) {
    $h = 1 + (($x * 7) % 4)
    for ($y = 0; $y -lt $h; $y++) {
        if (($x % 3) -ne 1) { $b.SetPixel($x, $y, (C 52 (96 + (($x * 13) % 40)) 40)) }
    }
    $b.SetPixel($x, 5, (C 24 52 22))
}
# pebbles + roots in the dirt
foreach ($p in @(@(8,16),@(24,22),@(33,14),@(14,30),@(29,34),@(5,26))) {
    $b.SetPixel($p[0], $p[1], (C 70 60 48)); $b.SetPixel($p[0]+1, $p[1], (C 88 76 60))
    $b.SetPixel($p[0], $p[1]+1, (C 52 44 36))
}
$b.Save("$sprDir\block_17.png", [System.Drawing.Imaging.ImageFormat]::Png); Save-Scaled $b "$sprDir\block_17_16.png"; $b.Dispose()

# ── block_18 (5017): DIRT — layered earth strata, stones ──
$rng = New-Object System.Random(5017)
$b = New-Object System.Drawing.Bitmap(40, 40)
for ($y = 0; $y -lt 40; $y++) {
    for ($x = 0; $x -lt 40; $x++) {
        $v = 44 - [int]($y * 0.35) + $rng.Next(-6, 7)
        if ((($y + [int](3 * [Math]::Sin($x * 0.35))) % 11) -lt 2) { $v -= 7 }  # strata bands
        $b.SetPixel($x, $y, (C ($v+16) ($v+3) ([int]($v*0.6))))
    }
}
foreach ($p in @(@(6,8),@(20,15),@(32,6),@(12,26),@(27,31),@(35,22),@(3,34))) {
    $b.SetPixel($p[0], $p[1], (C 84 72 58)); $b.SetPixel($p[0]+1, $p[1], (C 66 56 44))
    $b.SetPixel($p[0], $p[1]+1, (C 58 48 38)); $b.SetPixel($p[0]+1, $p[1]+1, (C 92 80 64))
}
$b.Save("$sprDir\block_18.png", [System.Drawing.Imaging.ImageFormat]::Png); Save-Scaled $b "$sprDir\block_18_16.png"; $b.Dispose()

# ── block_19 (5018): BARK — vertical grain, knot, moss flecks ──
$rng = New-Object System.Random(5018)
$b = New-Object System.Drawing.Bitmap(40, 40)
for ($y = 0; $y -lt 40; $y++) {
    for ($x = 0; $x -lt 40; $x++) {
        $v = 52 + [int](10 * [Math]::Sin($x * 0.55 + [Math]::Sin($y * 0.12) * 2.2)) + $rng.Next(-5, 5)
        if (($x % 9) -lt 1) { $v -= 14 }  # deep grain grooves
        $b.SetPixel($x, $y, (C ([int]($v*0.9)) ([int]($v*0.62)) ([int]($v*0.38))))
    }
}
# knot
for ($a = 0; $a -lt 360; $a += 6) {
    $rad = 3.6 + 1.1 * [Math]::Sin($a * 0.09)
    $kx = 28 + [int]($rad * [Math]::Cos($a * [Math]::PI / 180)); $ky = 13 + [int]($rad * 0.7 * [Math]::Sin($a * [Math]::PI / 180))
    if ($kx -ge 0 -and $kx -lt 40 -and $ky -ge 0 -and $ky -lt 40) { $b.SetPixel($kx, $ky, (C 34 22 14)) }
}
$b.SetPixel(28, 13, (C 22 14 8)); $b.SetPixel(29, 13, (C 22 14 8))
# moss on the left edge
for ($y = 0; $y -lt 40; $y += 1) { if (($y % 3) -ne 2) { $b.SetPixel(0, $y, (C 40 66 30)); if (($y % 4) -eq 0) { $b.SetPixel(1, $y, (C 34 58 26)) } } }
$b.Save("$sprDir\block_19.png", [System.Drawing.Imaging.ImageFormat]::Png); Save-Scaled $b "$sprDir\block_19_16.png"; $b.Dispose()

# ── block_20 (5019): LEAVES — layered midnight foliage, highlight leaves ──
$rng = New-Object System.Random(5019)
$b = New-Object System.Drawing.Bitmap(40, 40)
for ($y = 0; $y -lt 40; $y++) {
    for ($x = 0; $x -lt 40; $x++) {
        $v = 34 + [int](9 * [Math]::Sin($x * 0.5 + $y * 0.35)) + [int](7 * [Math]::Sin($y * 0.75 - $x * 0.2)) + $rng.Next(-5, 6)
        $b.SetPixel($x, $y, (C ([int]($v*0.42)) $v ([int]($v*0.5))))
    }
}
# leaf cluster highlights (crescent strokes)
foreach ($p in @(@(7,6),@(19,12),@(31,5),@(12,22),@(27,26),@(35,18),@(4,32),@(20,34))) {
    for ($i = -2; $i -le 2; $i++) {
        $lx = $p[0] + $i; $ly = $p[1] + [int]([Math]::Abs($i) * 0.7)
        if ($lx -ge 0 -and $lx -lt 40 -and $ly -ge 0 -and $ly -lt 40) { $b.SetPixel($lx, $ly, (C 44 96 52)) }
    }
    $b.SetPixel($p[0], $p[1] - 1, (C 60 122 64))
}
$b.Save("$sprDir\block_20.png", [System.Drawing.Imaging.ImageFormat]::Png); Save-Scaled $b "$sprDir\block_20_16.png"; $b.Dispose()

# ── block_21 (5020): CITY BRICK — staggered courses, grime, one cracked ──
$rng = New-Object System.Random(5020)
$b = New-Object System.Drawing.Bitmap(40, 40)
for ($y = 0; $y -lt 40; $y++) {
    $row = [int]($y / 8)
    for ($x = 0; $x -lt 40; $x++) {
        $ox = $x + $row * 6
        $mortarY = (($y % 8) -ge 7); $mortarX = (($ox % 13) -ge 12)
        if ($mortarY -or $mortarX) { $b.SetPixel($x, $y, (C 38 34 34)) }
        else {
            $v = 96 - $row * 5 + $rng.Next(-7, 8)
            $b.SetPixel($x, $y, (C $v ([int]($v*0.42)) ([int]($v*0.32))))
        }
    }
}
# cracked brick + grime drip
foreach ($ck in @(@(9,18),@(10,19),@(11,20),@(12,20),@(13,21))) { $b.SetPixel($ck[0], $ck[1], (C 30 22 20)) }
for ($y = 24; $y -lt 40; $y++) { $b.SetPixel(31, $y, (C 40 34 32)); if (($y % 2) -eq 0) { $b.SetPixel(32, $y, (C 46 40 36)) } }
$b.Save("$sprDir\block_21.png", [System.Drawing.Imaging.ImageFormat]::Png); Save-Scaled $b "$sprDir\block_21_16.png"; $b.Dispose()

# ── block_22 (5021): CONCRETE — panel, bolts, crack, water stain ──
$rng = New-Object System.Random(5021)
$b = New-Object System.Drawing.Bitmap(40, 40)
for ($y = 0; $y -lt 40; $y++) {
    for ($x = 0; $x -lt 40; $x++) {
        $edge = [Math]::Min([Math]::Min($x, 39 - $x), [Math]::Min($y, 39 - $y))
        $v = 78 + $rng.Next(-5, 6) - [int]($y * 0.3)
        if ($edge -eq 0) { $v -= 22 } elseif ($edge -eq 1) { $v += 8 }
        $b.SetPixel($x, $y, (C $v $v ($v+4)))
    }
}
foreach ($bolt in @(@(4,4),@(35,4),@(4,35),@(35,35))) {
    $b.SetPixel($bolt[0], $bolt[1], (C 120 120 126)); $b.SetPixel($bolt[0]+1, $bolt[1], (C 46 46 50))
    $b.SetPixel($bolt[0], $bolt[1]+1, (C 46 46 50))
}
$cx = 22
for ($y = 6; $y -lt 26; $y++) { $cx += $rng.Next(-1, 2); $cx = [Math]::Max(14, [Math]::Min(30, $cx)); $b.SetPixel($cx, $y, (C 48 48 52)) }
for ($y = 28; $y -lt 39; $y++) { for ($x = 8; $x -lt 14; $x++) { if ($rng.Next(3) -eq 0) { $px = $b.GetPixel($x, $y); $b.SetPixel($x, $y, (C ([int]($px.R*0.8)) ([int]($px.G*0.8)) ([int]($px.B*0.85)))) } } }
$b.Save("$sprDir\block_22.png", [System.Drawing.Imaging.ImageFormat]::Png); Save-Scaled $b "$sprDir\block_22_16.png"; $b.Dispose()

# ── block_23 (5022): WINDOW — dark glass, cross frame, moon glint, warm pane ──
$rng = New-Object System.Random(5022)
$b = New-Object System.Drawing.Bitmap(40, 40)
for ($y = 0; $y -lt 40; $y++) {
    for ($x = 0; $x -lt 40; $x++) {
        $edge = [Math]::Min([Math]::Min($x, 39 - $x), [Math]::Min($y, 39 - $y))
        if ($edge -lt 3) { $b.SetPixel($x, $y, (C 52 44 40)) }             # outer frame
        elseif ($edge -eq 3) { $b.SetPixel($x, $y, (C 28 24 22)) }
        elseif ([Math]::Abs($x - 20) -lt 2 -or [Math]::Abs($y - 20) -lt 2) { $b.SetPixel($x, $y, (C 44 38 34)) }  # cross mullion
        else {
            $v = 16 + [int](($x + $y) * 0.28) + $rng.Next(-2, 3)
            $b.SetPixel($x, $y, (C ([int]($v*0.7)) ([int]($v*0.85)) ($v+16)))
        }
    }
}
# moon glint across the upper-left pane + one warm lit pane (bottom-right)
for ($i = 0; $i -lt 9; $i++) { $gx = 6 + $i; $gy = 14 - $i; if ($gy -ge 4 -and $gx -lt 18) { $b.SetPixel($gx, $gy, (C 150 170 200)); $b.SetPixel($gx, $gy+1, (C 90 105 140)) } }
for ($y = 24; $y -lt 36; $y++) { for ($x = 24; $x -lt 36; $x++) { $v = 70 + $rng.Next(-6, 8); $b.SetPixel($x, $y, (C ($v+40) ($v+18) ([int]($v*0.5)))) } }
$b.Save("$sprDir\block_23.png", [System.Drawing.Imaging.ImageFormat]::Png); Save-Scaled $b "$sprDir\block_23_16.png"; $b.Dispose()

# ── block_24 (5023): ROAD — night asphalt, worn yellow dash on top ──
$rng = New-Object System.Random(5023)
$b = New-Object System.Drawing.Bitmap(40, 40)
for ($y = 0; $y -lt 40; $y++) {
    for ($x = 0; $x -lt 40; $x++) {
        $v = 42 - [int]($y * 0.35) + $rng.Next(-4, 5)
        if ($rng.Next(30) -eq 0) { $v += 16 }  # aggregate sparkle
        $b.SetPixel($x, $y, (C $v $v ($v+3)))
    }
}
for ($x = 0; $x -lt 40; $x++) {
    if (($x % 14) -lt 8) {
        $b.SetPixel($x, 2, (C 168 140 40)); $b.SetPixel($x, 3, (C 148 122 34))
        if ($rng.Next(4) -eq 0) { $b.SetPixel($x, 2, (C 110 94 34)) }      # worn paint
    }
    $b.SetPixel($x, 0, (C 58 58 62))
}
foreach ($p in @(@(10,18),@(26,28),@(33,12))) {                            # cracks
    $cx = $p[0]
    for ($y = $p[1]; $y -lt [Math]::Min(39, $p[1] + 9); $y++) { $cx += $rng.Next(-1, 2); if ($cx -ge 0 -and $cx -lt 40) { $b.SetPixel($cx, $y, (C 24 24 28)) } }
}
$b.Save("$sprDir\block_24.png", [System.Drawing.Imaging.ImageFormat]::Png); Save-Scaled $b "$sprDir\block_24_16.png"; $b.Dispose()

# ── block_25 (5024): CAVE ROCK — deep blue-grey facets, mineral veins ──
$rng = New-Object System.Random(5024)
$b = New-Object System.Drawing.Bitmap(40, 40)
for ($y = 0; $y -lt 40; $y++) {
    for ($x = 0; $x -lt 40; $x++) {
        $v = 34 + [int](8 * [Math]::Sin($x * 0.3 + $y * 0.5)) + [int](6 * [Math]::Sin($x * 0.8 - $y * 0.25)) + $rng.Next(-4, 5)
        $b.SetPixel($x, $y, (C ([int]($v*0.8)) ([int]($v*0.85)) ($v+10)))
    }
}
# facet edges (bright top-left / dark bottom-right diagonals)
foreach ($f in @(@(4,10,14,6),@(18,4,30,12),@(8,24,20,32),@(26,20,36,30))) {
    $steps = [Math]::Max([Math]::Abs($f[2]-$f[0]), [Math]::Abs($f[3]-$f[1]))
    for ($i = 0; $i -le $steps; $i++) {
        $fx = $f[0] + [int](($f[2]-$f[0]) * $i / $steps); $fy = $f[1] + [int](($f[3]-$f[1]) * $i / $steps)
        $b.SetPixel($fx, $fy, (C 58 62 78)); if ($fy+1 -lt 40) { $b.SetPixel($fx, $fy+1, (C 18 20 30)) }
    }
}
# thin cyan mineral vein
$vx = 6
for ($y = 30; $y -ge 14; $y--) { $vx += $rng.Next(-1, 2); $vx = [Math]::Max(2, [Math]::Min(37, $vx)); $b.SetPixel($vx, $y, (C 44 88 96)) }
$b.Save("$sprDir\block_25.png", [System.Drawing.Imaging.ImageFormat]::Png); Save-Scaled $b "$sprDir\block_25_16.png"; $b.Dispose()

# ── block_26 (5025): CRYSTAL — violet cluster, glowing facets on dark rock ──
$rng = New-Object System.Random(5025)
$b = New-Object System.Drawing.Bitmap(40, 40)
for ($y = 0; $y -lt 40; $y++) {
    for ($x = 0; $x -lt 40; $x++) {
        $v = 26 + [int](6 * [Math]::Sin($x * 0.4 + $y * 0.6)) + $rng.Next(-3, 4)
        $b.SetPixel($x, $y, (C ([int]($v*0.85)) ([int]($v*0.75)) ($v+8)))
    }
}
# three crystal shards (triangles) with bright core lines
foreach ($sh in @(@(12,36,7,14,17,30), @(24,38,20,8,30,34), @(33,36,36,18,39,32))) {
    $x0=$sh[0]; $y0=$sh[1]; $x1=$sh[2]; $y1=$sh[3]; $x2=$sh[4]; $y2=$sh[5]
    for ($y = 0; $y -lt 40; $y++) {
        for ($x = 0; $x -lt 40; $x++) {
            $d0 = ($x1-$x0)*($y-$y0)-($y1-$y0)*($x-$x0); $d1 = ($x2-$x1)*($y-$y1)-($y2-$y1)*($x-$x1); $d2 = ($x0-$x2)*($y-$y2)-($y0-$y2)*($x-$x2)
            if (($d0 -ge 0 -and $d1 -ge 0 -and $d2 -ge 0) -or ($d0 -le 0 -and $d1 -le 0 -and $d2 -le 0)) {
                $depth = 120 + [int](($x - $x0) * 3.5) + $rng.Next(-8, 9)
                $b.SetPixel($x, $y, (C ([int]($depth*0.75)) ([int]($depth*0.4)) ([Math]::Min(255, $depth+60))))
            }
        }
    }
    # bright core line tip->base
    $steps = [Math]::Max([Math]::Abs($x1-$x0), [Math]::Abs($y1-$y0))
    for ($i = 0; $i -le $steps; $i++) {
        $fx = $x0 + [int](($x1-$x0) * $i / $steps); $fy = $y0 + [int](($y1-$y0) * $i / $steps)
        $b.SetPixel($fx, $fy, (C 210 150 255))
    }
    $b.SetPixel($x1, $y1, (C 255 230 255))
}
$b.Save("$sprDir\block_26.png", [System.Drawing.Imaging.ImageFormat]::Png); Save-Scaled $b "$sprDir\block_26_16.png"; $b.Dispose()

Write-Output "ZOMBIE ZONE BLOCKS 17-26 GENERATED"
