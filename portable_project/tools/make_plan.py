"""Build the fixed-size, XOR-protected PLAN.BIN used by the FPGA."""
from pathlib import Path
import argparse
import json

AUDIOS = {'ALARM.PCM': 0, 'FIRE.PCM': 1, 'QUAKE.PCM': 2, 'FLOOD.PCM': 3}
SCENES = {'campus': 0, 'drill': 1, 'mall': 2}


def packed(values, width):
    result = 0
    for index, value in enumerate(values):
        result |= value << (index * width)
    return result


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('config', nargs='?', type=Path,
                        default=root / 'config/plan_template.json')
    parser.add_argument('-o', '--output', type=Path,
                        default=root / 'TF_CARD_ROOT/PLAN.BIN')
    args = parser.parse_args()
    cfg = json.loads(args.config.read_text(encoding='utf-8'))
    normal = int(cfg['normal_dwell_seconds'])
    emergency = int(cfg['emergency_dwell_seconds'])
    volume = int(cfg['default_volume'])
    scene = SCENES[cfg['default_scene']]
    events = cfg['events']
    if not 3 <= normal <= 30:
        raise ValueError('normal_dwell_seconds must be 3..30')
    if not 2 <= emergency <= 15:
        raise ValueError('emergency_dwell_seconds must be 2..15')
    if not 0 <= volume <= 4:
        raise ValueError('default_volume must be 0..4 (0 loudest, 4 mute)')
    if len(events) != 4:
        raise ValueError('exactly four event entries are required')
    priorities = [int(item['priority']) for item in events]
    if any(value < 0 or value > 3 for value in priorities):
        raise ValueError('event priority must be 0..3')
    audio = [AUDIOS[item['audio'].upper()] for item in events]

    data = bytearray(24)
    data[0:4] = b'EPLN'
    data[4:12] = bytes((1, 1, normal, emergency, volume, scene,
                        packed(priorities, 2), packed(audio, 2)))
    # Bytes 12..22 are reserved and must be zero. Event/image correspondence
    # stays fixed so a configurable plan cannot display a wrong hazard card.
    data[23] = 0
    for value in data[:23]:
        data[23] ^= value
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(data)
    print(f'{args.output}: 24 bytes, XOR8=0x{data[23]:02x}')


if __name__ == '__main__':
    main()
