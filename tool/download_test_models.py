#!/usr/bin/env python3
"""Download checksum-pinned Mozilla models for native compatibility tests."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import gzip
import hashlib
import json
from pathlib import Path
import urllib.request


def download(entry, directory):
	output = directory / entry['file']
	if output.is_file() and hashlib.sha256(output.read_bytes()).hexdigest() == entry['sha256']:
		return
	compressed = urllib.request.urlopen(entry['url'], timeout=180).read()
	data = gzip.decompress(compressed)
	if hashlib.sha256(data).hexdigest() != entry['sha256']:
		raise RuntimeError(f"Model checksum mismatch: {entry['file']}")
	output.write_bytes(data)
	print(f'Verified {output.name}', flush=True)


if __name__ == '__main__':
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('directory', type=Path)
	args = parser.parse_args()
	args.directory.mkdir(parents=True, exist_ok=True)
	manifest = json.loads(Path(__file__).with_name('test_models.json').read_text())
	with ThreadPoolExecutor(max_workers=4) as pool:
		list(pool.map(lambda entry: download(entry, args.directory), manifest['files']))
