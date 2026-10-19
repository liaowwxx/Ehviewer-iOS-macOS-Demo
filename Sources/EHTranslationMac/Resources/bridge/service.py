"""One bounded JSON request over private pipes; long operations are cancellable
process groups owned by the native application. stdout contains protocol only.
"""
import contextlib
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import traceback
from uuid import uuid4

from .runtime import configure


def secrets_in(config):
    values = []
    def visit(node):
        if isinstance(node, dict):
            for key, value in node.items():
                if key.lower() != 'max_tokens' and any(part in key.lower() for part in ('api_key', 'api key', 'password', 'secret', 'token')):
                    if isinstance(value, str) and value:
                        values.append(value)
                    elif isinstance(value, dict) and value.get('storage') == 'portable_obfuscated':
                        import base64
                        payload = base64.urlsafe_b64decode(value['value'])
                        nonce, cipher = payload[:12], payload[12:]
                        stream = b''
                        for index in range((len(cipher) + 31) // 32):
                            stream += hashlib.sha256(b'BallonsTranslator portable LLM profile secret v1' + nonce + index.to_bytes(4, 'big')).digest()
                        values.append(bytes(a ^ b for a, b in zip(cipher, stream)).decode())
                    elif isinstance(value, dict) and isinstance(value.get('value'), str) and value['value']:
                        values.append(value['value'])
                else:
                    visit(value)
        elif isinstance(node, list):
            for item in node: visit(item)
    visit(config)
    return [value for value in values if value]


class RedactedStream:
    def __init__(self, destination, secrets):
        self.destination, self.secrets = destination, secrets
    def write(self, text):
        for secret in self.secrets:
            text = text.replace(secret, '[REDACTED]')
        return self.destination.write(text)
    def flush(self): self.destination.flush()


def rerun(python, request):
    child = subprocess.run([str(python), '-B', '-m', 'bridge.service'],
                           input=json.dumps(request) + '\n', text=True, stdout=subprocess.PIPE)
    result = json.loads(child.stdout)
    if 'error' in result:
        raise RuntimeError('虚拟环境准备失败')
    return result['result']


def selected_specs(config):
    from ballontranslator.modules import MODULETYPE_TO_REGISTRIES
    flags = {'textdetector': 'detect', 'ocr': 'ocr', 'translator': 'translate', 'inpainter': 'inpaint'}
    module = config.get('module', {})
    return [(stage, registry.get_spec(module[stage])) for stage, registry in MODULETYPE_TO_REGISTRIES.items()
            if module.get('enable_' + flags[stage], True)]


def inspect(config):
    from ballontranslator.utils.core_requirements import check_core_requirements_file, check_core_imports
    from ballontranslator.utils import shared
    core = check_core_requirements_file(Path(shared.PROGRAM_PATH) / 'requirements.txt')
    if not core:
        core = check_core_imports()
    if core:
        return {'packages': core, 'files': [], 'python': sys.version.split()[0], 'ready': False}
    from ballontranslator.modules.prepare_local_files import _missing_module_requirements
    from ballontranslator.utils.download_util import check_local_file
    missing_packages, missing_files = [], []
    for stage, spec in selected_specs(config):
        missing_packages.extend(item.requirement for item in _missing_module_requirements(spec))
        for group in spec.download_file_list or []:
            names = group.get('save_files') or group.get('files') or []
            names = [names] if isinstance(names, str) else names
            hashes = group.get('sha256_pre_calculated') or [None] * len(names)
            hashes = [hashes] if isinstance(hashes, str) else hashes
            for name, sha in zip(names, hashes):
                path = Path(group.get('save_dir') or '') / name
                exists, valid, _ = check_local_file(str(path), sha, cache_hash=False)
                if not exists or not valid:
                    missing_files.append(str(path))
    return {'packages': sorted(set(missing_packages)), 'files': sorted(set(missing_files)),
            'python': sys.version.split()[0], 'ready': not missing_packages and not missing_files}


def execute(request):
    engine, root = Path(request['engine']).resolve(), Path(request['root']).resolve()
    command = request['command']
    if not (engine / 'ballontranslator/launch.py').is_file():
        raise ValueError('所选目录不是 BallonsTranslator 安装')
    if not (3, 10) <= sys.version_info[:2] < (3, 13):
        raise ValueError('需要 Python 3.10–3.12')
    installed_python = engine / '.venv/bin/python'
    if command == 'check' and not installed_python.is_file():
        return {'packages': ['创建 .venv 虚拟环境并安装 requirements.txt 核心依赖'], 'files': [],
                'python': sys.version.split()[0], 'ready': False}
    if command == 'prepare' and not installed_python.is_file():
        # Only this explicit command may create an environment. Never run pip
        # against the fallback/system interpreter selected for bootstrapping.
        subprocess.run([sys.executable, '-m', 'venv', str(engine / '.venv')], check=True)
    if command == 'prepare' and Path(sys.prefix).resolve() != (engine / '.venv').resolve():
        return rerun(installed_python, request)
    if command == 'run' and (not installed_python.is_file() or Path(sys.prefix).resolve() != (engine / '.venv').resolve()):
        raise RuntimeError('请先准备安装内的虚拟环境')
    config = request.get('config', {})
    runtime = root / 'runtime' / hashlib.sha256(str(engine).encode()).hexdigest()[:16]
    configure(engine, runtime, preparing=command == 'prepare')
    if command == 'catalog':
        from .catalog import build_catalog
        return build_catalog(engine, runtime)
    if command == 'models':
        from .model_list import profile_models
        return profile_models(config, request.get('profileID', ''))
    if command == 'check':
        return inspect(config)
    if command == 'prepare':
        from ballontranslator.utils.core_requirements import ensure_core_requirements
        from ballontranslator.utils.network_mirrors import installer_env_with_pypi_mirror
        install_env = installer_env_with_pypi_mirror(os.environ.copy(), config.get('mirrors', {}).get('pypi'))
        # This process ends after preparation; the next fresh process verifies
        # native imports without stale import caches.
        repaired = ensure_core_requirements(repo_root=str(engine), requirements_file=str(engine / 'requirements.txt'), env=install_env)
        if repaired:
            if request.get('_coreRestart'):
                raise RuntimeError('核心依赖仍不可用，请检查安装诊断')
            # Upstream's native dependency repair requires a fresh interpreter.
            return rerun(sys.executable, {**request, '_coreRestart': True})
        from ballontranslator.modules.prepare_local_files import ensure_module_files, _missing_module_requirements
        from ballontranslator.utils.py_package_manager import PyPackageManager
        from ballontranslator.utils.config import pcfg
        pcfg.mirrors.huggingface = config.get('mirrors', {}).get('huggingface')
        for stage, spec in selected_specs(config):
            missing = _missing_module_requirements(spec)
            if missing:
                result = PyPackageManager(env=install_env).install([item.requirement for item in missing],
                    progress_callback=lambda event: print(json.dumps(event), file=sys.stderr, flush=True))
                if not result.ok:
                    raise RuntimeError('依赖安装失败，请重新检查环境')
            if not ensure_module_files(spec, progress_callback=lambda event: print(json.dumps(event), file=sys.stderr, flush=True)):
                raise RuntimeError('模型下载或校验失败')
        return {'prepared': True}
    if command == 'run':
        report = inspect(config)
        if not report['ready']:
            raise RuntimeError('所选模型尚未就绪，请在环境与模型页面准备')
        from .job import atomic_json, digest, validate_image
        directory = Path(request['directory']).resolve()
        if not directory.is_relative_to(root):
            raise ValueError('任务目录超出工作区')
        job = json.loads((directory / 'request.json').read_text())
        # The native owner already snapped the exact private config.
        # Upstream persists runtime adjustments to --config. Give it a working
        # copy so neither that behavior nor cancellation changes the snapshot.
        working_config = directory / 'engine-config.json'
        working_config.write_bytes((directory / 'preset.json').read_bytes())
        log = directory / 'engine.log'
        with log.open('w') as output:
            safe_log = RedactedStream(output, secrets_in(config))
            child = subprocess.Popen([sys.executable, '-B', '-m', 'bridge.engine', '--engine', str(engine),
                                    '--runtime', str(runtime), '--config', str(working_config),
                                    '--job', str(directory / 'request.json')],
                                   cwd=Path(__file__).resolve().parents[1],
                                   env={**os.environ, 'PYTHONPATH': str(Path(__file__).resolve().parents[1])},
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, errors='replace')
            for line in child.stdout:
                safe_log.write(line)
                safe_log.flush()
            child.wait()
        status = json.loads((directory / 'engine-status.json').read_text())
        if child.returncode or status.get('state') != 'succeeded' or status.get('requestID') != job['requestID']:
            raise RuntimeError('翻译流水线失败，请检查任务诊断')
        if len(status['pages']) != job['pageCount']:
            raise ValueError('整本页数不完整')
        for index, page in enumerate(status['pages']):
            if page['index'] != index or Path(page['fileName']).name != page['fileName'] or page['sourceSHA256'] != job['pages'][index]['sha256']:
                raise ValueError('结果页面映射不匹配')
            path = directory / 'project/result' / page['fileName']
            if path.stat().st_size != page['byteCount'] or digest(path) != page['sha256']:
                raise ValueError('结果校验失败')
            validate_image(path)
        result = {'formatVersion': 1, 'versionID': str(uuid4()), 'gallery': job['gallery'], 'createdAt': time.time(),
                  'targetLanguage': config.get('module', {}).get('translate_target', ''),
                  'presetFingerprint': digest(directory / 'preset.json'), 'pages': status['pages']}
        atomic_json(directory / 'result.json', result)
        return result
    raise ValueError('不支持的桥接操作')


def main():
    os.umask(0o077)
    protocol_output = sys.stdout
    safe_log = RedactedStream(sys.stderr, [])
    # Native libraries can write directly to fd 1, bypassing redirect_stdout.
    # Reserve a duplicate pipe for protocol and route their diagnostics to fd 2.
    try:
        protocol_fd = os.dup(sys.stdout.fileno())
        os.dup2(sys.stderr.fileno(), sys.stdout.fileno())
        protocol_output = os.fdopen(protocol_fd, 'w', encoding='utf-8')
    except (AttributeError, io.UnsupportedOperation):
        pass
    try:
        raw = sys.stdin.buffer.readline(4 * 1024 * 1024 + 1)
        if len(raw) > 4 * 1024 * 1024:
            raise ValueError('请求过大')
        request = json.loads(raw)
        safe_log = RedactedStream(sys.stderr, secrets_in(request.get('config', {})))
        with contextlib.redirect_stdout(safe_log), contextlib.redirect_stderr(safe_log):
            result = execute(request)
        protocol_output.write(json.dumps({'result': result}, ensure_ascii=False) + '\n')
    except Exception as error:
        # Never include provider exception text, config contents or keys.
        safe_log.write(type(error).__name__ + '\n' + ''.join(traceback.format_tb(error.__traceback__)))
        safe_log.flush()
        protocol_output.write(json.dumps({'error': type(error).__name__ + '：操作未完成，请检查环境或任务诊断'}, ensure_ascii=False) + '\n')
    protocol_output.flush()


if __name__ == '__main__':
    main()
