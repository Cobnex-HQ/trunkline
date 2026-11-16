"""Two local processes via a real helper. Never labels this as an external-phone test."""
import argparse
import json
from pathlib import Path
import subprocess
import time

def events(path):
    result=[]
    if not path.exists(): return result
    for line in path.read_text().splitlines():
        try: result.append(json.loads(line))
        except json.JSONDecodeError: pass
    return result

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--helper',required=True)
    args=parser.parse_args()
    root=Path(__file__).resolve().parent
    private=root/'Private';private.mkdir(mode=0o700,exist_ok=True);private.chmod(0o700)
    run=private/('public-pair-'+str(time.time_ns()));run.mkdir(mode=0o700)
    binary=str(root/'target/debug/trunkline-p2p-probe')
    subprocess.run([binary,'pair',str(run/'pair')],check=True,capture_output=True)
    processes=[]
    try:
        with (run/'mac.jsonl').open('w') as a,(run/'second-process.jsonl').open('w') as b:
            listener=subprocess.Popen([binary,'probe','--config',str(run/'pair/mac.json'),'--helper',args.helper,'--mode','listen','--seconds','100'],stdout=a,stderr=subprocess.STDOUT)
            processes.append(listener)
            ready=False
            for _ in range(120):
                if any(e['event']=='helper_reserved' for e in events(run/'mac.jsonl')):ready=True;break
                if listener.poll() is not None:break
                time.sleep(.25)
            if not ready:raise RuntimeError('Listener did not obtain helper reservation; see '+str(run))
            print('Helper reservation accepted. Testing two Mac processes, not cellular.',flush=True)
            dialer=subprocess.Popen([binary,'probe','--config',str(run/'pair/phone.json'),'--helper',args.helper,'--mode','dial','--seconds','70'],stdout=b,stderr=subprocess.STDOUT)
            processes.append(dialer)
            dialer.wait(timeout=80);listener.wait(timeout=105)
        summary={'scope':'Two processes on the same Mac via a real public helper; NOT cellular',
                 'process_exit_codes':[p.returncode for p in processes],'results':[]}
        for name in ['mac.jsonl','second-process.jsonl']:
            for event in events(run/name):
                if event['event']=='finished':summary['results'].append({'process':name,**event['details']})
        (run/'summary.json').write_text(json.dumps(summary,indent=2))
        print(json.dumps(summary,indent=2),flush=True)
        print('Private run folder: '+str(run),flush=True)
        return 0 if all(code==0 for code in summary['process_exit_codes']) else 2
    finally:
        for process in processes:
            if process.poll() is None:
                process.terminate()
                try:process.wait(timeout=5)
                except subprocess.TimeoutExpired:process.kill();process.wait()

if __name__=='__main__':raise SystemExit(main())
