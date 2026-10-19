"""Single-job bridge into the existing Qt translation pipeline.

The request and all outputs live in a companion-owned workspace. No pipeline
algorithm is duplicated here. A terminal success record is written only after
the normal image-save worker has drained and every page has been verified.
"""
import hashlib
import json
from pathlib import Path

from PIL import Image


def atomic_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + '.tmp')
    with temporary.open('w', encoding='utf-8') as stream:
        json.dump(value, stream, ensure_ascii=False)
        stream.flush()
        import os
        os.fsync(stream.fileno())
    temporary.replace(path)


def digest(path: Path) -> str:
    hasher = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            hasher.update(chunk)
    return hasher.hexdigest()


def validate_image(path: Path) -> None:
    with Image.open(path) as image:
        if getattr(image, 'n_frames', 1) != 1:
            raise ValueError('Animated media is not supported for translation')
        if image.width * image.height > 100_000_000:
            raise ValueError('Image exceeds the 100 megapixel limit')
        image.verify()


class TranslationJob:
    """Owns one execution, while MainWindow continues to own the pipeline.

    >>> job_path = Path('/managed/jobs/request.json')
    >>> job_path.name
    'request.json'
    """

    def __init__(self, request_path: str) -> None:
        self.path = Path(request_path).resolve()
        self.request = json.loads(self.path.read_text(encoding='utf-8'))
        self.project = self.path.parent / 'project'
        self.error = False
        self.done = False
        self.rendered = set()

    def status(self, state: str, **extra) -> None:
        atomic_json(self.path.parent / 'engine-status.json', {
            'requestID': self.request['requestID'], 'state': state, **extra,
        })

    def start(self, window) -> None:
        try:
            from ballontranslator.utils.config import pcfg
            expected = json.loads((self.path.parent / 'preset.json').read_text())
            for key in ('textdetector', 'ocr', 'translator', 'inpainter'):
                if getattr(pcfg.module, key) != expected['module'][key]:
                    raise ValueError('Selected module was replaced during config validation')
            pages = self.request['pages']
            if not 1 <= len(pages) <= 10000:
                raise ValueError('Invalid page count')
            for index, page in enumerate(pages):
                if page['index'] != index or Path(page['fileName']).name != page['fileName']:
                    raise ValueError('Invalid page mapping')
                source = self.project / page['fileName']
                if source.stat().st_size != page['byteCount'] or digest(source) != page['sha256']:
                    raise ValueError('Source integrity check failed')
                validate_image(source)
            window.openDir(str(self.project))
            if list(window.imgtrans_proj.pages) != [p['fileName'] for p in pages]:
                raise ValueError('Engine page order differs from submitted mapping')
            self.status('preparing')
            window.on_run_imgtrans()
        except Exception:
            self.error = True
            self.status('failed', error='Input or pipeline initialization failed; inspect local diagnostics')
            window.app.exit(1)

    def page_finished(self, index: int) -> None:
        self.rendered.add(index)
        self.status('rendering', completedPages=len(self.rendered))

    def progress(self, window) -> None:
        if self.done or self.error:
            return
        thread = window.module_manager.imgtrans_thread
        counters = {stage: getattr(thread, stage + '_counter', 0) for stage in ('detect', 'ocr', 'translate', 'inpaint')}
        state = 'running' if any(counters.values()) else 'preparing'
        self.status(state, completedPages=len(self.rendered), stages=counters)

    def finish(self, window) -> None:
        if self.done:
            return
        self.done = True
        # Stage progress can reach 100% just before the worker's run() returns.
        # Drain workers before SIP destroys their QObject owners at shutdown.
        for thread in (window.module_manager.imgtrans_thread, window.module_manager.translate_thread):
            if thread.isRunning():
                thread.wait()
        window.imsave_thread.wait()
        try:
            if self.error or window.module_manager.imgtrans_thread.isStopRequested():
                raise ValueError('Pipeline failed or stopped')
            if self.rendered != set(range(len(self.request['pages']))):
                raise ValueError('Pipeline did not render every page')
            outputs = []
            for page in self.request['pages']:
                result = Path(window.imgtrans_proj.get_result_path(page['fileName'])).resolve()
                if result.parent != (self.project / 'result').resolve():
                    raise ValueError('Invalid output path')
                validate_image(result)
                outputs.append({
                    'index': page['index'], 'fileName': result.name,
                    'byteCount': result.stat().st_size, 'sha256': digest(result),
                    'sourceSHA256': page['sha256'],
                })
            self.status('succeeded', pages=outputs)
            window.app.exit(0)
        except Exception:
            self.status('failed', error='Pipeline or complete output validation failed')
            window.app.exit(1)
