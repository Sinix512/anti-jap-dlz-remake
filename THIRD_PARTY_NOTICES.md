# 许可范围与第三方说明

## 本项目的 MIT 范围

根目录 [LICENSE](LICENSE) 仅适用于贡献者有权授权的重写代码、脚本及原创说明。项目作者使用 GitHub 身份 Sinix512，不公开私人邮箱；这不替代实际权属核实。

下列内容**不因放在本仓库或由脚本生成而获得本项目的 MIT 授权**：

- 原版游戏的 EXE、DAT、IMG、TGA、NRG、视频、音频、字体和其他文件。
- 从原版提取、裁切、转换或内嵌的图像、音轨、字形、动画、剧情及其他受保护表达；包括 `docs/images/*.png` 展示图、字形样本以及 `docs/guide/guide.html` 中的原版图像。此处不对其可再分发性作结论。
- 测试契约中来源于原版的字形、调色板样本，以及任何第三方引文；这些内容应与独立重写的算法和格式事实区分判断。
- 第三方名称、商标、标识以及不属于贡献者的其他材料。

已知路径只用于说明，不是穷尽清单。原版游戏的权利仍属于各自权利人。MIT 允许本项目可授权代码的商业使用，但**不授予原版游戏内容、名称或商标的使用权**，也不保证某个发行包具有合法授权。独立重写代码与原程序受保护表达的边界仍需按实际内容核实。

## dlzopen/dlz_research

- 上游：[dlzopen/dlz_research](https://github.com/dlzopen/dlz_research)。
- 已知参考位置：`extract/people.py` 的 PEOPLE 字段表、`extract/game.py` 的 GAME 段布局；文件内保留来源说明。
- 上游许可：[MIT LICENSE](https://github.com/dlzopen/dlz_research/blob/main/LICENSE)，2026-10-30 核对版权行为 `Copyright (c) 2022 dlzopen`。
- 以下保留上游许可，避免在存在代码或实质性内容复用时丢失声明；这不是对所有参考内容均构成代码复制的判断，也不把上游收录的原版二进制自动视为 MIT。

```text
MIT License

Copyright (c) 2022 dlzopen

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## 其他参考与运行依赖

Godot、Python、Pillow、NumPy、FFmpeg 等是外部依赖，不因本仓库采用 MIT 而变更各自许可。本仓库不随代码附带这些软件；若将引擎、库或 FFmpeg 一同打包分发，应按实际版本和构建配置核查并附上对应许可与通知。
