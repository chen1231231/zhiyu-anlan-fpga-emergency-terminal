"""Rebuild a packaged standalone source tree with the release route settings."""
from pathlib import Path
import argparse, re, shutil, subprocess, xml.etree.ElementTree as ET
import hashlib, json
from datetime import datetime

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--td',type=Path,default=Path('D:/ANLUTD'))
    parser.add_argument('--dry-run',action='store_true',help='prepare build directories without running TD')
    parser.add_argument('--seed',type=int,default=3,help='TD placement seed used by the V2 release')
    args=parser.parse_args()
    root=Path(__file__).resolve().parents[1]
    project=root/'project/emergency_terminal.al'
    tree=ET.fromstring(project.read_text(encoding='utf-8').replace('&','&amp;'))
    for node in tree.findall('./Source_Files/*/File'):
        path=(project.parent/node.get('Path')).resolve()
        if not path.is_file():raise FileNotFoundError(path)
        node.set('Path',path.as_posix())
    tree.attrib.pop('Path',None)
    for tag in ('Runs','Project_Settings'):
        node=tree.find(tag)
        if node is not None:tree.remove(node)
    ET.indent(tree,space='    ')
    xml=b'<?xml version="1.0" encoding="UTF-8"?>\n'+ET.tostring(tree,encoding='utf-8',short_empty_elements=False).replace(b'&amp;',b'&')
    template=(args.td/'doc/scripts/DefaultFlow.tcl').as_posix()
    common=(f'set ADCList {{"{(root/"constraints/terminal.adc").as_posix()}"}}\n'
            f'set SDCList {{"{(root/"constraints/terminal.sdc").as_posix()}"}}\n'
            'set area_option -packarea\nset device_name eagle_s20.db\nset package_name EG4S20BG256\n'
            'set prj_name {emergency_terminal}\nset top_model_name {emergency_terminal_top}\n')
    modes={'syn_1':'set run_type syn\nset start_step read_design\nset end_step opt_gate\nset synWildParams {gate pack_effort medium}\n',
           'phy_1':('set run_type phy\nset start_step opt_place\nset end_step bitgen\nset parent ../syn_1\nset arr_filter false\nset drHoldFix on\n'
                    f'set phyWildParams {{place seed {args.seed} place effort high place hfn_opt_effort high place opt_timing high route effort high}}\n')}
    # TD can return exit code zero after HDL errors. Empty run directories
    # prevent an older database/bitstream from passing an existence check.
    if not args.dry_run:
        archive=root/'build'/('previous_'+datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
        for name in modes:
            old=root/'build'/name
            if old.exists():
                archive.mkdir(parents=True,exist_ok=True)
                shutil.move(str(old),str(archive/name))
        (root/'build/build_verified.json').unlink(missing_ok=True)
    inputs={str(p):hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(set(root.glob('src/*')) |
                {Path(n.get('Path')) for n in tree.findall('./Source_Files/*/File')}) if p.is_file()}
    for name,mode in modes.items():
        run=root/'build'/name;run.mkdir(parents=True,exist_ok=True)
        (run/'emergency_terminal.prj').write_bytes(xml)
        (run/'settings.cfg').write_text(common+mode,encoding='utf-8')
        for rel in ('src/sdram/enc_file/global_def.v','enc_file/global_def.v'):
            dest=run/rel;dest.parent.mkdir(parents=True,exist_ok=True)
            shutil.copy2(project.parent/rel,dest)
        flow=f'source {{{template}}}\n'
        if name=='phy_1':
            flow+=('fix_hold\nupdate_timing -mode final\n'
                   'report_timing_status -file emergency_terminal_phy.ts\n'
                   'report_timing_summary -file final_timing.rpt\n'
                   'report_area -io_info -file final_area.rpt\n'
                   'flow_status -file route_flow.status\n'
                   'export_db emergency_terminal_pr.db\n'
                   'bitgen -bit emergency_terminal.bit\n')
        script=run/'release_flow.tcl';script.write_text(flow,encoding='utf-8')
        print('Prepared',run,flush=True)
        if not args.dry_run:
            # Closing stdin lets TD terminate after the script instead of
            # waiting indefinitely at its interactive prompt under a PTY.
            subprocess.run([str(args.td/'bin/td_commands_prompt.exe'),script.as_posix()],cwd=run,check=True,stdin=subprocess.DEVNULL)
            logs=list(run.glob('td_*.log'))
            if not logs:raise RuntimeError('TD did not produce a log: '+str(run))
            log=max(logs,key=lambda p:p.stat().st_mtime).read_text(errors='replace')
            if re.search(r'\bERROR\b|\bFATAL\b|USR-8159|HDL-7225',log) or list(run.glob('.*.error.f')):
                raise RuntimeError('TD reported an error; inspect '+str(run))
            if name=='syn_1' and not (run/'emergency_terminal_gate.db').exists():
                raise RuntimeError('Synthesis database missing; inspect TD logs.')
    if args.dry_run:return
    phy=root/'build/phy_1'
    timing=(phy/'emergency_terminal_phy.ts').read_text()
    margins=[float(x) for x in re.findall(r'[SH]WNS:\s*([-\d.]+)ns',timing)]
    if len(margins)!=2 or min(margins)<0:raise RuntimeError('Timing did not pass: '+timing)
    bit=phy/'emergency_terminal.bit'
    if not bit.is_file():raise RuntimeError('Bitstream missing; inspect TD logs.')
    for path,digest in inputs.items():
        if hashlib.sha256(Path(path).read_bytes()).hexdigest()!=digest:
            raise RuntimeError('Source changed during build: '+path)
    (root/'build/build_verified.json').write_text(json.dumps({
        'verified_at':datetime.now().isoformat(),'route_seed':args.seed,'inputs':inputs,
        'bit_sha256':hashlib.sha256(bit.read_bytes()).hexdigest()},indent=2),encoding='utf-8')
    print(timing);print('Built',bit)

if __name__=='__main__':main()
