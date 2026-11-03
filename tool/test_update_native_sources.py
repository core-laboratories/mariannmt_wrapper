"""Check that failed upstream refreshes cannot replace pinned native sources."""
import hashlib
import io
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent


@unittest.skipUnless(shutil.which('bash'), 'Requires bash')
class UpdateTests(unittest.TestCase):
	def setUp(self):
		self.temporary = tempfile.TemporaryDirectory(prefix='marian-update-test-')
		self.addCleanup(self.temporary.cleanup)
		self.root = Path(self.temporary.name)
		(self.root / 'tool').mkdir()
		shutil.copy2(ROOT / 'tool/update_native_sources.sh', self.root / 'tool')
		(self.root / 'third_party/patches').mkdir(parents=True)
		(self.root / 'third_party/patches/00-bergamot-translator.patch').write_text('fixture patch')
		for folder in ('bergamot-translator', 'cld2'):
			path = self.root / 'third_party' / folder
			path.mkdir()
			(path / 'old-source').write_text('keep on failure')
		self.archive = self.root / 'fixture.tar.gz'
		with tarfile.open(self.archive, 'w:gz') as archive:
			data = b'fixture configure'
			info = tarfile.TarInfo('pcre2-10.39/configure')
			info.size = len(data)
			archive.addfile(info, io.BytesIO(data))
		self.sources_config = (
			'ENGINE_REPOSITORY=https://github.com/browsermt/bergamot-translator.git\n'
			f'ENGINE_REVISION={"a" * 40}\n'
			'CLD2_REPOSITORY=https://github.com/CLD2Owners/cld2.git\n'
			f'CLD2_REVISION={"a" * 40}\n'
			'PCRE2_ARCHIVE_URL=https://example.invalid/pcre2.tar.gz\n'
			f'PCRE2_ARCHIVE_SHA256={hashlib.sha256(self.archive.read_bytes()).hexdigest()}\n'
		)
		(self.root / 'tool/native_sources.conf').write_text(self.sources_config)
		bin_dir = self.root / 'bin'
		bin_dir.mkdir()
		git = bin_dir / 'git'
		git.write_text('''#!/usr/bin/env python3
import os,sys
from pathlib import Path
args=sys.argv[1:]
if args[0]=='ls-remote':
 rev=os.environ.get('TEST_UPSTREAM_REV', 'b'*40) if 'bergamot' in args[1] else 'c'*40
 print(rev+'\\tHEAD')
elif args[0]=='clone':
 dest=Path(args[-1]);dest.mkdir(parents=True)
 (dest/'.git').mkdir()
 (dest/'new-source').write_text('new source')
 (dest/'dependency.lock').write_text('unused dependency lock')
 (dest/'package-lock.json').write_text('{}')
 if 'bergamot' in args[-1]:
  config=dest/'3rd_party/ssplit-cpp/cmake/FindPCRE2.cmake'
  config.parent.mkdir(parents=True)
  config.write_text('set(PCRE2_VERSION "10.39")\\n')
 else:
  (dest/'internal').mkdir()
elif 'apply' in args and os.environ.get('TEST_FAIL_PATCH'):
 sys.exit(1)
''')
		git.chmod(0o755)
		curl = bin_dir / 'curl'
		curl.write_text('''#!/usr/bin/env python3
import os,sys
from pathlib import Path
source=Path(os.environ['TEST_ARCHIVE']).read_bytes()
if os.environ.get('TEST_BAD_ARCHIVE'): source=b'wrong checksum'
Path(sys.argv[sys.argv.index('-o')+1]).write_bytes(source)
''')
		curl.chmod(0o755)
		self.env = dict(os.environ, PATH=str(bin_dir) + os.pathsep + os.environ['PATH'], TEST_ARCHIVE=str(self.archive))

	def run_update(self, *arguments, **environment):
		return subprocess.run(['bash', str(self.root / 'tool/update_native_sources.sh'), *arguments], env=dict(self.env, **environment), capture_output=True, text=True)

	def assert_unchanged(self):
		self.assertEqual((self.root / 'tool/native_sources.conf').read_text(), self.sources_config)
		for folder in ('bergamot-translator', 'cld2'):
			self.assertTrue((self.root / 'third_party' / folder / 'old-source').is_file())

	def test_current_check_does_not_mutate_sources(self):
		self.assertEqual(self.run_update('--check', TEST_UPSTREAM_REV='a' * 40).returncode, 0)
		self.assert_unchanged()

	def test_outdated_check_returns_two_without_mutation(self):
		self.assertEqual(self.run_update('--check').returncode, 2)
		self.assert_unchanged()

	def test_failed_head_lookup_does_not_mutate_sources(self):
		self.assertNotEqual(self.run_update('--latest', TEST_UPSTREAM_REV='').returncode, 0)
		self.assert_unchanged()

	def test_patch_conflict_preserves_sources_and_config(self):
		self.assertNotEqual(self.run_update('--latest', TEST_FAIL_PATCH='1').returncode, 0)
		self.assert_unchanged()

	def test_bad_archive_preserves_sources_and_config(self):
		result = self.run_update('--latest', TEST_BAD_ARCHIVE='1')
		self.assertNotEqual(result.returncode, 0)
		self.assertIn('checksum mismatch', result.stderr)
		self.assert_unchanged()

	def test_success_updates_pins_and_vendors_pcre_without_git_metadata(self):
		result = self.run_update('--latest')
		self.assertEqual(result.returncode, 0, result.stderr)
		self.assertIn('ENGINE_REVISION=' + 'b' * 40, (self.root / 'tool/native_sources.conf').read_text())
		self.assertIn('CLD2_REVISION=' + 'c' * 40, (self.root / 'tool/native_sources.conf').read_text())
		engine = self.root / 'third_party/bergamot-translator'
		self.assertTrue((engine / 'new-source').is_file())
		self.assertTrue((engine / '3rd_party/ssplit-cpp/src/3rd-party/pcre2-10.39/configure').is_file())
		self.assertFalse((engine / '.git').exists())
		self.assertFalse((engine / 'dependency.lock').exists())
		self.assertFalse((engine / 'package-lock.json').exists())
		self.assertFalse((engine / 'old-source').exists())


if __name__ == '__main__':
	unittest.main(verbosity=2)
