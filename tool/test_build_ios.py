"""Regression checks for CocoaPods' multi-architecture native build."""
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('build_ios', Path(__file__).with_name('build_ios.py'))
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


class ArchitectureTests(unittest.TestCase):
	def test_supported_architectures_preserve_order_and_remove_duplicates(self):
		self.assertEqual(builder.architectures('arm64 x86_64 arm64', 'iphonesimulator'), ['arm64', 'x86_64'])
		self.assertEqual(builder.architectures('arm64', 'iphoneos'), ['arm64'])

	def test_invalid_architectures_fail_before_building(self):
		for archs, platform in [('', 'iphonesimulator'), ('armv7', 'iphoneos'), ('x86_64', 'iphoneos')]:
			with self.assertRaises(ValueError):
				builder.architectures(archs, platform)

	@unittest.skipUnless(sys.platform == 'darwin' and shutil.which('cmake'), 'Requires Xcode and CMake')
	def test_real_universal_simulator_archive_and_separate_device_archive(self):
		with tempfile.TemporaryDirectory(prefix='marian-ios-test-') as temporary:
			root = Path(temporary)
			source = root / 'source with spaces'
			(source / 'src').mkdir(parents=True)
			(source / 'src' / 'CMakeLists.txt').write_text('''cmake_minimum_required(VERSION 3.10)
project(ios_archive_fixture LANGUAGES CXX)
add_library(engine STATIC engine.cpp)
add_library(mariannmt_wrapper STATIC wrapper.cpp)
target_link_libraries(mariannmt_wrapper PRIVATE engine)
''')
			(source / 'src' / 'engine.cpp').write_text('extern "C" int translation_engine() { return 42; }')
			(source / 'src' / 'wrapper.cpp').write_text('extern "C" int translation_engine();\nextern "C" int wrapper() { return translation_engine(); }')
			for platform, archs in [('iphonesimulator', 'arm64 x86_64'), ('iphoneos', 'arm64')]:
				environment = dict(os.environ, CONFIGURATION='Debug', PLATFORM_NAME=platform, ARCHS=archs,
					SDKROOT=subprocess.check_output(['xcrun', '--sdk', platform, '--show-sdk-path'], text=True).strip(),
					IPHONEOS_DEPLOYMENT_TARGET='15.6')
				builder.build(source, root / 'build with spaces', environment)
				archive = root / 'build with spaces' / f'Debug-{platform}-{archs}' / 'libmariannmt_dependencies.a'
				for arch in archs.split():
					subprocess.run(['xcrun', 'lipo', str(archive), '-verify_arch', arch], check=True)
					symbols = subprocess.check_output(['xcrun', 'nm', '-arch', arch, '-gU', str(archive)], text=True)
					self.assertIn('_translation_engine', symbols)
					self.assertNotIn(' T _wrapper', symbols)


if __name__ == '__main__':
	unittest.main()
