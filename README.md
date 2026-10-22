# dlz-remake

《抗日：地雷战》(西山居, 1998, Win32/DirectDraw, MSVC 5.0) 的复刻工程。

原版素材放在 `../dlz/ANTI-JAP/`（918 MB，含 33 段真人 MPEG 过场与 CD 音轨），
本目录只放代码与抽取产物。

## 已确认的格式

### IMG（位图，86 个）

```
0x00  4B   'IMGV'
0x04  2B   pad (=1)
0x06  2B   宽 - 1 (LE)
0x08  2B   高 - 1 (LE)
0x0A  6B   pad
0x10  w*h  8bpp 索引像素，逐行无压缩
随后  768B 调色板，256 × RGB，每分量 6 位（×4 → 0-255）
```

尺寸恒等式 `16 + w*h + 768 == 文件长度` 在 84/86 个文件上成立。

### TXT.DAT（剧情文本，110,900 B）

整文件逐字节 XOR `0x51` 后即 GB18030 文本；记录为
`三位编号 + 若干行（行首 -1）+ 'xx' 终止`。解析出 478 条记录、55,005 字。

## 未解决

- `END04.IMG`（64,784 B，声明 640×480）：像素区只有 64,000 B，疑似 RLE。
- `ZYB.IMG`（4,840,464 B）：约 15.75 帧的 640×480，疑似多帧容器。
- `ANM`(38) / `FLM` / `FLC`(4) / `FACE.DAT` / `WAVE.DAT` / 各 DAT 结构未拆。

## 用法

```bash
python3 extract_all.py     # → out/img/*.png, out/txt/dialogue.txt, out/json/
```