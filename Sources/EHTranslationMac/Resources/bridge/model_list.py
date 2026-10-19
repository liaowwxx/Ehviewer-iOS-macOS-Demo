"""Read service model IDs without starting inference or downloading weights."""
import json
from urllib.parse import urlsplit, urlunsplit
from urllib.request import Request, HTTPRedirectHandler, build_opener


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, new_url):
        # Never forward a configured credential to a redirected endpoint.
        return None


def fetch_models(profile, api_key=''):
    parts = urlsplit(profile.get('base_url', '').strip())
    if parts.scheme not in ('http', 'https') or not parts.hostname or parts.username or parts.password:
        raise ValueError('请配置有效的服务 API 地址')
    path = parts.path.rstrip('/')
    for suffix in ('/chat/completions', '/responses'):
        if path.endswith(suffix):
            path = path[:-len(suffix)]
            break
    url = urlunsplit((parts.scheme, parts.netloc, path + '/models', '', ''))
    headers = {'Accept': 'application/json'}
    if api_key:
        headers['Authorization'] = 'Bearer ' + api_key
    with build_opener(NoRedirect()).open(Request(url, headers=headers), timeout=15) as response:
        raw = response.read(2 * 1024 * 1024 + 1)
    if len(raw) > 2 * 1024 * 1024:
        raise ValueError('模型列表响应过大')
    entries = json.loads(raw).get('data')
    if not isinstance(entries, list):
        raise ValueError('服务未返回兼容的模型列表')
    return sorted({item['id'] for item in entries if isinstance(item, dict)
                   and isinstance(item.get('id'), str) and 0 < len(item['id']) <= 256})


def profile_models(config, profile_id):
    profile = next((item for item in config.get('module', {}).get('llm_profiles', [])
                    if item.get('id') == profile_id), None)
    if profile is None:
        raise ValueError('服务配置不存在')
    if profile.get('backend') == 'codex':
        entries = config.get('module', {}).get('codex_models', {})
        return {'models': sorted(name for name, entry in entries.items() if 'text' in entry.get('modalities', []))}
    if profile.get('backend', 'openai') != 'openai':
        raise ValueError('服务协议不支持模型列表')
    from ballontranslator.utils.llm_profiles import resolve_api_key
    return {'models': fetch_models(profile, resolve_api_key(profile))}
