"""Read-only transcription of DLZ.exe town resident/commander phase scripts.

Not wired to gameplay by this module. Native phase indices refer to SAVE block13:
resident=town*5, commander=town*5+1; the remaining three per-town slots are
preserved, not free storage. Data follows code, not a fabricated per-level recruit
schedule. All recruit actions mean People[slot].side=0, no money is charged.

RESIDENT rules run in listed order, re-evaluating changed phases (except an
explicit else_if_group shares the original if/else boundary). COMMANDER chooses
one matching rule. phase_in is its commander phase. resident_not_in and
resident_in are additional gates; set_phase_before_choice happens even on cancel.
messages_if_phase use the phase before that assignment. accept actions happen
only on Yes (original 42738A returns 0). enter_recruit happens before the prompt,
including on cancel. deploy=True opens the original deployment screen for the
already-selected campaign index; do not increment campaign_index on town visit.

Messages are TXT table slots (n=(global_ptr-0x472588)/4), not WAV IDs. Prompt is
literal UI text, not a TXT record. Evidence IDs are assigned below each town.
Town0's resident first deployment/random repeat sidequests are special, specified
in RESIDENT_SPECIAL. Town15 first commander choice is direct solo deployment,
not the ordinary deployment screen. See notes; do not flatten these exceptions.
"""

TOWN_NAMES = ['桃花岭','赵村','花坪镇','李村','土桥','白洋淀','萧家庄','冉庄','枣庄',
              '阳村','清风寨','鸡公山','太平镇','黑风寨','长湾','施南镇','红岩镇','平阳县','天池山']

def txt(addr):
    assert 0x472588 <= addr < 0x472588 + 478 * 4 and (addr - 0x472588) % 4 == 0
    return (addr - 0x472588) // 4


def resident(phase, messages, new_phase, **kwargs):
    return {'phase': phase, 'messages': [txt(a) for a in messages],
            'set_phase': new_phase, **kwargs}


RESIDENT = {
 0: [resident(0,[0x4725DC],1)],
 1: [resident(0,[0x4725CC],1,reward_items={12:1}),
     resident(2,[0x4725F4],3,unlock_mine_types=[3])],
 2: [resident(0,[0x472604,0x472608],1,unlock_mine_types=[1])],
 3: [resident(0,[0x47262C],1),resident(2,[0x472658,0x47265C],3,unlock_mine_types=[2])],
 4: [resident(0,[0x472664,0x472668],1,unlock_mine_types=[4])],
 5: [resident(0,[0x472988],1),resident(2,[0x47299C],3)],
 6: [resident(0,[0x4726A4,0x4726A8],1,unlock_mine_types=[6]),
     resident(2,[0x4729D8],3,reward_items={29:1})],
 7: [resident(0,[0x472A10],1),resident(2,[0x472718],3,unlock_mine_types=[8])],
 8: [resident(0,[0x472A28],1),resident(2,[0x472A3C],3),
     resident(4,[0x472A50],5,else_if_group='phase4_or_5'),
     resident(5,[0x472A24],6,unlock_mine_types=[7],else_if_group='phase4_or_5')],
 9: [resident(0,[0x472780],1)],
 10:[resident(0,[0x4727A4],1,unlock_mine_types=[9])],
 11:[resident(0,[0x4729FC],1)],
 12:[resident(0,[0x4727D8],1)],
 13:[resident(0,[0x472820],1),resident(2,[0x472848,0x47284C],3,unlock_fuses=[3])],
 14:[resident(0,[0x47286C],1)],
 15:[resident(0,[0x4728AC],1),resident(2,[0x472AF0],3),resident(4,[0x472B04],5)],
 16:[resident(0,[0x4728E8],1),resident(2,[0x4728FC],3),resident(4,[0x472910],5),resident(6,[],7)],
 17:[resident(0,[0x472B6C],1),resident(2,[0x472BF4],3),resident(4,[0x472C74],5),
     resident(6,[0x472CD8],7),resident(8,[0x472C08],9)],
 18:[],
}

RESIDENT_SPECIAL = {
 0: {'after_resident_rules': True,
     'if_phase_1': {'prompt':'出战吗？','accept':{'set_resident_phase':2,'deploy':True}},
     'else_repeat': {'chance_percent':30,
       'first_unset_block13_slot_in_order':[3,4,9],
       'corresponding_battle_indices':[44,45,46],
       'on_trigger': {'set_selected_block13_slot':1,
                     'save_campaign_index_to_block13_slot':91,
                     'direct_next_battle':True},
       'note':'Only execute this else when phase was not1 at original if evaluation; no repeat sidequest after accepting first deploy in same visit.'}},
}


def commander(phases, new_phase, messages_if_phase=None, recruits=(), **kwargs):
    return {'phase_in':list(phases), 'messages_if_phase':{
        k:[txt(a) for a in v] for k,v in (messages_if_phase or {}).items()},
        'set_phase_before_choice':min(phases) if min(phases)%2 else min(phases)+1,
        'prompt':'出战吗？',
        'accept':{'set_phase':new_phase,'recruit':list(recruits),'deploy':True}, **kwargs}


COMMANDER = {
 0:[],
 1:[commander([0,1],2,{0:[0x4725E0]},[4]),
    commander([2,3],4,{2:[0x4725E0]},set_phase_before_choice=None)],
 2:[commander([0,1],2,{0:[0x4725E0],1:[0x4725E0]})],
 3:[commander([0,1],2,{0:[0x472630]},[7,8]),
    commander([2],3,{2:[0x4725E0]},set_phase_before_choice=None)],
 4:[commander([0,1],2,{0:[0x472964,0x472968]},[9,10])],
 5:[commander([0,1],2,{0:[0x47298C]},[11]),
    commander([2,3],4,{2:[0x4729A0]},[12],messages_always=[txt(0x4729A4)])],
 6:[commander([0,1],2,{0:[0x472630]},[13]),
    commander([2,3],4,{2:[0x4729DC,0x4729E0]})],
 7:[commander([0,1],2,{0:[0x472A08,0x472A0C]},[15,16]),
    {'phase_not_in':[0,1], 'resident_in':[2], 'messages':[txt(0x472A14)],'no_choice':True},
    commander([2,3],4,{2:[0x472A18]},resident_not_in=[2])],
 8:[commander([0,1],2,{0:[0x472A2C]},resident_not_in=[4]),
    commander([2,3],4,{2:[0x472A40]},[20],resident_not_in=[4]),
    commander([4,5],6,{4:[0x472A54]},[20],resident_not_in=[4],
              accept_extra={'set_resident_phase':6})],
 9:[{'resident_in':[0],'messages':[txt(0x472A7C)],'no_choice':True},
    commander([0,1],2,{0:[0x472A74,0x472A78]},[22],resident_not_in=[0])],
 10:[commander([0,1],2,{0:[0x4727BC]},[23])],
 11:[commander([0,1],2,{0:[0x4729F4]})],
 12:[commander([0,1],2,{0:[0x4727E4]})],
 13:[commander([0,1],2,{0:[0x472824]}),commander([2,3],4,{2:[0x472850]})],
 14:[commander([0,1],2,{0:[0x472870]},resident_not_in=[0]),
     commander([2,3],4,{2:[0x472850]},resident_not_in=[0])],
 15:[{'phase_in':[0,1], 'resident_not_in':[0,2,4],
      'messages_if_phase':{0:[txt(0x4728B0)]},'set_phase_before_choice':1,
      'prompt':None,'choice_options':[
        {'label':'肖飞','value':0,'battle_slot':8},
        {'label':'李霜泗','value':1,'battle_slot':9}],
      'accept':{'set_phase':2,'set_block13_slot_2_from_choice':True,
                'direct_solo_battle':True,'deploy_at_intro_special_position':0,
                'retarget_enemy_slots':list(range(40,48)),
                'note':'No ordinary deployment screen; chosen existing fighter stage1, initial position/direction from Intro special_positions[0].'}},
     commander([2,3],4,{2:[0x472AF4]},[7],resident_not_in=[0,2,4]),
     commander([4,5],6,{},resident_not_in=[0,2,4],
       messages_if_block13={79:{4:[txt(0x472B08)]}},
       note='Original checks 7D0804 (block13[79])==4 for message, not own phase4; preserve observed oddity.')],
 16:[commander([0,1],2,{0:[0x4728F8]},[32],resident_not_in=[0,2,4]),
     commander([2,3],4,{2:[0x472900]},resident_not_in=[0,2,4]),
     commander([4,5],6,{4:[0x472B14]},resident_not_in=[0,2,4],enter_recruit=[31]),
     commander([6,7],8,{},resident_not_in=[0,2,4])],
 17:[commander([0,1],2,{0:[0x472B70]},resident_not_in=[0]),
     commander([2,3],4,{2:[0x472BFC]},resident_not_in=[0]),
     commander([4,5],6,{4:[0x472C78]},resident_not_in=[0]),
     commander([6,7],8,{6:[0x472C78]},resident_not_in=[0]),
     commander([8,9],10,{8:[0x472BFC]},resident_not_in=[0])],
 18:[],
}

# Non-town joins are in the original entry/victory/tick phase tables. In
# particular People1/2/3 are victory joins,5/6 &17/18 are battle-entry joins,
# and remaining late candidates join through explicit battle scripts; do not
# infer missing characters from this town table or charge a recruit fee.

assert set(RESIDENT) == set(COMMANDER) == set(range(19))
assert txt(0x4725E0) == 22
assert COMMANDER[1][0]['accept']['recruit'] == [4]
assert COMMANDER[16][2]['enter_recruit'] == [31]


EVIDENCE = {
  0: {
    "resident_entry": "0x406ce8",
    "resident_evidence": "ev_23996125620352dd3cc4d68900a9fd9d5aeb9d408b4246537c30817b8bdedf98",
    "commander_entry": "0x4075de",
    "commander_evidence": "ev_ad38ae4eae17f6556829565ca4e787fe3f1c0d8c9688fa3040906eb585807a86"
  },
  1: {
    "resident_entry": "0x406f96",
    "resident_evidence": "ev_3d57191870971328ea752405f8a53ee96ebc4fe9f6a217b0c6be5f2dc3a34919",
    "commander_entry": "0x4075e3",
    "commander_evidence": "ev_a77eb5dbb8e167a4d6c2ee3f4a5da90f118a6cc6771b9fd8be80dd4a9c590254"
  },
  2: {
    "resident_entry": "0x407002",
    "resident_evidence": "ev_7ba18a0866e04597a51d41698e45825aff2d9e0ebb23b5ccd8914e5c71791930",
    "commander_entry": "0x407715",
    "commander_evidence": "ev_31fb753984ca4b043cb01fbd074d03df5f563deacbdb1614758d9dfbe2c5b69c"
  },
  3: {
    "resident_entry": "0x407049",
    "resident_evidence": "ev_0fa4d7079193c824d471f6854bf3e0547386f825d5a0c5746fa91d654cec9f2e",
    "commander_entry": "0x4077aa",
    "commander_evidence": "ev_02df03abf24183ca55a1e0143d1a34496aa88b814357bee480a929cd5fa5eafe"
  },
  4: {
    "resident_entry": "0x4070b6",
    "resident_evidence": "ev_959a3f76747fcf9d7c32d8c3dd717ca7e212f8d69827f7256f3ed5bc518568d0",
    "commander_entry": "0x4078d1",
    "commander_evidence": "ev_f97f7c5ad21805fe7975ad4738d04235b10dbf146b9e12f80599069ac275df08"
  },
  5: {
    "resident_entry": "0x4070fd",
    "resident_evidence": "ev_8640d63e495582a7887cd144aef3662c64c5a7db56a28586037bf583c3c12b55",
    "commander_entry": "0x40799a",
    "commander_evidence": "ev_3a4f55791a40eefcda954f20015ee3beacd9ae25031bb327d02ad641e4c680c1"
  },
  6: {
    "resident_entry": "0x40714d",
    "resident_evidence": "ev_6a92a76f2cdc5f3d8b0b7da4f40dc3db0072874f042f0194306b34425359dddb",
    "commander_entry": "0x407af7",
    "commander_evidence": "ev_0306ab45abda9917c75583d6e01d612ea608c0002992e812cbf80d2452834569"
  },
  7: {
    "resident_entry": "0x4071ca",
    "resident_evidence": "ev_d1c90b9dc5f39b6801e00233bcfcd7ae6fc7a6b6dbc8bcc15b9c0edf03cb6fbe",
    "commander_entry": "0x407c4a",
    "commander_evidence": "ev_384b78189fdda569b6e693d25d7769c163d7d5e5977edfb517a980e2a4cb3a8d"
  },
  8: {
    "resident_entry": "0x407224",
    "resident_evidence": "ev_861a087b4be76d8b612982fa5f7a6e0731a703df8fe0625e631bf67a976881d4",
    "commander_entry": "0x407dc4",
    "commander_evidence": "ev_bef154a25cb194c245040b896880aaf5aaa690c8b183f95b69f4ba7eb47f4569"
  },
  9: {
    "resident_entry": "0x4072cb",
    "resident_evidence": "ev_143eb4a4e396455d708b449a53cc2b25b3ac11eb891e9613066ace70b30f41c1",
    "commander_entry": "0x407fb7",
    "commander_evidence": "ev_2f3ac5b6ec5cc147e5e7bc2797fe49c8b68f75c8d60436d9f7e6fa9d2acc7efd"
  },
  10: {
    "resident_entry": "0x4072f5",
    "resident_evidence": "ev_48e5800f85b3e94e7d424bd95b84d328203d50530cbe58c9f6d60efdffc46dfb",
    "commander_entry": "0x408096",
    "commander_evidence": "ev_5377f15ea0f1792d5e11f9e41278ff08fef07635d67372d1099163243fd73a15"
  },
  11: {
    "resident_entry": "0x407329",
    "resident_evidence": "ev_8dd2289586c4ecebc69562985dd746e98b7abab1d713faf6d247874396b2a444",
    "commander_entry": "0x408142",
    "commander_evidence": "ev_bbf3d8589ed5f24e09a7b400393393f1a040755c1a343f71efda052baffddae0"
  },
  12: {
    "resident_entry": "0x407353",
    "resident_evidence": "ev_1b98c40cd2f9cbfb5d0f473e2c4b0d19cc04bd6c66cb55b7ebbe126e944cae81",
    "commander_entry": "0x4081e0",
    "commander_evidence": "ev_03c19d3c40dcb785f2f1d35b2d9a56d4c7d67b6ddecb2bce94a14e3c82f60e3f"
  },
  13: {
    "resident_entry": "0x40737d",
    "resident_evidence": "ev_6968ea0877e942e54d8aa937cb5f5511dcd05e037dc9e399406d29e562311732",
    "commander_entry": "0x40827e",
    "commander_evidence": "ev_77130394e3f84a75fcc0b2444360889125d09dc74608bd3d6cb1c32ae8707d91"
  },
  14: {
    "resident_entry": "0x4073ea",
    "resident_evidence": "ev_c35b8d39a90129a447f33fdd7e62e1d515105a7588d57708fe13a1a82aa95877",
    "commander_entry": "0x4083ac",
    "commander_evidence": "ev_ba6c44ee84bc904f47d104679a642e98c31b1d58551c85ddd67223aee536cde9"
  },
  15: {
    "resident_entry": "0x407414",
    "resident_evidence": "ev_636119cc15e9a5b3c6d5a5198847e90ade04e09916e451ec4e4efbd4b2001125",
    "commander_entry": "0x4084e8",
    "commander_evidence": "ev_559740a9e989fd5ca951901b310e09e838b7acd3fd77f1f07b425a53e564c8a4"
  },
  16: {
    "resident_entry": "0x40748a",
    "resident_evidence": "ev_a9f19d0be8f1ef611adf13a2acb837d36e47e834daa99493dd1df40bacf9f333",
    "commander_entry": "0x4087c5",
    "commander_evidence": "ev_666d8ed04b530d29b19f42b1e7139a99cef384ab49ed08b1a8f279342922a10f"
  },
  17: {
    "resident_entry": "0x407513",
    "resident_evidence": "ev_63667a62ca935c554d835b42670e4fdbd3aa15773ab3fd2c167654f84e36736d",
    "commander_entry": "0x408a31",
    "commander_evidence": "ev_c502ca5cc60906062314a120aed23812cf024ac9944137bfe901844f9cb5ecd7"
  },
  18: {
    "resident_entry": "0x4075d4",
    "resident_evidence": "ev_2a280aefbb221cbab97cd9aa3fcfd31ea2ee97e6100d7f79e9c688aa63210de4",
    "commander_entry": "0x408d1e",
    "commander_evidence": "ev_c1d8c3b19210bc971a058e247b54e6461d1db867f3cea01c36c9e7b9edd43504"
  }
}
