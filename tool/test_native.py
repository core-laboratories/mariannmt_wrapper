#!/usr/bin/env python3
"""Exercise the compiled FFI library, optionally including real translations."""
import argparse
import ctypes as c
import json
import os
from pathlib import Path
import unittest


class Detection(c.Structure):
	_fields_ = [('language', c.c_char * 8), ('is_reliable', c.c_int), ('confidence', c.c_int)]


class NativeTests(unittest.TestCase):
	@classmethod
	def setUpClass(cls):
		if os.name == 'nt':
			cls.dll_directory = os.add_dll_directory(str(LIBRARY.parent))
		cls.lib = c.CDLL(str(LIBRARY))
		cls.lib.bergamot_initialize_service.restype = c.c_int
		cls.lib.bergamot_detect_language.argtypes = [c.c_char_p, c.c_char_p, c.POINTER(Detection)]
		cls.lib.bergamot_detect_language.restype = c.c_int
		cls.lib.bergamot_load_model.argtypes = [c.c_char_p, c.c_char_p]
		cls.lib.bergamot_load_model.restype = c.c_int
		cls.lib.bergamot_translate_multiple.argtypes = [c.POINTER(c.c_char_p), c.c_int, c.c_char_p, c.POINTER(c.POINTER(c.c_char_p)), c.POINTER(c.c_int)]
		cls.lib.bergamot_translate_multiple.restype = c.c_int
		cls.lib.bergamot_pivot_multiple.argtypes = [c.c_char_p, c.c_char_p, c.POINTER(c.c_char_p), c.c_int, c.POINTER(c.POINTER(c.c_char_p)), c.POINTER(c.c_int)]
		cls.lib.bergamot_pivot_multiple.restype = c.c_int
		cls.lib.bergamot_free_string_array.argtypes = [c.POINTER(c.c_char_p), c.c_int]
		cls.lib.bergamot_free_string_array.restype = None
		cls.lib.bergamot_cleanup.argtypes = [c.c_int]
		cls.lib.bergamot_cleanup.restype = None
		if MODEL_DIRECTORY:
			for pair in ('enes', 'esen'):
				model = MODEL_DIRECTORY / f'model.{pair}.intgemm.alphas.bin'
				vocab = MODEL_DIRECTORY / f'vocab.{pair}.spm'
				if not model.is_file() or not vocab.is_file():
					raise RuntimeError(f'Missing test model files for {pair}')
				config = {'models': [str(model)], 'vocabs': [str(vocab)] * 2, 'beam-size': 1, 'cpu-threads': 1, 'quiet': True, 'quiet-translation': True, 'gemm-precision': 'int8shiftAlphaAll', 'max-length-break': 128, 'mini-batch-words': 1024, 'workspace': 128}
				if cls.lib.bergamot_load_model(json.dumps(config).encode(), pair.encode()) != 0:
					raise RuntimeError(f'Failed to load real model: {pair}')

	@classmethod
	def tearDownClass(cls):
		cls.lib.bergamot_cleanup(1)

	def test_service_initialization_is_repeatable(self):
		self.assertEqual(self.lib.bergamot_initialize_service(), 0)
		self.assertEqual(self.lib.bergamot_initialize_service(), 0)

	def test_language_detection(self):
		result = Detection()
		text = b'This is an English language paragraph about the weather, the people in our neighbourhood, and the places we would like to visit on our next holiday.'
		self.assertEqual(self.lib.bergamot_detect_language(text, None, c.byref(result)), 0)
		self.assertEqual(result.language, b'en')
		self.assertTrue(result.is_reliable)
		self.assertGreater(result.confidence, 0)

	def translate(self, inputs, key=b'enes', pivot=False):
		values = (c.c_char_p * len(inputs))(*(text.encode() for text in inputs))
		output = c.POINTER(c.c_char_p)()
		count = c.c_int()
		if pivot:
			status = self.lib.bergamot_pivot_multiple(b'enes', b'esen', values, len(inputs), c.byref(output), c.byref(count))
		else:
			status = self.lib.bergamot_translate_multiple(values, len(inputs), key, c.byref(output), c.byref(count))
		try:
			return status, [output[i].decode() for i in range(count.value)]
		finally:
			if output:
				self.lib.bergamot_free_string_array(output, count.value)

	def test_missing_model_returns_error(self):
		status, output = self.translate(['Hello'], key=b'not-loaded')
		self.assertNotEqual(status, 0)
		self.assertEqual(output, [])

	def test_real_translation_batch_and_repeat(self):
		if not MODEL_DIRECTORY:
			self.skipTest('Pass --model-directory for translation inference')
		inputs = ['Hello world.', 'Good morning.', 'Thank you.']
		status, output = self.translate(inputs)
		self.assertEqual(status, 0)
		self.assertEqual(len(output), len(inputs))
		for translated, keyword in zip(output, ['hola', 'buenos', 'gracias']):
			self.assertIn(keyword, translated.lower())
		self.assertEqual(self.translate(inputs), (0, output))
		print('English → Spanish:', output, flush=True)

	def test_real_pivot(self):
		if not MODEL_DIRECTORY:
			self.skipTest('Pass --model-directory for translation inference')
		status, output = self.translate(['Hello world.'], pivot=True)
		self.assertEqual(status, 0)
		self.assertEqual(len(output), 1)
		self.assertIn('hello', output[0].lower())
		self.assertIn('world', output[0].lower())
		print('English → Spanish → English:', output, flush=True)


if __name__ == '__main__':
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('library', type=Path)
	parser.add_argument('--model-directory', type=Path)
	args = parser.parse_args()
	LIBRARY = args.library.resolve()
	MODEL_DIRECTORY = args.model_directory.resolve() if args.model_directory else None
	unittest.main(argv=[__file__], verbosity=2)
