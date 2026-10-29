#!/usr/bin/env python3
# Pearl 充电控制守护：
#   1) 80% 充电上限（capacity >= 80 停充，<= 75 恢复，中间为回差区）
#   2) 旁路供电（插电停充、系统由 VBUS 供电），由 pearl-bypass 开关，状态存 JSON
#
# sysfs 契约（pearl 新内核提供）：
#   /sys/class/power_supply/mtk-master-charger/charge_behaviour
#   可写：auto | inhibit-charge
#   读回："[auto] inhibit-charge" 或 "auto [inhibit-charge]"（方括号是当前值）
# 属性不存在时只记一条日志，之后每 30 秒重试，不退出。
#
# 以 root 运行：需要写 power_supply 的 sysfs 属性。
import json, os, select, signal, sys

PSY = os.environ.get('PEARL_PSY_DIR', '/sys/class/power_supply')
CHARGER = os.environ.get('PEARL_CHARGER', 'mtk-master-charger')
BATTERY = os.environ.get('PEARL_BATTERY', 'bq28z610-0')
STATE = os.environ.get('PEARL_STATE_FILE', '/var/lib/pearl-charge/state.json')

BEHAVIOUR = os.path.join(PSY, CHARGER, 'charge_behaviour')
ONLINE = os.path.join(PSY, CHARGER, 'online')
CAPACITY = os.path.join(PSY, BATTERY, 'capacity')
STATUS = os.path.join(PSY, BATTERY, 'status')

AUTO = 'auto'
INHIBIT = 'inhibit-charge'
LIMIT = int(os.environ.get('PEARL_LIMIT_PERCENT', '80'))
RESUME = int(os.environ.get('PEARL_RESUME_PERCENT', '75'))
POLL = float(os.environ.get('PEARL_POLL_SECONDS', '5'))
RETRY = float(os.environ.get('PEARL_RETRY_SECONDS', '30'))
RETRY_HEARTBEAT = 20


def log(msg):
    print('pearl-charge-limit: %s' % (msg,), flush=True)


def read(path):
    try:
        with open(path, encoding='utf-8', errors='replace') as fh:
            return fh.read().strip()
    except OSError:
        return None


def read_behaviour():
    """charge_behaviour 的当前值；属性缺失返回 None。"""
    raw = read(BEHAVIOUR)
    if raw is None:
        return None
    for tok in raw.split():
        if len(tok) > 2 and tok.startswith('[') and tok.endswith(']'):
            return tok[1:-1]
    toks = raw.split()
    return toks[0] if toks else ''


def load_bypass():
    try:
        with open(STATE, encoding='utf-8') as fh:
            return bool(json.load(fh).get('bypass', False))
    except (OSError, ValueError):
        return False


def write_behaviour(value):
    try:
        with open(BEHAVIOUR, 'w', encoding='utf-8') as fh:
            fh.write(value + '\n')
        return True
    except OSError as exc:
        log('写 charge_behaviour=%s 失败: %r' % (value, exc))
        return False


def decide(capacity, status, online, bypass, behaviour):
    """返回 (目标值或 None, 原因)。旁路优先于 80% 上限。"""
    if bypass:
        if online == '0':
            return None, '旁路供电开启，但 USB 未连接 -> 不动作'
        return INHIBIT, '旁路供电开启，USB 已连接 -> 停充，由 VBUS 供电'
    if capacity is None:
        return None, '读不到电量 -> 不动作'
    plug = online == '1' or status in ('Charging', 'Full')
    if capacity >= LIMIT:
        if behaviour in (AUTO, ''):
            if not plug:
                return None, '电量 %d%% >= %d%%，但未插电 -> 不动作' % (capacity, LIMIT)
            return INHIBIT, '电量 %d%% >= %d%% 且正在充电 -> 停充' % (capacity, LIMIT)
        return None, '电量 %d%% >= %d%%，当前已是 %s -> 保持' % (capacity, LIMIT, behaviour)
    if capacity <= RESUME:
        if behaviour == INHIBIT:
            return AUTO, '电量 %d%% <= %d%% 且已停充 -> 恢复充电' % (capacity, RESUME)
        return None, '电量 %d%% <= %d%%，当前已是 %s -> 保持' % (capacity, RESUME, behaviour)
    return None, '电量 %d%% 落在回差区 (%d, %d) -> 保持 %s' % (capacity, RESUME, LIMIT, behaviour)


def tick(fh_state):
    """执行一次决策。返回 'ok' / 'missing'。"""
    behaviour = read_behaviour()
    if behaviour is None:
        return 'missing'
    raw_cap = read(CAPACITY)
    capacity = int(raw_cap) if raw_cap is not None and raw_cap.isdigit() else None
    status = read(STATUS) or '?'
    online = read(ONLINE)
    bypass = load_bypass()

    if behaviour == '':
        line = 'cap=%s status=%s online=%s behaviour=<空> bypass=%s | 无动作 | charge_behaviour 内容为空' % (
            capacity, status, online, bypass)
    else:
        target, reason = decide(capacity, status, online, bypass, behaviour)
        head = 'cap=%s status=%s online=%s behaviour=%s bypass=%s' % (
            capacity, status, online, behaviour, 'on' if bypass else 'off')
        if target is None:
            line = '%s | 无动作 | %s' % (head, reason)
        elif target == behaviour:
            line = '%s | 保持 %s | %s' % (head, behaviour, reason)
        else:
            if write_behaviour(target):
                line = '%s | 写入 %s -> %s | %s' % (head, behaviour, target, reason)
                fh_state['last'] = line
                log(line)
                return 'ok'
            line = '%s | 写入 %s 失败 | %s' % (head, target, reason)
            log(line)  # 失败每次都记，便于发现
            fh_state['last'] = None
            return 'ok'
    if line != fh_state['last']:
        fh_state['last'] = line
        log(line)
    return 'ok'


def wait_for_event(fd, timeout):
    """睡 timeout 秒；期间收到 SIGHUP 则提前返回 True。"""
    try:
        ready, _, _ = select.select([fd], [], [], timeout)
    except InterruptedError:
        return False
    if not ready:
        return False
    try:
        while os.read(fd, 4096):
            pass
    except OSError:
        pass
    return True


def main():
    once = '--once' in sys.argv[1:]
    wake_r, wake_w = os.pipe()
    os.set_blocking(wake_r, False)
    os.set_blocking(wake_w, False)
    signal.set_wakeup_fd(wake_w)
    signal.signal(signal.SIGHUP, lambda *_a: None)  # 只用于唤醒；pearl-bypass 改状态后发 HUP

    log('启动: 上限=%d%% 恢复=%d%% 轮询=%.0fs 属性=%s 状态=%s' % (
        LIMIT, RESUME, POLL, BEHAVIOUR, STATE))

    fh_state = {'last': None}
    missing_logged = False
    retries = 0
    while True:
        result = tick(fh_state)
        if result == 'missing':
            retries += 1
            if not missing_logged:
                log('%s 不存在，等待新内核；每 %.0f 秒重试' % (BEHAVIOUR, RETRY))
                missing_logged = True
            elif retries % RETRY_HEARTBEAT == 0:
                log('仍在等待 charge_behaviour（已重试 %d 次，约 %.0f 分钟）' % (
                    retries, retries * RETRY / 60.0))
            if once:
                return 0
            if wait_for_event(wake_r, RETRY):
                log('收到 SIGHUP，立即重试（旁路状态已重读）')
            continue
        if missing_logged:
            log('%s 已出现，开始按 %d%% 上限 / 旁路逻辑工作' % (BEHAVIOUR, LIMIT))
            missing_logged = False
            retries = 0
            fh_state['last'] = None
        if once:
            return 0
        if wait_for_event(wake_r, POLL):
            log('收到 SIGHUP，重新读取旁路状态')
            fh_state['last'] = None


if __name__ == '__main__':
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(0)
