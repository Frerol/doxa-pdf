#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later

"""Measure Linux OCR, write a PDF copy, and verify its rendered pixels."""

import argparse
import filecmp
import os
from pathlib import Path
import shutil
import statistics
import subprocess
import tempfile
import time


def measured(command, output=None, env=None):
    start = time.perf_counter()
    with subprocess.Popen(command, stdout=output, env=env) as child:
        _, status, usage = os.wait4(child.pid, 0)
        child.returncode = os.waitstatus_to_exitcode(status)
        if child.returncode:
            raise subprocess.CalledProcessError(child.returncode, command)
    return (time.perf_counter() - start) * 1000, usage.ru_maxrss / 1024


def rasterize(pdf, page, prefix):
    return measured([
        'pdftoppm', '-f', str(page), '-l', str(page), '-singlefile',
        '-cropbox', '-gray', '-r', '300', pdf, prefix,
    ])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('pdf', type=Path)
    parser.add_argument('pages', nargs='+', type=int)
    parser.add_argument('--repeats', type=int, default=3)
    args = parser.parse_args()
    if (min(args.pages) < 1 or args.repeats < 1
            or len(set(args.pages)) != len(args.pages)):
        parser.error('Provide unique positive page numbers and repeats')

    args.pdf = args.pdf.resolve()
    os.chdir(Path(__file__).resolve().parent)
    out = Path('out')
    run = Path(tempfile.mkdtemp(
        prefix=args.pdf.stem + '-' + '-'.join(map(str, args.pages)) + '-',
        dir=out,
    ))
    print(f'Output directory {run}', flush=True)
    text_args = []
    env = dict(os.environ, OMP_THREAD_LIMIT='1')
    for page in args.pages:
        prefix = run / f'page-{page}'
        raster_ms, raster_rss = rasterize(args.pdf, page, prefix)
        image = prefix.with_suffix('.pgm')
        with image.open('rb') as source:
            if source.readline().strip() != b'P5':
                raise ValueError(f'Expected a grayscale PGM: {image}')
            width, height = source.readline().decode('ascii').split()

        tsv = prefix.with_suffix('.tsv')
        samples = []
        for _ in range(args.repeats):
            with tsv.open('wb') as output:
                samples.append(measured([
                    'tesseract', image, 'stdout', '--tessdata-dir',
                    out / 'tessdata', '-l', 'por+eng', '--dpi', '300',
                    '--oem', '1', '--psm', '3', '-c', 'tessedit_create_tsv=1',
                ], output=output, env=env))
        times, peaks = zip(*samples)
        print(
            f'Page {page} ({width}×{height}) raster {raster_ms:.1f} ms '
            f'({raster_rss:.1f} MiB peak RSS), OCR median '
            f'{statistics.median(times):.1f} ms (range {min(times):.1f}–'
            f'{max(times):.1f}), max peak RSS {max(peaks):.1f} MiB',
            flush=True,
        )
        text_args.extend([str(page), width, height, tsv])

    output = run / 'searchable.pdf'
    _, writer_rss = measured([
        'dart', 'bin/text_layer.dart', args.pdf, output, *text_args,
    ])
    print(f'Dart writer and verification peak RSS {writer_rss:.1f} MiB', flush=True)
    if shutil.which('qpdf'):
        subprocess.run(['qpdf', '--check', output], check=True)
    else:
        print('qpdf unavailable', flush=True)

    for page in args.pages:
        prefix = run / f'verified-{page}'
        rasterize(output, page, prefix)
        if not filecmp.cmp(run / f'page-{page}.pgm', prefix.with_suffix('.pgm'),
                           shallow=False):
            raise ValueError(f'Rendered pixels changed on page {page}')
    print('Rendered pixels identical on all processed pages', flush=True)


if __name__ == '__main__':
    main()
