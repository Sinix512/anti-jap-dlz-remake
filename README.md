# dlz-remake

《抗日：地雷战》（1998）的Godot复刻。原版`../dlz/ANTI-JAP/`只读，未运行EXE。

**2026-10-27：用户已停止旧47关目标，本会话改为整理当前实现版攻略；可玩性/成长验证由另一会话负责。好玩优先，不要求严格原味或兼容原版旧存档。踩雷软锁仍有未解决反馈。以下验收/试验状态为历史记录，不是自动续跑指令。**

[玩家攻略](docs/guide/README.md) · [离线合订版](docs/guide/guide.html) · [地形图鉴](docs/guide/terrain.md) · [兵种范围图](docs/guide/unit_ranges.md) · [全部数值](docs/guide/reference.md) · [47关任务事件](docs/guide/missions.md)

[交接](HANDOVER.md) · [缺口](GAPS.md) · [计划](PLAN.md) · [验收](ACCEPTANCE.md) · [试玩](MANUAL_PLAYTEST.md)

```bash
./run_game.sh
./run_playtest.sh
./verify_final.sh  # 47关未证不能成功退出
```

最新完整strict259：**67/69 PASS、195实际图+SHA、同源/UUID一致、exit1**。真正normal新档L00–07胜，L08 T7主角死亡，47未完成。失败保留。260进一步检出range背景/半像素拖影，262修复后完整无legal UI **69/69、195图、exit0同源**；263另纠正L22专用完整菜单，完整68/69、195图、exit1同源，world_system截图被桌面motion改行；267静态捕获隔离已应用，266终局原输入26项接runner；完整UI268 **70/70、195实际图、exit0同源f7ca6730…1b0a7**，无新fresh/47证明。详`out/evidence/strict259/`及当前验收页。

已实现原47关/19镇资源与规则、成长/AI/技能/雷/库存、标题/战略/服务/部署/剧情/战报、END/JZ及JSON续存；**资源装载不等于47可玩已证明**。原EXE mode150续战明确拒绝，为高成本兼容边界。

原标题仅五项；附加工具必须显式CLI，不作正常战役证据：

```bash
./run_game.sh -- --remake-tools=drill
# drill / story / settings / intro / gallery
```

生成数据改生成器，新增中文后跑`python3 tools/rebuild_font.py`。新逆向只用GPT-6.1 Sol子代理；不改HP/等级/AI/时限救自动玩家，不拼开发档当新档。261固定缴获装备实际T6败已停止；264有限H2实际T7败已停止；269有限缴获制铁雷实际T6败（3杀/2损失）已停止，不是fresh；失败历史和未完成项见当前台账。

270新增自然多档viewport路线驱动与联合来源gate，完整 **74/74、195图、同源6198508e…1b1e8、exit2**；两条真正fresh各仅L00–01胜，47不足被正确拒绝。后期自然路线仍未证明，不是通过47。详`out/evidence/routes270/full/summary.json`。

```bash
# 工程短档：两条独立新档各两关，预期47门槛exit2，不代替完整验收
./verify_original.sh --ui --legal --require-campaign --campaign-battle-limit=2
```


## 271–272补交（2026-10-26）

- **271正式一次原T11 escort_lost败，已停止**。source259完整entry0差、同源6198508e…1b1e8、UUID4cbd197b7bc7496fbd74c5f20356dcaa；183.560518333s/child exit0/maxRSS1067548672B。仅T7扩展一次/改选一次42合法wait中的@(4,29)；hero存活Lv1 XP23 HP90，NPC9李霜泗HP0；3枪杀/7损失/余13敌，权限/故事/运行诊断0错。只补测试玩家漏候选，不是原规则修复；不接默认、不重跑、不续L09、不算fresh。证据`out/evidence/candidate271/`与研究计划结果。
- **272 Sol证实插曲/关系真实别名**：原D4/D8严格DWORD==0才进入44/45，而公共回合邻接及三类技能同址累加。source259 L08已有8/4，晚到30再访无法覆盖44/45。270晚访策略是测试玩家路线规划缺口，非生产规则差异。应在L00之后最早合法town0、phase!=1且两计数仍零时尝试；不得清零、换bit或强触发。44战中是否会堵45需实际验证，不能宣称多fresh必需或单fresh必足。报告`docs/research/interlude_alias272_20261026.md`，3082缓存指令按PE核同。
- 270完整74/74/195图/exit2属于其固定619源；后续改早期路线后必须重新验证，不把旧绿归属新源码。**47关与goal仍未完成**。


## 273–276进展（2026-10-26）

- 早期插曲策略已改：首个可用战略窗口寻访，不能把非零共享计数当完成记录。原L00胜后直接L01部署，首次实际可回访是L01胜后index2；初次budget2仅L00–01胜/无44，已保留而非虚报。修正观察预算3后，真正fresh normal103/4/100，25.451948125s/exit0、source前后02846e65…7ea58，7次实际民房输入自然launch44，D4=1/D8=0/R=2；联合validator valid=true、complete=false。**44仅观测入口，未打赢**。证据`out/evidence/early273/capture/`。
- Sol273核1306指令确认44原手控41..55、保护自动40/杀56；固定阵容无7/8，已见正常路径不污染D8。46首轮全自动、turn2仅80可控，70..80必须全活且全歼。没有借此改AI/胜负/控制权。
- **已修真实L45额外插队缺陷**：原直接模板入口不部署，Intro的raw17只是保留元数据。generator仅将45.party_deploy=false；builder不再添主线roster，Campaign清旧选择并跳K00。原17/Special坐标、原slot40手控/41..65敌军、虚构40..43正常部署均保留。新OriginalInterludeParty30/0已通过，已接strict；初版测试m2_data拼错及错误漏掉敌42..65的oracle均留失败，不称生产故障。早期route30/0继续通过。
- Sol274核932指令确认L08 NPC9/10原b0驻守、control0不可接管；9无HP治疗、b0不使用疑兵，10不自动滚木。271不是NPC冲阵，是敌49..55追9到达；前排不等于挡枪/改仇恨。合法双战区方案仍待实际胜利，未发现新增确定规则差异。报告`docs/research/l08_escort274_20261026.md`。
- 275旧局部fight_unit在273真实44入口的开发JSON续试，完整entry0差、同源970d09d7…a2e147、10.2518s/exit0，原T15 unit_40_lost败，4枪杀/余12敌，权限/故事0错。追兵穿中路打自动40，部分我军已前进北区，局部自身避险不足。停止同参、不接默认、不续45、不称fresh。276独立验证现默认全阶段forecast玩家，尚在运行，未有结果。
- 已启动新源970d09d7…a2e147完整strict UI+两条fresh短链回归；**未结束前不称通过**。270旧619源74/74/195图/exit2继续独立保留。47关/持续成长/长档与goal仍未完成。


### 273正式回归收口

新源970d09d75e6eec908bd0830188156423e46070f42a2e033478a435c407a2e147前后一致，**75/75 PASS、195本次实际图、548.7323s、exit2（47不足，正确拒绝）**。六张当前实际图目检无明显异常。两条fresh仍各仅L00–01胜，来源/权限/故事0错；与旧028源早期44入口观察分开。276也已结束：419.8561s/exit0/整entry0差，原默认120工程watchdog停在T121、finished=false/result空，11枪杀/9损失/余5敌；自动40完整HP564、56仍688。**不是原超时败、不是胜利**。停止同参；278正独立测试原目标普通攻击收尾，不改游戏胜负或资源。


## 277–280补交（2026-10-26）

- 277只读检查：source259 L08整entry0差、未发任何战斗命令。T1北区敌远、双方无伤，旧/扩展均无技能候选；空集合不算控场有效证据。未改生产。
- **278已终止：456.6353s/child exit0，同源970d09d7…a2e147，完整entry0差。T121仍player/finished=false/result空，11枪杀/9损失/余5敌，56仍688；不是原败或胜利。** 每轮普通攻击burst只读规划未找到足量合击，未战报确认，不续45，停止同参。证据`out/evidence/interlude278/`。潜在真胜后已释放battle再取snapshot的后处理问题未在本次watchdog触发；新试验已把终态捕获置于战报确认前。
- **279已原T12 escort_lost败：202.59058s/exit0，UUID f7707c58aeb7435f9b0d0ff87b698561，source前后970一致、3脚本/input一致、双重整entry0差、历史前8精确、权限/故事/诊断0错。** 仅一次hero T7待机扩展改变，3枪杀/8损失/余13敌；hero活HP90/Lv1/XP29，9在原(30,9)HP0。补已学技能候选不等于联合护送规划；实际疑兵既有成功也有0目标。停止同参，不接默认、不续09、不称fresh。证据`out/evidence/skills279/`。
- 280新增6.1 Sol窄审boss（报告及证据见`docs/research/boss280_original_20261026.md`），无新增确定生产差异。原56 behavior12/type45/智93，原治疗及低概率掠夺/持续骚扰均不能视为必中；初版报告误将两件装备防累加为76，主agent源码交叉核对指出，Sol原42B0EA复核应取max64，成功偷首件后剩12、净降52。错误历史需单留，不能据此改生产。
- 281单次隔离合法编队试验正在执行：守40附近集结→追兵全灭后整队推进→现有54/55可达/存活时真实掠夺56；不改规则、不增资源、不称fresh。未有结果前不称通关。
- 已补early273、277、278、279总artifact_manifest；273正式75/75、195图、exit2仍为最新完整工程回归，47/成长长档与goal仍未完成。
