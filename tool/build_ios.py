#!/usr/bin/env python3
"""Build every requested iOS architecture, then publish one universal archive."""
import argparse
import os
from pathlib import Path
import subprocess


def architectures(value, platform):
	result = list(dict.fromkeys(value.split()))
	if platform not in {'iphoneos', 'iphonesimulator'}:
		raise ValueError(f'Unsupported iOS platform: {platform!r}')
	allowed = {'arm64', 'x86_64'} if platform == 'iphonesimulator' else {'arm64'}
	if not result or not set(result) <= allowed:
		raise ValueError(f'Unsupported {platform} architectures: {value!r}')
	return result


def run(*args):
	subprocess.run([str(arg) for arg in args], check=True)


def build(source, root, environment):
	configuration = environment['CONFIGURATION']
	platform = environment['PLATFORM_NAME']
	archs = architectures(environment['ARCHS'], platform)
	output = root / f'{configuration}-{platform}-{environment["ARCHS"]}'
	output.mkdir(parents=True, exist_ok=True)
	bundles = []
	for arch in archs:
		thin = root / 'thin' / f'{configuration}-{platform}-{arch}'
		run('cmake', '-S', source / 'src', '-B', thin,
			'-DIOS=ON',
			f'-DCMAKE_BUILD_TYPE={"Debug" if configuration == "Debug" else "Release"}',
			'-DCMAKE_SYSTEM_NAME=iOS', f'-DCMAKE_SYSTEM_PROCESSOR={arch}',
			f'-DCMAKE_OSX_SYSROOT={environment["SDKROOT"]}',
			f'-DCMAKE_OSX_ARCHITECTURES={arch}',
			f'-DCMAKE_OSX_DEPLOYMENT_TARGET={environment["IPHONEOS_DEPLOYMENT_TARGET"]}')
		run('cmake', '--build', thin, '--target', 'mariannmt_wrapper', '-j',
			environment.get('CMAKE_BUILD_PARALLEL_LEVEL', '8'))
		# The C wrapper is compiled by CocoaPods' ObjC++ forwarder. Bundle its
		# static dependencies, including architecture-specific transitive ones.
		archives = sorted(path for path in thin.rglob('*.a')
			if path.name not in {'libmariannmt_wrapper.a', 'libmariannmt_dependencies.a'})
		if not archives:
			raise RuntimeError(f'No native dependencies built for {arch}')
		for archive in archives:
			run('xcrun', 'lipo', archive, '-verify_arch', arch)
		bundle = thin / 'libmariannmt_dependencies.a'
		run('xcrun', 'libtool', '-static', '-o', bundle, *archives)
		bundles.append(bundle)
	# Publish only after all slices succeed; do not expose a partial build.
	temporary = output / 'libmariannmt_dependencies.pending.a'
	run('xcrun', 'lipo', '-create', *bundles, '-output', temporary)
	for arch in archs:
		run('xcrun', 'lipo', temporary, '-verify_arch', arch)
	temporary.replace(output / 'libmariannmt_dependencies.a')


if __name__ == '__main__':
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('--source-root', type=Path, required=True)
	parser.add_argument('--build-root', type=Path, required=True)
	args = parser.parse_args()
	build(args.source_root.resolve(), args.build_root.resolve(), os.environ)
