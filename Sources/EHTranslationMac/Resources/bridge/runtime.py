"""Writable overlay referencing installed resources; never clone weights."""
import fcntl
import json
import os
from pathlib import Path
import shutil
import sys


def prepare_runtime(engine: Path, runtime: Path) -> None:
    engine, runtime = engine.resolve(), runtime.resolve()
    if not (engine / 'ballontranslator/launch.py').is_file():
        raise ValueError('请选择有效的 BallonsTranslator 目录')
    if runtime == engine or engine in runtime.parents:
        raise ValueError('工作目录必须位于引擎安装之外')
    runtime.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (runtime / '.prepare.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        marker = runtime / 'source.json'
        if marker.exists() and json.loads(marker.read_text())['engine'] != str(engine):
            raise ValueError('工作目录属于另一引擎')
        (runtime / 'data').mkdir(exist_ok=True)
        (runtime / 'config/textstyles').mkdir(parents=True, exist_ok=True)
        # Whole data directories can contain writable caches. Link individual
        # installed entries instead; resolved-path guards protect their targets.
        for parent in ('', 'data'):
            names = ('resources', 'fonts', 'custom_modules') if not parent else tuple(dict.fromkeys(
                ['models', *(p.name for p in (engine / parent).iterdir())]))
            for name in names:
                source = engine / parent / name
                target = runtime / parent / name
                if (source.exists() or (parent == 'data' and name == 'models')) and not target.exists() and not target.is_symlink():
                    target.symlink_to(source, target_is_directory=source.is_dir())
        for source in [engine / 'pyproject.toml', *engine.glob('requirements*.txt')]:
            target = runtime / source.name
            if source.is_file() and not target.exists():
                shutil.copy2(source, target)
        if not marker.exists():
            marker.write_text(json.dumps({'engine': str(engine)}))


def protect_checkout(engine: Path, preparing=False) -> None:
    engine = engine.resolve()
    model_root = (engine / 'data/models').resolve()
    environment_root = (engine / '.venv').resolve()
    allowed = [environment_root, model_root] if preparing else []
    protected = [engine, environment_root, model_root]
    protected.extend((engine / name).resolve() for name in ('resources', 'fonts', 'custom_modules'))

    def check(path):
        if not isinstance(path, (str, bytes, os.PathLike)):
            return
        path = Path(os.fsdecode(path)).resolve()
        if any(path == item or item in path.parents for item in allowed):
            return
        if any(path == item or item in path.parents for item in protected):
            raise PermissionError('BallonsTranslator 源码、原配置及安装资源只读')

    def audit(event, args):
        if event == 'open':
            mode, flags = args[1:3]
            if (isinstance(mode, str) and any(c in mode for c in 'wax+')) or (
                isinstance(flags, int) and flags & (os.O_WRONLY | os.O_RDWR | os.O_CREAT | os.O_TRUNC | os.O_APPEND)):
                check(args[0])
        elif event in ('os.remove', 'os.rmdir', 'os.mkdir', 'os.chmod', 'os.utime', 'os.truncate'):
            check(args[0])
        elif event in ('os.rename', 'os.link'):
            check(args[0]); check(args[1])
        elif event == 'os.symlink':
            check(args[1])
    sys.addaudithook(audit)


def configure(engine: Path, runtime: Path, preparing=False):
    prepare_runtime(engine, runtime)
    protect_checkout(engine, preparing)
    sys.dont_write_bytecode = True
    os.environ.update(BALLOONTRANS_APP_ROOT=str(runtime), QT_API='pyqt6',
                      PYTHONDONTWRITEBYTECODE='1', XDG_CACHE_HOME=str(runtime / '.cache'),
                      TORCH_HOME=str(runtime / '.cache/torch'), MPLCONFIGDIR=str(runtime / '.cache/matplotlib'),
                      NUMBA_CACHE_DIR=str(runtime / '.cache/numba'),
                      HF_HOME=str(runtime / '.cache/huggingface'))
    os.chdir(runtime)
    sys.path.insert(0, str(engine))
