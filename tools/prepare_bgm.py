"""Read-only NRG DAOX/CUEX CD-DA split; native 16 complete tracks.
The retained TOCs independently agree on every 2352-byte boundary. No guessed
5.8-second cut, data-track PCM, leadout bytes or invented loop points.
"""
from __future__ import annotations
import argparse,json,shutil,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent
NRG=ROOT.parent/'dlz/ANTI-JAP/ISO/抗日地雷战音效光盘.nrg'
OUT=ROOT/'godot/assets/audio'
TOC=ROOT/'extract/research_bgm_tracks_20261025.json'

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--force',action='store_true');args=parser.parse_args()
    ffmpeg=shutil.which('ffmpeg')
    if not ffmpeg or not NRG.exists():raise SystemExit('missing ffmpeg/NRG')
    toc=json.loads(TOC.read_text());OUT.mkdir(parents=True,exist_ok=True)
    for track in toc['tracks']:
        if track['sector_bytes']!=2352:continue
        dst=OUT/f"bgm_track_{track['track']:02d}.ogg"
        if dst.exists() and not args.force:continue
        cmd=[ffmpeg,'-hide_banner','-loglevel','error','-y','-f','s16be','-ar','44100','-ac','2','-i','pipe:0','-c:a','libvorbis','-q:a','3',str(dst)]
        proc=subprocess.Popen(cmd,stdin=subprocess.PIPE)
        with NRG.open('rb') as src:
            src.seek(track['index1_offset']);left=track['byte_length']
            while left:
                chunk=src.read(min(left,4*1024*1024))
                if not chunk:raise RuntimeError('short NRG')
                proc.stdin.write(chunk);left-=len(chunk)
        proc.stdin.close()
        if proc.wait()!=0:raise RuntimeError(f'ffmpeg failed {dst}')
        print(dst.name,track['duration_seconds'],flush=True)
    shutil.copyfile(OUT/'bgm_track_14.ogg',OUT/'bgm_title.ogg')
if __name__=='__main__':main()
