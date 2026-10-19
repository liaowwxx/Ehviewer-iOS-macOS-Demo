"""Read upstream lazy metadata without constructing models or upstream widgets."""
import argparse
import ast
import json
import os
from pathlib import Path
import sys

from .engine import DEFAULT_ENGINE, prepare_runtime, protect_checkout
from .job import atomic_json


def literal_params(engine: Path, spec) -> dict:
    """Retain static fields when one dynamic selector defeats lazy evaluation."""
    path = engine / (spec.import_path.replace('.', '/') + '.py')
    if not path.is_file():
        return {}

    def literal(node):
        try:
            return ast.literal_eval(node)
        except (ValueError, TypeError):
            if isinstance(node, ast.Dict):
                return {literal(k): literal(v) for k, v in zip(node.keys, node.values) if isinstance(k, ast.Constant)}
            return None

    for node in ast.walk(ast.parse(path.read_text())):
        if isinstance(node, ast.ClassDef) and node.name == spec.class_name:
            for item in node.body:
                targets = item.targets if isinstance(item, ast.Assign) else [item.target] if isinstance(item, ast.AnnAssign) else []
                if any(isinstance(target, ast.Name) and target.id == 'params' for target in targets):
                    return literal(item.value) or {}
    return {}


def build_catalog(engine: Path, runtime: Path) -> dict:
    engine, runtime = engine.resolve(), runtime.resolve()
    if runtime == engine or engine in runtime.parents:
        raise ValueError('模型目录必须位于引擎项目之外')
    prepare_runtime(engine, runtime)
    protect_checkout(engine)
    sys.dont_write_bytecode = True
    os.environ['BALLOONTRANS_APP_ROOT'] = str(runtime)
    os.environ['QT_API'] = 'pyqt6'
    sys.path.insert(0, str(engine))
    from ballontranslator.modules import MODULETYPE_TO_REGISTRIES
    result = {}
    for stage, registry in MODULETYPE_TO_REGISTRIES.items():
        result[stage] = {}
        for key in registry.module_dict:
            spec = registry.get_spec(key)
            result[stage][key] = {
                'params': spec.params_copy() or literal_params(engine, spec),
                'sourceLanguages': spec.supported_src_list or [],
                'targetLanguages': spec.supported_tgt_list or [],
            }
    # Lazy metadata can contain Python types or an unknown-expression sentinel.
    # Their values are unavailable, so the editor retains the saved config value.
    return json.loads(json.dumps(result, default=lambda value: None))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--engine', type=Path, default=DEFAULT_ENGINE)
    parser.add_argument('--runtime', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    options = parser.parse_args()
    os.umask(0o077)
    atomic_json(options.output, build_catalog(options.engine, options.runtime))


if __name__ == '__main__':
    main()
