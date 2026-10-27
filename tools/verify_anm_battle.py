"""Source-index audit of all38 battle-only sheets, independent of gallery RGB.

Static resource proof, not original EXE runtime or full media-path acceptance.
"""
from pathlib import Path
import json
import sys
import tempfile
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.prepare_m5_media import (DEFAULT_SRC, parse_anm, anm_frames,
                                   battle_anm_signature, encode_anm_alpha_sheet)


def main():
    palette = np.frombuffer(bytes(v*4 for v in (DEFAULT_SRC/'KUANG04.IMG').read_bytes()[-768:]), dtype=np.uint8).reshape(256,3)
    manifest = json.loads((ROOT/'godot/data/m5_anm.json').read_text())
    by_source = {row['source']:row for row in manifest['files']}
    rows = []
    for source in sorted(DEFAULT_SRC.glob('*.ANM')):
        parsed = parse_anm(source)
        signature = battle_anm_signature(parsed)
        n = signature['battle_frames']
        path = ROOT/'godot/assets/m5/anm'/f'{source.stem.lower()}_sheet.png'
        actual = np.array(Image.open(path).convert('RGBA'))
        shape_ok = actual.shape == (200,320*n,4)
        wrong = 0
        pixels = 0
        all_frames = list(anm_frames(parsed))
        loop_back = all_frames[0][1] == all_frames[-1][1]
        if shape_ok:
            for i, frame in all_frames[:n]:
                indices = np.frombuffer(frame,dtype=np.uint8).reshape(200,320)
                got = actual[:,i*320:(i+1)*320]
                opaque = indices != 0
                mismatch = (np.any(got[:,:,:3] != palette[indices],axis=2) & opaque)
                mismatch |= got[:,:,3] != np.where(opaque,255,0)
                wrong += int(np.sum(mismatch))
                pixels += indices.size
        else:
            wrong = 320*200*n
        meta_ok = (json.loads(path.with_suffix('.json').read_text()) == signature
                   and by_source[source.name]['decode']['sheet_frames'] == n
                   and by_source[source.name]['decode']['battle_sheet'] == signature)
        rows.append(dict(source=source.name,decoded_records=len(all_frames),battle_frames=n,
                         loop_back=loop_back,pixels=pixels,wrong_pixels=wrong,metadata_ok=meta_ok))
    # The export must replace an old file/signature, not require --force.
    with tempfile.TemporaryDirectory() as directory:
        dst=Path(directory)/'sheet.png'
        parsed=parse_anm(DEFAULT_SRC/'FFPACT00.ANM')
        dst.write_bytes(b'stale')
        count=encode_anm_alpha_sheet(parsed,dst)
        generation_ok=(count==30 and Image.open(dst).size==(9600,200)
                       and json.loads(dst.with_suffix('.json').read_text())==battle_anm_signature(parsed))
    ok=(len(rows)==38 and generation_ok and all(r['wrong_pixels']==0 and r['metadata_ok'] and r['loop_back'] for r in rows))
    report=dict(scope='38 static ANM sheets, KUANG04, native N-1 bound; not EXE runtime',
                ok=ok,generation_ok=generation_ok,files=rows)
    (ROOT/'out/anm_battle_audit.json').write_text(json.dumps(report,indent=2)+'\n')
    print('NATIVE_BATTLE_ANM','PASS' if ok else 'FAIL',
          'files=',len(rows),'frames=',sum(r['battle_frames'] for r in rows),
          'pixels=',sum(r['pixels'] for r in rows),'wrong=',sum(r['wrong_pixels'] for r in rows))
    return 0 if ok else 1


if __name__=='__main__':
    raise SystemExit(main())
