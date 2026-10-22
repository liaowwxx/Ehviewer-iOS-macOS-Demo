"""Deterministic bridge tests: no downloads, paid services or installed changes."""
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from types import ModuleType, SimpleNamespace
from unittest.mock import Mock, patch

RESOURCE = Path(__file__).resolve().parents[2] / 'Sources/EHTranslationMac/Resources'
sys.path.insert(0, str(RESOURCE))
from bridge.runtime import prepare_runtime
from bridge.service import RedactedStream, secrets_in


class NativeBridgeTests(unittest.TestCase):
    def fixture(self):
        root = Path(tempfile.mkdtemp(prefix='eh-native-bridge-test-'))
        engine, runtime = root / 'engine', root / 'runtime'
        for item in ('ballontranslator', 'config', 'data/models', 'resources/icons', 'resources/translate'):
            (engine / item).mkdir(parents=True, exist_ok=True)
        (engine / 'ballontranslator/launch.py').write_text('')
        (engine / 'config/config.json').write_text('{"original": true}')
        (engine / 'data/models/model.bin').write_bytes(b'weights')
        prepare_runtime(engine, runtime)
        return engine, runtime

    def test_overlay_reuses_model_inode_without_copying_config(self):
        engine, runtime = self.fixture()
        self.assertTrue((runtime / 'data/models').is_symlink())
        self.assertEqual((engine / 'data/models/model.bin').stat().st_ino,
                         (runtime / 'data/models/model.bin').stat().st_ino)
        self.assertFalse((runtime / 'config/config.json').exists())
        self.assertTrue((runtime / 'config/textstyles').is_dir())

    def test_ordinary_guard_rejects_symlink_writes(self):
        engine, runtime = self.fixture()
        code = '''from pathlib import Path
from bridge.runtime import protect_checkout
import sys
protect_checkout(Path(sys.argv[1]), preparing=sys.argv[3]=='prepare')
try:
    Path(sys.argv[2]).write_text('change')
except PermissionError:
    print('denied')
else:
    print('allowed')
'''
        def run(path, mode):
            return subprocess.check_output([sys.executable, '-B', '-c', code, str(engine), str(path), mode],
                                           env={**os.environ, 'PYTHONPATH': str(RESOURCE)}, text=True).strip()
        self.assertEqual(run(runtime / 'data/models/model.bin', 'normal'), 'denied')
        self.assertEqual(run(engine / 'config/config.json', 'prepare'), 'denied')
        self.assertEqual(run(engine / 'ballontranslator/launch.py', 'prepare'), 'denied')
        self.assertEqual(run(engine / 'data/models/new-model.bin', 'prepare'), 'allowed')
        self.assertEqual((engine / 'data/models/model.bin').read_bytes(), b'weights')

    def test_protocol_bounds_input_and_sanitizes_errors(self):
        proc = subprocess.run([sys.executable, '-B', '-m', 'bridge.service'], cwd=RESOURCE,
                              input='x' * (4 * 1024 * 1024 + 1), text=True, capture_output=True)
        response = json.loads(proc.stdout)
        self.assertIn('error', response)
        self.assertLess(len(proc.stdout), 300)

    def test_logs_redact_configured_secrets(self):
        secret = 'test-secret-do-not-log'
        config = {'module': {'llm_profiles': [{'api_key': secret}], 'other': 1}}
        output = io.StringIO()
        RedactedStream(output, secrets_in(config)).write('provider error ' + secret)
        self.assertNotIn(secret, output.getvalue())
        self.assertIn('[REDACTED]', output.getvalue())

    def test_llm_activity_preserves_response_and_redacts_bounded_output(self):
        from bridge.activity import LLMActivity, install_llm_activity
        directory = Path(tempfile.mkdtemp(prefix='eh-llm-activity-'))
        activity = LLMActivity(directory, 'owned-task', ['private-key'])
        response = SimpleNamespace(content='译文 private-key')
        class Requester:
            def request_chat_completion(self, profile, api_args, **kwargs):
                snapshot = json.loads(activity.path.read_text())
                self_test.assertEqual(snapshot['state'], 'requesting')
                return response
        self_test = self
        install_llm_activity(Requester, activity)
        self.assertIs(Requester().request_chat_completion(None, {}, codex_turn=None), response)
        snapshot = json.loads(activity.path.read_text())
        self.assertEqual(snapshot['requestID'], 'owned-task')
        self.assertEqual(snapshot['state'], 'received')
        self.assertIn('译文 [REDACTED]', snapshot['text'])
        self.assertNotIn('private-key', snapshot['text'])
        activity.publish('received', 'x' * 100000)
        self.assertLessEqual(len(json.loads(activity.path.read_text())['text']), 32000)

    def test_llm_activity_preserves_failure_without_logging_provider_secrets(self):
        from bridge.activity import LLMActivity, install_llm_activity
        activity = LLMActivity(Path(tempfile.mkdtemp(prefix='eh-llm-activity-')), 'task', [])
        class Requester:
            def request_chat_completion(self, profile, api_args):
                raise RuntimeError('provider-private-key')
        install_llm_activity(Requester, activity)
        with self.assertRaises(RuntimeError):
            Requester().request_chat_completion(None, {})
        snapshot = json.loads(activity.path.read_text())
        self.assertEqual(snapshot['state'], 'failed')
        self.assertNotIn('provider-private-key', activity.path.read_text())

    def test_preview_waits_for_saved_result_and_preserves_latest_page_in_progress(self):
        from bridge.job import TranslationJob
        directory = Path(tempfile.mkdtemp(prefix='eh-page-preview-'))
        request = directory / 'request.json'
        request.write_text(json.dumps({'requestID': 'task', 'pages': [{'index': 0, 'fileName': 'source.jpg'}]}))
        job = TranslationJob(str(request))
        result = directory / 'project/result/source.png'
        window = SimpleNamespace(imgtrans_proj=SimpleNamespace(get_result_path=lambda name: str(result)),
                                 module_manager=SimpleNamespace(imgtrans_thread=SimpleNamespace(ocr_counter=1, parallel_trans=True),
                                                                translate_thread=SimpleNamespace(finished_counter=1)))
        job.page_finished(0)
        job.page_saved(window, 'source.jpg')
        status = lambda: json.loads((directory / 'engine-status.json').read_text())
        self.assertIsNone(status()['latestPage'])
        self.assertEqual(status()['completedPages'], 0)
        result.parent.mkdir(parents=True)
        result.write_bytes(b'test-image')
        with patch('bridge.job.validate_image'):
            job.page_saved(window, 'source.jpg')
        job.progress(window)
        self.assertEqual(status()['latestPage'], {'index': 0, 'fileName': 'source.png'})
        self.assertEqual(status()['completedPages'], 1)
        self.assertEqual(status()['stages']['ocr'], 1)
        self.assertEqual(status()['stages']['translate'], 1)

    def test_model_list_uses_metadata_endpoint_and_preserves_full_model_ids(self):
        from bridge import model_list
        response = io.BytesIO(json.dumps({'data': [{'id': 'qwen3:14b'}, {'id': 'qwen3:14b'},
                                                 {'id': 'vendor/custom-model'}, {'id': None}]}).encode())
        opener = SimpleNamespace(open=Mock(return_value=response))
        with patch.object(model_list, 'build_opener', return_value=opener):
            result = model_list.fetch_models({'base_url': 'http://localhost:11434/v1/chat/completions'}, 'test-key')
        self.assertEqual(result, ['qwen3:14b', 'vendor/custom-model'])
        request = opener.open.call_args.args[0]
        self.assertEqual(request.full_url, 'http://localhost:11434/v1/models')
        self.assertEqual(request.get_method(), 'GET')
        self.assertEqual(request.get_header('Authorization'), 'Bearer test-key')
        self.assertEqual(opener.open.call_args.kwargs['timeout'], 15)

    def test_model_list_rejects_invalid_addresses_oversize_and_malformed_responses(self):
        from bridge import model_list
        for url in ['file:///private/config', 'https://user:password@example.invalid/v1']:
            with self.assertRaises(ValueError):
                model_list.fetch_models({'base_url': url})
        for payload in [b'x' * (2 * 1024 * 1024 + 1), b'{"models":[]}']:
            opener = SimpleNamespace(open=lambda request, timeout: io.BytesIO(payload))
            with patch.object(model_list, 'build_opener', return_value=opener), self.assertRaises(ValueError):
                model_list.fetch_models({'base_url': 'http://localhost:11434/v1'})
        self.assertIsNone(model_list.NoRedirect().redirect_request(None, None, 302, '', {}, 'https://other.invalid'))

    def test_cancelled_download_or_failed_install_has_no_success_response(self):
        from bridge import service
        for error in (InterruptedError('cancelled'), RuntimeError('installer failed')):
            with self.subTest(error=type(error).__name__):
                fake_input = type('Input', (), {'buffer': io.BytesIO(b'{}\n')})()
                output = io.StringIO()
                with patch.object(service, 'execute', side_effect=error), patch.object(sys, 'stdin', fake_input), patch.object(sys, 'stdout', output):
                    service.main()
                self.assertIn('error', json.loads(output.getvalue()))
                self.assertNotIn('result', json.loads(output.getvalue()))

    def test_missing_environment_check_does_not_install_or_create_venv(self):
        from bridge import service
        engine, runtime = self.fixture()
        with patch.object(sys, 'version_info', (3, 12, 0)), patch.object(service.subprocess, 'run') as install:
            report = service.execute({'command': 'check', 'engine': str(engine), 'root': str(runtime)})
        self.assertFalse(report['ready'])
        self.assertTrue(report['packages'])
        self.assertFalse((engine / '.venv').exists())
        install.assert_not_called()

    def test_missing_package_and_model_are_reported_without_download(self):
        from bridge import service
        modules = {}
        for name in ('ballontranslator', 'ballontranslator.utils', 'ballontranslator.modules',
                     'ballontranslator.utils.core_requirements', 'ballontranslator.modules.prepare_local_files',
                     'ballontranslator.utils.download_util'):
            modules[name] = ModuleType(name)
        modules['ballontranslator.utils'].shared = SimpleNamespace(PROGRAM_PATH='/unused')
        core = modules['ballontranslator.utils.core_requirements']
        core.check_core_requirements_file = lambda path: []
        core.check_core_imports = lambda: []
        modules['ballontranslator.modules.prepare_local_files']._missing_module_requirements = lambda spec: [SimpleNamespace(requirement='missing-backend')]
        modules['ballontranslator.utils.download_util'].check_local_file = lambda *args, **kwargs: (False, False, None)
        spec = SimpleNamespace(download_file_list=[{'files': 'data/models/missing.bin'}])
        with patch.dict(sys.modules, modules), patch.object(service, 'selected_specs', return_value=[('ocr', spec)]):
            report = service.inspect({})
        self.assertFalse(report['ready'])
        self.assertEqual(report['packages'], ['missing-backend'])
        self.assertEqual(report['files'], ['data/models/missing.bin'])

    def test_explicit_bootstrap_never_installs_into_system_interpreter(self):
        from bridge import service
        engine, runtime = self.fixture()
        commands = []
        def run(command, **kwargs):
            commands.append(command)
            if command[1:3] == ['-m', 'venv']:
                target = engine / '.venv/bin/python'
                target.parent.mkdir(parents=True)
                target.write_text('test-only-interpreter')
                return SimpleNamespace(returncode=0)
            return SimpleNamespace(stdout=json.dumps({'result': {'prepared': True}}), returncode=0)
        with patch.object(sys, 'version_info', (3, 12, 0)), patch.object(service.subprocess, 'run', side_effect=run):
            result = service.execute({'command': 'prepare', 'engine': str(engine), 'root': str(runtime)})
        self.assertTrue(result['prepared'])
        self.assertEqual(commands[0], [sys.executable, '-m', 'venv', str((engine / '.venv').resolve())])
        self.assertEqual(commands[1][0], str((engine / '.venv/bin/python').resolve()))
        self.assertFalse(any('pip' in command for command in commands))


if __name__ == '__main__':
    unittest.main()
