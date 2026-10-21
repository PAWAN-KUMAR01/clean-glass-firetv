#!/usr/bin/env python3
"""Reads a `logcat -v time` dump and prints how long Glass took to appear after each MARK line."""
import re, sys

LINE = re.compile(r'^\d\d-\d\d (\d\d):(\d\d):(\d\d)\.(\d+)\s+\w/(\S+?)\s*\(\s*\d+\):\s*(.*)$')
AMAZON = 'com.amazon.tv.launcher/.ui.HomeActivity_vNext'
GLASS = 'com.ivantrj.glasslauncher'

def parse(path):
    rows = []
    for raw in open(path, errors='replace'):
        m = LINE.match(raw.rstrip('\n'))
        if m:
            h, mi, s, ms, tag, msg = m.groups()
            rows.append((int(h) * 3600 + int(mi) * 60 + int(s) + int(ms) / 1000.0, tag, msg))
    return rows

def main(path):
    rows = parse(path)
    marks = [i for i, r in enumerate(rows) if r[1] == 'GlassGap' and r[2].startswith('MARK')]
    if not marks:
        # No marker (logcat -c can race the marker): measure from the first Amazon home appearance instead
        hits = [i for i, r in enumerate(rows) if r[1] == 'am_resume_activity' and AMAZON in r[2]]
        first = hits[-1] if hits else None  # the most recent Home press
        if first is None:
            print('Nothing to measure: Amazon home never came up in this log.')
            return
        rows.insert(first, (rows[first][0], 'GlassGap', 'MARK latest Home press (no marker, timed from Amazon home)'))
        marks = [first]
    for n, start in enumerate(marks):
        end = marks[n + 1] if n + 1 < len(marks) else len(rows)
        block = rows[start:end]
        t0 = block[0][0]
        amazon = next((t for t, tag, msg in block if tag == 'am_resume_activity' and AMAZON in msg), None)
        glass = next((t for t, tag, msg in block
                      if tag == 'am_resume_activity' and GLASS in msg and (amazon is None or t >= amazon)), None)
        print('--- %s' % block[0][2])
        if amazon is None:
            print('  Amazon home never came to the front (nothing to measure).')
        else:
            print('  Home press -> Amazon home resumed : %.2f s' % (amazon - t0))
        if glass is None:
            print('  Glass never came back to the front within the test window.')
        elif amazon is not None:
            gap = glass - amazon
            verdict = 'FAST' if gap < 1.5 else 'SLOW (the 5 second hold)' if gap > 3.5 else 'in between'
            print('  Amazon home -> Glass in front      : %.2f s   [%s]' % (gap, verdict))
        for t, tag, msg in block:
            if tag == 'GlassGap' and not msg.startswith('MARK') and not msg.startswith('key '):
                print('    +%.2fs  %s' % (t - t0, msg))

if __name__ == '__main__':
    main(sys.argv[1])
