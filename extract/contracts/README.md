# 构建与测试契约

这里只保留当前生成器和回归测试实际读取的字段，不包含原始工具回执、反编译缓存或会话记录。格式解析器仍在 `extract/*.py`，游戏逻辑在 `godot/scripts/`。

| 文件 | 消费方 / 内容 |
|---|---|
| `ui_controls.json` | 原版菜单选中背景的256色 LUT；UI 构建与独立像素检查 |
| `strategic_ui.json` | 19城镇布局、入口矩形和战略地图事实；对应原版4310B9/4304E0/43B680 |
| `bgm_tracks.json` | 音效光盘 NRG 的音轨边界；本地音轨转换 |
| `history_photos.json` | 历史图像尺寸、位置和背景色；媒体回归 |
| `range_mask.fixtures.json` | 选格/移动范围及生命周期向量 |
| `mine_ui_mask.fixtures.json` | 雷操作选格、资格判定及生命周期向量 |
| `highlight_lut.bin` | 424B31/421F68/421D10 的256字节暗化测试向量 |
| `luan_glyph.bin` | 原版HZK16“乱”字的32字节测试样本 |

改动契约后应重建资源并执行当前回归，不能为了让测试通过而直接修改预期值。原版字形/调色板样本不因作为测试数据存在而获得本项目 MIT 授权，见根目录 `THIRD_PARTY_NOTICES.md`。
