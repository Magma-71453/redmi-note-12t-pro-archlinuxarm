#!/usr/bin/env python3
"""修复 mtkclient v6 DA patch 在纯 UFS DA 上的崩溃。

症状:
  File .../xmlflash/extension/v6.py, line ...,
    mmc_get_card_ptr2 = self.archtools.get_next_bl_from_off(mmc_switch_part_offset)
  TypeError: '<' not supported between instances of 'NoneType' and 'int'

原因: 该 DA_BR.bin 是纯 UFS DA，没有 eMMC 的 mmc_switch_part 符号；
mtkclient 把 None 传给 get_next_bl_from_off。这里在符号缺失时回退为 0。
"""
from pathlib import Path
import glob
import sys

repo = Path(__file__).resolve().parents[1]
candidates = sorted(glob.glob(str(repo / 'build' / 'mtk-venv' / 'lib*' / 'python*' / 'site-packages' /
                                 'mtkclient' / 'Library' / 'DA' / 'xmlflash' / 'extension' / 'v6.py')))
if not candidates:
    print(f'v6.py not found under {repo}/build/mtk-venv', file=sys.stderr)
    sys.exit(1)

old_block = '''                # EMMC
                mmc_switch_part_offset = self.archtools.find_function_from_string("mmc_switch_part")
                mmc_get_card_ptr2 = self.archtools.get_next_bl_from_off(mmc_switch_part_offset)
                mmc_get_card = self.archtools.get_bl_target(mmc_get_card_ptr2)

                mmc_set_part_config = self.archtools.find_function_from_string("%sset_part_config fail %x\\n")
                if mmc_set_part_config is not None:
                    mmc_set_part_config = mmc_set_part_config + self.da2address

                mmc_rpmb_offs = self.archtools.find_function_from_string("%sreq/1 fail %d\\n")
                logl = self.archtools.get_next_bl_from_off(mmc_rpmb_offs)
                mmc_rpmb_send_command_ptr2 = self.archtools.get_next_bl_from_off(logl + 0x8)
                mmc_rpmb_send_command = self.archtools.get_bl_target(mmc_rpmb_send_command_ptr2)
                if mmc_rpmb_send_command is None:
                    mmc_rpmb_send_command = 0
'''

new_block = '''                # EMMC (pure-UFS DA may not contain these symbols)
                mmc_switch_part_offset = self.archtools.find_function_from_string("mmc_switch_part")
                if mmc_switch_part_offset is None:
                    mmc_get_card = 0
                else:
                    mmc_get_card_ptr2 = self.archtools.get_next_bl_from_off(mmc_switch_part_offset)
                    mmc_get_card = self.archtools.get_bl_target(mmc_get_card_ptr2)

                mmc_set_part_config = self.archtools.find_function_from_string("%sset_part_config fail %x\\n")
                if mmc_set_part_config is None:
                    mmc_set_part_config = 0
                else:
                    mmc_set_part_config = mmc_set_part_config + self.da2address

                mmc_rpmb_offs = self.archtools.find_function_from_string("%sreq/1 fail %d\\n")
                if mmc_rpmb_offs is None:
                    mmc_rpmb_send_command = 0
                else:
                    logl = self.archtools.get_next_bl_from_off(mmc_rpmb_offs)
                    mmc_rpmb_send_command_ptr2 = self.archtools.get_next_bl_from_off(logl + 0x8)
                    mmc_rpmb_send_command = self.archtools.get_bl_target(mmc_rpmb_send_command_ptr2)
                    if mmc_rpmb_send_command is None:
                        mmc_rpmb_send_command = 0
'''

for path in candidates:
    p = Path(path)
    s = p.read_text()
    if 'pure-UFS DA may not contain these symbols' in s:
        print(f'already patched: {p}')
        continue
    n = s.count(old_block)
    if n == 0:
        print(f'ERROR: expected block not found in {p}', file=sys.stderr)
        sys.exit(2)
    p.write_text(s.replace(old_block, new_block))
    print(f'patched {n} block(s): {p}')
