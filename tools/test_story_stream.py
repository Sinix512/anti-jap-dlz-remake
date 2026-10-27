"""43C9EC/43CC96 vectors; not a claim of original Windows runtime execution."""
from pathlib import Path
import json,sys
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from extract import txt
from prepare_m5 import native_segments

def main():
    records=txt.load(ROOT.parent/'dlz/ANTI-JAP/TXT.DAT');by_n={r.number:r for r in records}
    expected={4:[-1,-1],8:[33,0],251:[40,0,41],474:[72,67],521:[-1,98,-1,99,98,99,98,99]}
    assert len(records)==478 and sum(len(r.text) for r in records)==54997
    assert sum(len(native_segments(r.native_stream)) for r in records)==1753
    generated={r['n']:r for r in json.loads((ROOT/'godot/data/m5.json').read_text())['records']}
    for n,codes in expected.items():assert [c for c,_ in native_segments(by_n[n].native_stream)]==codes,(n,codes)
    assert '殉国' in native_segments(by_n[4].native_stream)[0][1]
    assert all('\r' not in r.native_stream and '\n' not in r.native_stream for r in records)
    for r in records:
        expected_segments=native_segments(r.native_stream)
        actual=[(l['code'],l['text']) for l in generated[r.number]['lines']]
        assert expected_segments==actual,r.number
    fixture=txt.parse('000 xx\r\n001 -1甲\r\n   乙-1丙xx\n002 xx')[0]
    assert fixture.native_stream=='-1甲乙-1丙'
    assert native_segments('00甲01乙-1丙')==[(0,'甲'),(1,'乙'),(-1,'丙')]
    assert native_segments('ab甲b0乙')==[(-1,'甲'),(-1,'乙')]
    assert native_segments('-1甲\0-1乙')==[(-1,'甲')]
    assert native_segments('00G101乙')==[(0,'G1'),(1,'乙')]
    assert len(native_segments(by_n[474].native_stream))==2 # intra-line code, not newline
    print('STORY_STREAM_CONTRACT PASS records=478 original-byte vectors=5')
    return 0
if __name__=='__main__':raise SystemExit(main())
