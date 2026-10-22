"""Process-local adapter for unmodified BallonsTranslator code and reused models.
Only the overlay, private task files and caches are writable during inference.
"""
import argparse
import fcntl
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
from uuid import uuid4

from .job import TranslationJob, atomic_json

PROJECT = Path(__file__).resolve().parent.parent
DEFAULT_ENGINE = Path()


# Runtime and write guards are shared with metadata and explicit preparation.
from .runtime import prepare_runtime, protect_checkout


def install_window_adapter(launch, options) -> None:
    """Attach lifecycle hooks after Qt/font initialization, before construction."""
    from qtpy.QtCore import QTimer
    from ballontranslator.utils import config, shared
    from ballontranslator.ui import mainwindow

    # Recent upstream projects must never be auto-opened by the companion.
    config.pcfg.open_recent_on_startup = False
    config.pcfg.check_update_on_startup = False
    config.pcfg.text_styles_path = str(options.runtime / 'config/textstyles')

    # These are interactive warmups; short-lived children can otherwise exit
    # while a background numba compilation still owns native state.
    mainwindow.start_effect_paint_numba_warmup = lambda: None
    mainwindow.start_grid_numba_warmup = lambda: None
    if shared.ON_MACOS:
        from ballontranslator.ui.framelesswindow.fw_qt6.mac_frameless_window import MacFramelessWindowBase
        from ballontranslator.ui.framelesswindow.mac_window_effect import MacWindowEffect
        MacFramelessWindowBase.updateFrameless = lambda self: None
        MacFramelessWindowBase.changeEvent = lambda self, event: None
        MacFramelessWindowBase.hideSystemTitleBar = lambda self: None
        MacFramelessWindowBase.setSystemTitleBarButtonVisible = lambda self, visible: setattr(self, '_isSystemButtonVisible', visible)
        for name in ('addShadowEffect', 'removeMenuShadowEffect', 'removeShadowEffect'):
            setattr(MacWindowEffect, name, lambda self, *args: None)

    class ManagedWindow(mainwindow.MainWindow):
        def __init__(self, app, program_config, **kwargs):
            self.managed_job = TranslationJob(str(options.job))
            app.setQuitOnLastWindowClosed(False)
            super().__init__(app, program_config, **kwargs)
            self.imsave_thread.img_writed.connect(self.on_managed_page_saved)
            self.progress_timer = QTimer(self)
            self.progress_timer.timeout.connect(self.update_progress)
            self.progress_timer.start(500)
            QTimer.singleShot(0, self.start_job)

        def run_batch(self, **kwargs):
            # Replace the upstream interactive directory/input() loop.
            pass

        def hideSystemTitleBar(self):
            pass

        def showMaximized(self):
            pass

        def start_job(self):
            self.managed_job.start(self)

        def update_progress(self):
            self.managed_job.progress(self)

        def on_pagtrans_finished(self, index):
            super().on_pagtrans_finished(index)
            self.managed_job.page_finished(index)

        def on_managed_page_saved(self, name):
            self.managed_job.page_saved(self, name)

        def on_imgtrans_pipeline_finished(self):
            self.progress_timer.stop()
            self.managed_job.finish(self)

        def on_create_errdialog(self, *args):
            self.managed_job.error = True
            self.managed_job.status('failed', error='Engine reported an error; inspect local diagnostics')
            self.app.exit(1)

        def on_show_llm_key_dialog(self, *args):
            self.on_create_errdialog('LLM credentials require configuration')

        def on_show_llm_model_dialog(self, *args):
            self.on_create_errdialog('LLM model requires configuration')

        def on_show_llm_base_url_dialog(self, *args):
            self.on_create_errdialog('LLM URL requires configuration')

    mainwindow.MainWindow = ManagedWindow


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--engine', type=Path, default=DEFAULT_ENGINE)
    parser.add_argument('--runtime', type=Path, required=True)
    parser.add_argument('--config', type=Path, required=True)
    parser.add_argument('--job', type=Path, required=True)
    options = parser.parse_args()
    options.engine = options.engine.resolve()
    options.runtime = options.runtime.resolve()
    options.config = options.config.resolve()
    options.job = options.job.resolve()
    if options.runtime == options.engine or options.engine in options.runtime.parents:
        raise ValueError('运行目录必须位于 BallonsTranslator 项目之外')
    if options.config == options.engine or options.engine in options.config.parents:
        raise ValueError('配置必须是独立应用托管的副本')
    os.umask(0o077)
    prepare_runtime(options.engine, options.runtime)
    protect_checkout(options.engine)
    sys.dont_write_bytecode = True
    os.environ['PYTHONDONTWRITEBYTECODE'] = '1'
    os.environ['QT_API'] = 'pyqt6'
    os.environ['QT_QPA_PLATFORM'] = 'offscreen'
    os.environ['HF_HUB_OFFLINE'] = '1'
    os.environ['TRANSFORMERS_OFFLINE'] = '1'
    os.environ['BALLOONTRANS_APP_ROOT'] = str(options.runtime)
    os.environ['XDG_CACHE_HOME'] = str(options.runtime / '.cache')
    os.environ['TORCH_HOME'] = str(options.runtime / '.cache/torch')
    os.environ['MPLCONFIGDIR'] = str(options.runtime / '.cache/matplotlib')
    sys.path.insert(0, str(options.engine))
    sys.argv = ['ballontranslator', '--config', str(options.config), '--headless']
    # Redact upstream file-handler output too, not just the captured stdout.
    import logging
    from .service import secrets_in
    secrets = secrets_in(json.loads(options.config.read_text()))
    original_format = logging.Formatter.format
    def safe_format(formatter, record):
        message = original_format(formatter, record)
        for secret in secrets:
            message = message.replace(secret, '[REDACTED]')
        return message
    logging.Formatter.format = safe_format
    from ballontranslator import launch
    from ballontranslator.modules.llm_chat import LLMChatRequester
    from .activity import LLMActivity, install_llm_activity
    request_id = json.loads(options.job.read_text())['requestID']
    install_llm_activity(LLMChatRequester, LLMActivity(options.job.parent, request_id, secrets))
    from ballontranslator.utils import core_requirements, network_mirrors
    # The companion owns dependency installation and its environment. Startup
    # must not silently install/restart or rewrite the user's chosen preset.
    core_requirements.ensure_core_requirements = lambda *args, **kwargs: False
    network_mirrors.auto_fill_network_mirrors = lambda *args, **kwargs: []
    # Ordinary execution may never install dependencies or download weights.
    from ballontranslator.utils import download_util, package_installer
    from ballontranslator.utils.py_package_manager import PyPackageManager
    def forbidden(*args, **kwargs):
        raise RuntimeError('请先在环境与模型页面准备所选模型')
    package_installer.install = forbidden
    PyPackageManager.install = forbidden
    download_util.download_url_to_file = forbidden
    setup_locks = launch.setup_locks

    def setup_adapter():
        setup_locks()
        install_window_adapter(launch, options)
    launch.setup_locks = setup_adapter

    exit_code = launch.main()
    from qtpy.QtCore import QCoreApplication, QEvent
    window, launch.BT = launch.BT, None
    if window is not None:
        if window.font_change_detector is not None:
            window.font_change_detector.stop()
        window.font_refresh.shutdown()
        window.deleteLater()
        QCoreApplication.sendPostedEvents(None, QEvent.Type.DeferredDelete)
    return exit_code or 0


if __name__ == '__main__':
    raise SystemExit(main())
