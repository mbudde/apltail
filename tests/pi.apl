⍝ Compute pi
n ← 10000
pi ← 4×(+/1>(+/(?n 2⍴0)*2)*÷2)÷n

⍝ ⎕ ← pi

0.1 > | pi - ○ 1